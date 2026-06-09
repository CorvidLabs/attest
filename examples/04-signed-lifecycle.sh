#!/bin/sh
# 04 — Signed lifecycle: generate an Ed25519 key into a throwaway config dir,
# sign an attestation cryptographically, see `signed[ok]` in the ledger, and
# gate on a `{"requireSignature": true}` policy — a signed commit PASSES and a
# later unsigned commit FAILS. Fully self-contained against /tmp scratch dirs.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex04.XXXXXX)"
# Isolate the signing key in a throwaway config dir so we never touch ~/.config.
CONFIG="$(mktemp -d /tmp/attest-ex04-cfg.XXXXXX)"
export XDG_CONFIG_HOME="$CONFIG"
trap 'rm -rf "$REPO" "$CONFIG"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'fn ship() {}\n' > ship.swift
git add ship.swift
git commit -q -m "Add: ship function"

echo "== generate a signing key (into a throwaway XDG_CONFIG_HOME) =="
"$ATTEST" keygen

echo
echo "== sign an attestation for HEAD cryptographically (--sign) =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.95 \
  --verdict proceed --tests-passed --human-approved --sign

echo
echo "== the ledger — note the signed[ok] badge =="
"$ATTEST" log

echo
cat > .attest.json <<'JSON'
{
  "requireSignature": true
}
JSON
echo "== policy (.attest.json) requires a valid signed attestation =="
cat .attest.json

echo
echo "== verify the signed commit — expect PASS (exit 0) =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== add a second, UNSIGNED commit and attestation =="
printf 'fn rollback() {}\n' > rollback.swift
git add rollback.swift
git commit -q -m "Add: rollback function"
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.6 --verdict proceed --tests-passed

echo
echo "== verify the unsigned commit against requireSignature — expect FAIL (exit 1) =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e
