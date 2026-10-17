#!/usr/bin/env bash
# apply-with-deadman.sh: apply the firewall with an automatic rollback in 5 minutes.
# If you lock yourself out, just wait. If everything works from OUTSIDE, confirm and the
# rollback is cancelled.
set -euo pipefail
FW=${FW:-/usr/local/sbin/firewall.sh}
MINUTES=${MINUTES:-5}

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -x "$FW" ] || { echo "$FW not found/executable" >&2; exit 1; }

systemctl stop fw-deadman.timer 2>/dev/null || true
systemd-run --quiet --unit=fw-deadman --on-active="${MINUTES}m" "$FW" off
echo ">> rollback armed: firewall goes OFF in $MINUTES min unless you confirm"

"$FW" on

cat <<MSG

Now test from ANOTHER machine (not this one, loopback proves nothing):
  ssh <this-box> true
  curl -sI https://<your-site>/ | head -1
  nc -vz <this-box> 993          # any other public port you kept
  ping -c2 <this-box>
  ping -6 -c2 <this-box>         # if the box has IPv6

MSG
read -r -p "All checks passed from outside? Type YES to keep the firewall: " ans
if [ "$ans" = YES ]; then
  systemctl stop fw-deadman.timer && echo ">> rollback cancelled, firewall stays ON"
  echo ">> next: enable firewall.service so it survives reboots, and reboot-test it"
else
  echo ">> leaving the rollback armed; firewall goes off in a few minutes"
fi
