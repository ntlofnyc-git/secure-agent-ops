#!/usr/bin/env bash
# move-baks-out.sh [--apply] [web roots...]
# Finds backup/dump/env junk in web roots and MOVES it (never deletes) to
# /root/webroot-junk-<date>/<original path>, keeping owner/perms/mtime. Dry run by default.
set -euo pipefail
APPLY=0; [ "${1:-}" = --apply ] && { APPLY=1; shift; }
ROOTS=("$@"); [ ${#ROOTS[@]} -eq 0 ] && ROOTS=(/var/www /home/*/public_html)
DEST=/root/webroot-junk-$(date +%Y%m%d-%H%M%S)

mapfile -t files < <(find "${ROOTS[@]}" -xdev -type f \( -name '*.bak*' -o -name '*.orig' -o -name '*.old' \
   -o -name '*.save' -o -name '*.swp' -o -name '*~' -o -name '*.sql' -o -name '*.sql.gz' -o -name '*.dump' \
   -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '.env' -o -name '.env.*' \) 2>/dev/null)

[ ${#files[@]} -eq 0 ] && { echo "nothing found"; exit 0; }
printf '%s\n' "${files[@]}" | while read -r f; do printf '%8s  %s\n' "$(du -h "$f" | cut -f1)" "$f"; done
echo "-- ${#files[@]} file(s)"
[ $APPLY = 0 ] && { echo "dry run: re-run with --apply to move them to $DEST"; exit 0; }

install -d -m 700 "$DEST"
for f in "${files[@]}"; do
  install -d -m 700 "$DEST$(dirname "$f")"
  mv -n "$f" "$DEST$f"
done
printf '%s\n' "${files[@]}" > "$DEST/MANIFEST.txt"
echo "moved ${#files[@]} file(s) to $DEST (manifest inside). Put one back with: mv $DEST/<path> /<path>"
echo "Now: check access logs for past downloads, and ROTATE any key that was in an exposed config."
