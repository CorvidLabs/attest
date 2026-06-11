# Changelog

## [v0.3.2] - 2026-06-10

### Other

- Fix: statically link the Swift stdlib in the Linux release binary
  (`--static-swift-stdlib`) so `attest-linux-x86_64` runs on a bare runner with
  no Swift toolchain. The v0.3.1 Linux asset failed at runtime with a missing
  `libswiftCore.so`. Caught by a new CI smoke-test of the action itself.

## [v0.3.1] - 2026-06-10

### Other

- Add: Marketplace-ready GitHub Action that gates any repo (#26) — installs a
  prebuilt attest (macOS universal / Linux x86_64) for the runner with a
  source-build fallback, publishes the Linux release asset, and moves the `v0`
  major tag on each release.

## [v0.3.0] - 2026-06-10

### Other

- Release v0.3.0: bump CLI version (ecf1121)
- Add: Linux support via posix_spawn ProcessRunner and Linux CI job (#25) (c0adfcb)
- Add: animated demo GIF to README and site (#24) (545fdfe)
- Security: move CI off self-hosted runners to GitHub-hosted (#23) (e640814)
- Fix: read the hero badge version from CHANGELOG so it does not drift (#22) (298a5f4)
- Add: release binary + brew formula automation, lead with brew, decouple Pages from self-hosted (#21) (f81dc1d)
- Fix: rebuild the site on CHANGELOG changes so the version badge stays accurate (#20) (6e4ce27)

## [v0.2.0] - 2026-06-09

### Other

- Release v0.2.0: bump CLI version (5e1a803)
- Fix: bind attestations to their commit, rejecting cross-commit signature replay (#19) (4afd4b1)
- Chore: surface policy trust-model caveats, tidy errors and changelog (#18) (d3e967a)
- Fix: mobile horizontal overflow on the attest landing pillars (#17) (2b9f682)
- Add: Quickstart and a live-examples index (#16) (a8d8900)
- Fix: PR CI checkout depth so attest sign finds the PR head commit (#15) (126f138)
- Fix: CI ledger now grows (fetch notes before signing, consistent SHA) (#14) (83dbc9f)
- Add: commit-status check + live Pages badge for attest (#13) (650967e)
- Chore: rewrite docs/site copy in plain voice, drop em-dashes (#12) (cca5146)
- Add: attest self-dogfooding (CI provenance ledger + examples/dogfood.sh + docs/dogfooding.md) (#11) (0e8500b)
- Add: terminal snapshot tests + site mockups accurate to colored output (#10) (a4e3caa)
- Add: colorful terminal output + red site palette (#9) (fca01e2)
- Chore: Node 24 workflow opt-in + review polish (#8) (c6f9826)
- Add: Astro GitHub Pages marketing + docs site (#7) (69c5191)

## [Unreleased]

### Other

- Fix: an explicitly passed `--policy` path that does not exist is now a hard error (exit 1, `Policy file not found: …`) instead of a silent PASS under the permissive default — a typo'd policy path in CI can no longer drop `requireSignature`/pinning rules. The implicit `.attest.json` lookup still falls back silently when absent.
- Fix: policy parsing is strict — an unknown (misspelled) rule name like `minimumConfidenceTYPO` is a hard error naming the offending key(s) and listing the valid rule names, instead of being silently ignored.
- Fix: a malformed policy file now renders a human message (`Malformed policy <file>: not valid JSON (… line/column …)`, or the offending key path on a type mismatch) instead of dumping a raw Swift `DecodingError`.
- Fix: `attest sign` rejects out-of-range `--confidence` at the CLI (exit 64, `confidence must be in 0...1`) instead of silently clamping 1.5 to 1.0; the library clamp remains as a safety net. Negative values use the `--confidence=-0.3` form.
- Fix: a bare `attest log` lists attested commits newest-first in history order (like the `--range` path) instead of SHA-alphabetical order; a bare `attest export` covers them oldest-first, matching its range convention.
- Fix: bad commit/range errors surface git's own explanation (`Unknown revision: deadbeef123`; `… unknown revision or path not in the working tree.`) instead of leaking plumbing like `git rev-parse --verify deadbeef123^{commit} failed (exit 128)`.
- Fix: one corrupt note line no longer hides the valid records stored in the same note — `attest log` skips it with a stderr warning (and still exits non-zero) while printing every readable record.
- Add: `attest sign --sign` warns on stderr when the signing key file's permissions are looser than `0600`.
- Chore: surface the policy trust-model caveats in the docs, tidy the malformed-record error and `attest log` corrupt-note handling, and scrub the changelog.
- Add: attest self-dogfooding. attest records provenance attestations on its OWN commits. CI (self-hosted macOS) attests each commit with an `agent:ci` record and gates it against `.attest.json` (fatal), pushing the growing ledger to `refs/notes/attest` on `main`. New `examples/dogfood.sh` (PASS under a lax / FAIL under a strict policy on attest's real HEAD) and `docs/dogfooding.md` with real captured proof.
- Add: colorful terminal output for `attest log` and `verify`. Semantic, TTY/`NO_COLOR`-aware ANSI colour via a dependency-free `Colorizer`, gated by `--color auto|always|never`; piped and `--json` output stays plain.

## [v0.1.0] - 2026-06-09

### Other

- Add: maxAgeDays freshness policy, expanded tests, and docs/ (#6) (c02a7e5)
- Add: trustedKeys and signerPinning policy rules (prevent reviewer spoofing) (#5) (8c9453a)
- Add: allowedReviewers, requireSignatureWhenVerdictAtLeast, requireTestsPassedWhenVerdictAtLeast policy rules (#4) (e4616d2)
- Fix: --human-approved no longer requires --confidence (#3) (eff5cf6)
- Fix: human-approval policy accepts a separate human-approved attestation (#2) (d6cfe71)
- Add: attest export, range-wide JSON audit trail (#1) (25ec6c2)
- Add: attest-verify composite action, signed-lifecycle example, default policy (8e0972f)
- Add: attest, signed provenance & attestation ledger for code changes (dd68f53)
</content>
</invoke>
