#!/usr/bin/env bash
# Builds a throwaway git repo for the attest demo (demo/demo.gif): one commit to
# attest, plus a release.json policy that requires a signature and passing tests.
# It also ensures a signing key exists so `--sign` works. Safe to re-run: it wipes
# and rebuilds the scratch repo (it never touches your real signing key).
#
#   ./demo/setup.sh            # builds the scratch repo at /tmp/demo-attest
#   ./demo/setup.sh /path/dir  # or at a directory you choose
set -euo pipefail

DIR="${1:-/tmp/demo-attest}"
rm -rf "$DIR"
mkdir -p "$DIR"
cd "$DIR"

git init -q
git config user.name  "demo"
git config user.email "demo@example.com"
git config commit.gpgsign false

mkdir -p src/auth
printf 'func startSession() {}\n' > src/auth/session.swift
git add -A && git commit -q -m "feat: add auth session"

# A release policy: an attestation must be signed and must record passing tests.
printf '{"requireSignature":true,"requireTestsPassed":true}\n' > release.json

# Ensure a signing key exists so `attest sign --sign` works. keygen without
# --force is a no-op (and non-zero) if a key is already present, so swallow that.
attest keygen >/dev/null 2>&1 || true

echo "scratch repo ready at $DIR"
echo "run:  (cd $DIR && attest sign --reviewer human:leif --confidence 0.92 --tests-passed --sign && attest log && attest verify --policy release.json)"
