---
title: "CLI reference"
description: "Every attest command and flag — sign, verify, log, export, keygen — with examples and exit codes."
section: "Reference"
order: 2
---

`attest` has five subcommands: `sign`, `verify`, `log`, `export`, and `keygen`. The default
subcommand (running `attest` with no subcommand) is `log`.

All commands that touch a repository accept `--path <dir>` / `-C <dir>` (default `.`) to point at
the repository to operate on.

```
attest <subcommand> [options]
```

## Exit codes

| Command | Exit 0 | Exit 1 | Other non-zero |
|---------|--------|--------|----------------|
| `verify` | every checked commit passes the policy | a commit violates the policy | usage / git / I/O error |
| `sign`, `log`, `export`, `keygen` | success | — | usage / git / I/O error |

`attest verify`'s exit code is its contract: a policy violation propagates exit `1`, which is what
CI and agent loops gate on. The other commands exit non-zero only on an actual error (invalid
arguments, not a git repository, a missing signing key, malformed input).

## `attest sign`

Record an attestation for a commit, written to git notes (`refs/notes/attest`).

| Flag | Default | Description |
|------|---------|-------------|
| `--commit <rev>` | `HEAD` | the commit to attest (SHA or revision). |
| `--reviewer <id>` | *(required)* | who or what reviewed, e.g. `agent:claude`, `human:leif`. |
| `--confidence <0..1>` | — | reviewer confidence; clamped to `0…1`. |
| `--verdict <v>` | — | recorded verdict: `proceed`, `review`, or `block`. |
| `--tests-passed` | off | record that the change's tests passed. |
| `--human-approved` | off | record that a human approved (implies confidence `1.0` if none given). |
| `--note <text>` | — | optional free-text note. |
| `--from-augur <file\|->` | — | read `augur check --json` and merge `verdict` + derived `confidence`. |
| `--sign` | off | sign the attestation with the key from `attest keygen`. |
| `--json` | off | emit the stored attestation as JSON. |

A confidence value must come from somewhere: pass `--confidence`, `--human-approved`, or
`--from-augur`. Explicit `--verdict` / `--confidence` flags override augur-derived values.

```sh
# Unsigned, zero setup:
attest sign --commit HEAD --reviewer agent:claude --confidence 0.92 --tests-passed

# Signed sign-off by a human:
attest sign --commit HEAD --reviewer human:leif --confidence 0.7 --human-approved --sign

# Pipe augur straight in (verdict + confidence auto-filled from its JSON):
augur check --json | attest sign --commit HEAD --reviewer agent:claude --from-augur -
```

### `--from-augur`

Reads `augur check --json` from a file or `-` (stdin) and merges it: augur's `verdict` is copied,
and its `riskScore` (0…100) becomes `confidence = 1 − riskScore/100` (so risk 45 → confidence
0.55). See [Signing & identity](/attest/docs/signing) and the project README for the full augur
pipeline.

## `attest verify`

Exit non-zero if any commit in a range violates the policy — the gate for CI and agent loops.

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | — | a git range to check, e.g. `origin/main..HEAD`. |
| `--commit <rev>` | — | check a single commit; defaults to `HEAD` when neither `--range` nor `--commit` is given. |
| `--policy <path>` | `.attest.json` | path to the policy file (falls back to the permissive default if absent). |
| `--json` | off | emit machine-readable JSON instead of the human report. |

```sh
attest verify --range origin/main..HEAD --policy .attest.json
attest verify --commit HEAD --json
```

JSON shape:

```json
{ "checkedCommits": 1, "passed": false,
  "violations": [ { "commit": "…", "detail": "…", "rule": "requireTestsPassed" } ] }
```

The current epoch is used as the reference time for the `maxAgeDays` freshness rule (see
[Policy reference](/attest/docs/policy)).

## `attest log`

List recorded attestations, human-readable or JSON. This is the **default** subcommand.

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | — | limit to a git range. |
| `--commit <rev>` | — | limit to a single commit. |
| `--json` | off | emit machine-readable JSON. |

With neither `--range` nor `--commit`, `log` lists every attested commit.

```sh
attest log                        # all attested commits
attest log --commit HEAD --json   # one commit, machine-readable
attest log --range main..HEAD
```

`log` is a *human / diagnostic* listing. For a durable, machine-stable audit document, use
`export`.

## `attest export`

Emit the complete provenance trail across a range as one stable JSON audit document, suitable for
compliance archival. Always JSON (no `--json` flag).

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | — | a git range to export. |
| `--commit <rev>` | — | export a single commit; with neither, exports every attested commit. |
| `--policy <path>` | — | optional; when set, each commit's pass/fail is included. |
| `--pretty` / `--no-pretty` | `--pretty` | pretty-print (default) or emit compact JSON. |

```sh
attest export --range origin/main..HEAD                    # whole range
attest export --commit HEAD                                # one commit
attest export --range main..HEAD --policy .attest.json     # with per-commit verdicts
attest export --range main..HEAD --no-pretty > audit.json  # compact, for storage
```

Output is deterministic: commits appear oldest-first (the order `git rev-list --reverse` returns),
records in store order, and JSON keys are sorted — so it diffs cleanly. Every commit in the range
is represented, including commits with no attestations. Each record carries a `verification` block:
`signed`, and for signed records whether the signature `verified` (a tampered or wrong-key record
reports `verified: false`; unsigned records omit `verified`).

```json
{
  "allPassed": true,
  "commitCount": 1,
  "commits": [
    {
      "commit": "9f2c1a7b04...",
      "policyPassed": true,
      "records": [
        { "attestation": { "...": "..." },
          "verification": { "signed": true, "verified": true } }
      ]
    }
  ],
  "policyApplied": true,
  "recordCount": 1,
  "version": 1
}
```

## `attest keygen`

Generate an Ed25519 signing keypair for signing attestations.

| Flag | Default | Description |
|------|---------|-------------|
| `--force` | off | overwrite an existing key. |

```sh
attest keygen
# attest · wrote private key to ~/.config/attest/key (0600)
# public key: BASE64_PUBKEY      <- copy into signerPinning / trustedKeys
```

The private key is written to `$XDG_CONFIG_HOME/attest/key` (or `~/.config/attest/key`) with
`0600` permissions. `keygen` prints the **public** key to copy into a policy's `signerPinning` /
`trustedKeys`. See [Signing & identity](/attest/docs/signing).
