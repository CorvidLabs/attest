# attest Architecture

How `attest` is put together: the split between the engine and the CLI, the canonical
serialization that anchors signatures, the git-notes storage model, the optional signing
model, and the verify / export flow.

## Two layers: `AttestKit` vs the `attest` CLI

`attest` is deliberately split so the engine is testable with zero I/O.

- **`AttestKit`** (`Sources/AttestKit/`) is the engine library. It owns the data model
  (`Attestation`, `Verdict`), the canonical serialization, Ed25519 signing/verification,
  the `Policy` + `Verifier`, the `Exporter`, augur ingestion, and the storage protocol. It
  depends only on Apple's [`swift-crypto`](https://github.com/apple/swift-crypto) — no third-party
  packages, no networking, no global state.
- **`attest`** (`Sources/attest/`) is the CLI. It uses
  [`swift-argument-parser`](https://github.com/apple/swift-argument-parser), resolves git
  revisions and ranges, loads `.attest.json`, and renders human or JSON output. It is a thin
  driver over `AttestKit`.

The boundary matters for two reasons:

1. **Testability.** The engine reads attestations through the `AttestationStore` protocol, so
   the test suite drives it against an in-memory fake (`InMemoryStore`) without shelling out to
   `git`. The same `Verifier` and `Ed25519Verifier` the CLI uses are exercised directly.
2. **Determinism.** All time-dependent behavior (today: the `maxAgeDays` freshness rule) takes
   an *injected* reference time rather than reading the system clock inside the engine. The CLI
   supplies `Int(Date().timeIntervalSince1970)` at its boundary; tests supply a fixed epoch.

```
┌──────────────────────────────┐
│  attest (CLI)                │  argument-parser, git resolution,
│  Sources/attest/             │  .attest.json loading, rendering,
│                              │  injects `now` = current epoch
└───────────────┬──────────────┘
                │ drives
┌───────────────▼──────────────┐
│  AttestKit (engine)          │  Attestation, Canonical, Ed25519,
│  Sources/AttestKit/          │  Policy/Verifier, Exporter, Augur,
│                              │  AttestationStore protocol
└───────────────┬──────────────┘
                │ persists through
┌───────────────▼──────────────┐
│  AttestationStore            │  NotesStore (git notes)  │ InMemoryStore (tests)
└──────────────────────────────┘
```

## The data model

An `Attestation` (`Models.swift`) is a provenance record keyed to a git commit SHA:

| Field | Meaning |
|-------|---------|
| `commit` | the commit SHA this record is about |
| `reviewer` | who or what reviewed, e.g. `agent:claude`, `human:leif`, `ci:runner` |
| `confidence` | reviewer confidence, clamped to `0...1` at construction |
| `verdict` | optional `proceed` / `review` / `block` (mirrors augur's vocabulary) |
| `testsPassed` | whether the change's tests passed |
| `humanApproved` | whether a human explicitly approved |
| `timestamp` | Unix epoch seconds when the attestation was made |
| `note` | optional free text |
| `signature` / `publicKey` | optional base64 Ed25519 pair (present only when signed) |

`Verdict` is `Comparable` (`proceed < review < block`) so a policy can express "at least
`review`". Multiple attestations can accrue on a single commit — a store appends, never
replaces.

## Canonical serialization: the signature contract

Signatures are only meaningful if everyone agrees on *which bytes* are signed. `Canonical.swift`
defines that contract:

- `Attestation.canonicalData()` encodes a **fixed subset** of the record (everything *except*
  `signature` and `publicKey`) as JSON with **sorted keys** and **slashes left unescaped**.
- Optional fields (`note`, `verdict`) are omitted when `nil` (`encodeIfPresent`), keeping the
  bytes compact and stable.

Two consequences hold by design and are covered by tests:

- **Attaching a signature never changes the signed bytes.** An unsigned record and its signed
  copy share canonical bytes, because the canonical form excludes the signature pair.
- **Identical content always yields identical bytes**, independent of field declaration order or
  platform.

> The canonical form is the contract. Changing it invalidates every existing signature, so it is
> treated as a breaking change and must never drift.

## Storage: git notes

`NotesStore` (`NotesStore.swift`) implements `AttestationStore` over git notes under a dedicated
ref, `refs/notes/attest`:

- Each commit's note holds **JSON Lines** — one attestation per line — so appending a new
  attestation is concatenating a line, and each record stays individually parseable
  (`AttestationCodec`).
- Notes are **portable**: no service, no database. They travel with `git push origin
  "refs/notes/*"` and never touch the working tree.
- `NotesStore` shells out to `git` via `Process`, reads stdout, and treats a missing note (a
  non-zero exit from `git notes show`) as "no attestations" rather than an error.
- Reading attestations is strict: a corrupt JSON line surfaces `AttestError.malformedRecord`
  rather than being silently dropped — corruption in an audit ledger must be loud, not lossy.

The `InMemoryStore` fake mirrors the same protocol for tests and dry runs, guarded by a lock.

## Signing model

Signing is **optional** end to end (`Ed25519Signer.swift`, `KeyStore.swift`):

- `attest keygen` generates a Curve25519 (Ed25519) keypair and writes the private key as base64
  to `~/.config/attest/key` (or `$XDG_CONFIG_HOME/attest/key`) with `0600` permissions.
- `attest sign --sign` loads that key and produces a detached base64 signature over
  `canonicalData()`, embedding the signer's base64 **public** key on the record so any party can
  verify it later without a key server.
- `Ed25519Verifier.verify` recomputes the canonical bytes and checks the embedded signature
  against the embedded public key (and, optionally, an expected key for pinning). Any mutation of
  signed content fails verification.

An unsigned attestation is a fully valid record. Signing is what lets a policy *trust* a record
(`requireSignature`, `trustedKeys`, `signerPinning`) — see [signing.md](signing.md).

## The verify flow

`attest verify` (and the `Attest.verify` facade) does:

1. Resolve the target commits — a single commit, an oldest-first range
   (`NotesStore.commits(inRange:)`), or `HEAD`.
2. Load the `Policy` from `.attest.json` (or the permissive default if absent).
3. For each commit, read its attestations and run `Verifier.evaluate`, collecting `Violation`s.
4. Return a `VerificationResult` (`passed`, `checkedCommits`, `violations`). The CLI exits
   non-zero when `passed` is false — that exit code is the contract CI and agent loops read.

The verifier injects a reference time `now` (defaulted to the current epoch at the CLI boundary)
used only by the `maxAgeDays` freshness rule. See [policy.md](policy.md) for every rule.

## The export flow

`attest export` (`Exporter.swift`) produces a single, stable JSON `AuditReport` for compliance
archival — distinct from `attest log` (a human/diagnostic listing):

1. The caller resolves the range to an ordered commit list (oldest first), exactly as `verify` /
   `log` do — the exporter does **no** git walking of its own.
2. For each commit, every attestation is paired with a computed `VerificationStatus` (`signed`,
   and for signed records `verified`), reusing the same `Ed25519Verifier`.
3. When a `Policy` is supplied, each commit gets a `policyPassed` and the report a top-level
   `allPassed`, computed with the same `Verifier` as `attest verify`.

Output is deterministic: commits in supplied order, records in store order (oldest first),
sorted JSON keys — so identical inputs yield byte-identical JSON and the document diffs cleanly.
See [cli.md](cli.md) for flags and [ci-integration.md](ci-integration.md) for the archival step.
