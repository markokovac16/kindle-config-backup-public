#!/bin/sh
# Streams a tar.gz of the KOReader setup to stdout. Run by the Raspberry Pi's
# daily backup (forced command for its key in settings/SSH/authorized_keys).
cd /mnt/us || exit 1
LIST=/tmp/kindle-backup.list
{
    echo koreader/settings
    echo koreader/settings.reader.lua
    echo koreader/history.lua
    echo koreader/patches
    echo koreader/plugins/kindlehome.koplugin
    echo koreader/styletweaks
    echo koreader/backup-out.sh
    echo /etc/upstart/koreader-autostart.conf
    find documents -name "*.sdr" -type d
} > "$LIST"
exec /mnt/us/koreader/tar czf - --ignore-failed-read -T "$LIST" 2>/dev/null
