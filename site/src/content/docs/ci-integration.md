---
title: "CI integration"
description: "Self-hosted macOS runners, the attest-verify action, the augur → attest pipeline, and audit export."
section: "Integrations"
order: 1
---

`attest verify` is built to gate CI and agent loops: it exits non-zero when a commit lacks the
trust a policy demands. This guide covers running it on the self-hosted macOS runners, the bundled
`attest-verify` composite action, the augur → attest trust pipeline, and exporting an audit trail
for compliance.

> **Platform.** `attest` is **macOS-only for now**. The git-notes store, signing, and the
> composite action all target macOS, and CI runs on the self-hosted **macOS ARM64** runners
> (`runs-on: [self-hosted, macOS]`). Linux/Windows support is plausible (Foundation `Process` +
> swift-crypto) but is not yet on the matrix.

## Running the binary directly

The simplest integration is to build `attest` and run `verify` against your range:

```yaml
jobs:
  trust:
    runs-on: [self-hosted, macOS]
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # need history for the range
      - run: git fetch origin "refs/notes/*:refs/notes/*"   # pull attestation notes
      - run: swift build -c release
      - run: .build/release/attest verify --range origin/main..HEAD --policy .attest.json
```

Two details matter:

- **Fetch the notes.** Attestations live in `refs/notes/attest`. They are not fetched by a plain
  `checkout`, so pull them explicitly with `git fetch origin "refs/notes/*:refs/notes/*"` (and push
  them on the producing side with `git push origin "refs/notes/*"`).
- **Enough history.** A range like `origin/main..HEAD` needs the commits on both sides, so set
  `fetch-depth: 0` (or a depth large enough for the PR).

## The `attest-verify` composite action

The repository ships a composite GitHub Action (`action.yml`) that builds `attest` from its own
checkout and runs `attest verify`, failing the job on any policy violation:

```yaml
jobs:
  trust:
    runs-on: [self-hosted, macOS]   # macOS-only for now
    steps:
      - uses: actions/checkout@v4
      - uses: CorvidLabs/attest@main
        with:
          range: origin/main..HEAD   # default
          policy: .attest.json       # default
          working-directory: .       # default
```

| Input | Default | Description |
|-------|---------|-------------|
| `range` | `origin/main..HEAD` | git range to verify. |
| `policy` | `.attest.json` | policy file path, relative to `working-directory`. |
| `working-directory` | `.` | directory to run `attest verify` in. |

The action has **no outputs**; its contract is the **exit code**. A policy violation propagates
`attest`'s non-zero exit and fails the job.

> **Honest scope.** The action builds `attest` from *its own* checkout with `swift build -c
> release`. Cross-repo packaging (shipping a prebuilt binary and installing it into other repos
> without a Swift toolchain) is a deferred later step.

## The augur → attest trust pipeline

[`augur`](https://github.com/CorvidLabs/augur) scores diff risk and emits a verdict (`proceed` /
`review` / `block`) with a risk score. That verdict is *ephemeral*; `attest` makes it durable. They
compose over a pipe; `attest` never links `augur`:

```sh
# An agent scores the diff, records the verdict as an attestation, then gates on the policy:
augur check --range main..HEAD --json \
  | attest sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed

attest verify --commit HEAD || echo "trust policy not satisfied, escalating to a human"
```

`--from-augur` copies augur's `verdict` and maps its `riskScore` (0…100) to `confidence = 1 −
riskScore/100`. In an agent loop this turns a risk score into a recorded, optionally-signed trust
artifact that the next step, or a human, can verify. A typical loop:

1. `augur check --json` scores the change.
2. `attest sign --from-augur -` records the verdict + confidence as an attestation (signed if the
   agent holds a key).
3. `attest verify` gates: a `review`/`block` verdict under a policy with
   `requireHumanApprovalWhenVerdictAtLeast` exits non-zero until a human files a separate
   `--human-approved` sign-off, so the agent **escalates instead of merging blind**.

Pair the policy with `maxAgeDays` (see [Policy reference](/attest/docs/policy)) so a stale verdict
from a previous run cannot keep clearing today's commit.

## Exporting an audit trail for compliance

`attest export` produces a single, stable JSON document covering the *complete* provenance trail
across a range: every commit, every attestation, each record's cryptographic verification status,
and (with `--policy`) a per-commit pass/fail. It is deterministic (sorted keys; commits
oldest-first), so it diffs cleanly and is suitable for archival.

A natural CI step archives the trust trail alongside the build artifacts:

```yaml
      - run: |
          .build/release/attest export \
            --range origin/main..HEAD \
            --policy .attest.json \
            --no-pretty > audit.json
      - uses: actions/upload-artifact@v4
        with:
          name: attest-audit
          path: audit.json
```

`export` folds in `verify`'s policy verdict *and* the per-record signature checks, across the full
range, in one machine-stable file: the durable record an auditor keeps. See
[CLI reference](/attest/docs/cli) for the document shape and
[`examples/05-audit-export.sh`](https://github.com/CorvidLabs/attest/blob/main/examples/05-audit-export.sh)
for an end-to-end run.
