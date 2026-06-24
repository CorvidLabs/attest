# CI Integration

`attest verify` is built to gate CI and agent loops: it exits non-zero when a commit lacks the
trust a policy demands. This guide covers running it on macOS and Linux, the bundled
`attest-verify` composite action, the augur to attest trust pipeline, and exporting an audit
trail for compliance.

> **Platform.** `attest` supports **macOS and Linux**. The composite action currently targets
> macOS. Windows is out of scope.

## Running the binary directly

The simplest integration is to build `attest` and run `verify` against your range:

```yaml
jobs:
  trust:
    runs-on: macos-latest
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
  `checkout`, so pull them explicitly with `git fetch origin "refs/notes/*:refs/notes/*"` (and
  push them on the producing side with `git push origin "refs/notes/*"`).
- **Enough history.** A range like `origin/main..HEAD` needs the commits on both sides, so set
  `fetch-depth: 0` (or a depth large enough for the PR).

## The `attest-verify` action

The repository ships a GitHub Action (`action.yml`) you can drop into **any** repo. It installs a
prebuilt `attest` for the runner (macOS universal or Linux x86_64) from the matching release, then
runs `attest verify` against your checkout — no Swift toolchain required. On other platforms it
falls back to building `attest` from its own source:

```yaml
jobs:
  trust:
    runs-on: ubuntu-latest        # or macos-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # range needs history
      - uses: CorvidLabs/attest@v0   # pin to the major tag, not @main
        with:
          range: origin/main..HEAD   # default
          policy: .attest.json       # default
          working-directory: .       # default
```

| Input | Default | Description |
|-------|---------|-------------|
| `range` | `origin/main..HEAD` | git range to verify (needs full history). |
| `policy` | `.attest.json` | policy file path, relative to `working-directory`. |
| `forward-from` | `""` | optional reviewed source commit to forward before verification, useful for squash merges. |
| `forward-to` | `HEAD` | landed commit to attest when `forward-from` is set. |
| `forward-reviewer` | `ci:attest-forward` | reviewer identity for the forwarded attestation. |
| `forward-sign` | `false` | sign the forwarded attestation with the runner's `attest keygen` key. |
| `working-directory` | `.` | directory to run `attest verify` in. |
| `version` | *(action ref)* | attest release to install (`v0.3.0` or `latest`); defaults to the pinned tag, else `latest`. |

The single output is `binary` (path to the `attest` used); the gate's contract is the **exit
code**. A policy violation propagates `attest`'s non-zero exit and fails the job. Prebuilt binaries
cover GitHub-hosted macOS and Linux x86_64 runners; other runners need a Swift toolchain.

## Squash merges

Because `Attestation.commit` is part of the signed payload, a PR-head attestation cannot be moved
onto GitHub's squash commit. The supported protected-branch workflow is post-merge
re-attestation:

```yaml
- uses: CorvidLabs/attest@v0
  with:
    range: ${{ github.event.before }}..HEAD
    policy: .attest.json
    forward-from: ${{ env.REVIEWED_PR_HEAD_SHA }}
    forward-to: HEAD
    forward-reviewer: ci:merge-bot
    forward-sign: true
```

The action runs `attest forward` first, recording a fresh attestation on `forward-to` that points
back to `forward-from` in its note, then runs ordinary `attest verify --range ... --policy ...`.
Use `trustedKeys` / `signerPinning` to decide whether the merge CI key is trusted to make that
forwarding statement.

> **Honest scope.** The action builds `attest` from *its own* checkout with `swift build -c
> release`. Cross-repo packaging (shipping a prebuilt binary and installing it into other repos
> without a Swift toolchain) is a deferred later step.

## Surfacing provenance in the GitHub web UI

attest stores its ledger in git notes (`refs/notes/attest`). Git notes are **not** rendered
anywhere in the GitHub web UI, so a verified commit looks the same as an unverified one in the
browser. attest's own CI closes that gap with two browser-visible surfaces, both backed by the
same `refs/notes/attest` ledger.

### Commit-status check

After the fatal `attest verify` gate, CI posts a GitHub **commit status** named `attest` on the
verified SHA. It shows up as a check on the commit page and in the PR checks list, with a link
back to the run:

```yaml
permissions:
  contents: write     # push the notes ledger
  statuses: write     # post the commit status below
```

```yaml
      - name: Post attest commit status
        if: always() && steps.verify.outcome != 'skipped'
        env:
          GH_TOKEN: ${{ github.token }}
          ATTEST_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
          VERIFY_CODE: ${{ steps.verify.outputs.exit_code }}
        run: |
          if [ "${VERIFY_CODE:-1}" = "0" ]; then STATE=success; DESC="provenance verified";
          else STATE=failure; DESC="policy not satisfied"; fi
          gh api -X POST "repos/${{ github.repository }}/statuses/$ATTEST_SHA" \
            -f state="$STATE" -f context="attest" -f description="$DESC" \
            -f target_url="https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            || echo "status post skipped"
```

The mapping is direct: `attest verify` exit `0` posts `state=success` ("provenance verified"),
any non-zero exit posts `state=failure` ("policy not satisfied"). The SHA is the PR head on a
`pull_request` event and the pushed SHA otherwise. The call uses the default `github.token` and
is best-effort (`|| echo "status post skipped"`) so a token hiccup can never redden CI by itself;
the fatal verify gate in the prior step remains the only thing that fails the job.

### Live README badge

The public Pages build (`.github/workflows/pages.yml`) emits a [shields.io endpoint](
https://shields.io/badges/endpoint-badge) JSON at the site root that reflects attest's provenance
status for `HEAD`. Before the Astro build it builds the release binary, fetches the notes ledger,
runs `attest verify --commit HEAD --policy .attest.json`, and writes `site/public/badge.json`:

```json
{"schemaVersion":1,"label":"attest","message":"verified","color":"brightgreen"}
```

On a verify failure (or no attestation) it writes `"message":"unverified","color":"red"` instead.
Astro copies `site/public/*` to the site root, so the file is served at
`https://corvidlabs.github.io/attest/badge.json`. The README badge points shields.io at that
endpoint, so the badge text tracks attest's own provenance ledger:

```markdown
[![attest](https://img.shields.io/endpoint?url=https://corvidlabs.github.io/attest/badge.json)](https://corvidlabs.github.io/attest/)
```

Both surfaces are read-only views of the same `refs/notes/attest` ledger that `attest verify`
gates on: the commit status reflects per-commit verification at CI time, and the badge reflects
`HEAD` at each Pages build.

## The augur → attest trust pipeline

[`augur`](https://github.com/CorvidLabs/augur) scores diff risk and emits a verdict (`proceed` /
`review` / `block`) with a risk score. That verdict is *ephemeral*; `attest` makes it durable.
They compose over a pipe; `attest` never links `augur`:

```sh
# An agent scores the diff, records the verdict as an attestation, then gates on the policy:
augur check --range main..HEAD --json \
  | attest sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed

attest verify --commit HEAD || echo "trust policy not satisfied, escalating to a human"
```

`--from-augur` copies augur's `verdict` and maps its `riskScore` (0...100) to `confidence = 1 -
riskScore/100`. In an agent loop this turns a risk score into a recorded, optionally-signed trust
artifact that the next step, or a human, can verify. A typical loop:

1. `augur check --json` scores the change.
2. `attest sign --from-augur -` records the verdict + confidence as an attestation (signed if the
   agent holds a key).
3. `attest verify` gates: a `review`/`block` verdict under a policy with
   `requireHumanApprovalWhenVerdictAtLeast` exits non-zero until a human files a separate
   `--human-approved` sign-off, so the agent **escalates instead of merging blind**.

Pair the policy with `maxAgeDays` (see [policy.md](policy.md)) so a stale verdict from a previous
run cannot keep clearing today's commit.

## Exporting an audit trail for compliance

`attest export` produces a single, stable JSON document covering the *complete* provenance trail
across a range: every commit, every attestation, each record's cryptographic verification
status, and (with `--policy`) a per-commit pass/fail. It is deterministic (sorted keys; commits
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

`export` folds in `verify`'s policy verdict *and* the per-record signature checks, across the
full range, in one machine-stable file: the durable record an auditor keeps. See
[cli.md](cli.md#attest-export) for the document shape and
[`examples/05-audit-export.sh`](../examples/05-audit-export.sh) for an end-to-end run.
