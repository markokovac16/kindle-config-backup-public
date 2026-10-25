#!/bin/sh
# Make the stock Kindle library open sideloaded MOBI and PDF books in KOReader, through the
# KOmpanion KPM package (handler com.notmarek.kompanion.launcher). Run ON the Kindle, as root:
#   ssh -p 2222 root@<kindle-ip> sh -s < system/route-to-koreader.sh
# Backs up appreg.db and cc.db to /mnt/us/appreg-backup first. Restart the Kindle afterwards.
# Undo: copy the backups back over /var/local/appreg.db and /var/local/cc.db and restart.
# (Note: the table really is called "extenstions" in Amazon's appreg.db.)
set -e
mkdir -p /mnt/us/appreg-backup
STAMP=$(date +%Y%m%d%H%M%S)
cp /var/local/appreg.db /mnt/us/appreg-backup/appreg.db.$STAMP
cp /var/local/cc.db /mnt/us/appreg-backup/cc.db.$STAMP
for EXT in mobi pdf; do
    MT="MT:application/x-kompanion-$EXT"
    sqlite3 /var/local/appreg.db "BEGIN;
DELETE FROM mimetypes WHERE ext=\"$EXT\";
INSERT INTO mimetypes (ext, mimetype) VALUES (\"$EXT\", \"$MT\");
DELETE FROM extenstions WHERE ext=\"$EXT\";
INSERT INTO extenstions (ext, mimetype) VALUES (\"$EXT\", \"$MT\");
DELETE FROM associations WHERE contentId=\"$MT\";
INSERT INTO associations (interface, handlerId, contentId, defaultAssoc) VALUES (\"application\", \"com.notmarek.kompanion.launcher\", \"$MT\", \"true\");
COMMIT;"
done
# Books already in the library keep their old type until retagged (same as the Retag scriptlet).
sqlite3 /var/local/cc.db "UPDATE Entries SET p_mimeType=\"application/x-kompanion-mobi\" WHERE p_location LIKE \"%.mobi\";
UPDATE Entries SET p_mimeType=\"application/x-kompanion-pdf\" WHERE p_location LIKE \"%.pdf\";"
[ -f "/mnt/us/documents/Retag for KOReader.sh" ] || echo "Tip: also copy 'system/Retag for KOReader.sh' to /mnt/us/documents/ (chmod +x)."
echo "Done. Backups: /mnt/us/appreg-backup/*.$STAMP. Restart the Kindle."
