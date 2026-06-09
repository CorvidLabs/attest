# Live examples

Every example here is self-contained: it builds the `attest` binary if needed, runs
against a throwaway repo in `/tmp` (signing keys in a temporary config dir), and cleans
up after itself. Nothing touches your real repo, your notes ref, or `~/.config`. Run one
and watch real output in seconds, with no setup:

```sh
bash examples/01-basic-attestation.sh
```

## Start here

- **[`01-basic-attestation.sh`](01-basic-attestation.sh)**: the shortest path. Record an
  attestation and read it back, no key, no policy.
- **[`04-signed-lifecycle.sh`](04-signed-lifecycle.sh)**: the full signed flow. `keygen`,
  `--sign`, the `signed[ok]` badge, and a `requireSignature` gate that PASSES then FAILS.

[`02-augur-integration.sh`](02-augur-integration.sh) uses `../augur` if it is present on
disk; if not, it falls back to a literal augur-shaped JSON payload so the integration still
runs end-to-end.

## All examples (simplest to most advanced)

| Example | What it shows | Run |
|---------|---------------|-----|
| [`01-basic-attestation.sh`](01-basic-attestation.sh) | Init a scratch repo, record an unsigned attestation for HEAD, and read it back. No key, no setup. | `bash examples/01-basic-attestation.sh` |
| [`02-augur-integration.sh`](02-augur-integration.sh) | Pipe `augur check --json` into `attest sign --from-augur -` so verdict and confidence fill in automatically. Falls back to a sample payload if augur is absent. | `bash examples/02-augur-integration.sh` |
| [`03-policy-gate.sh`](03-policy-gate.sh) | Write an `.attest.json` policy, then `attest verify` both passing and failing, with the exit codes a CI / agent loop reads. | `bash examples/03-policy-gate.sh` |
| [`04-signed-lifecycle.sh`](04-signed-lifecycle.sh) | Generate an Ed25519 key, sign an attestation, see `signed[ok]`, and gate on `requireSignature` (signed PASSES, later unsigned FAILS). | `bash examples/04-signed-lifecycle.sh` |
| [`05-audit-export.sh`](05-audit-export.sh) | Build a mixed history (signed/unsigned, human/agent) and emit the whole provenance trail as one stable JSON audit document with `attest export`. | `bash examples/05-audit-export.sh` |
| [`06-policy-rules.sh`](06-policy-rules.sh) | `allowedReviewers` (a per-commit reviewer allow-list) and `requireSignatureWhenVerdictAtLeast` (signature required once a verdict crosses a threshold), each with a PASS and a FAIL path. | `bash examples/06-policy-rules.sh` |
| [`07-signer-pinning.sh`](07-signer-pinning.sh) | Bind a reviewer identity to a key with `signerPinning` and restrict trusted signers with `trustedKeys`, so a spoofed `human:leif` cannot pass. | `bash examples/07-signer-pinning.sh` |
| [`08-freshness.sh`](08-freshness.sh) | `maxAgeDays` requires a recent attestation: a fresh sign-off PASSES, a backdated one FAILS. | `bash examples/08-freshness.sh` |
| [`dogfood.sh`](dogfood.sh) | attest attests attest: record provenance on attest's own real HEAD in a scratch clone, then PASS a lax policy and FAIL a strict one. | `bash examples/dogfood.sh` |

All scripts are macOS-only and require `git` on `PATH`. The first run builds `attest` with
`swift build`; later runs reuse the binary.
