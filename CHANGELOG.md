# Changelog

## [Unreleased]

### Other

- Add: colorful terminal output for `attest log`/`verify` — semantic, TTY/`NO_COLOR`-aware ANSI colour via a dependency-free `Colorizer`, gated by `--color auto|always|never`; piped and `--json` output stays plain.

## [v0.1.0] - 2026-06-09

### Other

- Add: maxAgeDays freshness policy, expanded tests, and docs/ (#6) (c02a7e5)
- Add: trustedKeys and signerPinning policy rules (prevent reviewer spoofing) (#5) (8c9453a)
- Add: allowedReviewers, requireSignatureWhenVerdictAtLeast, requireTestsPassedWhenVerdictAtLeast policy rules (#4) (e4616d2)
- Fix: --human-approved no longer requires --confidence (#3) (eff5cf6)
- Fix: human-approval policy accepts a separate human-approved attestation (#2) (d6cfe71)
- Add: attest export — range-wide JSON audit trail (#1) (25ec6c2)
- Add: attest-verify composite action, signed-lifecycle example, default policy (8e0972f)
- Add: attest — signed provenance & attestation ledger for code changes (dd68f53)

