# 01 · SSH & identity

> **Goal:** every login on every box tells you exactly *who* came in, and losing one key costs you one key.

## Why this matters more with agents

When you run several agents (a builder, a support agent, a research agent), it's tempting to give them all the same `id_ed25519`. Then one day you see a login at 3 a.m. and can't tell who made it. Or one agent's sandbox leaks its key, and you have to rotate access on every box for every agent at once.

## The rules

1. **One key per agent or person.** `alice`, `builder-agent`, `support-agent` each get their own keypair.
2. **One key per box class** (or per box, if you can afford it). The agent that manages client sites uses a `clientbox` key, not the key that unlocks your control-plane box.
3. **Aliases in `~/.ssh/config`.** Nobody, human or agent, should type raw IPs. An alias pins the key, user and port, so the wrong key is never tried by accident.
4. **Root logs in with a key or not at all.** `PermitRootLogin prohibit-password`. Better still, log in as a named user with sudo.
5. **Passwords off.** `PasswordAuthentication no` and `KbdInteractiveAuthentication no`.
6. **The second-session rule.** Before you close the session you used to change SSH, open a *new* one and prove you can still get in.
7. **Rotate on a schedule, and immediately on exposure.** The rotate script adds the new key, tests it, and only then removes the old one.

## Key layout example

```text
~/.ssh/
├── config
├── id_ed25519_alice            # human
├── id_ed25519_builder          # agent: builds/deploys
├── id_ed25519_support          # agent: read-mostly support tasks
└── id_ed25519_clientbox        # only for customer-facing hosts
```

Generate with a comment that says who and when:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_builder -C "builder-agent@control 2026-10"
```

## `~/.ssh/config`

See [`scripts/ssh/ssh-config.example`](../scripts/ssh/ssh-config.example):

```sshconfig
Host web1
    HostName 198.51.100.10
    User deploy
    IdentityFile ~/.ssh/id_ed25519_builder
    IdentitiesOnly yes
```

`IdentitiesOnly yes` is the important line. Without it, SSH offers every key in your agent, one by one. That can trip fail2ban on your own box ("5 failed attempts") and leaks which keys you hold.

## Server side

[`scripts/ssh/99-hardening.conf`](../scripts/ssh/99-hardening.conf) goes in `/etc/ssh/sshd_config.d/`:

```bash
sudo install -m 644 scripts/ssh/99-hardening.conf /etc/ssh/sshd_config.d/
sudo sshd -t                     # syntax check, ALWAYS
sudo systemctl reload ssh        # reload, not restart; your session survives
# now open a SECOND terminal and log in. Only then close the first.
```

Use `sshd -T | grep -E 'passwordauth|permitroot|kbdinter'` to see what's actually in effect. A drop-in can be overridden by an earlier file that sets the same key (first match wins in sshd), so check the effective values. Don't assume.

## Real-world example

> **"I don't have access to that box."** An agent reported it couldn't SSH into a customer host and started planning a workaround. It *did* have access. It had tried the default key instead of the customer-host key. One `Host` alias with `IdentityFile` + `IdentitiesOnly` fixed it for good, and fixed the confusion that came with it.

## Rotation

[`scripts/ssh/rotate-key.sh`](../scripts/ssh/rotate-key.sh) `web1 ~/.ssh/id_ed25519_builder`:

1. generates `..._new`,
2. appends the new public key to the box's `authorized_keys`,
3. logs in **with the new key only** to prove it works,
4. removes the old public key line,
5. swaps the files locally and keeps the old private key as `.retired-<date>` until you delete it.

If step 3 fails, nothing is removed.

## Checklist → [08-checklists.md#01](08-checklists.md#01--ssh--identity)
