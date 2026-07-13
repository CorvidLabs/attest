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
| `action.yml` | GitHub Action ("attest verify") that installs a prebuilt attest (macOS universal / Linux x86_64) for the runner — falling back to building from its own checkout — and gates a range against `.attest.json`. |
| `.attest.json` | The committed default policy (permissive; demonstrates the schema). |

## CI / platform

attest supports **macOS and Linux**. Windows is out of scope.

CI runs two jobs:

- **`build-test-macos`** (`runs-on: macos-latest`): `swift build`, `swift test`,
  `fledge spec check`, plus the dogfood sign/verify/notes steps.
- **`build-test-linux`** (`runs-on: ubuntu-latest`, `container: swift:6.0`):
  `swift build` and `swift test` only. No brew, fledge, dogfood, or notes steps.

The action in `action.yml` installs a prebuilt attest matching the runner
(`attest-macos-universal` / `attest-linux-x86_64`, published by `release.yml`),
falling back to building from its own checkout when no prebuilt binary fits. So
`release.yml` must keep publishing both assets + their sha256 sidecars.

Do not add Windows runners or Windows-specific code.

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

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge lanes run verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
