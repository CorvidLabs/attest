#!/bin/sh
# 07 — Signer pinning: bind a reviewer identity to a cryptographic key so a
# claimed `reviewer: human:leif` cannot be spoofed. Demonstrates `signerPinning`
# (a pinned reviewer must be signed with its pinned key) and `trustedKeys` (only
# listed keys count as trusted), with the PASS / FAIL exit codes a CI / agent
# loop reads. Self-contained against /tmp; the signing key lives in a throwaway
# XDG_CONFIG_HOME so we never touch ~/.config.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex07.XXXXXX)"
CONFIG="$(mktemp -d /tmp/attest-ex07-cfg.XXXXXX)"
export XDG_CONFIG_HOME="$CONFIG"
trap 'rm -rf "$REPO" "$CONFIG"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'fn deploy() {}\n' > deploy.swift
git add deploy.swift
git commit -q -m "Add: deploy function"

echo "== leif generates a signing key; capture its PUBLIC key for the policy =="
KEYGEN_OUT="$("$ATTEST" keygen)"
echo "$KEYGEN_OUT"
LEIF_PUBKEY="$(printf '%s\n' "$KEYGEN_OUT" | sed -n 's/^public key: //p')"
echo "leif's pinned public key: $LEIF_PUBKEY"

echo
echo "############################################################"
echo "# Part 1 — signerPinning: human:leif is bound to leif's key #"
echo "############################################################"
echo
cat > .attest.json <<JSON
{
  "signerPinning": { "human:leif": "$LEIF_PUBKEY" }
}
JSON
echo "== policy: any attestation claiming human:leif MUST be signed by the pinned key =="
cat .attest.json

echo
echo "== a genuine, SIGNED sign-off as human:leif (with the pinned key) =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.95 \
  --verdict review --human-approved --sign

echo
echo "== verify — expect PASS (exit 0): human:leif is signed by its pinned key =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== a non-pinned reviewer (agent:claude) records an UNSIGNED attestation — unaffected =="
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.7 --verdict proceed --tests-passed

echo
echo "== verify — expect PASS (exit 0): agent:claude is not pinned, so it is unconstrained =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "###########################################################"
echo "# Part 2 — the spoof: claim human:leif WITHOUT the key    #"
echo "###########################################################"
echo
printf 'fn migrate() {}\n' > migrate.swift
git add migrate.swift
git commit -q -m "Add: migrate function"

echo "== an attacker files an UNSIGNED attestation simply CLAIMING reviewer human:leif =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.99 --verdict proceed --tests-passed

echo
echo "== verify — expect FAIL (exit 1): human:leif is pinned but this record is unsigned =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== now the attacker signs as human:leif with their OWN (different) key =="
# A second, independent key in a separate config dir stands in for the attacker.
ATTACKER_CFG="$(mktemp -d /tmp/attest-ex07-atk.XXXXXX)"
trap 'rm -rf "$REPO" "$CONFIG" "$ATTACKER_CFG"' EXIT
printf 'fn rollback() {}\n' > rollback.swift
git add rollback.swift
git commit -q -m "Add: rollback function"
XDG_CONFIG_HOME="$ATTACKER_CFG" "$ATTEST" keygen >/dev/null
XDG_CONFIG_HOME="$ATTACKER_CFG" "$ATTEST" sign --commit HEAD --reviewer human:leif \
  --confidence 0.99 --verdict proceed --tests-passed --sign

echo
echo "== verify — expect FAIL (exit 1): signed, but NOT by human:leif's pinned key =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "######################################################################"
echo "# Part 3 — trustedKeys: constrain WHICH keys count as trusted at all  #"
echo "######################################################################"
echo
printf 'fn audit() {}\n' > audit.swift
git add audit.swift
git commit -q -m "Add: audit function"

cat > .attest.json <<JSON
{
  "requireSignature": true,
  "trustedKeys": ["$LEIF_PUBKEY"]
}
JSON
echo "== policy: require a signature AND that it use a trusted key =="
cat .attest.json

echo
echo "== leif signs with his trusted key =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.9 --verdict proceed --tests-passed --sign

echo
echo "== verify — expect PASS (exit 0): signed by a trusted key =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== the attacker's (untrusted-key) signature lands on a fresh commit =="
printf 'fn purge() {}\n' > purge.swift
git add purge.swift
git commit -q -m "Add: purge function"
XDG_CONFIG_HOME="$ATTACKER_CFG" "$ATTEST" sign --commit HEAD --reviewer agent:rogue \
  --confidence 0.9 --verdict proceed --tests-passed --sign

echo
echo "== verify — expect FAIL (exit 1): the signed record uses an untrusted key =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e
