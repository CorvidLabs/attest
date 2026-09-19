---
hi: 1
families: [AUDIT]
---

# The record an auditor keeps

## Intent

A terminal listing is for a person looking at their own work right now; an audit is for somebody who was not there, years later. So there should be one document covering a whole range of commits, carrying every record, whether each signature actually holds, and what the policy made of each commit. It must be identical bytes for identical input so two exports diff cleanly and nobody has to trust a hand-edited summary. It should cover the full surface of the range, including the commits nothing was ever recorded against, because a gap is itself a finding.

## Criteria

- **AUDIT-1**  An auditor can get the whole trust trail for a range of commits as one file.
- **AUDIT-2**  The file covers every commit in the range, including the ones nothing was recorded against.
- **AUDIT-3**  Each record in the file says whether it was signed.
  - **AUDIT-3.a**  Each signed record says whether its signature holds up.
  - **AUDIT-3.b**  A tampered or wrong-key record is reported as not verified rather than quietly left out.
  - **AUDIT-3.c**  A record moved from another commit is never presented as a good signature.
- **AUDIT-4**  I can fold the policy's verdict into the same file, commit by commit.
  - **AUDIT-4.a**  The file also says whether the range as a whole cleared the policy.
- **AUDIT-5**  The same ledger always exports the same bytes, so two exports diff cleanly.
  - **AUDIT-5.a**  Commits appear oldest first.
  - **AUDIT-5.b**  Records appear in the order they were recorded.
- **AUDIT-6**  The document names its own format version, so a reader years later knows what they are holding.
- **AUDIT-7**  The document says how much it covers, so a truncated or trimmed copy is obvious.
- **AUDIT-8**  I can ask for a compact file when I am storing it rather than reading it.
- **AUDIT-9**  Exporting works without any policy file existing.
- **AUDIT-10**  Archiving the trail alongside a build's other artifacts is a single step.
