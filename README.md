# attest

**A verifiable trust record for code changes.**

[![attest](https://img.shields.io/endpoint?url=https://corvidlabs.github.io/attest/badge.json)](https://corvidlabs.github.io/attest/)
[![CI](https://github.com/CorvidLabs/attest/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/attest/actions/workflows/ci.yml)
[![docs](https://img.shields.io/badge/docs-corvidlabs.github.io%2Fattest-blue)](https://corvidlabs.github.io/attest/)

<p align="center">
  <img src="site/public/demo.gif" alt="attest sign records a signed attestation, attest log shows the ledger, attest verify passes the policy" width="760">
</p>

```sh
brew install corvidlabs/tap/attest
```

`attest` records signed attestations (who or what reviewed a change, and at what confidence)
keyed to git commit SHAs and stored in **git notes**, so the trail travels with your repository
across every git host.

Built for the world where agents write most of the code. `augur` answers *how risky is this
diff, and should a human look?*, but that verdict is ephemeral. `attest` makes it durable: a
portable, optionally-signed record of what vetted a change, and a policy CI and agents can
gate on. **augur scores the risk; attest records the trust.**

## Quickstart

**Install** (macOS). The fastest path is Homebrew (macOS binary only):

```sh
brew install corvidlabs/tap/attest
```

Prefer to build from source? You need Swift 6 and `git` on `PATH`:

```sh
swift build -c release && install -m 0755 .build/release/attest /usr/local/bin/attest
```

**Try it instantly (no setup).** This builds the binary, records an attestation against a
throwaway `/tmp` repo, and reads it back. It touches nothing of yours:

```sh
bash examples/01-basic-attestation.sh
```

More runnable, self-contained examples (each against a throwaway repo) are catalogued in
[`examples/README.md`](examples/README.md).

**The core flow.** Generate a key once, sign an attestation on `HEAD`, read the ledger,
then gate on a policy (output below is real):

```sh
$ attest keygen
attest · wrote private key to ~/.config/attest/key (0600)
public key: SP19xVbn1MrVF3Ips/aQDR1sHAjHGb9iVzG9ePtluA0=

$ attest sign --commit HEAD --reviewer human:you --confidence 0.9 --tests-passed --sign
attest · recorded human:you on 77fe5ac11c (signed)

$ attest log --commit HEAD
attest · ledger

  commit 77fe5ac11c  (1 attestation)
    [·] human:you  verdict:-  conf:90%  tests:ok  human:-  signed[ok]
```

Verify against a policy. A floor it clears PASSES (exit 0); a stricter floor FAILS (exit 1),
the non-zero exit a CI job or agent loop gates on:

```sh
$ echo '{ "requireTestsPassed": true }' > lax.json
$ attest verify --commit HEAD --policy lax.json
attest verify · [ok] PASS (1 commit checked)        # exit 0

$ echo '{ "minimumConfidence": 0.95 }' > strict.json
$ attest verify --commit HEAD --policy strict.json
attest verify · [x] FAIL (1 commit checked)

  violations:
    x 77fe5ac11c  minimumConfidence: highest confidence 0.9 is below floor 0.95
                                                    # exit 1
```

**Where next:**

- [Documentation site](https://corvidlabs.github.io/attest/): the rendered docs.
- [`docs/cli.md`](docs/cli.md): every command and flag (`sign`, `verify`, `log`, `export`, `keygen`).
- [`docs/policy.md`](docs/policy.md): every policy rule with JSON examples.
- [`docs/signing.md`](docs/signing.md): keys, Ed25519, signing, and preventing reviewer spoofing.
- [`examples/README.md`](examples/README.md): the full catalog of live examples.

## Why it exists

Agents made code cheap to produce; the scarce resource is now *trust*. When an agent lands
a change, there is no native, portable record of which agent or human vetted it, and that
context is lost the moment the PR merges. `attest` is that missing primitive:

- **Humans** get an auditable trail: who signed off on what, and how sure they were.
- **Agents** get a gate: `attest verify` exits non-zero when a commit lacks the trust a
  policy demands, so an agent escalates instead of merging blind.

## How it works

- **Records** are `Attestation`s: a commit SHA, a reviewer (`agent:claude`, `human:leif`),
  a confidence (`0...1`), an optional verdict (`proceed`/`review`/`block`), tests-passed and
  human-approved flags, a timestamp, and an optional note.
- **Storage** is git notes under `refs/notes/attest`. No service, no database. Multiple
  attestations can accrue on one commit. Sync them with `git push origin "refs/notes/*"`.
- **Signing is optional.** Out of the box, attestations are unsigned but valid. Run
  `attest keygen` once and pass `--sign` to attach an Ed25519 signature over a deterministic
  canonical serialization (sorted keys, signature field excluded) that anyone can verify.
- **Policy** is plain JSON in `.attest.json`. No extra config language.

## Install

The recommended install on macOS is Homebrew, which pulls a prebuilt universal binary:

```sh
brew install corvidlabs/tap/attest
```

From source (Swift 6 and `git` on `PATH`):

```sh
swift build -c release
install -m 0755 .build/release/attest /usr/local/bin/attest
# or, with fledge:
fledge run install
```

Other options:

```sh
# Mint:
mint install CorvidLabs/attest

# SwiftPM experimental install (drops attest into ~/.swiftpm/bin):
swift package experimental-install
```

Signing uses [swift-crypto](https://github.com/apple/swift-crypto).

## Usage

```sh
# Record an attestation for the current commit (unsigned, zero setup):
attest sign --commit HEAD --reviewer agent:claude --confidence 0.92 --tests-passed

# Pipe augur straight in; verdict and confidence are auto-filled from its JSON:
augur check --json | attest sign --commit HEAD --reviewer agent:claude --from-augur -

# Optional: generate a key once, then sign records cryptographically:
attest keygen
attest sign --commit HEAD --reviewer human:leif --confidence 0.7 --human-approved --sign

# Read the ledger:
attest log                      # all attested commits
attest log --commit HEAD --json # one commit, machine-readable
attest log --range main..HEAD

# Gate in CI / an agent loop (exits non-zero on any violation):
attest verify --range origin/main..HEAD --policy .attest.json

# Export the whole range as one stable JSON audit document (for archival):
attest export --range origin/main..HEAD --policy .attest.json
```

### `--from-augur`

`attest sign --from-augur <file|->` reads `augur check --json` and merges it: augur's
`verdict` is copied, and its `riskScore` (0...100) becomes `confidence = 1 - riskScore/100`.
Explicit `--verdict` / `--confidence` flags override the augur-derived values.

```sh
augur check --range main..HEAD --json \
  | attest sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed
```

## Policy (`.attest.json`)

All rules are optional with permissive defaults. An empty `{}` still requires one
attestation per commit and passes any commit that has one.

> **Trust-model warning, read first.** A gate is only as strong as the rule that ties a
> record to a key:
>
> - `requireSignature: true` **alone does NOT bind identity.** It proves only that *some*
>   key signed, not *whose*. An attacker can sign with their own key while claiming
>   `reviewer: human:leif` and pass. To actually stop reviewer spoofing, use **`signerPinning`**
>   (binds a reviewer to a key) or **`trustedKeys` + `requireSignature` together**. `trustedKeys`
>   alone does not force signing; `requireSignature` alone does not check the key.
> - `minimumConfidence` and `requireTestsPassed` are satisfied by **any** attestation on the
>   commit, including an injected one. Combine them with **`allowedReviewers`** or
>   **`signerPinning`** to bind that evidence to reviewers you trust.
>
> See [`docs/policy.md`](docs/policy.md) for the full trust model.

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireHumanApprovalWhenVerdictAtLeast": "review",
  "requireSignature": false,
  "minimumConfidence": 0.6,
  "allowedReviewers": ["human:", "agent:claude"],
  "requireSignatureWhenVerdictAtLeast": "block",
  "requireTestsPassedWhenVerdictAtLeast": "review",
  "trustedKeys": ["BASE64_PUBKEY_A", "BASE64_PUBKEY_B"],
  "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" },
  "maxAgeDays": 90
}
```

| Rule | Fails a commit when… |
|------|----------------------|
| `requireAttestation` | the commit has no attestations. |
| `requireTestsPassed` | no attestation reports `testsPassed`. |
| `requireHumanApprovalWhenVerdictAtLeast` | some attestation's verdict is at/above the level but no attestation on the commit is `humanApproved`. The human sign-off can be a *separate* attestation (e.g. `attest sign --reviewer human:leif --human-approved`); it need not restate the verdict. |
| `requireSignature` | no *valid signed* attestation exists. |
| `minimumConfidence` | the highest recorded confidence is below the floor. |
| `allowedReviewers` | any attestation on the commit has a `reviewer` outside the allow-list. Matching per pattern: an **exact** match against the full reviewer string, *or* (when the pattern ends with `:`, e.g. `"human:"`) a **prefix** match, so `"human:"` allows any `human:*` reviewer while `"agent:claude"` matches only exactly. A `nil`/empty list disables the rule. |
| `requireSignatureWhenVerdictAtLeast` | some attestation's verdict is at/above the level but no attestation on the commit is *validly signed*. The signature can be a *separate* attestation. Not triggered when every verdict is below the level. |
| `requireTestsPassedWhenVerdictAtLeast` | some attestation's verdict is at/above the level but no attestation on the commit reports `testsPassed`. The passing-tests record can be a *separate* attestation. Not triggered when every verdict is below the level. |
| `trustedKeys` | any *signed* attestation on the commit fails to verify, or carries a `publicKey` that is **not** in this list of trusted base64 Ed25519 keys. Unsigned attestations are **unaffected**: `trustedKeys` constrains *which keys count as trusted*, it does **not** force signing (use `requireSignature` for that). A `nil`/empty list disables the rule. |
| `signerPinning` | an attestation whose `reviewer` is a key in this `{reviewer: base64 pubkey}` map is **unsigned**, or **signed with a different key** (or tampered). Reviewers absent from the map are unaffected. This binds identity to a key, and it is what stops a spoofed `reviewer: human:leif` that `allowedReviewers` (a string-only gate) cannot. A `nil`/empty map disables the rule. |
| `maxAgeDays` | the commit's **newest** attestation is older than this many whole days (or the commit has no attestations at all). A single fresh record clears the commit even alongside older ones; age is measured against an injected reference time, so a stale `block` from months ago can no longer rubber-stamp today's commit. A `nil` value disables the rule. |

### Preventing reviewer spoofing

`allowedReviewers` gates the reviewer *string*, but nothing stops anyone from filing an
attestation that simply *claims* `reviewer: human:leif`. To bind an identity to a
cryptographic key, use **`signerPinning`** (pin specific reviewers to specific keys) and/or
**`trustedKeys`** (restrict which keys count as trusted at all):

```json
{
  "requireSignature": true,
  "trustedKeys": ["BASE64_LEIF_PUBKEY", "BASE64_CI_PUBKEY"],
  "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" }
}
```

```sh
# leif generates a key once; keygen prints the PUBLIC key to copy into the policy:
attest keygen
# attest · wrote private key to ~/.config/attest/key (0600)
# public key: BASE64_LEIF_PUBKEY      <- copy this into signerPinning / trustedKeys

# a genuine, signed sign-off as human:leif PASSES:
attest sign --commit HEAD --reviewer human:leif --confidence 0.95 \
  --verdict review --human-approved --sign
attest verify --commit HEAD            # exit 0

# a spoof (claiming human:leif unsigned, or signed with someone else's key) FAILS:
attest sign --commit HEAD --reviewer human:leif --confidence 0.95   # unsigned claim
attest verify --commit HEAD            # exit 1: reviewer human:leif is pinned but unsigned
```

The two rules compose:

- **`signerPinning`** is per-reviewer: only reviewers in the map are constrained, and each must
  be signed with its *exact* pinned key. This is the rule that stops `human:leif` spoofing.
- **`trustedKeys`** is global: it does **not** force signing (an unsigned record passes it, so pair
  it with `requireSignature: true` to require a signature), but *any* record that **is** signed
  must verify and use a key from the trusted set. It bounds the universe of acceptable signers.

The full pinned lifecycle (correct-key PASS, then wrong-key/unsigned FAIL) is demonstrated
end-to-end in [`examples/07-signer-pinning.sh`](examples/07-signer-pinning.sh).

### Keeping trust fresh (`maxAgeDays`)

Trust decays. A `block`/`review` verdict, or any sign-off, from months ago should not silently
keep clearing today's commit. `maxAgeDays` makes the commit's **newest** attestation prove
recency: the commit passes only when some attestation is within `maxAgeDays` whole days of the
verification time (a single fresh record clears it, even alongside older ones), and a commit with
no attestations at all fails too.

```json
{ "maxAgeDays": 30 }
```

The reference "now" is **injected** into the engine (defaulted to the current epoch at the CLI),
not read from the system clock inside the verifier, so verification is deterministic and testable.
A fresh-PASS → stale-FAIL lifecycle is demonstrated end-to-end in
[`examples/08-freshness.sh`](examples/08-freshness.sh). See [`docs/policy.md`](docs/policy.md) for
the exact semantics.

A default `.attest.json` ships at the repo root. It is intentionally permissive
(it gates nothing yet) so it demonstrates the schema without breaking a repo that
has no attestations:

```json
{
  "requireAttestation": false,
  "requireTestsPassed": false,
  "requireSignature": false,
  "requireHumanApprovalWhenVerdictAtLeast": "block"
}
```

Tighten the rules as a repo starts recording attestations.

### In CI

Run the binary directly:

```yaml
- run: attest verify --range origin/main..HEAD --policy .attest.json
```

Or drop in the **GitHub Action** (`CorvidLabs/attest`) from **any** repo. It
installs a prebuilt `attest` for the runner (macOS universal or Linux x86_64)
from the matching release, then runs `attest verify` against your checkout — no
Swift toolchain required. On other platforms it falls back to building `attest`
from its own source (which needs Swift on the runner):

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

Pin to the moving `@v0` tag to track the latest 0.x release, or to an exact tag
(e.g. `@v0.3.0`) to lock a specific version.

| Input | Default | Description |
|-------|---------|-------------|
| `range` | `origin/main..HEAD` | Git range to verify (needs full history). |
| `policy` | `.attest.json` | Path to the policy file (relative to `working-directory`). It must exist: a missing or misspelled policy fails the gate rather than silently passing under the permissive default. |
| `forward-from` | `""` | Optional reviewed source commit to forward before verification, useful for squash merges. |
| `forward-to` | `HEAD` | Landed commit to attest when `forward-from` is set. |
| `forward-reviewer` | `ci:attest-forward` | Reviewer identity for the forwarded attestation. |
| `forward-sign` | `false` | Sign the forwarded attestation with the runner's `attest keygen` key. |
| `working-directory` | `.` | Directory to run `attest verify` in. |
| `version` | *(action ref)* | attest release to install (`v0.3.0` or `latest`); defaults to the pinned tag, else `latest`. |

| Output | Description |
|--------|-------------|
| `binary` | Absolute path to the `attest` binary used. |

The gate's contract is the **exit code**: a policy violation propagates
`attest`'s non-zero exit and fails the job.

For squash-merge repositories, attest the reviewed PR head before merge, then forward that
provenance to the squash commit in the protected-branch workflow before the normal verify step:

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

Forwarding records a new attestation whose `commit` is the landed squash SHA; the reviewed source
SHA is preserved in the note for audit. Verification remains exact-SHA verification.

> **Platform.** Prebuilt binaries cover **GitHub-hosted macOS and Linux x86_64
> runners**. Other runners (e.g. `windows-latest`, Linux arm64) need a Swift
> toolchain so the action can build from source. Windows is out of scope.

### For agents

```sh
augur check --range main..HEAD --json | attest sign --commit HEAD --reviewer agent:claude --from-augur -
attest verify --commit HEAD || echo "trust policy not satisfied, escalating to a human"
```

## JSON shape

`attest log --commit HEAD --json`:

```json
[
  {
    "attestations": [
      {
        "commit": "9f2c1a7b04...",
        "confidence": 0.92,
        "humanApproved": false,
        "publicKey": "base64...",
        "reviewer": "agent:claude",
        "signature": "base64...",
        "testsPassed": true,
        "timestamp": 1700000000,
        "verdict": "proceed"
      }
    ],
    "commit": "9f2c1a7b04..."
  }
]
```

`attest verify --json`:

```json
{ "checkedCommits": 1, "passed": false, "violations": [ { "commit": "…", "detail": "…", "rule": "requireTestsPassed" } ] }
```

## Audit & compliance

`attest log` is a *human/diagnostic* listing. `attest export` is its archival
counterpart: a single, **stable JSON document** covering the *complete*
provenance trail across a commit range: every commit, every attestation, each
record's cryptographic **verification status**, and (with `--policy`) a
per-commit pass/fail. Output is deterministic (sorted keys; commits oldest-first,
the order `git rev-list --reverse` returns), so it diffs cleanly and is suitable
for compliance archival.

```sh
attest export --range origin/main..HEAD                      # whole range
attest export --commit HEAD                                  # one commit
attest export --range main..HEAD --policy .attest.json       # with per-commit verdicts
attest export --range main..HEAD --no-pretty > audit.json    # compact, for storage
```

It is always JSON (no `--json` flag); pass `--no-pretty` for compact output.
Each record's `verification` says whether it is `signed` and, for signed
records, whether the embedded signature `verified` against its embedded public
key (a tampered or wrong-key record reports `verified: false`); unsigned records
omit `verified`.

```json
{
  "allPassed": true,
  "commitCount": 1,
  "commits": [
    {
      "commit": "9f2c1a7b04...",
      "policyPassed": true,
      "records": [
        {
          "attestation": {
            "commit": "9f2c1a7b04...",
            "confidence": 0.92,
            "humanApproved": false,
            "publicKey": "base64...",
            "reviewer": "agent:claude",
            "signature": "base64...",
            "testsPassed": true,
            "timestamp": 1700000000,
            "verdict": "proceed"
          },
          "verification": { "signed": true, "verified": true }
        }
      ]
    }
  ],
  "policyApplied": true,
  "recordCount": 1,
  "version": 1
}
```

**How it complements `log`/`verify`.** `log` is for a human reading the ledger;
`verify` is an exit-code gate for CI / agent loops; `export` is the durable
record an auditor keeps. It folds in `verify`'s policy verdict *and* the
per-record signature checks `log` only badges, across the full range, in one
machine-stable file. A natural CI / pre-commit archival step:

```sh
# archive the trust trail for this PR alongside the build artifacts
attest export --range origin/main..HEAD --policy .attest.json --no-pretty > audit.json
```

The full mixed (signed/unsigned, human/agent) lifecycle is demonstrated
end-to-end in [`examples/05-audit-export.sh`](examples/05-audit-export.sh).

## Documentation

In-depth docs live in [`docs/`](docs/):

- [`docs/architecture.md`](docs/architecture.md): the `AttestKit` vs CLI split, canonical
  serialization, git-notes storage, the signing model, and the verify / export flow.
- [`docs/policy.md`](docs/policy.md): every policy rule (all 11, including `maxAgeDays`) with JSON
  examples, the `WhenVerdictAtLeast` semantics, and signer pinning.
- [`docs/cli.md`](docs/cli.md): every command and flag (`sign`, `verify`, `log`, `export`,
  `keygen`) with examples and exit codes.
- [`docs/signing.md`](docs/signing.md): `keygen`, Ed25519, optional signing,
  `trustedKeys`/`signerPinning`, and preventing reviewer spoofing.
- [`docs/ci-integration.md`](docs/ci-integration.md): macOS and Linux CI, the `attest-verify`
  action, the augur → attest trust pipeline, and audit export for compliance.
- [`docs/dogfooding.md`](docs/dogfooding.md): **proof:** attest attests attest. Real captured
  output of attest recording + verifying provenance on its own commits (a PASS and a FAIL),
  plus the growing CI provenance ledger. Reproduce with [`examples/dogfood.sh`](examples/dogfood.sh).

## Dogfooding (proof)

attest uses itself: every commit on `main` gets an `agent:ci` attestation recorded **by attest,
on attest's own history**, gated against [`​.attest.json`](.attest.json) in CI, with the ledger
pushed to `refs/notes/attest` so it accumulates over time. Run [`examples/dogfood.sh`](examples/dogfood.sh)
to see attest attest its real `HEAD` and both pass a lax policy and fail a strict one. Full
captured proof and the CI wiring live in [`docs/dogfooding.md`](docs/dogfooding.md).

## Development

```sh
fledge run check     # build + test + spec check
fledge run test
fledge run spec      # spec-sync alignment
fledge run examples  # run the example scripts against scratch repos
```

The engine (`AttestKit`) is fully testable without `git` via the `AttestationStore`
protocol and an `InMemoryStore` fake. It depends only on Apple's `swift-crypto`; the CLI
uses `swift-argument-parser`.

## Trust layer (attest + augur)

[`augur`](https://github.com/CorvidLabs/augur) is the upstream risk scorer:
`augur check` emits `proceed | review | block` with a risk score. That verdict is
*ephemeral*. `attest` makes it durable: it records that verdict (and anything
else a reviewer asserts) as a portable, optionally-signed artifact, then gates on
it. **augur scores the risk; attest records the trust.** They compose over a
pipe; `attest` never links `augur`.

```sh
augur check --json | attest sign --from-augur -
```

`--from-augur` copies augur's `verdict` and maps its `riskScore` (0...100) to
`confidence = 1 - riskScore/100`. A worked, verified run (a risk-45 `review` diff
becomes a 0.55-confidence attestation):

```
$ echo '{"verdict":"review","riskScore":45.0}' \
    | attest sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed
attest · recorded agent:claude on 9f2c1a7b04

$ attest log --commit HEAD
attest · ledger

  commit 9f2c1a7b04  (1 attestation)
    [!] agent:claude  verdict:review  conf:55%  tests:ok  human:-  unsigned
```

The full signed lifecycle (`keygen` → `--sign` → `signed[ok]` → `verify` against
`{"requireSignature": true}`) is demonstrated end-to-end in
[`examples/04-signed-lifecycle.sh`](examples/04-signed-lifecycle.sh).

## Limitations & roadmap

- **macOS and Linux.** CI runs on both platforms (`build-test-macos` and
  `build-test-linux`). The Homebrew prebuilt binary and the composite `action.yml`
  currently target macOS. Windows is out of scope.
- The composite action (`action.yml`) builds `attest` from its own checkout.
  **Cross-repo packaging** (shipping a prebuilt binary and installing it into
  other repos without a Swift toolchain) is a deferred later step.
- `attest` uses a single local Ed25519 key and embeds the public key on each
  record. It is not a CA: key distribution / web-of-trust and signer pinning are
  roadmap items.

## License

MIT © CorvidLabs
