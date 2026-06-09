# Dogfooding: attest attests attest

`attest` uses itself. Every commit that lands on `main` gets a provenance
attestation recorded **by attest, on attest's own history**, and gated against
the committed [`​.attest.json`](../.attest.json) policy in CI. The trust record
for this repository is itself an attest ledger, stored in `refs/notes/attest`
and travelling with the repo like any other git data.

This is not a toy fixture: the output below is captured from running the real
release binary against attest's real `HEAD`. If you don't believe it, run it
yourself: [`examples/dogfood.sh`](../examples/dogfood.sh) reproduces all of it
in a `/tmp` scratch clone (your working tree and notes ref are never touched).

> **Platform.** macOS only, like the rest of attest.

## Why "attest attests attest" is the honest test

A provenance tool is only trustworthy if it survives being pointed at itself.
So we record an `agent:ci` attestation (the same shape CI records) on attest's
own commit, then show it both **passing** a realistic gate and **failing** a
strict one. The failure is the interesting half: it proves attest actually
catches a missing signature / human sign-off rather than rubber-stamping.

## 1. Record an attestation on attest's own HEAD

```console
$ attest sign --commit "$HEAD" --reviewer agent:ci \
      --confidence 0.9 --verdict proceed --tests-passed \
      --note "attest dogfooding its own CI: build + 106 tests green"
attest · recorded agent:ci on ab181efcdd
```

The ledger row on attest's real commit (`ab181ef`, *"Add: terminal snapshot
tests + site mockups accurate to colored output (#10)"*):

```console
$ attest log --commit "$HEAD"
attest · ledger

  commit ab181efcdd  (1 attestation)
    [ok] agent:ci  verdict:proceed  conf:90%  tests:ok  human:-  unsigned
        note: attest dogfooding its own CI: build + 106 tests green
```

It's `unsigned` and `human:-` on purpose. That's exactly what an automated CI
attestation looks like, and it's what the strict policy below will catch.

## 2. Verify PASS under a lax policy (exit 0)

A realistic CI gate: a commit must carry an attestation and report passing
tests. That's satisfied, so verify exits `0`.

```jsonc
// lax policy
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

This is the same fatal gate CI runs against the committed `.attest.json`
(which is even more permissive: it only requires an attestation), which is why
the CI `attest verify` step is a real gate and not `|| true`-guarded.

## 3. Verify FAIL under a strict policy (exit 1)

Now demand a cryptographic signature *and* a human sign-off. The `agent:ci`
attestation has neither, so attest catches it on its own commit and exits `1`:

```jsonc
// strict policy
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

## The CI dogfood: a growing provenance ledger

The [CI workflow](../.github/workflows/ci.yml) wires this into every run on the
self-hosted macOS runner. After `swift build`, `swift test`, and
`fledge spec check` pass, it:

1. builds the release binary;
2. runs `attest sign --commit "$GITHUB_SHA" --reviewer agent:ci --confidence 0.9
   --tests-passed --verdict proceed` (unsigned, since keygen/signing in CI is
   optional, and an unsigned attestation is still a valid record);
3. runs `attest verify --commit "$GITHUB_SHA" --policy .attest.json` as a
   **fatal** gate (no `|| true`), printing the ledger and verdict to the log;
4. on a push to `main` only (never on PRs), best-effort `git push origin
   refs/notes/attest` so the ledger accumulates over time. The job has
   `permissions: contents: write`, and the push is guarded with
   `|| echo "note push skipped"` so a permissions or race issue can't redden CI.
   Only the verify gate in step 3 can fail the job.

Over time `refs/notes/attest` becomes attest's own audit trail: one `agent:ci`
attestation per merged commit. To inspect it from a fresh clone:

```sh
git clone https://github.com/CorvidLabs/attest.git
cd attest
git fetch origin "refs/notes/*:refs/notes/*"   # pull the attestation notes
attest log                                       # every attested commit
attest log --range origin/main~10..origin/main   # a recent slice
attest export --range origin/main~10..origin/main --policy .attest.json  # audit JSON
```

## Reproduce it locally

```sh
examples/dogfood.sh
```

The script clones attest into `/tmp` (falling back to the local checkout if the
remote needs auth), records the `agent:ci` attestation on the real `HEAD`, and
runs both the lax (PASS) and strict (FAIL) verifies, printing each exit code.
The strict FAIL is expected and captured, so the script itself exits `0`:

```console
lax    verify exit code: 0     (expected 0, PASS)
strict verify exit code: 1     (expected 1, FAIL, caught)
dogfood OK: attest attested attest, both outcomes as expected.
```

## Caveats

- CI attestations are **unsigned**. No signing key is provisioned on the runner
  (signing is optional by design). To make the ledger cryptographically
  verifiable, provision a key via `attest keygen`, sign with `--sign`, and
  tighten `.attest.json` with `requireSignature` / `trustedKeys`.
- The notes push is **best-effort and main-only**. PR runs record an attestation
  and verify it, but don't push notes (they often run without a write token).
- The committed `.attest.json` is intentionally permissive so the tool is usable
  with zero configuration; the strict policy above lives only in the demo/docs.
