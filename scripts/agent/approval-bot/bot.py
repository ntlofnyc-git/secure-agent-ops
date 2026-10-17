#!/usr/bin/env python3
"""bot.py: the only process that turns a ✅ tap into a real send.

Long-polls Telegram, accepts button taps ONLY from OWNER_CHAT_ID, and:
  send:<tok>    → dispatch the queued message, log it, mark the card ✅ Sent
  cancel:<tok>  → mark cancelled
  go/bg:<tok>   → hand the approved plan to PLAN_RUNNER (mode "live" or "background")
  revise:<tok>  → mark revise; the owner replies in chat with changes
  later:<tok>   → append to backlog.jsonl
Run as its own user (approvalbot). Provider keys live in 600 files only this user can read.
"""
import json, os, subprocess, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from common import cfg, tg, load, save, log


def read_key(path):
    return open(path).read().strip()


# ---- senders: replace with your providers ------------------------------------------
def send_email(it):
    payload = {"sender": it["from"], "to": [it["to"]], "subject": it["subject"], "text_body": it["body"]}
    req = urllib.request.Request("https://api.mailprovider.example/v3/email/send",
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json",
                                          "X-Api-Key": read_key("/etc/approval-bot/.mail-api-key")})
    with urllib.request.urlopen(req, timeout=30) as r:
        return f"http {r.status}"


def send_sms(it):
    raise NotImplementedError("wire your SMS provider here (key in /etc/approval-bot/.sms-api-key)")


SENDERS = {"email": send_email, "sms": send_sms}
# -------------------------------------------------------------------------------------


def edit(it, status):
    if "message_id" in it:
        tg("editMessageReplyMarkup", chat_id=cfg()["OWNER_CHAT_ID"], message_id=it["message_id"],
           reply_markup={"inline_keyboard": [[{"text": status, "callback_data": "noop"}]]})


def handle(cb):
    c = cfg()
    if str(cb["from"]["id"]) != c["OWNER_CHAT_ID"]:          # only the owner's taps count
        tg("answerCallbackQuery", callback_query_id=cb["id"], text="Not allowed")
        return
    action, _, tok = cb.get("data", "").partition(":")
    try:
        it = load(tok)
    except (OSError, ValueError):
        tg("answerCallbackQuery", callback_query_id=cb["id"], text="Unknown or expired token")
        return
    if it["state"] != "pending":                              # a tap only works once
        tg("answerCallbackQuery", callback_query_id=cb["id"], text=f"Already {it['state']}")
        return

    if action == "send":
        try:
            res = SENDERS[it["channel"]](it)
            it["state"] = "sent"; log(f"{tok} SENT {it['channel']} to={it['to']} {res}"); edit(it, "✅ Sent")
        except Exception as e:
            it["state"] = "failed"; log(f"{tok} FAILED {it['channel']} to={it['to']} {e}"); edit(it, "⚠️ Failed, see log")
    elif action == "cancel":
        it["state"] = "cancelled"; log(f"{tok} CANCELLED"); edit(it, "❌ Cancelled")
    elif action in ("go", "bg"):
        mode = "live" if action == "go" else "background"
        it["state"] = "approved-" + mode
        subprocess.Popen([c["PLAN_RUNNER"], mode, tok], stdin=subprocess.PIPE).communicate(it["plan"].encode())
        edit(it, "✅ Approved, running" if mode == "live" else "🌙 Approved, running in background")
    elif action == "revise":
        it["state"] = "revise"; edit(it, "✏️ Revise: reply with changes")
    elif action == "later":
        it["state"] = "saved"
        with open(os.path.join(c["QUEUE"], "backlog.jsonl"), "a") as fh:
            fh.write(json.dumps({"token": tok, "saved": time.time(), "plan": it["plan"]}) + "\n")
        edit(it, "🔖 Saved for later")
    else:
        return
    save(tok, it)
    tg("answerCallbackQuery", callback_query_id=cb["id"], text="Done")


def main():
    offset = 0
    while True:
        try:
            r = tg("getUpdates", offset=offset, timeout=50, allowed_updates=["callback_query"])
            for u in r.get("result", []):
                offset = u["update_id"] + 1
                if "callback_query" in u:
                    handle(u["callback_query"])
        except Exception as e:
            print("poll error:", e, file=sys.stderr)
            time.sleep(5)


if __name__ == "__main__":
    main()
