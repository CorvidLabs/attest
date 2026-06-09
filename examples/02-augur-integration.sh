#!/bin/sh
# 02 — augur integration: pipe `augur check --json` into `attest sign --from-augur -`
# so the verdict and confidence are filled from augur automatically.
#
# If augur is not on PATH, this script falls back to a literal augur-shaped JSON
# payload so the integration is still demonstrated end-to-end.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex02.XXXXXX)"
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
mkdir -p src/auth
printf 'func validateToken() {}\n' > src/auth/token.swift
git add .
git commit -q -m "Add: token validation"

echo "== obtain an augur verdict (real augur if present, else a sample payload) =="
if command -v augur >/dev/null 2>&1; then
  AUGUR_JSON="$(augur check --range HEAD~1..HEAD --json 2>/dev/null || echo '')"
fi
if [ -z "${AUGUR_JSON:-}" ]; then
  # augur emits this shape: a top-level verdict + riskScore (0...100).
  AUGUR_JSON='{"verdict":"review","riskScore":45.0,"files":[{"path":"src/auth/token.swift","riskScore":45.0}]}'
  echo "(augur not available — using a sample augur payload)"
fi
echo "$AUGUR_JSON"

echo
echo "== pipe augur JSON into attest; verdict + confidence are auto-filled =="
echo "$AUGUR_JSON" | "$ATTEST" sign --commit HEAD --reviewer agent:claude --from-augur - --tests-passed

echo
echo "== the resulting attestation (risk 45 -> confidence 0.55, verdict review) =="
"$ATTEST" log --commit HEAD --json
