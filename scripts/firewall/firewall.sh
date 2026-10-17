#!/usr/bin/env bash
# firewall.sh: default-drop host firewall for IPv4 + IPv6, in its OWN chains.
#
#   firewall.sh on       apply (default-drop everything not allowlisted below)
#   firewall.sh off      remove our chains (back to whatever was there before)
#   firewall.sh status   show our chains
#
# Our chains are jumped from the END of INPUT, so rules other tools insert at the top
# (wg-quick PostUp, Docker, fail2ban) keep working, and "off" removes only what we added.
# Apply with apply-with-deadman.sh the first time. Make it survive reboots with
# firewall.service (below) and REBOOT-TEST it in a maintenance window.
set -u

# ---- edit these -----------------------------------------------------------
PUBLIC_TCP="22,80,443"            # e.g. add 25,465,587,993,995 on a mail host
PUBLIC_UDP="443"                  # HTTP/3; add 51820 for WireGuard
TRUSTED_IFACES="lo wg+"           # interfaces trusted completely (VPN)
ADMIN_ONLY_TCP=""                 # ports only ADMIN_SOURCES may reach, e.g. "10000" (Webmin) "2083" (cPanel)
ADMIN_SOURCES="192.0.2.10/32"     # your office / control box / VPN egress (space separated)
# ---------------------------------------------------------------------------

C4=AGENTOPS-IN; C6=AGENTOPS-IN6
mode=${1:-status}

flush() { local ipt=$1 ch=$2
  while $ipt -D INPUT -j "$ch" 2>/dev/null; do :; done
  $ipt -F "$ch" 2>/dev/null; $ipt -X "$ch" 2>/dev/null; }

case "$mode" in
  status) iptables -S "$C4" 2>/dev/null || echo "$C4 not present"
          ip6tables -S "$C6" 2>/dev/null || echo "$C6 not present"; exit 0 ;;
  off)    flush iptables "$C4"; flush ip6tables "$C6"; echo "firewall: off"; exit 0 ;;
  on)     ;;
  *)      echo "usage: $0 on|off|status" >&2; exit 2 ;;
esac

flush iptables "$C4"; flush ip6tables "$C6"

# ---------- IPv4 ----------
iptables -N "$C4"
for i in $TRUSTED_IFACES; do iptables -A "$C4" -i "$i" -j ACCEPT; done
iptables -A "$C4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A "$C4" -m conntrack --ctstate INVALID -j DROP
iptables -A "$C4" -p icmp -j ACCEPT                                   # ping + PMTU; providers monitor with ping
[ -n "$PUBLIC_TCP" ] && iptables -A "$C4" -p tcp -m multiport --dports "$PUBLIC_TCP" -j ACCEPT
[ -n "$PUBLIC_UDP" ] && iptables -A "$C4" -p udp -m multiport --dports "$PUBLIC_UDP" -j ACCEPT
for p in $ADMIN_ONLY_TCP; do for s in $ADMIN_SOURCES; do
  [[ $s == *:* ]] || iptables -A "$C4" -p tcp -s "$s" --dport "$p" -j ACCEPT; done; done
iptables -A "$C4" -p udp --sport 67 --dport 68 -j ACCEPT              # DHCP lease renewals
iptables -A "$C4" -j DROP
iptables -A INPUT -j "$C4"

# ---------- IPv6 (a v4-only firewall on a dual-stack box is a side door) ----------
ip6tables -N "$C6"
for i in $TRUSTED_IFACES; do ip6tables -A "$C6" -i "$i" -j ACCEPT; done
ip6tables -A "$C6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A "$C6" -m conntrack --ctstate INVALID -j DROP
ip6tables -A "$C6" -p ipv6-icmp -j ACCEPT                             # NDP/RA: IPv6 DIES without this
[ -n "$PUBLIC_TCP" ] && ip6tables -A "$C6" -p tcp -m multiport --dports "$PUBLIC_TCP" -j ACCEPT
[ -n "$PUBLIC_UDP" ] && ip6tables -A "$C6" -p udp -m multiport --dports "$PUBLIC_UDP" -j ACCEPT
for p in $ADMIN_ONLY_TCP; do for s in $ADMIN_SOURCES; do
  [[ $s == *:* ]] && ip6tables -A "$C6" -p tcp -s "$s" --dport "$p" -j ACCEPT; done; done
ip6tables -A "$C6" -p udp --dport 546 -j ACCEPT                       # DHCPv6 client
ip6tables -A "$C6" -j DROP
ip6tables -A INPUT -j "$C6"

echo "firewall: on (tcp $PUBLIC_TCP | udp $PUBLIC_UDP | admin-only ${ADMIN_ONLY_TCP:-none})"

# ---- firewall.service (save as /etc/systemd/system/firewall.service) ----
# [Unit]
# Description=Host firewall (AGENTOPS chains)
# After=network-pre.target
# Before=network-online.target
# [Service]
# Type=oneshot
# RemainAfterExit=yes
# ExecStart=/usr/local/sbin/firewall.sh on
# ExecStop=/usr/local/sbin/firewall.sh off
# [Install]
# WantedBy=multi-user.target
