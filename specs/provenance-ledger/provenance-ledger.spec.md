---
module: provenance-ledger
version: 8
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
  - Sources/AttestKit/ANSI.swift
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
| `Attest.verify(commits:policy:now:)` | Check commits' attestations against a `Policy`, returning a `VerificationResult`. `now` (Unix epoch seconds) is the injected reference time for the `maxAgeDays` freshness rule; defaults to the current epoch. |

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
| `Policy.init(requireAttestation:requireHumanApprovalWhenVerdictAtLeast:requireTestsPassed:requireSignature:minimumConfidence:allowedReviewers:requireSignatureWhenVerdictAtLeast:requireTestsPassedWhenVerdictAtLeast:trustedKeys:signerPinning:maxAgeDays:)` | Construct a gate; all rules optional with permissive defaults. |
| `Policy.allowedReviewers` | When set, every attestation on a commit must have a `reviewer` matching one of the patterns (exact, or role-prefix when the pattern ends with `:`). |
| `Policy.requireSignatureWhenVerdictAtLeast` | When any attestation's verdict is at/above this level, require at least one *valid signed* attestation on the commit. |
| `Policy.requireTestsPassedWhenVerdictAtLeast` | When any attestation's verdict is at/above this level, require at least one attestation with `testsPassed == true` on the commit. |
| `Policy.trustedKeys` | When set (non-empty), every *signed* attestation on a commit must verify and carry a `publicKey` in this list of trusted base64 Ed25519 keys; untrusted or invalid signed records fail. Unsigned records are unaffected (governed by `requireSignature*`). |
| `Policy.signerPinning` | When set (non-empty), any attestation whose `reviewer` is a key in this `[reviewer: base64 pubkey]` map must be signed with the pinned key and verify; a pinned reviewer signed with a different key or left unsigned fails. Stops reviewer spoofing. |
| `Policy.maxAgeDays` | When set, the commit must carry at least one attestation whose `timestamp` is within `maxAgeDays` whole days of an injected reference time (`now`); a commit whose newest attestation is older, or which has none, fails. `nil` disables the rule. |
| `Policy.default` | The default policy: require an attestation, nothing more. |
| `Policy.load(fromFile:)` | Load a policy from a `.attest.json` file. |
| `Verifier.init(policy:)` / `verify(commits:now:)` | Evaluate a policy over commits' attestations; `now` (Unix epoch seconds, defaulting to the current epoch) is the injected clock for the `maxAgeDays` freshness rule. |
| `AugurVerdict.parse(_:)` | Parse `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100`. |
| `Reporter.renderLog(_:colorizer:)` / `renderVerification(_:colorizer:)` | Human-readable terminal rendering. `colorizer` defaults to `.plain` (byte-identical, unstyled output); pass an enabled `Colorizer` for semantic ANSI colour. |

### Audit Export

| Export | Description |
|--------|-------------|
| `Exporter.init(store:)` | Construct the aggregator over an `AttestationStore`. |
| `Exporter.report(commits:policy:now:)` | Build an `AuditReport` over the given commits; with a `Policy`, include per-commit pass/fail. `now` (Unix epoch seconds, defaulting to the current epoch) is the injected clock for the policy's `maxAgeDays` freshness rule. |
| `AuditReport.formatVersion` | The stable integer format version of the report document. |
| `AuditReport.jsonString(pretty:)` / `jsonData(pretty:)` | Stable, sorted-key JSON of the report (pretty by default). |
| `VerificationStatus.evaluate(_:)` | Compute a record's `signed` flag and (for signed records) whether it verifies. |
| `VerificationStatus.evaluate(_:noteKey:)` | As above, but bound to the commit the record is filed under: a record whose inner `commit` differs from `noteKey` reports `commitMatches == false` and is never `verified == true`. |

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
| `VerificationStatus` | A record's `signed` flag, (for signed records) `verified` result, and `commitMatches` flag (whether the record names the commit it is filed under). |
| `Exporter` | Aggregates a range's attestations into an `AuditReport`. |
| `ANSIColor` | The SGR codes (`red`/`amber`/`green`/`cyan`/`dim`/`bold`/`reset`) used for terminal styling. |
| `Colorizer` | Wraps strings in ANSI codes when `enabled`; `.plain` is a pass-through gate for non-TTY/`--json` output. |

## Invariants

- `Attestation.confidence` is clamped to `0...1` at construction.
- `canonicalData()` excludes `signature` and `publicKey`; attaching a signature never
  changes the bytes being signed, so an unsigned record and its signed copy share canonical bytes.
- Canonical serialization is deterministic: identical content yields identical bytes
  (sorted keys, slashes unescaped), independent of field or platform order.
- A signature produced by `Ed25519Signer.sign` verifies via `Ed25519Verifier.verify`; any
  mutation of a signed record's content (other than the signature pair) fails verification.
- Multiple attestations per commit are permitted; stores append rather than replace.
- **Commit binding.** Each attestation is bound to the commit it is filed against (the git-note key
  it is stored under). Before any policy rule runs, `Verifier.evaluate` discards every attestation
  whose inner `commit` does not equal the commit being evaluated. The canonical bytes include the
  inner `commit`, so a signature is bound to that commit, but nothing in git prevents a holder of
  write access to `refs/notes/attest` from copying a legitimately signed record off commit A and
  filing it verbatim under commit B (its signature still validates over A's unchanged bytes). The
  verifier therefore treats a relocated record as absent: a commit whose only record names a
  different commit fails `requireAttestation`, `requireSignature`, `minimumConfidence`, and every
  other evidence-requiring rule, so a signed attestation cannot be replayed onto another commit even
  against a strict policy. This needs no change to the canonical serialization or the signature
  format. In the audit export, `VerificationStatus.evaluate(_:noteKey:)` reports a relocated record
  as `commitMatches == false` and never `verified == true`, and `attest log` renders it as
  `commit-mismatch` (not `signed[ok]`), warns on stderr, and exits non-zero.
- `requireHumanApprovalWhenVerdictAtLeast` is evaluated across all of a commit's
  attestations as a set: it triggers when any attestation's verdict is at or above the
  threshold, and is satisfied when any attestation on the commit is `humanApproved`. The
  triggering verdict and the human sign-off need not be the same record.
- `allowedReviewers`, when non-`nil` and non-empty, is an allow-list: *every* attestation on
  the commit must match at least one pattern, or the commit fails. A pattern matches a
  reviewer exactly, or — when the pattern ends with `:` (a role prefix such as `"human:"`) —
  when the reviewer begins with that prefix (so `"human:"` allows any `human:*`, while
  `"agent:claude"` matches only exactly). A `nil` or empty list disables the rule.
- `requireSignatureWhenVerdictAtLeast` and `requireTestsPassedWhenVerdictAtLeast` mirror the
  set-evaluation semantics of `requireHumanApprovalWhenVerdictAtLeast`: each triggers when
  *any* attestation on the commit carries a verdict at or above the threshold, and is
  satisfied by *any* qualifying attestation anywhere on the commit (a valid signature, or
  `testsPassed == true`, respectively) — not necessarily the record carrying the high
  verdict. Neither triggers when no attestation reaches the threshold.
  `requireSignatureWhenVerdictAtLeast` reuses the existing `Ed25519Verifier`.
- `trustedKeys`, when non-`nil` and non-empty, constrains *which signing keys count as trusted*:
  every attestation that is signed (carries both `signature` and `publicKey`) must verify against
  its embedded key via the existing `Ed25519Verifier` **and** that `publicKey` must be a member of
  `trustedKeys`; a signed record whose key is absent from the set, or whose signature does not
  validate (tampered content or key mismatch), fails the commit. Crucially, `trustedKeys` does
  **not** force signing — an unsigned attestation is untouched by this rule, because *whether*
  signing is required is the job of the separate `requireSignature` / `requireSignatureWhenVerdictAtLeast`
  rules. Composing `trustedKeys` with `requireSignature` (or its conditional form) is how a policy
  both demands a signature and restricts it to a trusted key. A `nil` or empty list disables the rule.
- `signerPinning`, when non-`nil` and non-empty, binds identity to a key: for any attestation
  whose `reviewer` is a key in the `[reviewer: base64 publicKey]` map, the record must be signed
  with that exact pinned public key and the signature must verify (reusing
  `Ed25519Verifier.verify(_:expectedPublicKey:)`); a pinned reviewer that is unsigned, signed with a
  different key, or signed but tampered fails the commit. Reviewers absent from the map are
  unaffected. This is the rule that actually stops a spoofed `reviewer: human:leif`, which
  `allowedReviewers` (a string gate) cannot. A `nil` or empty map disables the rule.
- `maxAgeDays`, when non-`nil`, is a freshness gate: the commit passes only when at least one of
  its attestations is recent. An attestation's age is the whole-day quotient
  `(now - timestamp) / 86400` (integer division on Unix epoch seconds), and the rule uses the
  *newest* attestation (smallest age), so a single fresh record clears a commit even when older
  records are also present. The commit fails when that newest age is strictly greater than
  `maxAgeDays`, with the detail `"newest attestation is N days old, exceeds maxAgeDays=M"`. A commit
  with no attestations cannot satisfy freshness and fails with `"no attestation exists to satisfy
  maxAgeDays=M"`. A timestamp at or in the future yields a non-positive age and is always within the
  window; a sub-day difference rounds down to `0` days. Crucially, the reference time `now` is
  **injected** into `Verifier.verify(commits:now:)` (threaded through `Attest.verify` and
  `Exporter.report`) rather than read from the system clock inside the evaluation logic, so
  verification is deterministic and testable; the CLI supplies the current epoch at its boundary.
  A `nil` value disables the rule.
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
  The note-key form `VerificationStatus.evaluate(_:noteKey:)` additionally sets
  `commitMatches` to whether the record's inner `commit` equals `noteKey`; a relocated record
  (`commitMatches == false`) is never `verified == true`. The `commitMatches` field is encoded
  only when `false`, so a matching record's exported JSON is byte-identical to the prior shape.
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
- `requireHumanApprovalWhenVerdictAtLeast: "review"` fails a commit that has any
  attestation with a verdict at or above `review` (e.g. `review` or `block`) unless *some*
  attestation on that commit is `humanApproved`. The human sign-off may be a separate
  attestation that does not restate the verdict: an agent record `verdict:review,
  humanApproved:false` plus a human record `humanApproved:true` (verdict `nil`) on the same
  commit passes. A commit whose verdicts are all below the threshold is unaffected.
- `allowedReviewers: ["human:", "agent:claude"]` passes a commit whose reviewers are
  `human:leif` (prefix match) and `agent:claude` (exact match), but fails a commit with an
  `agent:gpt` attestation (exact-only pattern, no match).
- `requireSignatureWhenVerdictAtLeast: "review"` fails a commit that has any attestation with
  a verdict at or above `review` unless *some* attestation on that commit is validly signed;
  a separate signed `human:leif` record (verdict `nil`) clears an agent's unsigned `block`
  verdict. A commit whose verdicts are all below the threshold is unaffected.
- `requireTestsPassedWhenVerdictAtLeast: "review"` fails a commit with a verdict at or above
  `review` unless *some* attestation on that commit reports `testsPassed: true` (which may be
  a separate CI record). A commit whose verdicts are all below the threshold is unaffected.
- `trustedKeys: ["<base64 pubkey>"]` passes a commit whose signed attestation verifies against a
  key in the list, but fails one whose signed attestation uses a key not in the list (even when that
  signature is itself cryptographically valid) or whose signature is tampered. An *unsigned*
  attestation on the same commit is unaffected — `trustedKeys` alone does not force signing; pair it
  with `requireSignature: true` to both require a signature and pin it to a trusted key.
- `signerPinning: { "human:leif": "<leif's base64 pubkey>" }` passes an attestation
  `reviewer:human:leif` signed with leif's pinned key, but fails one claiming `reviewer:human:leif`
  that is unsigned or signed with a different key — closing the spoof that `allowedReviewers`
  (a string-only gate) leaves open. An attestation by `agent:claude` (a reviewer not in the map) is
  unaffected and passes whether signed or not.
- `maxAgeDays: 30` passes a commit whose newest attestation was recorded within 30 days of the
  reference `now` (e.g. 10 days ago, or exactly 30 days ago — age at the limit is within the window),
  but fails one whose newest attestation is 31+ days old with `"newest attestation is 31 days old,
  exceeds maxAgeDays=30"`. A commit with a mix of stale and fresh records passes on the fresh one. A
  commit with no attestations fails with `"no attestation exists to satisfy maxAgeDays=30"`. Because
  `now` is injected, the same attestation verifies fresh at one supplied `now` and stale at a later
  one — the rule never reads the wall clock during evaluation.
- `attest export --range A..B` emits one JSON `AuditReport` covering every commit in the
  range (oldest first), each attestation enriched with a `verification` status, suitable for
  compliance archival — distinct from `attest log`, which is a human/diagnostic listing.
- A signed attestation whose signature verifies exports `"verification": { "signed": true,
  "verified": true }`; a tampered or wrong-key signed record exports `"verified": false`; an
  unsigned record exports `"verification": { "signed": false }` (no `verified`).
- `attest export --range A..B --policy .attest.json` adds a per-commit `policyPassed` and a
  top-level `allPassed`, computed with the same `Verifier` as `attest verify`.
- A signed attestation for commit A copied verbatim onto commit B's note (a cross-commit replay)
  no longer passes B's policy: `attest verify --commit B` with a strict policy
  (`requireSignature` + `trustedKeys` + `minimumConfidence`) exits non-zero, because the verifier
  discards the relocated record before any rule runs. `attest export` marks the record
  `"commitMatches": false` / `"verified": false`, and `attest log` renders it `commit-mismatch`
  with a stderr warning and a non-zero exit. The same record on its own commit A still passes.

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
- v3: Corrected `requireHumanApprovalWhenVerdictAtLeast` semantics. The rule now evaluates a
  commit's attestations as a set: it is satisfied when *any* attestation on the commit is
  `humanApproved`, rather than requiring the human approval to live on the same record that
  carries the high verdict. This lets a human file a separate `--human-approved` attestation
  (without restating the verdict) to clear an agent's `review`/`block` verdict, fixing a
  footgun where a legitimate separate sign-off was rejected. No API, schema, or canonical
  serialization change; only the `Verifier` evaluation and the violation message wording.
- v4: Three additional, optional policy rules (all permissive-default off, decoded with
  `decodeIfPresent`, purely additive — no canonical serialization, signature, or storage
  change). `allowedReviewers: [String]` is a per-commit reviewer allow-list with exact and
  role-prefix (`"human:"`) matching. `requireSignatureWhenVerdictAtLeast: Verdict` and
  `requireTestsPassedWhenVerdictAtLeast: Verdict` are conditional forms of `requireSignature`
  / `requireTestsPassed` that trigger only when a commit's verdict reaches the threshold,
  mirroring `requireHumanApprovalWhenVerdictAtLeast`'s set-evaluation semantics (satisfied by
  any qualifying attestation on the commit). The signature rule reuses `Ed25519Verifier`.
- v5: Two related signer-pinning policy rules (both permissive-default off, decoded with
  `decodeIfPresent`, purely additive — no canonical serialization, signature, or storage change),
  closing the gap where `allowedReviewers` gates the reviewer *string* but not the *key*, letting
  anyone file `reviewer: human:leif`. `trustedKeys: [String]` is a set of trusted base64 Ed25519
  public keys: every *signed* attestation must verify and use a trusted key (untrusted/invalid
  signed records fail), while unsigned records stay governed by the `requireSignature*` rules —
  `trustedKeys` constrains *which keys count as trusted*, it does not force signing.
  `signerPinning: [String: String]` binds specific reviewers to specific public keys: a pinned
  reviewer must be signed with its pinned key and verify, so an unsigned or wrong-key claim to a
  pinned reviewer fails — this is what actually stops reviewer spoofing. Both rules reuse the
  existing `Ed25519Verifier` (`signerPinning` via the `expectedPublicKey` parameter).
- v6: One additional, optional freshness policy rule (permissive-default off, decoded with
  `decodeIfPresent`, purely additive — no canonical serialization, signature, or storage change).
  `maxAgeDays: Int` requires a commit to carry at least one attestation within `maxAgeDays` whole
  days of a reference "now"; a commit whose newest attestation is older, or which has none, fails
  with a clear detail. The reference time is **injected** as a new `now` parameter on
  `Verifier.verify(commits:now:)`, `Attest.verify(commits:policy:now:)`, and
  `Exporter.report(commits:policy:now:)` (all defaulting to the current epoch at the CLI boundary)
  rather than read from the system clock inside the evaluation logic, keeping verification
  deterministic and testable. Adding the `now` parameter is source-compatible (defaulted); all other
  rules ignore it.
- v7: Optional semantic ANSI colour for the human-readable reporters (purely additive — no change to
  canonical serialization, signatures, storage, JSON output, or any policy rule). Adds a
  dependency-free `Colorizer` (gated by an `enabled: Bool`) and `ANSIColor` SGR codes in `ANSI.swift`,
  built only from Foundation strings (no new dependency). `Reporter.renderLog`/`renderVerification`
  gain a `colorizer:` parameter defaulting to `.plain`, so all existing call sites and tests stay
  byte-identical. Colour is **semantic**, not a brand hue: verify PASS is bold green / FAIL bold red,
  violations red with an amber header; in the ledger, `proceed`/`review`/`block` and confidence tint
  green/amber/red, reviewers are cyan, valid signatures and `human:ok`/`tests:ok` green, and
  unsigned/secondary text is dim. The CLI's `log`/`verify` subcommands add a `--color auto|always|never`
  option (default `auto`): `auto` enables colour only when stdout is a TTY and `NO_COLOR` is unset
  (https://no-color.org); `--json` and piped/non-TTY output stay plain. `export` is unchanged (always JSON).
- v8: Commit binding, closing a cross-commit signature replay (no change to canonical serialization
  or the signature format). Because the canonical bytes include the inner `commit`, a signature is
  bound to the commit it names, but nothing checked that an attestation's inner `commit` equalled the
  git-note key it was stored under, so a legitimately signed record could be copied verbatim off
  commit A onto commit B and still validate as evidence for B. `Verifier.evaluate` now discards every
  attestation whose inner `commit` differs from the commit being evaluated *before* any rule runs, so
  a relocated record is treated as absent and a commit whose only record was transplanted fails
  `requireAttestation` and every other evidence rule. The audit export gains
  `VerificationStatus.evaluate(_:noteKey:)` and a `commitMatches` field (emitted only when `false`, so
  a matching record's JSON is byte-identical to before); a relocated record reports
  `commitMatches: false` and never `verified: true`. `attest log` renders a relocated record as
  `commit-mismatch` (not `signed[ok]`), warns on stderr, and exits non-zero. Source-compatible and
  additive: existing `VerificationStatus.evaluate(_:)` and all other APIs are unchanged.
