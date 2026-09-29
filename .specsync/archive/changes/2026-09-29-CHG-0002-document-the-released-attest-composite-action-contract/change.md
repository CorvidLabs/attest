---
id: CHG-0002-document-the-released-attest-composite-action-contract
state: archived
type: documentation
base_commit: a738ac9f76e5c389ca9a43d46f4ebba3ee4f650e
---

# Document the released Attest composite action contract

## Intent

Document the released Attest composite action contract

## Affected Canonical Specs

- `attest-action`

## Acceptance Criteria

- The canonical companion documents action inputs, binary installation and checksum behavior, forwarding semantics, verification, output, failure behavior, and OS coverage; direct CI evidence validates the composite action on macOS and Linux; strict SpecSync coverage remains 100%.

## No-spec Rationale

Not applicable

## Migration Note

Migrated by hand to SpecSync 6 per Leif's decision (2026-09-28); the 6.0.0 tool refused to archive this legacy record (`` exact-only delivery input `.github/workflows/ci.yml` changed after acceptance and requires an audited reopen; run `specsync change reopen CHG-0002-document-the-released-attest-composite-action-contract` to re-verify the accepted change, or supersede it from a later change under a module granted the path by `owns` in `.specsync/config.toml` ``).

- Workflow v1 (SpecSync 5) record, accepted on 2026-07-13 by the closing approval already stored in `approvals.json`. SpecSync 6.0.0 reports its accepted evidence as stale, for the reason quoted above.
- Moved by hand from `.specsync/changes/CHG-0002-document-the-released-attest-composite-action-contract/` into the layout `specsync change archive` writes: `accepted-state.json` is the unchanged accepted `state.json`, `state.json` is marked `archived`, and this file's front matter says `archived`.
- `approvals.json`, `verification.json` and every other artifact are the original SpecSync 5 evidence, unchanged. `verification.json` verifies commit `12fb30ffb307e31bd446f00e6a5109b00bbf3cab`, not the tree this record was archived from.
- There is no `verification-attempts.json`: SpecSync 5 did not write one for this record, and this migration does not invent attempt history.
- This migration added no verification evidence, test result, attempt history, or approval. It is a manual migration, not a fresh re-verification.
- Closing it through the tool takes `specsync change reopen`, `specsync change verify`, then `specsync change accept`, which writes a new closing approval. Per Leif's decision it was archived by hand instead, so no reopen or new approval is recorded.
