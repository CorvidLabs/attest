# attest

**A verifiable trust record for code changes.** `attest` records signed attestations —
*who or what reviewed a change, and at what confidence* — keyed to git commit SHAs and
stored in **git notes**, so the trail travels with your repository across every git host.

It's built for the world where agents write most of the code. `augur` answers *how risky
is this diff, and should a human look?* — but that verdict is ephemeral. `attest` makes it
durable: a portable, optionally-signed record of what vetted a change, and a policy CI and
agents can gate on. **augur scores the risk; attest records the trust.**

```
$ attest log

attest · ledger

  commit 9f2c1a7b04  (2 attestations)
    [ok] agent:claude  verdict:proceed  conf:92%  tests:ok  human:—  signed[ok]
    [!] human:leif  verdict:review  conf:70%  tests:ok  human:ok  unsigned
        note: looked at the auth path, fine to ship
```

## Why it exists

Agents made code cheap to produce; the scarce resource is now *trust*. When an agent lands
a change, there is no native, portable record of which agent or human vetted it — that
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
- **Policy** is plain JSON in `.attest.json` — no extra config language.

## Install

```sh
swift build -c release
install -m 0755 .build/release/attest /usr/local/bin/attest
# or, with fledge:
fledge run install
```

Requires Swift 6 and `git` on `PATH`. Signing uses [swift-crypto](https://github.com/apple/swift-crypto).

## Usage

```sh
# Record an attestation for the current commit (unsigned, zero setup):
attest sign --commit HEAD --reviewer agent:claude --confidence 0.92 --tests-passed

# Pipe augur straight in — verdict + confidence are auto-filled from its JSON:
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

All rules are optional with permissive defaults — an empty `{}` still requires one
attestation per commit and passes any commit that has one.

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireHumanApprovalWhenVerdictAtLeast": "review",
  "requireSignature": false,
  "minimumConfidence": 0.6
}
```

| Rule | Fails a commit when… |
|------|----------------------|
| `requireAttestation` | the commit has no attestations. |
| `requireTestsPassed` | no attestation reports `testsPassed`. |
| `requireHumanApprovalWhenVerdictAtLeast` | a verdict is at/above the level but no attestation is `humanApproved`. |
| `requireSignature` | no *valid signed* attestation exists. |
| `minimumConfidence` | the highest recorded confidence is below the floor. |

### In CI

```yaml
- run: attest verify --range origin/main..HEAD --policy .attest.json
```

### For agents

```sh
augur check --range main..HEAD --json | attest sign --commit HEAD --reviewer agent:claude --from-augur -
attest verify --commit HEAD || echo "trust policy not satisfied — escalating to a human"
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

## Relationship to augur

[`augur`](https://github.com/CorvidLabs/augur) is the upstream risk scorer:
`augur check` emits `proceed | review | block` with a risk score. `attest` records that
verdict (and anything else a reviewer asserts) as a durable, signed artifact, then gates on
it. They compose over a pipe — `attest` never links `augur`.

## Limitations

- The git-notes store and signing are validated on **macOS** (the package targets
  `.macOS(.v13)`). Linux/Windows support is plausible via Foundation `Process` + swift-crypto
  but is not yet on the CI matrix.
- `attest` uses a single local Ed25519 key and embeds the public key on each record. It is
  not a CA: key distribution / web-of-trust and signer pinning are roadmap items.

## License

MIT © CorvidLabs
