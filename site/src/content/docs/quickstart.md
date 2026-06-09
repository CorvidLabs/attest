---
title: "Quickstart"
description: "Install attest, record your first attestation, and gate a commit against a policy."
section: "Getting started"
order: 1
---

Get `attest` recording and verifying provenance in under a minute. attest stores attestations in
git notes (`refs/notes/attest`), so there is no service to run and nothing to configure beyond an
optional policy file.

## Requirements

- **Swift 6** and **`git`** on `PATH`.
- **macOS** — attest is macOS-only for now (the git-notes store, signing, and CI all target
  macOS). Linux/Windows support is plausible but not yet on the matrix.
- Signing uses Apple's [`swift-crypto`](https://github.com/apple/swift-crypto); the CLI uses
  [`swift-argument-parser`](https://github.com/apple/swift-argument-parser).

## Install

```sh
swift build -c release
install -m 0755 .build/release/attest /usr/local/bin/attest
# or, with fledge:
fledge run install
```

## 1. Record an attestation (unsigned, zero setup)

Out of the box, attestations are **unsigned but valid** — no key required.

```sh
attest sign --commit HEAD --reviewer agent:claude --confidence 0.92 --tests-passed
```

A confidence value must come from somewhere: pass `--confidence`, `--human-approved`, or
`--from-augur`.

## 2. Read the ledger

```sh
attest log                        # all attested commits
attest log --commit HEAD --json   # one commit, machine-readable
attest log --range main..HEAD
```

```
attest · ledger

  commit 9f2c1a7b04  (1 attestation)
    [ok] agent:claude  verdict:—  conf:92%  tests:ok  human:—  unsigned
```

## 3. Pipe augur straight in

`attest sign --from-augur <file|->` reads `augur check --json` and merges it: augur's `verdict` is
copied, and its `riskScore` (0…100) becomes `confidence = 1 − riskScore/100`.

```sh
augur check --range main..HEAD --json \
  | attest sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed
```

## 4. Sign cryptographically (optional)

Generate a key once, then add `--sign`. `keygen` prints the **public** key to copy into a policy's
`trustedKeys` / `signerPinning`.

```sh
attest keygen
# attest · wrote private key to ~/.config/attest/key (0600)
# public key: BASE64_PUBKEY      <- copy into signerPinning / trustedKeys

attest sign --commit HEAD --reviewer human:leif --confidence 0.7 --human-approved --sign
```

See [Signing & identity](/attest/docs/signing) for the full model.

## 5. Gate a commit against a policy

Policy is plain JSON in `.attest.json`. Every rule is optional with permissive defaults — an empty
`{}` still requires one attestation per commit and passes any commit that has one.

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "minimumConfidence": 0.6,
  "requireHumanApprovalWhenVerdictAtLeast": "review"
}
```

```sh
attest verify --range origin/main..HEAD --policy .attest.json
```

`attest verify`'s **exit code** is its contract: it exits non-zero on any policy violation, so CI
and agent loops gate on it.

```sh
attest verify --commit HEAD || echo "trust policy not satisfied — escalating to a human"
```

See the [Policy reference](/attest/docs/policy) for all 11 rules.

## 6. Sync the notes

Attestations live in `refs/notes/attest`. They are not fetched or pushed by a plain
`checkout`/`push`, so move them explicitly:

```sh
git push origin "refs/notes/*"
git fetch origin "refs/notes/*:refs/notes/*"
```

## Next steps

- [Policy reference](/attest/docs/policy) — all 11 rules.
- [CLI reference](/attest/docs/cli) — every command and flag.
- [CI integration](/attest/docs/ci-integration) — the `attest-verify` action and the augur →
  attest pipeline.
