---
hi: 1
families: [RECORD]
---

# Writing down who vetted a change

## Intent

The moment a human or an agent actually looks at a change, that fact should be writable down in one breath, against the exact commit it is about. Recording should need no key, no account, no policy file and no service, because a tool that demands setup before it is useful gets skipped on the day it matters. A record should capture only what people genuinely argue about later: who reviewed, how sure they were, what they concluded, whether the tests passed, whether a human put their name on it, and anything worth saying in prose. When a risk scorer has already done the work, its verdict should flow straight in rather than being retyped.

## Criteria

- **RECORD-1**  I can record who vetted a commit with a single command.
  - **RECORD-1.a**  Recording needs no key, no account, no policy file and no service beforehand.
  - **RECORD-1.b**  The record is keyed to an exact commit, never to a branch or a tag that can move under it.
  - **RECORD-1.c**  I can attest any commit I can name, not only the one I have checked out.
- **RECORD-2**  A record names the reviewer in my own vocabulary, like human:leif or agent:claude.
- **RECORD-3**  A record carries how confident that reviewer was.
  - **RECORD-3.a**  A confidence outside the allowed range is refused as I type it rather than quietly rounded into range.
  - **RECORD-3.b**  A command that leaves attest nothing to derive a confidence from is refused.
  - **RECORD-3.c**  A refusal over a missing confidence names the ways I could have supplied one.
- **RECORD-4**  A record can carry a verdict of proceed, review or block.
  - **RECORD-4.a**  A verdict I mistyped is refused rather than stored as I wrote it.
  - **RECORD-4.b**  A refused verdict has the three real ones named back to me.
- **RECORD-5**  A record can state that the change's tests passed.
- **RECORD-6**  A record can state that a human approved the change.
  - **RECORD-6.a**  A bare human sign-off counts as full confidence without my having to invent a number for it.
- **RECORD-7**  A record can carry a free-text note saying what was actually looked at.
- **RECORD-8**  A record carries the moment it was made, so how fresh it is can be judged later.
- **RECORD-9**  Several reviewers can each record their own view of one commit without overwriting each other.
- **RECORD-10**  I can pipe a risk scorer's report straight in instead of retyping its findings.
  - **RECORD-10.a**  The verdict in that report becomes the verdict on the record.
  - **RECORD-10.b**  A higher risk score becomes a lower recorded confidence.
  - **RECORD-10.c**  Anything I state myself wins over what the risk report suggested.
  - **RECORD-10.d**  Risk input that is not the shape attest expects is refused with the reason.
- **RECORD-11**  Recording answers with one line naming the reviewer, the commit and whether it was signed.
  - **RECORD-11.a**  An agent can have the stored record back as data instead of that line.
