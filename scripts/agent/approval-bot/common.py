"""Shared helpers: config, Telegram calls, queue I/O. Stdlib only."""
import json, os, secrets, time, urllib.parse, urllib.request

CONFIG = os.environ.get("APPROVAL_BOT_CONFIG", "/etc/approval-bot/config")


def cfg():
    out = {"QUEUE": "/var/lib/outbound-gate"}
    for line in open(CONFIG):
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def tg(method, **params):
    c = cfg()
    data = urllib.parse.urlencode(
        {k: json.dumps(v) if isinstance(v, (dict, list)) else v for k, v in params.items()}
    ).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{c['BOT_TOKEN']}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def new_token():
    return secrets.token_hex(6)


def qpath(tok):
    if not tok.isalnum():
        raise ValueError("bad token")
    return os.path.join(cfg()["QUEUE"], tok + ".json")


def save(tok, obj):
    p = qpath(tok)
    tmp = p + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(obj, fh, indent=1)
    os.chmod(tmp, 0o640)
    os.replace(tmp, p)


def load(tok):
    with open(qpath(tok)) as fh:
        return json.load(fh)


def log(line):
    with open(os.path.join(cfg()["QUEUE"], "dispatch.log"), "a") as fh:
        fh.write(time.strftime("%Y-%m-%d %H:%M:%S ") + line + "\n")
