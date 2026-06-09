---
module: provenance-ledger
version: 2
status: draft
files:
  - Sources/AttestKit/Models.swift
  - Sources/AttestKit/Canonical.swift
  - Sources/AttestKit/Ed25519Signer.swift
  - Sources/AttestKit/Store.swift
  - Sources/AttestKit/NotesStore.swift
  - Sources/AttestKit/Policy.swift
  - Sources/AttestKit/AugurInput.swift
  - Sources/AttestKit/KeyStore.swift
  - Sources/AttestKit/Attest.swift
  - Sources/AttestKit/Reporter.swift
  - Sources/AttestKit/Exporter.swift
db_tables: []
depends_on: []
---

# Provenance Ledger

## Purpose

Record portable, verifiable attestations about code changes — *who or what reviewed a
change, and at what confidence* — keyed to git commit SHAs and stored in git notes
(`refs/notes/attest`), so the trust record travels with the repository across every git
host. As AI agents author more code, there is no native record of which agent or human
vetted a change; `attest` is that missing primitive and the trust-record companion to
`augur`, which scores diff risk. `augur` says how much to trust a change; `attest` records
that trust and enforces a policy over it in CI and agent loops.

Two design commitments make it usable everywhere:

1. **Signing is optional.** An unsigned attestation is still a valid record, so the tool
   works with zero setup. When signed, an Ed25519 signature covers a deterministic
   canonical serialization that excludes the signature field itself.
2. **Storage is portable.** Records live in git notes — no service, no database — and are
   abstracted behind `AttestationStore` so the engine is testable in memory.

## Public API

### Entry Point

| Export | Description |
|--------|-------------|
| `Attest.init(store:)` | Construct the facade over an `AttestationStore`. |
| `Attest.record(_:signer:)` | Record an attestation, optionally signing it first; returns the stored record. |
| `Attest.attestations(for:)` | All attestations recorded for a commit, oldest first. |
| `Attest.verify(commits:policy:)` | Check commits' attestations against a `Policy`, returning a `VerificationResult`. |

### Model & Serialization

| Export | Description |
|--------|-------------|
| `Attestation.init(commit:reviewer:confidence:verdict:testsPassed:humanApproved:timestamp:note:signature:publicKey:)` | Construct an attestation; `confidence` is clamped to `0...1`. |
| `Attestation.isSigned` | Whether the record carries both a signature and a public key. |
| `Attestation.attaching(signature:publicKey:)` | A copy with the signature pair attached. |
| `Attestation.canonicalData()` | Deterministic, sorted-key bytes to sign/verify, excluding the signature pair. |
| `Attestation.canonicalString()` | The canonical serialization as a UTF-8 string. |
| `Attestation.jsonString()` | Full record (including any signature) as stable, sorted-key JSON. |
| `Attestation.jsonData()` | Same as `jsonString()` but returns `Data`. |

### Signing

| Export | Description |
|--------|-------------|
| `Ed25519Signer.generate()` | Generate a fresh keypair. |
| `Ed25519Signer.init(base64PrivateKey:)` | Load a signer from a base64 raw private key. |
| `Ed25519Signer.base64PrivateKey` / `base64PublicKey` | The raw keys, base64-encoded. |
| `Ed25519Signer.sign(_:)` | Sign an attestation's canonical bytes; returns a signed copy. |
| `Ed25519Verifier.verify(_:expectedPublicKey:)` | Verify a record's signature; throws on failure. |
| `Ed25519Verifier.isValid(_:expectedPublicKey:)` | Non-throwing verification check. |
| `KeyStore.init(keyPath:)` / `defaultPath()` | Locate the on-disk key (`~/.config/attest/key`). |
| `KeyStore.generate(force:)` | Write a new `0600` private key and return its signer. |
| `KeyStore.load()` | Load the signer from disk; throws `keyNotFound` when absent. |

### Storage

| Export | Description |
|--------|-------------|
| `AttestationStore` | Protocol: `append(_:)`, `attestations(for:)`, `attestedCommits()`. |
| `NotesStore.init(path:)` | An `AttestationStore` backed by git notes under `refs/notes/attest`. |
| `NotesStore.validate()` | Confirm `path` is inside a git work tree. |
| `NotesStore.resolve(revision:)` | Resolve a revision (e.g. `HEAD`) to a full SHA. |
| `NotesStore.commits(inRange:)` | The commit SHAs in a range, oldest first. |
| `InMemoryStore` | A thread-safe in-memory `AttestationStore` for tests and dry runs. |
| `AttestationCodec.encodeLine(_:)` / `decodeLines(_:)` | JSON-Lines encode/decode for a note body. |

### Policy & Augur

| Export | Description |
|--------|-------------|
| `Policy.init(requireAttestation:requireHumanApprovalWhenVerdictAtLeast:requireTestsPassed:requireSignature:minimumConfidence:)` | Construct a gate; all rules optional with permissive defaults. |
| `Policy.default` | The default policy: require an attestation, nothing more. |
| `Policy.load(fromFile:)` | Load a policy from a `.attest.json` file. |
| `Verifier.init(policy:)` / `verify(commits:)` | Evaluate a policy over commits' attestations. |
| `AugurVerdict.parse(_:)` | Parse `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100`. |
| `Reporter.renderLog(_:)` / `renderVerification(_:)` | Human-readable terminal rendering. |

### Audit Export

| Export | Description |
|--------|-------------|
| `Exporter.init(store:)` | Construct the aggregator over an `AttestationStore`. |
| `Exporter.report(commits:policy:)` | Build an `AuditReport` over the given commits; with a `Policy`, include per-commit pass/fail. |
| `AuditReport.formatVersion` | The stable integer format version of the report document. |
| `AuditReport.jsonString(pretty:)` / `jsonData(pretty:)` | Stable, sorted-key JSON of the report (pretty by default). |
| `VerificationStatus.evaluate(_:)` | Compute a record's `signed` flag and (for signed records) whether it verifies. |

### Types & Enums

| Type | Description |
|------|-------------|
| `Attestation` | A signed-or-unsigned provenance record keyed to a commit SHA. |
| `Verdict` | `proceed`, `review`, or `block`; `Comparable`, mirroring augur. |
| `Policy` | Declarative gate decoded from `.attest.json`. |
| `Violation` | One reason a commit failed policy (`commit`, `rule`, `detail`). |
| `VerificationResult` | `passed`, `checkedCommits`, `violations`; emits stable JSON. |
| `AugurVerdict` | The `verdict` + derived `confidence` parsed from augur JSON. |
| `AttestError` | The error space: repository, git, parsing, key, and verification failures. |
| `AuditReport` | The complete provenance trail across a range as one stable, `Codable` document. |
| `AuditCommit` | One commit's `records` plus an optional `policyPassed`. |
| `AuditRecord` | An `Attestation` paired with its computed `VerificationStatus`. |
| `VerificationStatus` | A record's `signed` flag and (for signed records) `verified` result. |
| `Exporter` | Aggregates a range's attestations into an `AuditReport`. |

## Invariants

- `Attestation.confidence` is clamped to `0...1` at construction.
- `canonicalData()` excludes `signature` and `publicKey`; attaching a signature never
  changes the bytes being signed, so an unsigned record and its signed copy share canonical bytes.
- Canonical serialization is deterministic: identical content yields identical bytes
  (sorted keys, slashes unescaped), independent of field or platform order.
- A signature produced by `Ed25519Signer.sign` verifies via `Ed25519Verifier.verify`; any
  mutation of a signed record's content (other than the signature pair) fails verification.
- Multiple attestations per commit are permitted; stores append rather than replace.
- `Policy` decodes from JSON with permissive defaults: an empty `{}` policy still requires
  an attestation and passes any commit that has one.
- `AugurVerdict.parse` maps `riskScore` (0...100) to `confidence = 1 - riskScore/100`,
  clamped to `0...1`.
- `KeyStore.generate` writes the private key with `0600` permissions.
- `Attest.verify` passes only when there are zero violations across all checked commits.
- `Exporter.report` is deterministic: commits appear in the order supplied (the caller
  resolves the range with `NotesStore.commits(inRange:)`, oldest first, exactly as
  `verify`/`log` do — the exporter does no git walking of its own), records appear in store
  order (oldest first), and `AuditReport.jsonString` uses sorted keys, so identical inputs
  yield byte-identical JSON.
- A commit with no attestations is still represented in an `AuditReport` (empty `records`),
  so an audit covers the full surface of the range, not only attested commits.
- `VerificationStatus.evaluate` reuses `Ed25519Verifier`: an unsigned record is
  `{ signed: false }` with `verified` omitted; a signed record reports
  `verified: true` only when its embedded signature validates over its canonical bytes
  against its embedded public key, and `false` for any tampered content or key mismatch.
- `Exporter.report` includes a per-commit `policyPassed` and a top-level `allPassed` only
  when a `Policy` is supplied; both are omitted otherwise, and the policy evaluation reuses
  the same `Verifier` as `attest verify`.

## Behavioral Examples

- `attest sign --commit HEAD --reviewer agent:claude --confidence 0.92 --tests-passed`
  writes one unsigned attestation to `refs/notes/attest` for the resolved SHA.
- `augur check --json | attest sign --commit HEAD --from-augur -` records an attestation
  whose verdict and confidence are filled from augur's JSON (risk 45 → confidence 0.55).
- Signing the same attestation twice with the same key over identical content produces a
  signature that verifies, and tampering with any signed field fails verification.
- With `.attest.json` requiring `requireTestsPassed: true`, `attest verify --range A..B`
  exits non-zero for any commit lacking a passing-tests attestation, zero otherwise.
- `requireHumanApprovalWhenVerdictAtLeast: "review"` fails a `block`-verdict commit unless
  some attestation is `humanApproved`; a `proceed`-verdict commit is unaffected.
- `attest export --range A..B` emits one JSON `AuditReport` covering every commit in the
  range (oldest first), each attestation enriched with a `verification` status, suitable for
  compliance archival — distinct from `attest log`, which is a human/diagnostic listing.
- A signed attestation whose signature verifies exports `"verification": { "signed": true,
  "verified": true }`; a tampered or wrong-key signed record exports `"verified": false`; an
  unsigned record exports `"verification": { "signed": false }` (no `verified`).
- `attest export --range A..B --policy .attest.json` adds a per-commit `policyPassed` and a
  top-level `allPassed`, computed with the same `Verifier` as `attest verify`.

## Error Cases

- `AttestError.notARepository(path)` — `NotesStore.validate()` finds no git work tree.
- `AttestError.git(command:status:)` — an underlying `git` invocation exits non-zero.
- `AttestError.malformedRecord(detail)` — a stored note line is not valid attestation JSON.
- `AttestError.keyNotFound(path)` — signing requested but no key exists.
- `AttestError.keyAlreadyExists(path)` — `keygen` without `--force` over an existing key.
- `AttestError.invalidKey(detail)` — a base64 key is malformed or not a valid Ed25519 key.
- `AttestError.signatureMissing` — verification requested on an unsigned record.
- `AttestError.verificationFailed(reason:)` — key mismatch or signature/content mismatch.
- `AttestError.malformedAugurJSON(detail)` — augur input is not an object or lacks `riskScore`.

## Dependencies

- `git` available on `PATH` (the only runtime requirement for the git-notes store).
- `swift-crypto` (Apple) for Ed25519 signing/verification in `AttestKit`.
- `swift-argument-parser` (CLI target only).
- `augur` (optional) as the upstream source for `--from-augur`.

## Change Log

- v1: Initial provenance ledger — `Attestation` model with deterministic canonical
  serialization, optional Ed25519 signing/verification, git-notes `AttestationStore` with an
  in-memory fake, JSON `Policy` + `Verifier`, augur JSON ingestion, JSON/human reporters, and
  the `sign`/`verify`/`log`/`keygen` CLI.
- v2: Range-wide audit export — `Exporter` aggregates a range's attestations into a stable,
  `Codable` `AuditReport` (`AuditCommit` / `AuditRecord` / `VerificationStatus`), computing a
  per-record verification status with the existing `Ed25519Verifier` and an optional
  per-commit policy verdict via the existing `Verifier`. Adds the `attest export` CLI
  subcommand. Purely additive: no change to canonical serialization, signatures, storage, or
  any existing API.
