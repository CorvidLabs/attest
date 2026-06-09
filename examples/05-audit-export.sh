#!/bin/sh
# 05 — Audit export: build a small history with a MIX of attestations
# (signed/unsigned, human/agent), then emit the complete provenance trail across
# the range as one stable JSON audit document with `attest export`. Unlike
# `log` (a human listing), `export` is for compliance archival: every commit,
# each record's cryptographic verification status, and per-commit policy
# pass/fail. Fully self-contained against /tmp scratch dirs; validated with
# python3 -m json.tool (no jq required).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex05.XXXXXX)"
# Isolate the signing key in a throwaway config dir so we never touch ~/.config.
CONFIG="$(mktemp -d /tmp/attest-ex05-cfg.XXXXXX)"
export XDG_CONFIG_HOME="$CONFIG"
trap 'rm -rf "$REPO" "$CONFIG"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"

# A base commit (this becomes the range floor — excluded by A..B semantics).
printf 'fn boot() {}\n' > boot.swift
git add boot.swift
git commit -q -m "Add: boot"
BASE="$(git rev-parse HEAD)"

echo "== generate a signing key (into a throwaway XDG_CONFIG_HOME) =="
"$ATTEST" keygen

echo
echo "== commit 1: an agent attests, SIGNED =="
printf 'fn login() {}\n' > login.swift
git add login.swift
git commit -q -m "Add: login"
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.92 \
  --verdict proceed --tests-passed --sign --note "auto-reviewed by augur"

echo
echo "== commit 2: a human attests (UNSIGNED) + an agent attests (UNSIGNED) =="
printf 'fn logout() {}\n' > logout.swift
git add logout.swift
git commit -q -m "Add: logout"
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.8 \
  --verdict review --tests-passed --human-approved --note "checked the session teardown"
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.6 --verdict review

echo
echo "== a policy for the export to judge each commit against =="
cat > .attest.json <<'JSON'
{
  "requireTestsPassed": true,
  "requireHumanApprovalWhenVerdictAtLeast": "review"
}
JSON
cat .attest.json

echo
echo "== export the COMPLETE audit trail across the range, with policy verdicts =="
echo "   (commits oldest-first, verification status per record, per-commit pass/fail)"
"$ATTEST" export --range "$BASE..HEAD" --policy .attest.json | tee export.json

echo
echo "== validate the document is well-formed JSON (python3 -m json.tool) =="
python3 -m json.tool export.json >/dev/null && echo "valid JSON [ok]"

echo
echo "== how it complements 'log' (the human/diagnostic view) =="
"$ATTEST" log --range "$BASE..HEAD"
