#!/usr/bin/env bash
# private-path-guard.sh: PreToolUse hook that blocks reads/writes/commands touching a private
# vault (personal health, family, finance) for agents that have no business there.
# A guardrail, not a security boundary: if the agent runs as the same Unix user, file
# permissions are the real wall. Use a separate user for the vault where you can.
set -uo pipefail
VAULT_RE='/home/owner/private/|/srv/vault/'
EVENT="$(cat)"
TARGET="$(printf '%s' "$EVENT" | python3 -c 'import json,sys
try:
  t=json.load(sys.stdin).get("tool_input",{}); print(t.get("file_path") or t.get("path") or t.get("command") or "")
except Exception: print("")')"
if printf '%s' "$TARGET" | grep -qE "$VAULT_RE"; then
  echo "BLOCKED by private-path-guard: that path is in the owner's private vault." >&2
  exit 2
fi
exit 0
