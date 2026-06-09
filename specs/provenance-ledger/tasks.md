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

## Next

- [ ] `attest push` / `attest fetch` wrappers for `refs/notes/attest` syncing.
- [ ] Multiple trusted public keys / a signer allow-list in the policy.
- [ ] `attest verify --require-key <pub>` to pin an expected signer.
- [ ] Linux/Windows CI matrix (core is macOS-targeted today).
- [ ] Optional revocation / supersede semantics for attestations.
