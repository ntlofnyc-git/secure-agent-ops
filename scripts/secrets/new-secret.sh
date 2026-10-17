#!/usr/bin/env bash
# new-secret.sh <path>: save a secret into its own 600 file without it touching
# your screen, shell history, or an agent transcript.
#   new-secret.sh /root/.mailer-api-key           (prompts, input hidden)
#   some-cmd | new-secret.sh /root/.mailer-api-key (from stdin)
set -euo pipefail
F=${1:?usage: new-secret.sh /root/.<service>-<purpose>}
case "$F" in /var/www/*|/srv/*|/tmp/*|*/public_html/*) echo "refusing: $F is a public/shared location" >&2; exit 1;; esac
umask 077
[ -e "$F" ] && { cp -p "$F" "$F.prev-$(date +%Y%m%d-%H%M%S)"; echo "(old value kept as $F.prev-*; delete it once rotated)"; }
install -m 600 /dev/null "$F"
if [ -t 0 ]; then read -rs -p "secret for $F: " S; echo; else S=$(cat); fi
printf '%s' "$S" > "$F"; unset S
echo "saved $F ($(stat -c %a "$F"), $(wc -c < "$F") bytes). Use it as: \$(cat $F)"
echo "Next: run the scrubber so any earlier pasted copy becomes a pointer."
