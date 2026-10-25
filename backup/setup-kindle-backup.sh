#!/bin/sh
# One-time setup: the Raspberry Pi pulls a daily backup of the Kindle's KOReader setup.
# 1. Kindle: script that streams the backup as tar.gz.
# 2. Pi: its own SSH key, allowed on the Kindle ONLY to run that script (forced command, no shell).
# 3. Pi: puller script + cron every 15 min (backs up once per ~20h when the Kindle is awake on Wi-Fi).
set -e
# Usage: KINDLE_IP=192.168.1.50 PI=pi@raspberrypi sh backup/setup-kindle-backup.sh
# Set the same IP in pi-backup.sh first.
: "${KINDLE_IP:?set KINDLE_IP}" "${PI:?set PI (ssh target of the Pi)}"
S=$(dirname "$0")
scp -q -P 2222 $S/backup-out.sh root@$KINDLE_IP:/mnt/us/koreader/backup-out.sh
ssh $PI 'mkdir -p ~/kindle-backup; [ -f ~/.ssh/kindle_backup ] || ssh-keygen -q -t ed25519 -N "" -C "kindle-backup" -f ~/.ssh/kindle_backup'
KEY=$(ssh $PI 'cat ~/.ssh/kindle_backup.pub')
ssh -n -p 2222 root@$KINDLE_IP "cd /mnt/us/koreader/settings/SSH && cp authorized_keys authorized_keys.bak && { grep -q 'kindle-backup' authorized_keys || echo 'command=\"sh /mnt/us/koreader/backup-out.sh\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $KEY' >> authorized_keys; }"
scp -q $S/pi-backup.sh $PI:kindle-backup/backup.sh
ssh $PI 'chmod +x ~/kindle-backup/backup.sh; (crontab -l 2>/dev/null | grep -v kindle-backup; echo "*/15 * * * * $HOME/kindle-backup/backup.sh") | crontab -; ~/kindle-backup/backup.sh; ls -la ~/kindle-backup'
