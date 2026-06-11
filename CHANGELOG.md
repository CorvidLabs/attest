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
