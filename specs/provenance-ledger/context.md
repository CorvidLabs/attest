# Context — Provenance Ledger

## Why this exists

Agents made code cheap to produce; the scarce resource is now *trust*. `augur` answers
"how risky is this diff, and should a human look?" — but its verdict is ephemeral. Once a
change lands, there is no portable, verifiable record of *what or who vetted it and at what
confidence*. That record is what reviewers, auditors, and downstream agents actually need.
`attest` makes it a durable, signed artifact that lives with the code.

## Design decisions

- **Git notes as storage.** Notes are portable across every git host, travel with
  `git push origin "refs/notes/*"`, and never touch the working tree. No service, no
  database, no lock-in. The store is abstracted behind `AttestationStore` so the engine is
  testable in memory.
- **Optional signing.** Zero-setup usability matters more than mandatory cryptography. An
  unsigned attestation is still a valid provenance record; signing strengthens it. The
  canonical bytes exclude the signature field so attaching a signature is idempotent over content.
- **Deterministic canonical form.** Signatures are only meaningful if the bytes signed are
  reproducible. Sorted keys and unescaped slashes give a stable serialization across platforms.
- **Policy as plain JSON.** `.attest.json` decodes with Foundation — no YAML/TOML
  dependency. Permissive defaults keep the tool usable before any policy is written.
- **augur is the source, not a dependency.** `--from-augur` ingests augur's JSON over a
  pipe, so the two tools compose without `AttestKit` linking augur.

## Non-goals

- Not a risk scorer — that is `augur`. `attest` records and gates on trust, it does not compute it.
- Not a CA or key-management service; `attest` uses a single local Ed25519 key and embeds
  the public key on each record. Web-of-trust / key distribution is out of scope.
- Not a task runner, release tool, or spec checker (that is `fledge` / `spec-sync`).
