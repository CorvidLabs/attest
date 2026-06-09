#!/bin/sh
# dogfood — attest attests ATTEST. This records a provenance attestation on
# attest's OWN real HEAD commit and gates it under two policies, proving the
# tool works on its own history with BOTH outcomes:
#
#   * a LAX policy  -> PASS (exit 0)
#   * a STRICT policy -> FAIL (exit 1)   (catches the missing human sign-off
#                                          / signature on attest's own commit)
#
# Everything happens in a /tmp scratch CLONE of the repo (and a throwaway
# XDG_CONFIG_HOME), so the real working tree, its notes ref, and ~/.config are
# never touched. The script itself exits 0 — the strict FAIL is expected and
# captured. macOS only.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATTEST="$ROOT/.build/debug/attest"
[ -x "$ATTEST" ] || { echo "building attest..."; (cd "$ROOT" && swift build >/dev/null); }

# Scratch clone of attest itself, and an isolated key/config dir.
WORK="$(mktemp -d /tmp/attest-dogfood.XXXXXX)"
CONFIG="$(mktemp -d /tmp/attest-dogfood-cfg.XXXXXX)"
export XDG_CONFIG_HOME="$CONFIG"
trap 'rm -rf "$WORK" "$CONFIG"' EXIT

REPO="$WORK/attest"
echo "== clone attest into a /tmp scratch (real repo + notes stay untouched) =="
# Prefer a clone of the public/private remote; fall back to the local checkout
# (or even ROOT itself) when the remote needs auth that isn't available here.
if git clone -q "https://github.com/CorvidLabs/attest.git" "$REPO" 2>/dev/null; then
  echo "   cloned github.com/CorvidLabs/attest"
elif git clone -q "$ROOT" "$REPO" 2>/dev/null; then
  echo "   remote unavailable — cloned the local checkout at $ROOT"
else
  echo "   clone unavailable — operating directly on the current checkout"
  REPO="$ROOT"
fi
cd "$REPO"

HEAD_SHA="$(git rev-parse HEAD)"
HEAD_SHORT="$(git rev-parse --short=10 HEAD)"
HEAD_SUBJECT="$(git log -1 --pretty=%s)"
echo "   attest's real HEAD: $HEAD_SHORT  \"$HEAD_SUBJECT\""

echo
echo "== record an agent:ci attestation on attest's OWN HEAD =="
echo "   (this is exactly what CI records — tests-passed, verdict proceed)"
"$ATTEST" sign -C "$REPO" --commit "$HEAD_SHA" --reviewer agent:ci \
  --confidence 0.9 --verdict proceed --tests-passed \
  --note "attest dogfooding its own CI: build + 106 tests green"

echo
echo "== the ledger on attest's own commit =="
"$ATTEST" log -C "$REPO" --commit "$HEAD_SHA"

echo
echo "########################################################"
echo "# Outcome 1 — LAX policy: expect PASS (exit 0)         #"
echo "########################################################"
cat > "$WORK/lax.json" <<'JSON'
{
  "requireAttestation": true,
  "requireTestsPassed": true
}
JSON
echo "== lax policy (an attestation + passing tests is enough) =="
cat "$WORK/lax.json"
echo
echo "== verify attest's HEAD under the lax policy =="
set +e
"$ATTEST" verify -C "$REPO" --commit "$HEAD_SHA" --policy "$WORK/lax.json" --color never
LAX_EXIT=$?
set -e
echo "lax verify exit code: $LAX_EXIT"

echo
echo "########################################################"
echo "# Outcome 2 — STRICT policy: expect FAIL (exit 1)      #"
echo "########################################################"
cat > "$WORK/strict.json" <<'JSON'
{
  "requireAttestation": true,
  "requireTestsPassed": true,
  "requireSignature": true,
  "requireHumanApprovalWhenVerdictAtLeast": "proceed"
}
JSON
echo "== strict policy (demands a signature AND a human sign-off) =="
cat "$WORK/strict.json"
echo
echo "== verify attest's HEAD under the strict policy =="
echo "   the agent:ci attestation is unsigned and not human-approved, so this"
echo "   FAILS — attest catching the missing trust on its own commit:"
set +e
"$ATTEST" verify -C "$REPO" --commit "$HEAD_SHA" --policy "$WORK/strict.json" --color never
STRICT_EXIT=$?
set -e
echo "strict verify exit code: $STRICT_EXIT"

echo
echo "########################################################"
echo "# Summary                                              #"
echo "########################################################"
echo "lax    verify exit code: $LAX_EXIT     (expected 0 — PASS)"
echo "strict verify exit code: $STRICT_EXIT     (expected 1 — FAIL, caught)"

# The script succeeds only when both outcomes are exactly as expected.
if [ "$LAX_EXIT" -ne 0 ]; then
  echo "UNEXPECTED: lax policy should have PASSED" >&2
  exit 1
fi
if [ "$STRICT_EXIT" -eq 0 ]; then
  echo "UNEXPECTED: strict policy should have FAILED" >&2
  exit 1
fi
echo "dogfood OK — attest attested attest, both outcomes as expected."
