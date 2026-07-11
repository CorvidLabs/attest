# CLI Reference

`attest` has eight subcommands: `sign`, `forward`, `verify`, `log`, `export`, `keygen`, `push`, and
`fetch`. The default subcommand (running `attest` with no subcommand) is `log`.

All commands that touch a repository accept `--path <dir>` / `-C <dir>` (default `.`) to point at
the repository to operate on.

```
attest <subcommand> [options]
```

## Exit codes

| Command | Exit 0 | Exit 1 | Other non-zero |
|---------|--------|--------|----------------|
| `verify` | every checked commit passes the policy | a commit violates the policy | usage / git / I/O error |
| `sign`, `forward`, `log`, `export`, `keygen`, `push`, `fetch` | success | n/a | usage / git / I/O error |

`attest verify`'s exit code is its contract: a policy violation propagates exit `1`, which is
what CI and agent loops gate on. The other commands exit non-zero only on an actual error
(invalid arguments, not a git repository, a missing signing key, malformed input).

---

## `attest sign`

Record an attestation for a commit, written to git notes (`refs/notes/attest`).

| Flag | Default | Description |
|------|---------|-------------|
| `--commit <rev>` | `HEAD` | the commit to attest (SHA or revision). |
| `--reviewer <id>` | *(required)* | who or what reviewed, e.g. `agent:claude`, `human:leif`. |
| `--confidence <0..1>` | none | reviewer confidence in `0...1`; out-of-range values are rejected (exit `64`). Use `--confidence=VALUE` for negative values. |
| `--verdict <v>` | none | recorded verdict: `proceed`, `review`, or `block`. |
| `--tests-passed` | off | record that the change's tests passed. |
| `--human-approved` | off | record that a human approved (implies confidence `1.0` if none given). |
| `--note <text>` | none | optional free-text note. |
| `--from-augur <file\|->` | none | read `augur check --json` and merge `verdict` + derived `confidence`. |
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
and its `riskScore` (0...100) becomes `confidence = 1 - riskScore/100` (so risk 45 gives confidence
0.55). See [signing.md](signing.md) and the project README for the full augur pipeline.

---

## `attest forward`

Record a fresh attestation on a landed commit from an already-attested source commit. This is the
recommended squash-merge workflow: attest the reviewed PR head, squash merge, forward that
provenance onto the protected-branch commit, then run normal exact verification.

| Flag | Default | Description |
|------|---------|-------------|
| `--from <rev>` | none | reviewed source commit whose attestations are being forwarded. |
| `--to <rev>` | `HEAD` | landed commit to attest. |
| `--reviewer <id>` | `ci:attest-forward` | identity recording the forwarding attestation, e.g. `ci:merge-bot`. |
| `--note <text>` | none | optional text appended to the forwarding note. |
| `--sign` | off | sign the forwarded attestation with the key from `attest keygen`. |
| `--json` | off | emit the stored attestation as JSON. |

```sh
attest forward --from "$PR_HEAD_SHA" --to HEAD --reviewer ci:merge-bot --sign
attest verify --range "$BEFORE..HEAD" --policy .attest.json
```

The forwarded record's `commit` is the landed commit SHA. The source SHA and source reviewers are
preserved in the note for audit, while signatures remain bound to the exact commit they attest.
Signed source records are used only if their signatures verify; invalid signed source records are
discarded before deriving confidence, verdict, tests, or human-approval signals.

---

## `attest verify`

Exit non-zero if any commit in a range violates the policy. This is the gate for CI and agent loops.

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | none | a git range to check, e.g. `origin/main..HEAD`. |
| `--commit <rev>` | none | check a single commit; defaults to `HEAD` when neither `--range` nor `--commit` is given. |
| `--policy <path>` | none | path to the policy file. An explicitly passed path **must exist** — a typo'd path is a hard error, never a silent fall-back. Without the flag, `.attest.json` is used when present, else the permissive default. |
| `--json` | off | emit machine-readable JSON instead of the human report. |
| `--color <auto\|always\|never>` | `auto` | colorize the human report. `auto` colours only when stdout is a TTY and `NO_COLOR` is unset; `--json` and piped output stay plain. |

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
[policy.md](policy.md)).

---

## `attest log`

List recorded attestations, human-readable or JSON. This is the **default** subcommand.

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | none | limit to a git range. |
| `--commit <rev>` | none | limit to a single commit. |
| `--json` | off | emit machine-readable JSON. |
| `--color <auto\|always\|never>` | `auto` | colorize the listing. `auto` colours only when stdout is a TTY and `NO_COLOR` is unset; `--json` and piped output stay plain. |

With neither `--range` nor `--commit`, `log` lists every attested commit in history order
(newest first). A corrupt note line is skipped with a stderr warning and a non-zero exit,
while the valid records around it still print.

```sh
attest log                        # all attested commits
attest log --commit HEAD --json   # one commit, machine-readable
attest log --range main..HEAD
```

`log` is a *human / diagnostic* listing. For a durable, machine-stable audit document, use
`export`.

---

## `attest export`

Emit the complete provenance trail across a range as one stable JSON audit document, suitable for
compliance archival. Always JSON (no `--json` flag).

| Flag | Default | Description |
|------|---------|-------------|
| `--range <a..b>` | none | a git range to export. |
| `--commit <rev>` | none | export a single commit; with neither, exports every attested commit (oldest first). |
| `--policy <path>` | none | optional; when set, each commit's pass/fail is included. |
| `--pretty` / `--no-pretty` | `--pretty` | pretty-print (default) or emit compact JSON. |

```sh
attest export --range origin/main..HEAD                    # whole range
attest export --commit HEAD                                # one commit
attest export --range main..HEAD --policy .attest.json     # with per-commit verdicts
attest export --range main..HEAD --no-pretty > audit.json  # compact, for storage
```

Output is deterministic: commits appear oldest-first (the order `git rev-list --reverse`
returns), records in store order, and JSON keys are sorted, so it diffs cleanly. Every commit in
the range is represented, including commits with no attestations. Each record carries a
`verification` block: `signed`, and for signed records whether the signature `verified` (a
tampered or wrong-key record reports `verified: false`; unsigned records omit `verified`).

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

---

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
`trustedKeys`. See [signing.md](signing.md).

---

## `attest push` / `attest fetch`

Synchronize the provenance ledger without memorizing git-notes refspecs.

| Flag | Default | Description |
|------|---------|-------------|
| `--remote <name>` | `origin` | configured git remote to push to or fetch from. |

```sh
attest fetch                 # merge remote provenance into the local ledger
attest push                  # publish the local ledger after recording
attest fetch --remote upstream
```

`push` is never forced: if the remote ledger advanced, it fails rather than discarding records.
Run `attest fetch` to merge the remote records, then retry. `fetch` uses a temporary ref and the
git-notes `cat_sort_uniq` strategy so attestations added independently on both sides survive.
