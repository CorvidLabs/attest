#!/bin/sh
# 01 — Basic attestation: init a scratch repo, make a commit, sign an
# (unsigned) attestation, and read it back. No key, no setup required.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

REPO="$(mktemp -d /tmp/attest-ex01.XXXXXX)"
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"

git init -q
git config user.name "Example"
git config user.email "example@corvidlabs.dev"
printf 'fn main() {}\n' > main.swift
git add main.swift
git commit -q -m "Add: main entry point"

echo "== record an unsigned attestation for HEAD =="
"$ATTEST" sign --commit HEAD --reviewer agent:claude --confidence 0.92 \
  --verdict proceed --tests-passed --note "trivial entry point, looks fine"

echo
echo "== the ledger =="
"$ATTEST" log

echo
echo "== same commit as JSON =="
"$ATTEST" log --commit HEAD --json
