#!/bin/sh
# Name: Retag for KOReader
# Makes sideloaded MOBI and PDF books open in KOReader (via KOmpanion). Tap after adding books.
sqlite3 /var/local/cc.db "UPDATE Entries SET p_mimeType=\"application/x-kompanion-mobi\" WHERE p_location LIKE \"%.mobi\" AND p_mimeType<>\"application/x-kompanion-mobi\"; UPDATE Entries SET p_mimeType=\"application/x-kompanion-pdf\" WHERE p_location LIKE \"%.pdf\" AND p_mimeType<>\"application/x-kompanion-pdf\"; SELECT changes();" > /tmp/retag.out 2>&1
/mnt/us/libkh/bin/fbink -qmMp "Retagged for KOReader" 2>/dev/null
