#!/usr/bin/env bash
# security-sweep.sh: daily drift check. Alerts ONLY when the set of findings changes.
#
#   security-sweep.sh                   run, alert on drift
#   security-sweep.sh --print           run, print everything, never alert
#   security-sweep.sh --rebaseline X    accept current state for X = suid | admins | all
#
# Config: /etc/security-sweep.conf (see security-sweep.conf.example)
# State:  /var/lib/security-sweep/
set -u
CONF=/etc/security-sweep.conf
STATE=/var/lib/security-sweep
PRINT=0; REBASE=""
case "${1:-}" in
  --print) PRINT=1 ;;
  --rebaseline) REBASE=${2:?suid|admins|all} ;;
esac

# defaults (overridden by the conf)
ALLOW_TCP="22 80 443"; ALLOW_UDP="443 68 546"; FW_CHAIN_V4=""; FW_CHAIN_V6=""; F2B_JAILS="sshd"
WEB_ROOTS="/var/www"; BAK_PROBE_URL=""; FAILED_LOGIN_FACTOR=4; PHP_CHANGE_IGNORE=""
WP_SITES=""; WP_CLI_USER="www-data"; ALERT_CMD="logger -t security-sweep"; REMIND_DAYS=7
[ -f "$CONF" ] && . "$CONF"
install -d -m 700 "$STATE"
umask 077

drift=()
add() { drift+=("$*"); }

# ---------- 1. public listeners vs allowlist ----------
while read -r proto port proc; do
  allow=$ALLOW_TCP; [ "$proto" = udp ] && allow=$ALLOW_UDP
  [[ " $allow " == *" $port "* ]] || add "new public listener $proto/$port ($proc)"
done < <(ss -Htulnp 2>/dev/null | awk '{
    split($5,a,":"); port=a[length(a)]; addr=substr($5,1,length($5)-length(port)-1);
    if (addr ~ /^(127\.|10\.|\[::1\]|\[fe80|::1)/ || addr ~ /%lo$/) next;
    match($0,/users:\(\("[^"]+/); p=substr($0,RSTART+9,RLENGTH-9); if (p=="") p="?";
    print $1, port, p}' | sort -u)

# ---------- 2. firewall, fail2ban, ssh ----------
[ -n "$FW_CHAIN_V4" ] && { iptables -S INPUT 2>/dev/null | grep -q -- "-j $FW_CHAIN_V4\$" || add "firewall chain $FW_CHAIN_V4 not hooked into INPUT"; }
[ -n "$FW_CHAIN_V6" ] && { ip6tables -S INPUT 2>/dev/null | grep -q -- "-j $FW_CHAIN_V6\$" || add "IPv6 firewall chain $FW_CHAIN_V6 not hooked into INPUT"; }
if systemctl is-active -q fail2ban; then
  for j in $F2B_JAILS; do
    fail2ban-client status "$j" >/dev/null 2>&1 || { add "fail2ban jail '$j' not loaded"; continue; }
    tot=$(fail2ban-client status "$j" | awk -F: '/Total failed/{gsub(/ /,"",$2);print $2}')
    prev=$(cat "$STATE/f2b-$j.total" 2>/dev/null || echo -1); echo "${tot:-0}" > "$STATE/f2b-$j.total"
    # a public jail that counted NOTHING since yesterday is probably mis-wired (journalmatch!)
    [ "$prev" -ge 0 ] && [ "${tot:-0}" -eq 0 ] && add "fail2ban jail '$j' has counted 0 failures (check journalmatch/logpath)"
  done
else add "fail2ban not running"; fi
sshd -T 2>/dev/null | grep -qi '^passwordauthentication no' || add "SSH PasswordAuthentication is not 'no'"
sshd -T 2>/dev/null | grep -qiE '^permitrootlogin (no|prohibit-password|without-password)' || add "SSH PermitRootLogin allows passwords"

# ---------- 3. junk in web roots ----------
roots=$(ls -d $WEB_ROOTS 2>/dev/null)
if [ -n "$roots" ]; then
  mapfile -t junk < <(find $roots -xdev -type f \( -name '*.bak*' -o -name '*.orig' -o -name '*.old' \
      -o -name '*.sql' -o -name '*.sql.gz' -o -name '*.dump' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \
      -o -name '.env' -o -name '.env.*' -o -name '*.swp' -o -name '*~' \) 2>/dev/null | head -200)
  [ ${#junk[@]} -gt 0 ] && add "${#junk[@]} backup/dump/env file(s) in web roots (e.g. ${junk[0]})"

  # PHP inside uploads dirs (classic webshell drop spot)
  mapfile -t upphp < <(find $roots -xdev -path '*/uploads/*' -name '*.php' 2>/dev/null | grep -v '/index\.php$' | head -20)
  [ ${#upphp[@]} -gt 0 ] && add "${#upphp[@]} PHP file(s) inside uploads dirs (e.g. ${upphp[0]})"

  # webshell signatures in PHP changed in the last 2 days (full scan weekly is better)
  mapfile -t shells < <(find $roots -xdev -name '*.php' -mtime -2 -print0 2>/dev/null | xargs -0 -r grep -lE \
     'eval\s*\(\s*(base64_decode|gzinflate|gzuncompress|str_rot13)|assert\s*\(\s*\$_(POST|GET|REQUEST)|\$_(POST|GET|REQUEST|COOKIE)\s*\[[^]]+\]\s*\(' 2>/dev/null | head -10)
  [ ${#shells[@]} -gt 0 ] && add "possible webshell signature: ${shells[*]:0:3}"

  # changed PHP in 24h, minus known noisy paths
  n=$(find $roots -xdev -name '*.php' -mtime -1 2>/dev/null | { [ -n "$PHP_CHANGE_IGNORE" ] && grep -vE "$PHP_CHANGE_IGNORE" || cat; } | wc -l)
  [ "$n" -gt 0 ] && add "$n .php file(s) changed in the last 24h under web roots (expected a deploy?)"
fi
if [ -n "$BAK_PROBE_URL" ]; then
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BAK_PROBE_URL")
  [ "$c" = 404 ] || [ "$c" = 403 ] || add "block rule not answering: $BAK_PROBE_URL returned $c"
fi

# ---------- 4. failed logins: alert on a jump, not on the noise ----------
today=$(journalctl --since "-24h" -q 2>/dev/null | grep -cE 'sshd.*(Failed password|Invalid user|authentication failure)')
echo "$(date +%F) $today" >> "$STATE/failed-logins.hist"; tail -n 8 "$STATE/failed-logins.hist" > "$STATE/.h" && mv "$STATE/.h" "$STATE/failed-logins.hist"
median=$(head -n -1 "$STATE/failed-logins.hist" | awk '{print $2}' | sort -n | awk '{a[NR]=$1} END{if(NR) print a[int((NR+1)/2)]; else print 0}')
[ "${median:-0}" -gt 50 ] && [ "$today" -gt $(( median * FAILED_LOGIN_FACTOR )) ] && add "ssh failed logins 24h: $today (7-day median $median)"

# ---------- 5. new admins (sudo group + WordPress administrators) ----------
cur_admins=$( { getent group sudo wheel admin 2>/dev/null | cut -d: -f4 | tr ',' '\n';
  for s in $WP_SITES; do command -v wp >/dev/null && sudo -u "$WP_CLI_USER" wp --path="$s" user list --role=administrator --field=user_login 2>/dev/null | sed "s|^|$s:|"; done; } | grep -v '^$' | sort -u)
if [ -f "$STATE/admins.baseline" ] && [ "$REBASE" != admins ] && [ "$REBASE" != all ]; then
  new=$(comm -13 "$STATE/admins.baseline" <(echo "$cur_admins"))
  [ -n "$new" ] && add "new admin account(s): $(echo $new)"
else echo "$cur_admins" > "$STATE/admins.baseline"; fi

# ---------- 6. SUID drift ----------
cur_suid=$(find / -xdev \( -path /proc -o -path /sys -o -path /snap \) -prune -o -type f -perm -4000 -print 2>/dev/null | sort)
if [ -f "$STATE/suid.baseline" ] && [ "$REBASE" != suid ] && [ "$REBASE" != all ]; then
  new=$(comm -13 "$STATE/suid.baseline" <(echo "$cur_suid"))
  [ -n "$new" ] && add "new SUID binary: $(echo $new)"
else echo "$cur_suid" > "$STATE/suid.baseline"; fi

# ---------- 7. world-readable credentials in /tmp, /var/tmp, /dev/shm ----------
mapfile -t tmpcreds < <(find /tmp /var/tmp /dev/shm -xdev -type f -perm -004 -size -512k ! -name '*.log' 2>/dev/null | \
   xargs -r -d '\n' grep -lIiE '(pass(word)?|passwd|secret|api[_-]?key|token)\s*[=:]' 2>/dev/null | head -10)
[ ${#tmpcreds[@]} -gt 0 ] && add "${#tmpcreds[@]} world-readable file(s) in temp dirs look like they hold credentials (e.g. ${tmpcreds[0]})"

# ---------- 8. reboot / updates ----------
[ -f /var/run/reboot-required ] && add "reboot required since $(date -r /var/run/reboot-required +%F)"
if command -v apt-get >/dev/null; then
  sec=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst .*-security')
  [ "$sec" -gt 0 ] && add "$sec security update(s) pending (is unattended-upgrades running?)"
fi

[ -n "$REBASE" ] && { echo "rebaselined: $REBASE"; exit 0; }

# ---------- report: only on drift ----------
cur=$(printf '%s\n' "${drift[@]}" | sed '/^$/d' | sort)
if [ "$PRINT" = 1 ]; then
  [ -z "$cur" ] && echo "OK: no drift" || echo "$cur"; exit 0
fi
prev=$(cat "$STATE/last.txt" 2>/dev/null)
echo "$cur" > "$STATE/last.txt"
new=$(comm -13 <(echo "$prev") <(echo "$cur") | sed '/^$/d')
gone=$(comm -23 <(echo "$prev") <(echo "$cur") | sed '/^$/d')
remind=0
if [ -n "$cur" ] && [ "$REMIND_DAYS" -gt 0 ]; then
  last=$(cat "$STATE/last-remind" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - last )) -gt $(( REMIND_DAYS * 86400 )) ] && remind=1
fi
if [ -n "$new" ] || [ -n "$gone" ] || [ $remind = 1 ]; then
  {
    echo "🛡️ Security sweep: $(hostname -s)"
    [ -n "$new" ]  && { echo; echo "🆕 New:"; echo "$new" | sed 's/^/• /'; }
    [ -n "$gone" ] && { echo; echo "✅ Resolved:"; echo "$gone" | sed 's/^/• /'; }
    still=$(comm -12 <(echo "$prev") <(echo "$cur") | sed '/^$/d')
    [ -n "$still" ] && { echo; echo "⏳ Still open:"; echo "$still" | sed 's/^/• /'; }
  } | eval "$ALERT_CMD"
  date +%s > "$STATE/last-remind"
fi
