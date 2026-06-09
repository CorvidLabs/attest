---
title: "Documentation"
description: "attest: signed provenance & attestation ledger for code changes."
section: "Getting started"
order: 0
---

`attest` records signed **attestations** (*who or what reviewed a change, and at what
confidence*) keyed to git commit SHAs and stored in **git notes** (`refs/notes/attest`), so the
trail travels with your repository across every git host. It is the trust-record companion to
[`augur`](https://github.com/CorvidLabs/augur): **augur scores the risk; attest records the
trust.**

## Start here

- **[Quickstart](/attest/docs/quickstart)**: install, record your first attestation, and verify
  it against a policy in under a minute.
- **[Policy reference](/attest/docs/policy)**: every one of the 11 rules, with JSON examples and
  the `WhenVerdictAtLeast` semantics.
- **[CLI reference](/attest/docs/cli)**: `sign`, `verify`, `log`, `export`, `keygen`, every flag
  and exit code.
- **[Signing & identity](/attest/docs/signing)**: Ed25519, `keygen`, `trustedKeys` /
  `signerPinning`, and preventing reviewer spoofing.
- **[CI integration](/attest/docs/ci-integration)**: the `attest-verify` action, the augur →
  attest pipeline, and audit export.
- **[Architecture](/attest/docs/architecture)**: the `AttestKit` vs CLI split, canonical
  serialization, git-notes storage, and the verify / export flow.

## The shape of a record

An `Attestation` is a provenance record keyed to a commit SHA: a `reviewer`
(`agent:claude`, `human:leif`), a `confidence` (`0…1`), an optional `verdict`
(`proceed` / `review` / `block`), `testsPassed` and `humanApproved` flags, a `timestamp`, an
optional `note`, and (when signed) a base64 Ed25519 `signature` and `publicKey`.

Signing is **optional**: an unsigned attestation is a fully valid record. Signing is what lets a
policy *trust* a record and bind it to an identity.

## Why it exists

Agents made code cheap to produce; the scarce resource is now *trust*. When an agent lands a
change, there is no native, portable record of which agent or human vetted it, and that context is
lost the moment the PR merges. attest is that missing primitive:

- **Humans** get an auditable trail: who signed off on what, and how sure they were.
- **Agents** get a gate: `attest verify` exits non-zero when a commit lacks the trust a policy
  demands, so an agent escalates instead of merging blind.
