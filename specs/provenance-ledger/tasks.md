# Tasks — Provenance Ledger

## Done (v1)

- [x] `Attestation` model with clamped confidence and an optional signature pair.
- [x] Deterministic canonical serialization excluding the signature, used for signing.
- [x] `Ed25519Signer` / `Ed25519Verifier` over swift-crypto; `KeyStore` at `~/.config/attest/key` (0600).
- [x] `AttestationStore` protocol with a git-notes implementation and an in-memory fake.
- [x] JSON-Lines note encoding so multiple attestations accrue per commit.
- [x] `Policy` (JSON) + `Verifier` with rules: attestation, tests, signature, confidence floor, conditional human approval.
- [x] `AugurVerdict` ingestion of `augur check --json`.
- [x] JSON and human reporters.
- [x] CLI: `sign` (with `--from-augur`), `verify`, `log`, `keygen`.
- [x] Unit tests over the engine with an in-memory store.

## Done (v2)

- [x] `Exporter` aggregating a range's attestations into a stable, `Codable` `AuditReport`.
- [x] `AuditCommit` / `AuditRecord` / `VerificationStatus` with per-record verification reuse of `Ed25519Verifier`.
- [x] Optional per-commit policy pass/fail in the report via the existing `Verifier`.
- [x] `attest export` CLI subcommand (`--range` / `--commit` / `--policy` / `--[no-]pretty`).
- [x] Engine tests: completeness, determinism, signed/tampered/wrong-key status, policy verdicts, JSON round-trip.
- [x] `examples/05-audit-export.sh` and README "Audit & compliance" section.

## Done (v4)

- [x] `allowedReviewers` policy rule — per-commit reviewer allow-list with exact + role-prefix (`"human:"`) matching.
- [x] `requireSignatureWhenVerdictAtLeast` — conditional `requireSignature` keyed to a verdict threshold; reuses `Ed25519Verifier`.
- [x] `requireTestsPassedWhenVerdictAtLeast` — conditional `requireTestsPassed` keyed to a verdict threshold.
- [x] Engine tests: pass/fail per rule, not-triggered-below-threshold for the conditional rules, prefix-vs-exact for the allow-list, JSON decoding.
- [x] `examples/06-policy-rules.sh` and README policy-table rows + spec v4 (Public API / Invariants / Behavioral Examples / Change Log).

## Next

- [ ] `attest push` / `attest fetch` wrappers for `refs/notes/attest` syncing.
- [ ] Multiple trusted public keys in the policy (beyond `allowedReviewers`, which gates the reviewer string, not the key).
- [ ] `attest verify --require-key <pub>` to pin an expected signer.
- [ ] Linux/Windows CI matrix (core is macOS-targeted today).
- [ ] Optional revocation / supersede semantics for attestations.
