---
hi: 1
families: [START]
---

# Getting it and trying it

## Intent

Somebody curious should get from reading about attest to a real attestation in under a minute, without installing a toolchain, editing their repo or taking any claim on faith. Installing is one line, trying it touches nothing of theirs, and every capability has a runnable script that builds its own throwaway repo and cleans up after itself. The strongest argument a provenance tool can make is to be pointed at itself, so attest records and gates its own commits and shows the failing case as well as the passing one. Where it does not reach, it should say so rather than implying it reaches everywhere.

## Criteria

- **START-1**  Installing is one line on a Mac.
- **START-2**  I can build and install from source when I would rather not use a package manager.
- **START-3**  The only thing attest needs at run time is git.
- **START-4**  I can watch attest work end to end without touching my own repository, my ledger or my config.
- **START-5**  There is a runnable example for each thing attest can do, from the shortest record to pinning a signer.
  - **START-5.a**  An example that would rather use another tool still runs end to end when that tool is absent.
- **START-6**  The output shown in the docs is real captured output, not something typed out by hand.
- **START-7**  attest records and gates provenance on its own commits, so the claim that it works is checkable.
  - **START-7.a**  That proof includes a failure as well as a pass, so I can see the gate has teeth.
  - **START-7.b**  I can reproduce the proof myself in a scratch clone.
- **START-8**  The docs say plainly where attest does not go, rather than implying it goes everywhere.
- **START-9**  I can read the docs as a rendered site, not only as files in the repo.
