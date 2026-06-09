---
title: "Dogfooding"
description: "Proof: attest attests attest. Real captured output of attest recording and verifying provenance on its own commits, plus the growing CI ledger."
section: "Integrations"
order: 2
---

`attest` uses itself. Every commit that lands on `main` gets a provenance
attestation recorded **by attest, on attest's own history**, and gated against
the committed `.attest.json` policy in CI. The trust record for this repository
is itself an attest ledger, stored in `refs/notes/attest` and travelling with
the repo like any other git data.

This is not a toy fixture: the output below is captured from running the real
release binary against attest's real `HEAD`. Reproduce all of it with
`examples/dogfood.sh`, which runs in a `/tmp` scratch clone (your working tree
and notes ref are never touched).

> **Platform.** macOS only, like the rest of attest.

## Why "attest attests attest" is the honest test

A provenance tool is only trustworthy if it survives being pointed at itself. So
we record an `agent:ci` attestation — the same shape CI records — on attest's own
commit, then show it both **passing** a realistic gate and **failing** a strict
one. The failure is the interesting half: it proves attest actually catches a
missing signature / human sign-off rather than rubber-stamping.

## 1 — Record an attestation on attest's own HEAD

```console
$ attest sign --commit "$HEAD" --reviewer agent:ci \
      --confidence 0.9 --verdict proceed --tests-passed \
      --note "attest dogfooding its own CI: build + 106 tests green"
attest · recorded agent:ci on ab181efcdd
```

The ledger row on attest's real commit (`ab181ef`):

```console
$ attest log --commit "$HEAD"
attest · ledger

  commit ab181efcdd  (1 attestation)
    [ok] agent:ci  verdict:proceed  conf:90%  tests:ok  human:—  unsigned
        note: attest dogfooding its own CI: build + 106 tests green
```

It's `unsigned` and `human:—` on purpose — that's exactly what an automated CI
attestation looks like, and it's what the strict policy below will catch.

## 2 — Verify PASS under a lax policy (exit 0)

A realistic CI gate: a commit must carry an attestation and report passing tests.
That's satisfied, so verify exits `0`.

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true
}
```

```console
$ attest verify --commit "$HEAD" --policy lax.json
attest verify · [ok] PASS (1 commit checked)
$ echo $?
0
```

This is the same fatal gate CI runs against the committed `.attest.json`.

## 3 — Verify FAIL under a strict policy (exit 1)

Now demand a cryptographic signature *and* a human sign-off. The `agent:ci`
attestation has neither, so attest catches it on its own commit and exits `1`:

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireSignature": true,
  "requireHumanApprovalWhenVerdictAtLeast": "proceed"
}
```

```console
$ attest verify --commit "$HEAD" --policy strict.json
attest verify · [x] FAIL (1 commit checked)

  violations:
    x ab181efcdd  requireSignature: no valid signed attestation
    x ab181efcdd  requireHumanApprovalWhenVerdictAtLeast: verdict is at least proceed on this commit but no attestation is human-approved
$ echo $?
1
```

Those two `violations` lines are the real proof that the gate has teeth.

## The CI dogfood — a growing provenance ledger

The CI workflow wires this into every run on the self-hosted macOS runner. After
`swift build`, `swift test`, and `fledge spec check` pass, it builds the release
binary, records an unsigned `agent:ci` attestation on `$GITHUB_SHA`, runs
`attest verify --policy .attest.json` as a **fatal** gate (printing the ledger
and verdict), and — on a push to `main` only — best-effort `git push origin
refs/notes/attest` so the ledger accumulates over time. The job has
`permissions: contents: write`; the push is guarded with `|| echo "note push
skipped"` so a permissions or race issue can't redden CI — only the verify gate
can fail the job.

Inspect the ledger from a fresh clone:

```sh
git clone https://github.com/CorvidLabs/attest.git
cd attest
git fetch origin "refs/notes/*:refs/notes/*"   # pull the attestation notes
attest log                                       # every attested commit
attest log --range origin/main~10..origin/main   # a recent slice
```

## Reproduce it locally

```sh
examples/dogfood.sh
```

The strict FAIL is expected and captured, so the script itself exits `0`:

```console
lax    verify exit code: 0     (expected 0 — PASS)
strict verify exit code: 1     (expected 1 — FAIL, caught)
dogfood OK — attest attested attest, both outcomes as expected.
```

## Caveats

- CI attestations are **unsigned** — no signing key is provisioned on the runner
  (signing is optional by design). Provision a key with `attest keygen`, sign
  with `--sign`, and tighten `.attest.json` to make the ledger cryptographically
  verifiable.
- The notes push is **best-effort and main-only**. PR runs record and verify an
  attestation but don't push notes.
- The committed `.attest.json` is intentionally permissive so the tool is usable
  with zero configuration; the strict policy above lives only in the demo/docs.
