---
hi: 1
families: [CI]
---

# Dropping the gate into a pipeline

## Intent

A gate nobody wires up protects nothing, so adding trust verification to a pipeline should take a handful of lines and no toolchain. A ready-made step should fetch the right prebuilt binary for the runner, check it against its published checksum, and fail the job on anything that goes wrong rather than sailing on. Because the ledger is invisible in a web UI, CI should also be able to surface what it found where people already look, without those extra surfaces ever being able to fail a build by themselves. The gate itself is the only thing allowed to redden a run.

## Criteria

- **CI-1**  A repo can add the trust gate to its pipeline in a few lines.
- **CI-2**  The gate runs on a runner with no language toolchain installed, because a prebuilt binary is fetched for it.
  - **CI-2.a**  A runner nothing is prebuilt for still works by building from source when it can.
  - **CI-2.b**  A runner that can do neither says so plainly instead of failing obscurely.
- **CI-3**  A downloaded binary is checked against its published checksum before it is run.
  - **CI-3.a**  A checksum that does not match stops the job.
- **CI-4**  A repo can pin to a major version and keep getting fixes within it.
  - **CI-4.a**  A repo can instead pin to an exact release and never move.
  - **CI-4.b**  Pinning to a major version never quietly drags in the next one.
- **CI-5**  Every failure along the way fails the job rather than passing through.
- **CI-6**  The range being checked is mine to choose.
  - **CI-6.a**  The policy being checked is mine to choose.
  - **CI-6.b**  The defaults suit the common case, so most repos need change neither.
- **CI-7**  A missing or misspelled policy path fails the job rather than passing under a permissive default.
- **CI-8**  The step tells me which binary it ran, so a surprising result can be traced.
- **CI-9**  The instructions remind me to fetch the ledger, because a plain checkout leaves it behind.
  - **CI-9.a**  The instructions remind me to fetch enough history for the range I am checking.
- **CI-10**  A squash-merge pipeline can forward provenance in the same step that gates it.
- **CI-11**  A verified commit can be shown as a check in the web UI, since the ledger itself is invisible there.
- **CI-12**  A repo can carry a badge that reflects what its own ledger actually says.
  - **CI-12.a**  Posting that badge or check can never redden a build on its own; only the gate itself fails a job.
