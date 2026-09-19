---
hi: 1
families: [SIGNING]
---

# Signing, and proving who signed

## Intent

A record is only evidence if it cannot be forged, altered or moved. Signing should stay optional so the tool is useful with nothing configured, but when someone wants cryptographic weight it should cost one key generation and one flag, and checking a signature should never require fetching a key from anywhere. The hard promise is narrow and absolute: a signature belongs to one piece of content and one commit, so it cannot be lifted onto a different commit and cannot be claimed by somebody else. attest should be equally clear about what it is not, which is a certificate authority.

## Criteria

- **SIGNING-1**  Signing stays optional, so attest is useful with nothing configured.
- **SIGNING-2**  An unsigned attestation is a real record rather than a second-class one.
- **SIGNING-3**  I generate a signing key once.
  - **SIGNING-3.a**  Generating a key shows me the public half to paste into a policy.
  - **SIGNING-3.b**  The private key is written so that only I can read it.
  - **SIGNING-3.c**  Generating a key never silently replaces a key I already have.
- **SIGNING-4**  After that, signing a record costs me one extra flag.
  - **SIGNING-4.a**  I am warned before signing with a key file that other people on the machine can read.
- **SIGNING-5**  Anybody can check a signature without fetching a key from anywhere, because the record carries the key it was signed with.
- **SIGNING-6**  The bytes a signature covers are identical on every machine and every platform.
  - **SIGNING-6.a**  Attaching a signature never changes what was signed.
  - **SIGNING-6.b**  Changing anything a record claims, from the confidence to the note to the reviewer, breaks its signature.
  - **SIGNING-6.c**  Those bytes never change quietly between versions, because that would void every signature ever made.
- **SIGNING-7**  A signed record belongs to the commit it names, so copying it onto another commit makes it evidence for nothing.
  - **SIGNING-7.a**  A relocated record counts as absent wherever it was moved to, however strict the rules being applied.
  - **SIGNING-7.b**  A relocated record is shown as a mismatch rather than as a good signature.
  - **SIGNING-7.c**  The same record still counts on the commit it actually names.
- **SIGNING-8**  An unsigned record is reported as unsigned, never as a signature that happens to check out.
- **SIGNING-9**  A signature or key that is not even well formed fails cleanly with a reason.
- **SIGNING-10**  The docs say plainly that attest is not a certificate authority.
- **SIGNING-11**  The docs say plainly that trust comes from the keys somebody chose to put in a policy.
