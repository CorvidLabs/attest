---
change: CHG-0002-document-the-released-attest-composite-action-contract
artifact: research
---

# Research

`action.yml` is a Bash composite action. The current `smoke-test-action` matrix dogfoods `uses: ./` on macOS and Ubuntu, checks the emitted executable, and covers both universal macOS and Linux release assets while preserving source-build fallback.
