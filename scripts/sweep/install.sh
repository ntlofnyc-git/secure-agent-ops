#!/usr/bin/env bash
# install.sh: install the daily security sweep (script + conf + systemd timer)
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
install -m 700 security-sweep.sh /usr/local/sbin/security-sweep.sh
[ -f /etc/security-sweep.conf ] || install -m 600 security-sweep.conf.example /etc/security-sweep.conf
install -m 644 security-sweep.service security-sweep.timer /etc/systemd/system/
install -d -m 700 /var/lib/security-sweep
systemctl daemon-reload
echo ">> first run writes baselines (SUID, admins) and prints findings:"
/usr/local/sbin/security-sweep.sh --print || true
systemctl enable --now security-sweep.timer
echo ">> edit /etc/security-sweep.conf (allowlists, web roots, ALERT_CMD), then: security-sweep.sh --print"
