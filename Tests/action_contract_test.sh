#!/usr/bin/env bash
set -euo pipefail

# Direct SDD evidence: REQ-attest-action-001, REQ-attest-action-002,
# REQ-attest-action-003.
require() {
  local expected="$1"
  if ! grep -Fq -- "$expected" action.yml; then
    echo "missing action contract fragment: $expected" >&2
    exit 1
  fi
}

require "inputs:"
require "forward-from:"
require "forward-to:"
require "forward-reviewer:"
require "forward-sign:"
require "working-directory:"
require "version:"
require "outputs:"
require 'value: ${{ steps.install.outputs.binary }}'
require '"$ATTEST" "${forward_args[@]}"'
require '"$ATTEST" verify --range "$RANGE" --policy "$POLICY"'
require "checksum mismatch"

echo "attest action contract passed"
