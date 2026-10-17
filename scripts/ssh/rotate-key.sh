#!/usr/bin/env bash
# rotate-key.sh <ssh-alias> <private-key-path>
# Rotate one key on one box without ever locking yourself out:
#   1. make a new key   2. add its pubkey on the box   3. PROVE login with the new key only
#   4. only then remove the old pubkey   5. swap files locally, keep the old one as .retired-<date>
set -euo pipefail
HOST=${1:?usage: rotate-key.sh <ssh-alias> <private-key-path>}
OLD=${2:?usage: rotate-key.sh <ssh-alias> <private-key-path>}
NEW="${OLD}_new"
STAMP=$(date +%F)

[ -f "$OLD" ] || { echo "no such key: $OLD" >&2; exit 1; }
[ -e "$NEW" ] && { echo "$NEW already exists; clean it up first" >&2; exit 1; }

ssh-keygen -q -t ed25519 -a 100 -N '' -f "$NEW" -C "$(whoami)@$(hostname -s) rotated $STAMP"
OLDPUB=$(cut -d' ' -f1,2 "$OLD.pub")
NEWPUB=$(cat "$NEW.pub")

echo "[1/4] adding new key on $HOST"
ssh -o IdentitiesOnly=yes -i "$OLD" "$HOST" \
  "umask 077; mkdir -p ~/.ssh; grep -qxF '$NEWPUB' ~/.ssh/authorized_keys 2>/dev/null || echo '$NEWPUB' >> ~/.ssh/authorized_keys"

echo "[2/4] testing login with the NEW key only"
if ! ssh -o IdentitiesOnly=yes -o BatchMode=yes -i "$NEW" "$HOST" true; then
  echo "new key FAILED, old key left in place, nothing removed" >&2; exit 1
fi

echo "[3/4] removing old key from $HOST"
ssh -o IdentitiesOnly=yes -i "$NEW" "$HOST" \
  "cp -p ~/.ssh/authorized_keys ~/.ssh/authorized_keys.pre-rotate-$STAMP && grep -vF '$OLDPUB' ~/.ssh/authorized_keys.pre-rotate-$STAMP > ~/.ssh/authorized_keys || true"

echo "[4/4] swapping local files"
mv "$OLD" "$OLD.retired-$STAMP"; mv "$OLD.pub" "$OLD.pub.retired-$STAMP"
mv "$NEW" "$OLD"; mv "$NEW.pub" "$OLD.pub"
ssh -o IdentitiesOnly=yes -o BatchMode=yes -i "$OLD" "$HOST" true && echo "done: $HOST now uses the rotated key"
echo "If this key is used on OTHER boxes, rotate those too, then delete $OLD.retired-$STAMP"
