# Signing & Identity

`attest` signs attestations with **Ed25519** (via Apple's
[`swift-crypto`](https://github.com/apple/swift-crypto)). Signing is **optional**: an unsigned
attestation is still a valid provenance record, so the tool works with zero setup. Signing is
what lets a *policy* trust a record and bind it to an identity.

## Generating a key

```sh
attest keygen
# attest · wrote private key to ~/.config/attest/key (0600)
# public key: BASE64_PUBKEY      <- copy this into your policy
```

- The **private** key (32 raw bytes, base64) is written to `$XDG_CONFIG_HOME/attest/key` or
  `~/.config/attest/key` with `0600` permissions, created with restrictive permissions from the
  outset. Keep it secret; it never leaves the machine.
- The **public** key is printed so you can paste it into a policy's `signerPinning` /
  `trustedKeys` (see below). It is also embedded on every record you sign, so verifiers need no
  key server.
- `attest keygen` refuses to overwrite an existing key unless you pass `--force`.

## How a signature is computed

When you pass `--sign` to `attest sign`, the signer:

1. Computes the **canonical bytes** of the attestation: sorted-key JSON that deliberately
   **excludes** the `signature` and `publicKey` fields (see
   [architecture.md](architecture.md#canonical-serialization-the-signature-contract)).
2. Produces a detached Ed25519 signature over those bytes.
3. Attaches the base64 signature **and** the signer's base64 public key to the record.

```sh
attest sign --commit HEAD --reviewer human:leif --confidence 0.95 \
  --verdict review --human-approved --sign
```

`Ed25519Verifier.verify` reverses this: it recomputes the canonical bytes and checks the embedded
signature against the embedded public key. Because the canonical form excludes the signature
pair, attaching a signature never changes the signed bytes, but any mutation of the *content*
(confidence, verdict, note, timestamp, reviewer, commit) makes verification fail. An unsigned
record verifies as "not signed", never as "valid".

## Commit binding: no cross-commit replay

The canonical bytes include the attestation's inner `commit` field, so a signature is bound to the
commit it names. That alone is not enough, because nothing in git stops someone with write access to
`refs/notes/attest` (the same access as adding any note: a push, a PR, or CI) from copying a
legitimately signed record off commit A and filing it verbatim under commit B. The signature still
validates over A's unchanged bytes.

`attest` closes this by **binding every attestation to the note key it is stored under**. The
verifier discards any record whose inner `commit` does not equal the commit it is being evaluated
for, *before any policy rule runs*. A relocated record is not evidence for the commit it was moved
onto, so:

- `attest verify` treats the target commit as if the transplanted record were absent. A commit whose
  only record was relocated fails `requireAttestation`, `requireSignature`, `minimumConfidence`, and
  every other rule that needs evidence. This defeats the replay even against a strict policy
  combining `requireSignature`, `trustedKeys`, `signerPinning`, and `minimumConfidence`.
- `attest log` renders a relocated record as `commit-mismatch` (not `signed[ok]`), warns on stderr,
  and exits non-zero.
- `attest export` marks the record `"commitMatches": false` and never reports it as
  `"verified": true`, so an audit document cannot present a transplanted signed record as a valid
  signed record.

This holds the core promise: provenance is keyed to a commit SHA, and a signed record cannot be
relocated or replayed onto another commit. It requires no change to the canonical serialization or
the signature format.

## Preventing reviewer spoofing

A reviewer is just a string like `agent:claude` or `human:leif`. Nothing stops someone from filing an
attestation that simply *claims* `reviewer: human:leif`. `allowedReviewers` gates the reviewer
string, but it cannot tell a genuine `human:leif` from an impostor. Two policy rules close that
gap by binding identity to a key.

### `signerPinning`: per-reviewer key binding

`signerPinning` is a `{ reviewer: base64 pubkey }` map. Any attestation whose `reviewer` is a key
in the map **must** be signed with that exact pinned public key and verify. A pinned reviewer
that is unsigned, signed with a different key, or tampered fails the commit. Reviewers absent from
the map are unaffected.

```json
{ "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" } }
```

This is the rule that actually stops `human:leif` spoofing:

```sh
# leif's genuine, signed sign-off PASSES:
attest sign --commit HEAD --reviewer human:leif --confidence 0.95 \
  --verdict review --human-approved --sign
attest verify --commit HEAD            # exit 0

# a spoof (claiming human:leif unsigned, or signed with another key) FAILS:
attest sign --commit HEAD --reviewer human:leif --confidence 0.95   # unsigned claim
attest verify --commit HEAD            # exit 1: reviewer human:leif is pinned but unsigned
```

### `trustedKeys`: a global allow-list of signers

`trustedKeys` is a set of trusted base64 Ed25519 public keys. When non-empty, *any* record that
**is** signed must verify **and** carry a `publicKey` in the set; an untrusted or invalid signed
record fails. Crucially, `trustedKeys` does **not** force signing; an unsigned record passes it.
It bounds the *universe* of acceptable signers.

```json
{
  "requireSignature": true,
  "trustedKeys": ["BASE64_LEIF_PUBKEY", "BASE64_CI_PUBKEY"]
}
```

Pair `trustedKeys` with `requireSignature: true` to both **require** a signature and **restrict**
it to a trusted key.

### How the two compose

- **`signerPinning`** is per-reviewer: only reviewers in the map are constrained, and each must
  be signed with its exact pinned key. This stops `human:leif` spoofing specifically.
- **`trustedKeys`** is global: it does not force signing, but any record that *is* signed must
  use a key from the set.

A policy that pins a human and bounds the signer universe:

```json
{
  "requireSignature": true,
  "trustedKeys": ["BASE64_LEIF_PUBKEY", "BASE64_CI_PUBKEY"],
  "signerPinning": { "human:leif": "BASE64_LEIF_PUBKEY" }
}
```

The full pinned lifecycle (correct-key PASS, then wrong-key / unsigned FAIL) is demonstrated
end-to-end in [`examples/07-signer-pinning.sh`](../examples/07-signer-pinning.sh).

## Scope & limitations

- `attest` uses a single local Ed25519 key per machine and embeds the public key on each record.
  It is **not a CA**: key distribution, rotation, web-of-trust, and revocation are roadmap items.
- Trust today is expressed by pasting public keys into the policy (`trustedKeys` /
  `signerPinning`). That is deliberate: the policy file is the source of truth for *who counts*.
- Combine signing with the `maxAgeDays` freshness rule (see [policy.md](policy.md)) so a trusted
  signature also has to be *recent*. A signed sign-off from months ago will not silently keep
  passing.
