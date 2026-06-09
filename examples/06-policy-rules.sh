#!/bin/sh
# 06 — Additional policy rules: `allowedReviewers` (a per-commit reviewer
# allow-list) and `requireSignatureWhenVerdictAtLeast` (a signature required only
# once a verdict reaches a threshold). Demonstrates both a PASS and a FAIL path
# with the exit codes a CI / agent loop reads. Self-contained against /tmp.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex06.XXXXXX)"
# Isolate the signing key in a throwaway config dir so we never touch ~/.config.
CONFIG="$(mktemp -d /tmp/attest-ex06-cfg.XXXXXX)"
export XDG_CONFIG_HOME="$CONFIG"
trap 'rm -rf "$REPO" "$CONFIG"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'fn deploy() {}\n' > deploy.swift
git add deploy.swift
git commit -q -m "Add: deploy function"

"$ATTEST" keygen >/dev/null

echo "############################################################"
echo "# Part 1 — allowedReviewers (exact + role-prefix matching) #"
echo "############################################################"
echo
cat > .attest.json <<'JSON'
{
  "allowedReviewers": ["human:", "agent:claude"]
}
JSON
echo "== policy: only human:* (prefix) and agent:claude (exact) may attest =="
cat .attest.json

echo
echo "== a human:* reviewer is allowed (prefix match) =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.9 --verdict proceed --tests-passed

echo
echo "== verify — expect PASS (exit 0) =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== an OFF-LIST reviewer (agent:gpt) records an attestation on the same commit =="
"$ATTEST" sign --commit HEAD --reviewer agent:gpt --confidence 0.8 --verdict proceed --tests-passed

echo
echo "== verify — expect FAIL (exit 1): agent:gpt is not in the allow-list =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "######################################################################"
echo "# Part 2 — requireSignatureWhenVerdictAtLeast (signed PASS / unsigned FAIL) #"
echo "######################################################################"
echo
printf 'fn migrate() {}\n' > migrate.swift
git add migrate.swift
git commit -q -m "Add: migrate function"

cat > .attest.json <<'JSON'
{
  "requireSignatureWhenVerdictAtLeast": "review"
}
JSON
echo "== policy: a verdict >= review requires a validly SIGNED attestation =="
cat .attest.json

echo
echo "== record a SIGNED review attestation (--sign) on this commit =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.95 --verdict review --tests-passed --sign

echo
echo "== verify — expect PASS (exit 0): the review verdict is signed =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== a third commit gets an UNSIGNED review attestation =="
printf 'fn rollback() {}\n' > rollback.swift
git add rollback.swift
git commit -q -m "Add: rollback function"
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.7 --verdict review --tests-passed

echo
echo "== verify — expect FAIL (exit 1): review verdict but no signed attestation =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e
