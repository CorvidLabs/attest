# AGENTS.md: attest

Guidance for AI agents working in this repository.

## What attest is

A signed provenance & attestation ledger for code changes. It records *who or what
reviewed a change and at what confidence*, keyed to git commit SHAs, stored portably in
git notes (`refs/notes/attest`), and enforces a policy in CI / agent loops. It is the
trust-record companion to `augur`: augur scores diff risk, attest records the trust.

## Golden rules

1. Signing stays **optional**. An unsigned attestation must remain a valid record. Never
   make a key or a policy file mandatory for the tool to work.
2. The **canonical serialization** is the contract for signatures. It must stay
   deterministic (sorted keys, unescaped slashes) and must exclude the `signature` /
   `publicKey` fields. Changing it invalidates every existing signature, so treat it as breaking.
3. `AttestKit` depends only on Apple packages (`swift-crypto`). The CLI may add
   `swift-argument-parser`. No other third-party dependencies.
4. Policy is plain JSON via Foundation. Do **not** add a YAML/TOML parser for `.attest.json`.
5. Follow CorvidLabs Swift conventions: explicit access control, K&R braces, no force
   unwrap, `async`/`await`, `Sendable`, descriptive generics, strict concurrency.

## Layout

| Path | Role |
|------|------|
| `Sources/AttestKit/` | The engine library (model, signing, storage, policy). |
| `Sources/attest/` | The CLI (`swift-argument-parser`). |
| `Tests/AttestKitTests/` | Engine tests via an in-memory `AttestationStore`. |
| `specs/provenance-ledger/` | The spec spec-sync validates against the code. |
| `examples/` | Runnable shell scripts against throwaway `/tmp` repos. |
| `action.yml` | Composite GitHub Action ("attest verify") that builds attest from its own checkout and gates a range against `.attest.json`. |
| `.attest.json` | The committed default policy (permissive; demonstrates the schema). |

## CI / platform

attest is **macOS-only for now**. Do not add Linux/Windows runners or support. CI
runs on the self-hosted **macOS ARM64** runners (`runs-on: [self-hosted, macOS]`):
`swift build`, `swift test`, `fledge spec check`, plus a non-fatal dogfood step that
runs `attest verify` against the latest commit. The composite action in `action.yml`
builds attest from its own checkout; cross-repo binary packaging is deferred.

## Workflow

```sh
fledge run check     # build + test + spec, run before claiming done
fledge run test
fledge run spec
fledge run examples  # run the example scripts against scratch repos
```

If you change the public API of `AttestKit`, update
`specs/provenance-ledger/provenance-ledger.spec.md` and bump its `version` so
`fledge spec check` passes.

## Adding a policy rule

1. Add the field to `Policy` with a permissive default and `decodeIfPresent` in its decoder.
2. Add evaluation in `Verifier.evaluate`, emitting a `Violation` with a clear `detail`.
3. Add a test in `AttestKitTests` (pass and fail cases).
4. Document it in the README policy table and the spec's Public API / Behavioral Examples.
