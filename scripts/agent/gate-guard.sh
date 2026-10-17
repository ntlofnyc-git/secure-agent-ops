#!/usr/bin/env bash
# gate-guard.sh: PreToolUse(Bash) hook for Claude Code (or any runtime with pre-tool hooks).
#
# BLOCKS the agent from calling any outbound send primitive directly, so every message,
# email or call to a third party has to go through `gated-send` (the human approval card).
#
# Input:  the PreToolUse JSON event on stdin; the shell command is .tool_input.command
# Output: exit 0 = allow; exit 2 + reason on stderr = BLOCK (the reason is shown to the agent)
#
# It governs only the AGENT's tool calls. Your cron jobs and the approval bot's own
# dispatcher don't go through this hook, so they keep working.
set -uo pipefail

EVENT="$(cat)"
CMD="$(printf '%s' "$EVENT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")')"
[ -n "$CMD" ] || exit 0

# 1. The sanctioned entrypoint is allowed, but ONLY as a single plain command. A naive
#    `*gated-send*) exit 0` would wave through `gated-send ...; curl api.provider.com/send`.
#    So: it must START with gated-send and contain no chaining/substitution. Pass long bodies
#    with --body-file so message text never needs shell metacharacters.
CHAIN_RE='[;&|`<>]|\$\('
if [[ "$CMD" =~ ^[[:space:]]*gated-send[[:space:]] ]] && ! [[ "$CMD" =~ $CHAIN_RE ]]; then
  exit 0
fi

# 2. Narrow, deliberate exceptions: provider MANAGEMENT endpoints (create SMTP users, verify
#    domains). If the command ALSO mentions the send path, it is NOT exempt; it falls
#    through to the block below, so a management call can't smuggle a send.
case "$CMD" in
  *email/send*|*/messages*|*/Messages.json*) : ;;
  *api.mailprovider.example/v3/users*|*api.mailprovider.example/v3/domain*) exit 0 ;;
esac

# 3. Forbidden direct-send vectors. Generalized on purpose: any new wrapper you write named
#    *-sms, *-mail-send or *call.sh is blocked the day it is created.
#    gated-dispatch is the BACK half of the gate (what the bot runs after a ✅ tap). The agent
#    must never call it, or it could approve its own card.
PATTERNS='api\.twilio\.com|api\.telnyx\.com|api\.sendgrid\.com|api\.mailgun\.net|api\.postmarkapp\.com|api\.vonage\.com'
PATTERNS+='|/Messages\.json|/Calls\.json|/v3/email/send|graph\.facebook\.com/[^ ]*/messages'
PATTERNS+='|smtplib|aiosmtplib|nodemailer|sendmail +-t|swaks|:465\b|:587\b'
PATTERNS+='|[A-Za-z0-9_.-]*-mail-send|[A-Za-z0-9_.-]*-sms\b|[A-Za-z0-9_./-]*call\.sh|bulk-send'
PATTERNS+='|gated-dispatch'

if printf '%s' "$CMD" | grep -qE "$PATTERNS"; then
  HIT="$(printf '%s' "$CMD" | grep -oE "$PATTERNS" | head -1)"
  # Silent to the human (no phone alert); the agent reroutes and the human gets ONE clean card.
  echo "BLOCKED by gate-guard: '$HIT' is a direct send primitive. Route ALL third-party messages, emails and calls through 'gated-send --channel email|sms|wa|call ...' so they reach the owner's ✅/❌ approval card. Never call the underlying sender directly." >&2
  exit 2
fi
exit 0

# ---- self-test ---------------------------------------------------------------
#  echo '{"tool_input":{"command":"curl https://api.twilio.com/2010-04-01/Accounts/X/Messages.json"}}' | ./gate-guard.sh; echo "exit=$?"   # 2
#  echo '{"tool_input":{"command":"gated-send --channel sms --to +15555550123 --body hi"}}' | ./gate-guard.sh; echo "exit=$?"            # 0
#  echo '{"tool_input":{"command":"python3 -c \"import smtplib\""}}' | ./gate-guard.sh; echo "exit=$?"                                 # 2
