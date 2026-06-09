#!/bin/sh
# 03 — Policy gate: write an .attest.json policy, then show `attest verify`
# both passing and failing, with the exit codes a CI / agent loop reads.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex03.XXXXXX)"
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'migration v1\n' > migrate.sql
git add migrate.sql
git commit -q -m "Add: schema migration"

cat > .attest.json <<'JSON'
{
  "requireTestsPassed": true,
  "requireHumanApprovalWhenVerdictAtLeast": "review"
}
JSON
echo "== policy (.attest.json) =="
cat .attest.json

echo
echo "== verify with NO attestation yet — expect FAIL (exit 1) =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== record an attestation that violates the policy (review verdict, not human-approved) =="
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.6 --verdict review --tests-passed

echo
echo "== verify again — still FAIL: review verdict needs human approval (exit 1) =="
set +e
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
set -e

echo
echo "== a human signs off, satisfying the policy =="
"$ATTEST" sign --commit HEAD --reviewer human:leif --confidence 0.9 --verdict review --tests-passed --human-approved

echo
echo "== verify once more — expect PASS (exit 0) =="
"$ATTEST" verify --commit HEAD
echo "exit code: $?"
