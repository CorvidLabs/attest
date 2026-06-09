---
title: "Policy reference"
description: "Every one of attest's 11 policy rules, with JSON examples and the WhenVerdictAtLeast semantics."
section: "Reference"
order: 1
---

A policy is plain JSON in `.attest.json` — no extra config language. Every rule is **optional with
a permissive default**, so an empty `{}` policy still requires one attestation per commit and
passes any commit that has one. `attest verify` evaluates the policy over a commit (or range) and
exits non-zero on any violation.

```sh
attest verify --range origin/main..HEAD --policy .attest.json
```

A policy is evaluated against *all* of a commit's attestations as a set — the rules that talk
about "any attestation" or "some attestation" are satisfied (or violated) by records anywhere on
the commit, not necessarily the same one.

## All 11 rules

| Rule | Type | Default | Fails a commit when… |
|------|------|---------|----------------------|
| `requireAttestation` | `Bool` | `true` | the commit has no attestations. |
| `requireTestsPassed` | `Bool` | `false` | no attestation reports `testsPassed: true`. |
| `requireSignature` | `Bool` | `false` | no *valid signed* attestation exists. |
| `minimumConfidence` | `Double?` | `nil` | the highest recorded `confidence` is below the floor. |
| `requireHumanApprovalWhenVerdictAtLeast` | `Verdict?` | `nil` | some attestation's verdict is at/above the level but none on the commit is `humanApproved`. |
| `allowedReviewers` | `[String]?` | `nil` | any attestation's `reviewer` is outside the allow-list. |
| `requireSignatureWhenVerdictAtLeast` | `Verdict?` | `nil` | some verdict is at/above the level but no attestation is validly signed. |
| `requireTestsPassedWhenVerdictAtLeast` | `Verdict?` | `nil` | some verdict is at/above the level but no attestation reports passing tests. |
| `trustedKeys` | `[String]?` | `nil` | any *signed* attestation fails to verify or uses a `publicKey` not in the list. |
| `signerPinning` | `[String: String]?` | `nil` | a pinned reviewer is unsigned or signed with the wrong key. |
| `maxAgeDays` | `Int?` | `nil` | the commit's newest attestation is older than this many days (or it has none). |

A `Verdict` is one of `"proceed"`, `"review"`, `"block"` (ordered `proceed < review < block`).

## A maximal policy

```json
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireSignature": false,
  "minimumConfidence": 0.6,
  "requireHumanApprovalWhenVerdictAtLeast": "review",
  "allowedReviewers": ["human:", "agent:claude"],
  "requireSignatureWhenVerdictAtLeast": "block",
  "requireTestsPassedWhenVerdictAtLeast": "review",
  "trustedKeys": ["BASE64_PUBKEY_A", "BASE64_PUBKEY_B"],
  "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" },
  "maxAgeDays": 90
}
```

## Rule details

### `requireAttestation`

The baseline. When `true` (the default), a commit with zero attestations fails. Set it to `false`
to let commits with no provenance pass — useful for a permissive starter policy on a repo that is
only beginning to record attestations.

### `requireTestsPassed` / `requireSignature`

Unconditional evidence gates. `requireTestsPassed` needs at least one attestation with
`testsPassed: true`; `requireSignature` needs at least one attestation that is signed **and** whose
signature verifies.

### `minimumConfidence`

A floor on the **highest** recorded confidence across the commit's attestations. If the best
attestation's `confidence` is below the floor, the commit fails.

```json
{ "minimumConfidence": 0.8 }
```

### The `WhenVerdictAtLeast` rules

Three rules are *conditional* — they only trigger when the recorded risk is high enough, then
demand a stronger form of evidence. The "at least" semantics use `Verdict` ordering, and the rule
**triggers when any attestation on the commit carries a verdict at or above the threshold**:

- **`requireHumanApprovalWhenVerdictAtLeast`** — once triggered, the commit must have *some*
  attestation that is `humanApproved`. The human sign-off can be a **separate** record that does
  not restate the verdict.
- **`requireSignatureWhenVerdictAtLeast`** — once triggered, the commit must have *some* validly
  signed attestation (which can be a separate record).
- **`requireTestsPassedWhenVerdictAtLeast`** — once triggered, the commit must have *some*
  attestation reporting `testsPassed: true` (which can be a separate CI record).

None of them trigger when every verdict on the commit is below the threshold.

```json
{ "requireHumanApprovalWhenVerdictAtLeast": "review" }
```

> An agent records `verdict: review, humanApproved: false`; a human files a separate
> `--human-approved` record (verdict `nil`). The commit **passes** — the sign-off lives anywhere
> on the commit, not necessarily on the high-verdict record.

### `allowedReviewers`

A per-commit allow-list. When non-empty, **every** attestation's `reviewer` must match at least one
pattern, per pattern:

- an **exact** match against the full reviewer string, *or*
- when the pattern ends with `:` (a role prefix such as `"human:"`), a **prefix** match — so
  `"human:"` allows any `human:*` reviewer, while `"agent:claude"` matches only exactly.

```json
{ "allowedReviewers": ["human:", "agent:claude"] }
```

> Passes a commit whose reviewers are `human:leif` (prefix) and `agent:claude` (exact); fails a
> commit with an `agent:gpt` attestation.

`allowedReviewers` gates the reviewer **string only** — it does not stop someone *claiming* to be
`human:leif`. For that, use `signerPinning` (below).

### Signer pinning: `trustedKeys` + `signerPinning`

These two rules bind identity to a cryptographic key. See [Signing & identity](/attest/docs/signing)
for the full threat model and lifecycle.

- **`trustedKeys`** is a **global** set of trusted base64 Ed25519 public keys. When non-empty,
  *any* attestation that **is** signed must verify **and** carry a `publicKey` in the set; an
  untrusted or invalid signed record fails. It does **not** force signing — an unsigned record
  passes it. Pair it with `requireSignature` to both require a signature and pin it to a trusted
  key.
- **`signerPinning`** is a **per-reviewer** `{ reviewer: base64 pubkey }` map. Any attestation
  whose `reviewer` is a key in the map must be signed with that exact pinned key and verify; a
  pinned reviewer that is unsigned, signed with a different key, or tampered fails. Reviewers
  absent from the map are unaffected. **This is the rule that stops `reviewer: human:leif`
  spoofing.**

```json
{
  "requireSignature": true,
  "trustedKeys": ["BASE64_LEIF_PUBKEY", "BASE64_CI_PUBKEY"],
  "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" }
}
```

### `maxAgeDays` (freshness)

A freshness gate. When set, the commit must carry at least one attestation whose `timestamp` is
within `maxAgeDays` **whole days** of a reference "now". Semantics:

- Age is the integer-day quotient `(now − timestamp) / 86400`. The rule uses the **newest**
  attestation (smallest age), so a single fresh record clears the commit even alongside older
  ones.
- The commit fails when that newest age is **strictly greater** than `maxAgeDays` — so age *equal*
  to the limit still passes. The detail reads `"newest attestation is N days old, exceeds
  maxAgeDays=M"`.
- A commit with **no** attestations cannot satisfy freshness and fails with `"no attestation
  exists to satisfy maxAgeDays=M"`.
- A timestamp at or in the future yields a non-positive age and is always within the window; a
  sub-day difference rounds down to `0` days.

```json
{ "maxAgeDays": 90 }
```

> A stale `block` verdict from six months ago can no longer rubber-stamp today's commit — the trust
> record must be re-affirmed within the window.

**Injected clock.** The reference time is *injected*, not read from the system clock inside the
engine. `Verifier.verify(commits:now:)`, `Attest.verify(commits:policy:now:)`, and
`Exporter.report(commits:policy:now:)` all take a `now` (Unix epoch seconds) that defaults to the
current epoch at the CLI boundary. This keeps verification deterministic and testable — the same
attestation can verify fresh at one supplied `now` and stale at a later one. All other rules ignore
`now`.

## The shipped default

A permissive `.attest.json` ships at the repo root. It gates nothing yet, so it demonstrates the
schema without breaking a repo that has no attestations:

```json
{
  "requireAttestation": false,
  "requireTestsPassed": false,
  "requireSignature": false,
  "requireHumanApprovalWhenVerdictAtLeast": "block"
}
```

Tighten the rules as a repo starts recording attestations.
