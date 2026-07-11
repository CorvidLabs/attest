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

## Done (v5)

- [x] `trustedKeys` policy rule — a set of trusted base64 Ed25519 keys; every signed attestation must verify and use a trusted key. Reuses `Ed25519Verifier`. Does not force signing (that stays with `requireSignature*`).
- [x] `signerPinning` policy rule — bind specific reviewers to specific public keys; a pinned reviewer must be signed with its pinned key and verify, stopping reviewer-string spoofing. Reuses `Ed25519Verifier(expectedPublicKey:)`.
- [x] Engine tests: trusted-key pass/fail, untrusted-but-valid signature, tampered signed record, unsigned interaction; pinned correct-key/wrong-key/unsigned/tampered, non-pinned reviewer unaffected, JSON decoding.
- [x] `examples/07-signer-pinning.sh` and README policy-table rows + "Preventing reviewer spoofing" subsection + spec v5 (Public API / Invariants / Behavioral Examples / Change Log).

## Done (v6)

- [x] `maxAgeDays` freshness policy rule — a commit must carry at least one attestation within `maxAgeDays` whole days of a reference time; stale-only or empty commits fail with a clear detail.
- [x] Injected clock: `now` parameter threaded through `Verifier.verify`, `Attest.verify`, and `Exporter.report` (defaulted to the current epoch at the CLI boundary) so evaluation never reads `Date()`.
- [x] Engine tests: fresh pass, stale fail, mixed (newest fresh) pass, not-triggered when nil, boundary (exactly / just over the limit), sub-day, future timestamp, no-attestations, injected-clock determinism, facade path, JSON decoding.
- [x] Expanded robustness suite (55 → 88 tests): canonical stability/unicode/empty-optionals/slashes, signature edge cases (empty/garbage/non-base64/reused key/invalid-length key), store multi-commit/blank-line/malformed-line/empty-body, exporter empty-range/mixed/aggregation/order/freshness.
- [x] `docs/` directory (architecture, policy, cli, signing, ci-integration) linked from the README; README policy-table row for `maxAgeDays`; spec v6 (Public API / Invariants / Behavioral Examples / Change Log).

## Next

- [x] `attest push` / `attest fetch` wrappers for safe `refs/notes/attest` synchronization.
- [ ] `attest verify --require-key <pub>` CLI flag (the policy now expresses key trust via `trustedKeys` / `signerPinning`; a per-invocation flag is still convenient).
- [ ] Linux/Windows CI matrix (core is macOS-targeted today).
- [ ] Optional revocation / supersede semantics for attestations.
