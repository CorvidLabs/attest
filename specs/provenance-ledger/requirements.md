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

## Durable Requirements

### REQ-provenance-ledger-001

The implementation SHALL satisfy the following criterion: Record an attestation (commit, reviewer, confidence, optional verdict, tests/human flags, timestamp, note) keyed to a git commit SHA.

Acceptance Criteria

- Record an attestation (commit, reviewer, confidence, optional verdict, tests/human flags, timestamp, note) keyed to a git commit SHA.

### REQ-provenance-ledger-002

The implementation SHALL satisfy the following criterion: Store attestations portably in git notes under `refs/notes/attest`, allowing multiple attestations per commit.

Acceptance Criteria

- Store attestations portably in git notes under `refs/notes/attest`, allowing multiple attestations per commit.

### REQ-provenance-ledger-003

The implementation SHALL satisfy the following criterion: Optionally sign an attestation with Ed25519 over a deterministic canonical serialization that excludes the signature; verify signed records.

Acceptance Criteria

- Optionally sign an attestation with Ed25519 over a deterministic canonical serialization that excludes the signature; verify signed records.

### REQ-provenance-ledger-004

The implementation SHALL satisfy the following criterion: Ingest `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100` and copying the verdict.

Acceptance Criteria

- Ingest `augur check --json`, mapping `riskScore` to `confidence = 1 - riskScore/100` and copying the verdict.

### REQ-provenance-ledger-005

The implementation SHALL satisfy the following criterion: Evaluate a JSON policy (`.attest.json`) over a commit range and report violations.

Acceptance Criteria

- Evaluate a JSON policy (`.attest.json`) over a commit range and report violations.

### REQ-provenance-ledger-006

The implementation SHALL satisfy the following criterion: Provide a `verify` mode that exits non-zero on any policy violation (CI / agent gating).

Acceptance Criteria

- Provide a `verify` mode that exits non-zero on any policy violation (CI / agent gating).

### REQ-provenance-ledger-007

The implementation SHALL satisfy the following criterion: Provide stable, sorted-key JSON output for agent consumption on every command.

Acceptance Criteria

- Provide stable, sorted-key JSON output for agent consumption on every command.

### REQ-provenance-ledger-008

The implementation SHALL satisfy the following criterion: Synchronize `refs/notes/attest` through non-forced push and merge-preserving fetch commands.

Acceptance Criteria

- Synchronize `refs/notes/attest` through non-forced push and merge-preserving fetch commands.

### REQ-provenance-ledger-009

The implementation SHALL satisfy the following criterion: Signing is optional — the tool is fully usable with no key and no policy file.

Acceptance Criteria

- Signing is optional — the tool is fully usable with no key and no policy file.

### REQ-provenance-ledger-010

The implementation SHALL satisfy the following criterion: Canonical serialization is deterministic across platforms (sorted keys, unescaped slashes).

Acceptance Criteria

- Canonical serialization is deterministic across platforms (sorted keys, unescaped slashes).

### REQ-provenance-ledger-011

The implementation SHALL satisfy the following criterion: The engine is testable without invoking `git` via the `AttestationStore` protocol.

Acceptance Criteria

- The engine is testable without invoking `git` via the `AttestationStore` protocol.

### REQ-provenance-ledger-012

The implementation SHALL satisfy the following criterion: `AttestKit` depends only on Apple packages (`swift-crypto`); the CLI adds `swift-argument-parser`.

Acceptance Criteria

- `AttestKit` depends only on Apple packages (`swift-crypto`); the CLI adds `swift-argument-parser`.

### REQ-provenance-ledger-013

The implementation SHALL satisfy the following criterion: Private keys are written with `0600` permissions.

Acceptance Criteria

- Private keys are written with `0600` permissions.
