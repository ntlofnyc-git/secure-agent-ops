# 06 · Audit playbook (read-only)

> **Goal:** when something looks wrong, find out what happened **without changing anything**, then fix it in small steps with a human approving each one.

## Ground rules

1. **Read-only until proven.** No restarts, no deletes, no "quick fixes" during the audit. Changing things destroys evidence and can tip off an attacker.
2. **Separate the audit from the fix.** The audit ends with findings + a proposed plan. The plan goes to a human for approval ([07](07-agent-guardrails.md#3-plan-cards-only-a-tap-counts)).
3. **Write down what you ran.** The agent's transcript is your log. Ask the agent to quote the commands it ran, not just its conclusions.
4. **Distinguish "outside knocking" from "inside acting".** Most scary-looking events are bots knocking. The question is whether anything got *in*.

## The walkthrough

### Step 1: Scope the event

What exactly was observed? Collect timestamps (with time zones), affected hosts/sites, usernames and source IPs from the alert or email headers.

### Step 2: Who is knocking?

```bash
# web: top IPs hitting login/reset endpoints in the window
zgrep -hE 'wp-login\.php|xmlrpc\.php|lostpassword|/wp-json/wp/v2/users|/author/' /var/log/apache2/*access*.log* \
  | awk '{print $1}' | sort | uniq -c | sort -rn | head -20

# everything one IP did, across all vhosts
zgrep -h '^203\.0\.113\.45 ' /var/log/apache2/*access*.log* | awk '{print $4, $6, $7, $9}' | head -100

# ssh / mail / ftp / panel
journalctl -u ssh --since "-2 days" | grep -c 'Failed\|Invalid'
grep -h '203.0.113.45' /var/log/mail.log* /var/log/secure* /var/log/auth.log* 2>/dev/null | head
```

### Step 3: Did anything get in?

| Question | Where to look |
|---|---|
| Any **successful** login from the suspect IP? | web logs: `POST wp-login.php` → `302` to `/wp-admin/`; `auth.log` "Accepted"; mail "login ok" |
| Any **new admin** accounts? | `wp user list --role=administrator --fields=user_login,user_email,user_registered` per site; `getent group sudo` |
| Any **changed/planted code**? | `find /var/www -name '*.php' -newermt '-3 days'`; PHP files in `uploads/`; webshell grep |
| **System** files tampered? | `debsums -c` / `rpm -Va`; new SUID; new cron/systemd units; `~/.ssh/authorized_keys` changes |
| Is the box **sending** anything? | mail queue size; outbound connections `ss -tnp state established` |

Webshell signature grep (expect false positives, so read each hit):

```bash
grep -rlE --include='*.php' 'eval\s*\(\s*(base64_decode|gzinflate|str_rot13)|assert\s*\(\s*\$_(POST|GET|REQUEST)|preg_replace\s*\(.*/e|\$_(POST|GET|REQUEST)\s*\[\s*.\w+.\s*\]\s*\(' /var/www 2>/dev/null
```

### Step 4: Report

Structure: **bottom line → what the attacker did → what we checked (clean) → what needs fixing → proposed plan**. Then stop and wait for approval.

---

## Case study A: "Password-reset storm on six WordPress sites"

*(Sanitized: names, IPs and domains changed.)*

**What was observed.** Early one morning the owner's inbox got six "Password reset request" emails in about 40 minutes, from six different client WordPress sites on the same old shared host. Each named a username: `admin` on some sites, `root` on others.

**First read (from the emails alone, nothing touched).**
- All six requests came from **one IP** in a cheap hosting range abroad (`203.0.113.45` here).
- If malware on the host were doing this, the emails would show the *server's* own IP. An outside IP means an outside bot.
- Reset links only go to the account's email, so the attacker never receives them. **Don't click them, and let them expire.**
- A reset *request* is not a reset. Nothing yet suggests a password changed.

**The read-only audit of the host's web logs.**
- The IP sent ~6,700 requests to **19** WordPress sites over ~10 hours.
- Pattern: first **user enumeration** (`/wp-json/wp/v2/users`, `/?author=1` → `/author/root/`). That's how it learned `root` and `admin`. Then `wp-login.php` password guessing, then the lost-password form, then a few other endpoints.
- The host's own brute-force protection had blocked it **516 times** ("more than 10 login attempts in 3 minutes").

**Checked and clean.**
- No successful login (no `302 → /wp-admin/`) from that IP on any site.
- No new administrator accounts. Every account created in 30 days was a subscriber/customer.
- No planted or changed PHP. The recent changes were security-plugin logs, language-pack updates and one known in-house plugin.
- Nothing in `uploads/` but normal cache/form files.
- The IP never touched SSH, the hosting panel or mail.

**Context that kept it in proportion.** Five *other* IPs each hit `wp-login.php` more than 2,000 times the same day. This one only reached a human because it used the reset form, which sends an email.

**Two real findings.**
1. Every site **publicly listed its usernames** via the REST API and author archives. That's what fed the bot.
2. One site had an **administrator account nobody recognized** (named after a "growth/SEO" agency), created months earlier. This was the only finding that warranted urgent human follow-up: *who is this, and did we authorize it?*

**Proposed fix (as a plan card, approved step by step).**
- Disable public user enumeration (REST `users` endpoint for anonymous users + `?author=` redirects).
- Block the top offenders at the firewall and add a `wordpress` fail2ban jail.
- Rate-limit the lost-password form.
- Rename or remove `admin`/`root` usernames.
- Resolve the unknown admin with the client *before* removing it.

---

## Case study B: "Open backups on a hosting box"

*(Sanitized.)*

**Trigger.** A routine read-only audit of a shared web + mail host after hardening a different box.

**Clean.**
- No webshells, planted files or PHP in uploads.
- Core system files matched their packages.
- sudo rules and cron jobs were all known.
- SSH was key-only and root had no key, so no direct root login.
- Mail wasn't relaying and the queue was empty.
- Every recent mail login came from a known client or our own boxes.
- fail2ban was running.

**Needs fixing.**
1. **No firewall at all.** The package had been uninstalled at some point, and every port was open on v4 and v6.
2. **~180 backup/database files in public web folders.** These included a live 67 MB database dump and config backups containing passwords and API keys for four apps. Access logs (≈30 days) showed no outside downloads, only our own checks. One backup **predated the logs**, so its keys were treated as possibly exposed.
3. **Helper scripts in `/tmp`.** Seven of them held passwords, including root credentials for *another* server. Any site account on the box could read them.
4. **FTP:** ~33,000 failed logins and no legitimate use in 14 days.
5. **Hosting panel** open to the internet, with no 2FA on any user and bots trying `root`/`admin`.
6. A **pending reboot** for a kernel update.

**The fix plan, safest step first.**
1. Move the backups out of the web roots (move, don't delete) + add a server rule blocking those file types on every site.
2. Move the `/tmp` scripts to a root-only folder.
3. List the exposed keys **by name only** so the owner can decide which to rotate.
4. Turn off FTP.
5. Allowlist the panel to known IPs + enable 2FA.
6. Firewall on, under a 5-minute dead-man auto-undo.
7. Tighten SSH settings.
8. Add the box to the daily sweep.

The reboot was deliberately **left out** of the plan. The box carries everyone's mail and sites, so the owner picks the time.

**Lesson.** The box had not been broken into. But it was one curious visitor away from handing out a production database and the root password to another server. Audits find *exposure* far more often than *intrusion*. Fix exposure like it's an incident anyway.

## Checklist → [08-checklists.md#06](08-checklists.md#06--audit)
