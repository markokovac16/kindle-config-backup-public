#!/bin/sh
# Daily pull of the Kindle's KOReader setup (settings, stats, highlights, custom
# plugin and patches). Runs from cron every 15 min; does nothing until the last
# backup is 20h old and the Kindle is awake on Wi-Fi. Keeps the newest 30.
DIR="$HOME/kindle-backup"
KINDLE=192.168.1.50 # the Kindle's IP; give it a fixed DHCP lease
STAMP="$DIR/.last"
mkdir -p "$DIR"
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt 72000 ]; then exit 0; fi
nc -z -w 3 "$KINDLE" 2222 2>/dev/null || exit 0
OUT="$DIR/kindle-$(date +%Y-%m-%d).tar.gz"
if ssh -n -i "$HOME/.ssh/kindle_backup" -p 2222 -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new root@"$KINDLE" > "$OUT.part" \
    && [ -s "$OUT.part" ] && gzip -t "$OUT.part" 2>/dev/null; then
    mv "$OUT.part" "$OUT"
    touch "$STAMP"
    ls -1t "$DIR"/kindle-*.tar.gz | tail -n +31 | xargs -r rm --
else
    rm -f "$OUT.part"
fi
