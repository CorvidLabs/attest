---
hi: 1
families: [LEDGER]
---

# A ledger that travels with the repository

## Intent

The trust record belongs with the code, not in a service somebody has to keep alive or a database somebody has to migrate. Keeping it in the repository means it clones, pushes and fetches like any other git data, no git host is privileged, and nobody is locked in. Reading it back should feel like reading a git log: one glance per commit tells you what vetted it and how much weight that carries. Because it is an audit ledger, damage in it must be loud rather than lossy, and moving it between machines should not require memorising git plumbing.

## Criteria

- **LEDGER-1**  The trust record lives inside the repository, so there is no service to run and no database to keep.
- **LEDGER-2**  The ledger moves between machines with ordinary git pushes and fetches, needing no service in the middle.
- **LEDGER-3**  No git host is privileged, so recording trust never locks me into one.
- **LEDGER-4**  Recording provenance never touches my working tree, my commits or my branches.
- **LEDGER-5**  A new attestation is added to a commit rather than replacing what is already recorded there.
- **LEDGER-6**  I can read the whole ledger back, newest commit first.
  - **LEDGER-6.a**  Running attest with nothing else shows me the ledger, because that is what I usually want.
  - **LEDGER-6.b**  I can narrow the reading to a single commit or a range.
  - **LEDGER-6.c**  One row tells me the reviewer, the verdict, the confidence, whether tests passed, whether a human approved and whether it was signed.
  - **LEDGER-6.d**  On a terminal the listing is coloured by meaning: green for clear, amber for look closer, red for trouble.
  - **LEDGER-6.e**  Colour stays out of piped and machine-readable output.
  - **LEDGER-6.f**  I can force colour on or off rather than living with the guess.
- **LEDGER-7**  An agent can read the same ledger as stable, sorted data.
- **LEDGER-8**  One damaged record never hides the good records stored beside it.
  - **LEDGER-8.a**  I am told on the side exactly what could not be read.
  - **LEDGER-8.b**  A reading that hit damage ends unhappily rather than looking clean.
- **LEDGER-9**  I can publish my ledger to a remote without memorising git plumbing.
  - **LEDGER-9.a**  Publishing never discards records somebody else added.
  - **LEDGER-9.b**  Publishing onto a remote that has moved on stops and tells me to merge first.
- **LEDGER-10**  I can pull a remote ledger down and merge it into mine.
  - **LEDGER-10.a**  Records added independently on both sides all survive that merge.
  - **LEDGER-10.b**  Pulling from a remote that has no ledger yet tells me there is nothing to fetch rather than failing.
- **LEDGER-11**  I can point any attest command at a repository other than the one I am standing in.
- **LEDGER-12**  When git refuses something I see git's own explanation, not the plumbing command that failed.
  - **LEDGER-12.a**  A commit or range I mistyped is named back to me.
  - **LEDGER-12.b**  A directory that is not a git repository is called out as such straight away.
