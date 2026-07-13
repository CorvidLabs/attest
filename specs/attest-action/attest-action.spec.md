---
module: attest-action
version: 3
status: stable
files:
  - action.yml
db_tables: []
depends_on: [provenance-ledger]
---

# Attest GitHub Action

## Purpose

Install a compatible Attest release, optionally forward reviewed provenance to a landed commit, and verify a commit range against a committed policy from a composite GitHub Action.

## Public API

| Export | Description |
| --- | --- |
| `name` | Marketplace action name. |
| `description` | Marketplace action description. |
| `author` | Marketplace publisher. |
| `branding` | Marketplace presentation. |
| `inputs` | Public action input map. |
| `outputs` | Public action output map. |
| `runs` | Composite action implementation. |
| `inputs.range` | Git range passed to `attest verify`. |
| `inputs.policy` | Policy path relative to the working directory. |
| `inputs.forward-from` | Optional reviewed source commit to forward. |
| `inputs.forward-to` | Destination commit for forwarded provenance. |
| `inputs.forward-reviewer` | Reviewer identity recorded during forwarding. |
| `inputs.forward-sign` | Whether forwarded provenance is signed. |
| `inputs.working-directory` | Governed repository directory. |
| `inputs.version` | Exact release tag or `latest` Attest release selector. |
| `outputs.binary` | Absolute path to the installed Attest executable. |

## Invariants

1. An explicit version wins; moving major-channel resolution applies only when the action itself is referenced by a major tag such as `@v1`.
2. A downloaded binary is checked against its published SHA-256 sidecar when one exists.
3. Missing compatible assets fall back to building from the action checkout, never the consumer repository.
4. Provenance forwarding occurs only when `forward-from` is non-empty and always precedes verification.
5. Installation, checksum, forwarding, and policy failures propagate as action failures.

## Behavioral Examples

```text
Given a full-history checkout and a committed .attest.json policy
When CorvidLabs/attest runs for origin/main..HEAD
Then it installs a compatible binary and verifies that range
And the binary output names the executable used
```

## Error Cases

| Error | Behavior |
| --- | --- |
| Requested release asset unavailable | Build from the action source when Swift is installed; otherwise fail. |
| Published checksum mismatch | Fail without executing the downloaded binary. |
| Provenance forwarding fails | Stop before policy verification. |
| Policy verification fails | Return a non-zero action result. |

## Dependencies

- GitHub CLI for release asset discovery and download.
- Git and Bash on the runner.
- Swift only for the unsupported-asset source-build fallback.
- The released Attest CLI contract in `provenance-ledger`.

## Change Log

| Version | Date | Changes |
| --- | --- | --- |
| 1 | 2026-07-12 | Stable Attest action contract. |
| 2026-07-13 | CHG-0002-document-the-released-attest-composite-action-contract: Document the released Attest composite action contract |
| 2026-07-13 | CHG-0002-document-the-released-attest-composite-action-contract: Document the released Attest composite action contract |
