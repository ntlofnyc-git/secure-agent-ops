# 08 · Checklists

One page per guide. Print them, or copy them into an issue per box.

---

## 01 · SSH & identity

- [ ] Every human and every agent has its **own** keypair (ed25519, comment = who + date)
- [ ] Customer/production hosts use a **separate** key from the control box
- [ ] `~/.ssh/config` has an alias per box with `IdentityFile` + `IdentitiesOnly yes`
- [ ] `PasswordAuthentication no` and `KbdInteractiveAuthentication no` (check with `sshd -T`)
- [ ] `PermitRootLogin prohibit-password` (or `no` + a sudo user)
- [ ] `sshd -t` before every reload; **reload**, not restart
- [ ] Tested a **second** session before closing the first
- [ ] Rotation date recorded; exposed key = rotate today

<div style="page-break-after: always"></div>

## 02 · New box

- [ ] Firewall default-drop on **IPv4 and IPv6**
- [ ] Allowed: lo, established/related, ICMP, **ICMPv6**, DHCP (if used), VPN interface, required public ports only
- [ ] Applied under a **5-minute dead-man** rollback; tested from **outside**; dead-man cancelled
- [ ] Firewall restored at boot (systemd unit) and **reboot-tested**
- [ ] fail2ban jails on **every** login door: SSH, SMTP AUTH, IMAP/POP, FTP, panel, WordPress
- [ ] Ubuntu 24.04: sshd jail uses `journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd`
- [ ] Proved `Total failed` increases after a deliberate bad login
- [ ] Own boxes + VPN subnet in `ignoreip`
- [ ] unattended-upgrades: security only, no auto-reboot
- [ ] Admin panels: IP allowlist **and** 2FA for every user
- [ ] Unused services (FTP, etc.) disabled
- [ ] `ss -tulpn` reviewed: internals on 127.0.0.1 / VPN IP only; no transparent proxy reachable from outside
- [ ] Health check timer that alerts a human
- [ ] Note written: what's public + why, firewall location, rollback, out-of-band console route

<div style="page-break-after: always"></div>

## 03 · Web roots

- [ ] Agent instructions say: backups go **outside** the docroot
- [ ] Block rule for `*.bak* *.orig *.old *.sql* *.tar* *.zip .env* .git/ *.log *.swp *~` on **every** site
- [ ] Block rule tested with curl (expect 403/404)
- [ ] Probe for the block rule included in the daily sweep
- [ ] Existing junk **moved** out (not deleted), with paths preserved
- [ ] Access logs checked for successful downloads of anything that was exposed
- [ ] Keys from any exposed config **rotated**
- [ ] `/tmp` swept for leftover scripts holding credentials; agents use `umask 077` / private scratch dir

<div style="page-break-after: always"></div>

## 04 · Secrets

- [ ] Each secret in its **own** file, mode `600`, named `.<service>-<purpose>`
- [ ] Home directory `700`
- [ ] No secret inline in any script; scripts read the file
- [ ] No secret in web roots, shared drives, git, `/tmp`, memory notes
- [ ] Agent system prompt contains the "new secret" rules
- [ ] Transcript scrubber: encrypted backup taken, dry run reviewed, timer enabled (recent every 10–15 min + nightly full)
- [ ] `--find-unknown` reviewed weekly; unknown keys saved to files, then scrubbed
- [ ] Exposure log: which keys were ever public → rotated?

<div style="page-break-after: always"></div>

## 05 · Active defense

- [ ] Incremental bans on (`bantime.increment`, max 1 week)
- [ ] WordPress jail on every WP host
- [ ] Daily sweep installed, `--print` run reviewed, timer enabled
- [ ] Allowlists filled in (`/etc/security-sweep.conf`)
- [ ] Baselines written (SUID, admins); re-baseline after intended changes
- [ ] Alerts go to an **owner-only** channel and fire only on **drift**
- [ ] Weekly deeper audit: package integrity, cron/units diff, readable secrets, transcript key scan

<div style="page-break-after: always"></div>

## 06 · Audit

- [ ] Read-only: no restarts, deletes or "quick fixes" during the audit
- [ ] Timeline with time zones; IPs, hosts, usernames collected
- [ ] Everything the suspect IP did, across **all** vhosts and services
- [ ] Successful logins? New admins? Changed/planted PHP? PHP in uploads? Webshell grep?
- [ ] System integrity: packages, SUID, cron/units, authorized_keys
- [ ] Outbound: mail queue, established connections
- [ ] Report: bottom line → attacker actions → clean → needs fixing → plan
- [ ] Fix plan approved by a human; risky steps (reboots) scheduled separately

<div style="page-break-after: always"></div>

## 07 · Agent guardrails

- [ ] One outbound entrypoint (`gated-send`) for email/SMS/WhatsApp/calls/posts
- [ ] Send cards show recipient, sender identity, **exact** body, attachments, token; ✅ Send / ❌ Cancel only
- [ ] Only the bot's handler dispatches, and only tapped tokens; every dispatch logged
- [ ] PreToolUse **gate-guard** hook installed; blocks raw APIs, SMTP, wrappers **and the dispatcher**
- [ ] Hook tested: a direct send attempt is blocked; `gated-send` passes
- [ ] Plan cards for substantial work: found → steps → not included → rollback
- [ ] Rule in the agent prompt: verbal "go" ≠ tap; "wait" means wait
- [ ] Agent verifies a card/queue file exists before saying "tap ✅", and reads run state before reporting it
- [ ] New setups: non-root `agents` user, narrow sudo by full path
- [ ] Login helpers cap attempts (≤2) and back off
- [ ] Untrusted code: reviewed, pinned, sandboxed (no net, no secrets, no home)
- [ ] Personal data in a vault the work agents can't read
