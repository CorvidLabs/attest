---
change: CHG-0002-document-the-released-attest-composite-action-contract
artifact: requirements
---

# Requirements

- The action installs the requested compatible Attest binary and verifies published checksums when available.
- The action may forward provenance before verifying the configured range and policy.
- The action exposes the installed binary and fails on installation, checksum, forwarding, or verification errors.
- The action is exercised on its supported macOS and Linux hosted runners.
