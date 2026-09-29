## MODIFIED

### REQUIREMENT REQ-attest-action-001

The Attest action SHALL install a compatible requested release and verify its published checksum when a checksum sidecar is available.

Acceptance Criteria

- Supported macOS and Linux runners receive executable binaries, while unsupported assets fall back to a source build when Swift is available.

### REQUIREMENT REQ-attest-action-002

The Attest action SHALL optionally forward provenance before verifying the configured commit range against the configured policy.

Acceptance Criteria

- Forwarding arguments are applied only when `forward-from` is non-empty, and verification always uses the configured range and policy.

### REQUIREMENT REQ-attest-action-003

The Attest action SHALL expose the installed binary path and fail closed when installation, checksum verification, forwarding, or policy verification fails.

Acceptance Criteria

- The `binary` output names an executable, and fatal action paths return a non-zero status.
