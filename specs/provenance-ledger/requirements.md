# Requirements — Provenance Ledger

## Functional

- R1: Record an attestation (commit, reviewer, confidence, optional verdict, tests/human
  flags, timestamp, note) keyed to a git commit SHA.
- R2: Store attestations portably in git notes under `refs/notes/attest`, allowing multiple
  attestations per commit.
- R3: Optionally sign an attestation with Ed25519 over a deterministic canonical
  serialization that excludes the signature; verify signed records.
- R4: Ingest `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100`
  and copying the verdict.
- R5: Evaluate a JSON policy (`.attest.json`) over a commit range and report violations.
- R6: Provide a `verify` mode that exits non-zero on any policy violation (CI / agent gating).
- R7: Provide stable, sorted-key JSON output for agent consumption on every command.
- R8: Synchronize `refs/notes/attest` through non-forced push and merge-preserving fetch commands.

## Non-functional

- N1: Signing is optional — the tool is fully usable with no key and no policy file.
- N2: Canonical serialization is deterministic across platforms (sorted keys, unescaped slashes).
- N3: The engine is testable without invoking `git` via the `AttestationStore` protocol.
- N4: `AttestKit` depends only on Apple packages (`swift-crypto`); the CLI adds
  `swift-argument-parser`.
- N5: Private keys are written with `0600` permissions.
