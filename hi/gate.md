---
hi: 1
families: [GATE]
---

# The gate CI and agents run into

## Intent

One command exists purely to answer yes or no, and its answer has to be usable by something that cannot read prose. The exit code is the contract: zero when the trust a policy demands is present, non-zero the moment it is not, with no flag to soften it into advice. When it says no it must name the commit, the rule and the reason in a sentence, so the next move is obvious: fix it, get it reviewed, or hand it to a human. An agent that hits this gate should escalate rather than merge blind.

## Criteria

- **GATE-1**  One command tells me whether a commit carries the trust my policy demands.
- **GATE-2**  The answer is an exit code, so a CI job or an agent loop can gate on it without parsing anything.
  - **GATE-2.a**  Every commit clearing the bar exits happily.
  - **GATE-2.b**  Any violation exits unhappily.
  - **GATE-2.c**  A problem that is not a policy violation, such as a bad argument or an unreadable repo, is distinguishable from a violation.
- **GATE-3**  A failure names each commit, the rule it broke, and why, in a sentence I can act on.
- **GATE-4**  I can check one commit, a range, or just whatever I have checked out.
- **GATE-5**  An agent can get the same verdict as data instead of a report.
- **GATE-6**  A passing run says how many commits it checked, so I know it did not silently check nothing.
- **GATE-7**  An agent that fails the gate escalates to a human instead of merging blind.
- **GATE-8**  The gate fails a job outright, with no flag that softens it into advice.
- **GATE-9**  Checking a range with nothing in it passes rather than erroring, so a no-op run blocks nobody.
- **GATE-10**  The written report and the exit code always agree.
