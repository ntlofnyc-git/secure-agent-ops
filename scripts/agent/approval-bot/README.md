# approval-bot: minimal human-approval gate (Telegram, stdlib Python)

Three small programs:

| File | Who runs it | What it does |
|---|---|---|
| `gated-send` | the **agent** | Queues an outbound message and posts a ✅ Send / ❌ Cancel card to the owner. Never sends anything itself. |
| `plan-gate` | the **agent** | Posts a plan card: ✅ Go, stay with me · 🌙 Go, background it · ✏️ Revise · 🔖 Save for later. |
| `bot.py` | **systemd**, as a separate user | Listens for button taps **from the owner's chat only**, dispatches approved sends, hands approved plans back to the agent. |

The agent can queue, but only a tap makes `bot.py` dispatch. Pair it with `../gate-guard.sh`
so the agent can't call the real senders (or `bot.py`'s dispatch path) directly.

## Setup

```bash
# 1. Create a bot with @BotFather, get your own chat id (message the bot, then getUpdates)
sudo install -d -m 700 -o approvalbot /etc/approval-bot
sudo install -m 600 -o approvalbot /dev/null /etc/approval-bot/config
sudo $EDITOR /etc/approval-bot/config
#   BOT_TOKEN=123456:ABC...           (the bot's token)
#   OWNER_CHAT_ID=111111111           (ONLY this chat's taps count)
#   QUEUE=/var/lib/outbound-gate      (shared queue dir; agent user can write, bot reads)
#   PLAN_RUNNER=/usr/local/bin/run-approved-plan   (gets the approved plan on stdin + mode arg)

# 2. Queue dir: agents may CREATE entries, only the bot may dispatch them
sudo install -d -m 1770 -o approvalbot -g agents /var/lib/outbound-gate

# 3. Service
sudo cp approval-bot.service /etc/systemd/system/ && sudo systemctl enable --now approval-bot
```

The agent's copy of `gated-send` / `plan-gate` needs `BOT_TOKEN` + `OWNER_CHAT_ID` to *post* cards.
Give the agents a **separate posting bot token** if you can, so a leaked agent token can
post cards but can never receive taps.

## Senders

`bot.py` → `dispatch()` has one function per channel. The examples call an HTTP email API
and an SMS API, reading keys from `600` files. Replace them with your providers. Keep the
keys readable **only** by the `approvalbot` user, not the agents.
