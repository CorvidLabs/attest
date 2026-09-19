---
hi: 1
families: [FORWARD]
---

# When the commit that lands is not the one reviewed

## Intent

Squash merges destroy the commit that was actually reviewed, and attest refuses to paper over that by loosening what a match means. Instead, somebody forwards the provenance: a fresh, signed-if-you-like statement recorded against the commit that really landed, pointing back at the one that was really reviewed. That keeps verification exact while letting a protected-branch workflow stay honest. The forwarding actor is named on the record, so a policy gets to decide whether their word is worth anything.

## Criteria

- **FORWARD-1**  I can carry the provenance of a reviewed commit onto the commit that actually landed.
- **FORWARD-2**  Forwarding records a new statement about the landed commit instead of relocating the old record.
- **FORWARD-3**  The forwarded record keeps the source commit and the source reviewers in it, so an auditor can trace it back.
- **FORWARD-4**  The forwarded record inherits the strength of what it came from.
  - **FORWARD-4.a**  It carries the highest confidence found on the source.
  - **FORWARD-4.b**  It carries the most serious verdict found on the source.
  - **FORWARD-4.c**  It carries a passing-tests signal when the source had one.
  - **FORWARD-4.d**  It carries a human-approval signal when the source had one.
- **FORWARD-5**  Source records whose signatures do not hold up are thrown away, so a tampered record cannot be laundered into a fresh one.
- **FORWARD-6**  Forwarding from a commit with nothing recorded on it fails rather than inventing trust.
- **FORWARD-7**  Whoever did the forwarding is named on the record, so a policy can decide whether to trust them.
  - **FORWARD-7.a**  The forwarding actor can sign their statement.
- **FORWARD-8**  Verification stays exact, so no rule ever accepts a different commit merely because its contents look alike.
