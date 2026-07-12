# Requirements — Provenance Ledger

## Functional

### REQ-provenance-ledger-001

Attest SHALL ensure the following: Record an attestation (commit, reviewer, confidence, optional verdict, tests/human flags, timestamp, note) keyed to a git commit SHA.

Acceptance Criteria

- Record an attestation (commit, reviewer, confidence, optional verdict, tests/human
  flags, timestamp, note) keyed to a git commit SHA.
### REQ-provenance-ledger-002

Attest SHALL ensure the following: Store attestations portably in git notes under `refs/notes/attest`, allowing multiple attestations per commit.

Acceptance Criteria

- Store attestations portably in git notes under `refs/notes/attest`, allowing multiple
  attestations per commit.
### REQ-provenance-ledger-003

Attest SHALL ensure the following: Optionally sign an attestation with Ed25519 over a deterministic canonical serialization that excludes the signature; verify signed records.

Acceptance Criteria

- Optionally sign an attestation with Ed25519 over a deterministic canonical
  serialization that excludes the signature; verify signed records.
### REQ-provenance-ledger-004

Attest SHALL ensure the following: Ingest `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100` and copying the verdict.

Acceptance Criteria

- Ingest `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100`
  and copying the verdict.
### REQ-provenance-ledger-005

Attest SHALL ensure the following: Evaluate a JSON policy (`.attest.json`) over a commit range and report violations.

Acceptance Criteria

- Evaluate a JSON policy (`.attest.json`) over a commit range and report violations.
### REQ-provenance-ledger-006

Attest SHALL ensure the following: Provide a `verify` mode that exits non-zero on any policy violation (CI / agent gating).

Acceptance Criteria

- Provide a `verify` mode that exits non-zero on any policy violation (CI / agent gating).
### REQ-provenance-ledger-007

Attest SHALL ensure the following: Provide stable, sorted-key JSON output for agent consumption on every command.

Acceptance Criteria

- Provide stable, sorted-key JSON output for agent consumption on every command.
### REQ-provenance-ledger-008

Attest SHALL ensure the following: Synchronize `refs/notes/attest` through non-forced push and merge-preserving fetch commands.

Acceptance Criteria

- Synchronize `refs/notes/attest` through non-forced push and merge-preserving fetch commands.

## Non-functional

### REQ-provenance-ledger-009

Attest SHALL ensure the following: Signing is optional — the tool is fully usable with no key and no policy file.

Acceptance Criteria

- Signing is optional — the tool is fully usable with no key and no policy file.
### REQ-provenance-ledger-010

Attest SHALL ensure the following: Canonical serialization is deterministic across platforms (sorted keys, unescaped slashes).

Acceptance Criteria

- Canonical serialization is deterministic across platforms (sorted keys, unescaped slashes).
### REQ-provenance-ledger-011

Attest SHALL ensure the following: The engine is testable without invoking `git` via the `AttestationStore` protocol.

Acceptance Criteria

- The engine is testable without invoking `git` via the `AttestationStore` protocol.
### REQ-provenance-ledger-012

Attest SHALL ensure the following: `AttestKit` depends only on Apple packages (`swift-crypto`); the CLI adds `swift-argument-parser`.

Acceptance Criteria

- `AttestKit` depends only on Apple packages (`swift-crypto`); the CLI adds
  `swift-argument-parser`.
### REQ-provenance-ledger-013

Attest SHALL ensure the following: Private keys are written with `0600` permissions.

Acceptance Criteria

- Private keys are written with `0600` permissions.
