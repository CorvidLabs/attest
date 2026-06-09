#!/bin/sh
# 08 — Freshness: `maxAgeDays` requires a commit to carry a recent attestation.
# A fresh sign-off PASSES; a backdated one FAILS. Demonstrates the exit codes a
# CI / agent loop reads. Self-contained against /tmp.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex08.XXXXXX)"
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'fn ship() {}\n' > ship.swift
git add ship.swift
git commit -q -m "Add: ship function"
SHA="$(git rev-parse HEAD)"

cat > .attest.json <<'JSON'
{
  "requireAttestation": true,
  "maxAgeDays": 30
}
JSON
echo "== policy (.attest.json) =="
cat .attest.json

echo
echo "== record a FRESH attestation (timestamped now) =="
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.9

echo
echo "== verify with maxAgeDays=30 — expect PASS (exit 0) =="
set +e
"$ATTEST" verify --commit HEAD --policy .attest.json
echo "exit code: $?"
set -e

echo
echo "== now simulate a STALE record: overwrite the note, backdated 120 days =="
echo "   (attest sign always stamps 'now', so we hand-write a backdated note to"
echo "    demonstrate the freshness failure path a real aged ledger would hit)"
OLD_TS=$(( $(date +%s) - 120 * 86400 ))
STALE="{\"commit\":\"$SHA\",\"confidence\":0.9,\"humanApproved\":false,\"reviewer\":\"agent:claude\",\"testsPassed\":false,\"timestamp\":$OLD_TS,\"verdict\":\"proceed\"}"
git notes --ref=attest add -f -m "$STALE" "$SHA"

echo
echo "== verify again — expect FAIL: newest attestation is 120 days old (exit 1) =="
set +e
"$ATTEST" verify --commit HEAD --policy .attest.json
echo "exit code: $?"
set -e

echo
echo "== with maxAgeDays removed, the same stale record PASSES (rule is off) =="
echo '{ "requireAttestation": true }' > .attest.json
set +e
"$ATTEST" verify --commit HEAD --policy .attest.json
echo "exit code: $?"
set -e
