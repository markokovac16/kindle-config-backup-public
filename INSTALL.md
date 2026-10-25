# Install guide: from a stock Kindle to this setup

This is the full recipe for the setup in this repo, in the order it was done on a Kindle
Paperwhite 5 (11th gen, firmware 5.18.6) in October 2026. Following it on the same model should
give the same result; other models may need different steps (check https://kindlemodding.org). Every step says what it does, why, and how to undo it.

**What you end up with**
- A jailbroken Kindle that boots straight into KOReader, with Amazon's own reader out of the way.
- A Kindle-style home screen. It has "Jump back in", a library and collections, quick settings,
  reading stats, a daily goal, Reading Wrapped, and games (chess, Sudoku, 2048).
- Every book looks the same, in Bookerly. Pages turn smoothly and warmth follows the sun.
- Manga is set up properly: right-to-left reading, series collections, rotated two-page spreads,
  and the next volume opens automatically.
- SSH access, plus a daily backup pulled by a Raspberry Pi.

**Conventions**
- Commands marked **Mac** run in a terminal in this repo's folder.
- Commands marked **Kindle** run over SSH, as `ssh -p 2222 root@KINDLE_IP '...'`.
  `KINDLE_IP` is the Kindle's address on your Wi-Fi (look it up in your router; a fixed DHCP lease helps).
- `/mnt/us` on the Kindle is the USB drive you see on the Mac (`/Volumes/Kindle`).

---

## 0. Before you start

1. **Check the model and firmware.** Plug the Kindle in and run `python3 tools/check-device.py`,
   or read Settings → Device Options → Device Info. Jailbreaks depend on both. This guide uses
   **SpiderCat**, which kindlemodding.org lists for firmware **5.16.3 to 5.19.5**. If the check doesn't
   list SpiderCat for your Kindle, use one of the jailbreaks it lists instead, following that one's page on
   https://kindlemodding.org, then continue from step 2. Until then, keep the Kindle in airplane mode.
2. **Make a full backup over USB.** This matters: the jailbreak needs the drive almost full, and
   when storage ran low the firmware **deleted 39 books** on its own.
   ```sh
   # Mac, Kindle plugged in over USB
   rsync -a --exclude='.Spotlight-V100' --exclude='.fseventsd' /Volumes/Kindle/ ~/kindle-backup-$(date +%F)/
   ```
3. **Keep Mac junk off the Kindle.** macOS writes `._*` files next to anything it copies. Always
   copy with `COPYFILE_DISABLE=1`, or run `dot_clean -m /Volumes/Kindle` afterwards.
4. Delete any half-downloaded Amazon update: `rm -f /Volumes/Kindle/update.bin.tmp.partial`.

## 1. Jailbreak (SpiderCat)

SpiderCat is a "book" that, when opened, runs code as root and installs the jailbreak. It also
**blocks Amazon's automatic firmware updates**, which would remove the jailbreak. It does this by
renaming `/usr/bin/otaupd` and `/usr/bin/otav3` to `*.bck`. Follow the current instructions on
https://kindlemodding.org (SpiderCat page). What was done here:

1. **Mac:** download the SpiderCat book and put it in `documents/`:
   ```sh
   curl -fL -o /Volumes/Kindle/documents/spidercat.azw3 https://kindlemodding.org/spidercat/spidercat.azw3
   ```
2. **Mac:** fill the drive so only ~100 MB is left (SpiderCat needs this). About 13 GB of zero
   files went into a `filler` folder; at USB speed this takes ~15 minutes:
   ```sh
   mkdir /Volumes/Kindle/filler
   # repeat with new names until `df -h /Volumes/Kindle` shows ~100 MB free
   dd if=/dev/zero of=/Volumes/Kindle/filler/f1 bs=1m count=4000
   ```
3. Eject the Kindle. **On the Kindle:** turn airplane mode off, connect to Wi-Fi, open the
   SpiderCat book and wait while the text scrolls. Ignore any "application error" pop-ups. It shows
   "Restarting Kindle" and reboots by itself.
4. **Check that it worked:** on the USB drive, `privesc_marker.txt` should say
   `jb.so constructor: uid=0 euid=0`, and `documents/JAILBROKEN.txt` exists.
5. **Free the space straight away:** `rm -rf /Volumes/Kindle/filler`. If any books are missing,
   put them back from the backup:
   ```sh
   rsync -a --ignore-existing --exclude='._*' ~/kindle-backup-DATE/documents/ /Volumes/Kindle/documents/
   ```

The jailbreak also installs KPM (Kindle Package Manager, in `/mnt/us/kmc/kpm`) and its boot hook
`/etc/upstart/kmc.conf`. No KUAL, MRPI or hotfix was needed.

## 2. KOReader and KOmpanion (through KPM)

On the Kindle, with Wi-Fi on, type these into the **search bar** on the home screen, one at a time:

```
;kpm update
;kpm install koreader
;kpm install kompanion
```

- **KOReader** ends up in `/mnt/us/koreader`. The version tested with this repo is **v2026.07.1**
  (`koreader/git-rev`). `documents/KOReader.sh` starts it from the stock library.
- **KOmpanion** (KPM package 0.2.0, by Marek) lets the stock Kindle library open EPUB/CBZ/FB2 in
  KOReader. In step 6, MOBI and PDF are added to it.

Start KOReader once from the library (tap "KOReader"), then go on.

## 3. SSH (so the rest can be done from the Mac)

1. **Mac, over USB:** install your public key. KOReader's SSH server reads it from here:
   ```sh
   mkdir -p /Volumes/Kindle/koreader/settings/SSH
   cp ~/.ssh/id_ed25519.pub /Volumes/Kindle/koreader/settings/SSH/authorized_keys
   ```
2. **On the Kindle, in KOReader:** wrench icon → Network → SSH server → Start (only needed this once;
   the `2-kindle-like-text` patch later makes it start automatically, key-only).
3. **Mac:** `ssh -p 2222 root@KINDLE_IP` should log you in without a password. The userland is
   BusyBox: `grep` has no `--include`, there's no `rsync`, and GNU tar is at `/mnt/us/koreader/tar`.

SSH only runs while KOReader runs and Wi-Fi is on. **Restarting KOReader kills the SSH session**, so
never restart it in the middle of a transfer.

## 4. Project: Title (required by the home screen)

The home screen takes book covers and titles from Project: Title's cover cache.

```sh
# Mac
curl -fLO https://github.com/joshuacant/ProjectTitle/releases/download/2026.07-v3.8.3/ProjectTitle-2026-07-01-v3-8-3.zip
unzip ProjectTitle-2026-07-01-v3-8-3.zip -d pt
COPYFILE_DISABLE=1 scp -P 2222 -r pt/projecttitle.koplugin root@KINDLE_IP:/mnt/us/koreader/plugins/
```

**In KOReader:** ☰ → Tools (wrench) → Plugin management → User plugins. Untick **Cover browser**
and tick **Project: Title**. Then fully exit KOReader and start it again (a plain restart wasn't enough
for it to appear).

## 5. This repo's KOReader setup

Copy the custom plugins, patches and folder defaults:

```sh
# Mac, from this repo
K=root@KINDLE_IP
COPYFILE_DISABLE=1 scp -P 2222 -r koreader/plugins/kindlehome.koplugin koreader/plugins/chess.koplugin \
    $K:/mnt/us/koreader/plugins/
COPYFILE_DISABLE=1 scp -P 2222 -r koreader/patches $K:/mnt/us/koreader/
COPYFILE_DISABLE=1 scp -P 2222 koreader/settings/directory_defaults.lua $K:/mnt/us/koreader/settings/
```

Optional, for the home screen's games row (both are other people's plugins, so they aren't in this repo):
- **Sudoku+**: https://github.com/Borisvl/sudokuplus.koplugin/releases (tested with v1.2.0); unzip
  `sudokuplus.koplugin.zip` into `/mnt/us/koreader/plugins/`.
- **2048**: copy the `2048.koplugin` folder from https://codeberg.org/anserina/2048.koplugin (tested
  with 1.0.3) into `/mnt/us/koreader/plugins/`.

**Before restarting**, set your location in `koreader/patches/2-night.lua` (`LOCATION`), or warmth
won't follow the sun. Then, **in KOReader**, open the quick settings (swipe down from the top) and tap **Restart**, or use
☰ → Exit → Restart KOReader.

How the patches work (useful to know before you change one):
- Files in `koreader/patches/` run every time KOReader starts. They must be named `2-…`, because
  `1-` patches run before KOReader's settings exist and crash.
- KOReader only writes its settings file when it exits. So a patch that changes a setting does it
  once, behind a flag like `if not G_reader_settings:isTrue("x_applied")`. You can still change any
  of those settings by hand afterwards and the patch won't touch them again.
- To re-run a one-time patch, remove its flag from `settings.reader.lua` (with KOReader closed).

What each patch does:

| Patch | What it does |
|---|---|
| `2-kindle-like-text` | Darker text (contrast 25, font weight +0.5) and font size 12. Sleep screen shows the current book's cover, with no "Sleeping" text. Bigger render cache. Cover grid in the file browser. **SSH starts with KOReader, key-only.** |
| `2-uniform-books` | Every book looks the same, like Kindle's global Aa settings. When a book is saved, its own display options are moved into the global defaults, so changing the font in one book changes it for all. **Bookerly** (Amazon's system font, already on the Kindle) is the default, with pure black, justified text. Progress, highlights and hyphenation stay per book. |
| `2-pageturn` | No periodic black flash. The PW5's jittery hardware page animation is off. CPU governor `interactive`, so page renders get full speed immediately. |
| `2-speed` | Turns off 15 built-in plugins that aren't used (OPDS, Wallabag, News, Terminal…). Re-enable any of them under Plugin management. |
| `2-qol` | Reading footer with chapter time left and %. Sleep after 10 min, never auto power-off. Calibre wireless sends into `documents/`. Brightness (left edge) and warmth (right edge) swipes only in the lower half of the screen, so swipes from the top always reach the menus. |
| `2-night` | Warmth follows the sun at `LOCATION` (set it at the top of the patch first; change later under Settings → Auto warmth). Dark mode is **never** switched on automatically, only by hand. |
| `2-bedtime` | The first time the light is on after 21:00, brightness drops **once**, to 60%. A level you pick by hand is never overridden. The old level comes back in the morning, but only if you didn't change it. |
| `2-comics` | Manga/comics: a full refresh every 2 pages against ghosting. At the end of a volume it marks it read and opens the next one in the folder (natural sort, so Vol. 10 comes after Vol. 9). |
| `2-titles` | Template: clean titles and authors for books with messy metadata, written as KOReader custom metadata. Add entries to `FIXES` (by file name) and bump `FIXES_VERSION`. Does nothing while `FIXES` is empty. |
| `2-update-guard` | Tapping KOReader's Update first warns "tested on v2026.07.1". Test new versions before updating, then bump `TESTED`. |

`settings/directory_defaults.lua` gives everything under `documents/Manga/` manga settings the first
time a volume is opened: one page per screen, zoom to content, right-to-left, software dithering.

### The home screen (`kindlehome.koplugin`)

It replaces KOReader's file browser at startup and whenever you close a book.
- **Home:** "Jump back in" (the whole card opens the book). It also shows reading stats: today against the
  **30-minute daily goal** (`12 / 30 min`, then `✓ 34 min`), the streak of days that met the goal,
  and pages this week. Below that are recent books and collections.
- **Library:** opens on Collections, plus a 4×3 cover grid with a % or "Read" badge. The sort you
  pick is remembered. Every `documents/Manga/<Series>/` folder automatically gets its own
  collection, created once, so deleting one by hand keeps it deleted.
- **Quick settings** (swipe down from the top on home, or from the **top-right** of the screen in
  a book; top-left keeps KOReader's menus): Wi-Fi, dark mode, Calibre, Refresh, Restart, plus
  brightness and warmth sliders.
- **More:** Reading stats (calendar), **Reading Wrapped** (a story of your year or month: time,
  top books, manga, reader type, records), and Sudoku, 2048 and Chess.
- **In a book:** a small note when you pass the daily goal.
- **Speed:** folder listings, titles and scaled covers stay in memory between visits, so going home
  takes about 75 ms of work.
- Change the goal with `kindlehome_daily_goal_min` in `settings.reader.lua`.

### Games
- **Chess** (`chess.koplugin`, written for this Kindle). Full rules, verified with perft, plus undo,
  hints and 4 levels (Expert thinks 8 s). It saves the game. Tests: `tools/chess-tests/README.md`.
- **Sudoku+** and **2048** (optional, installed separately, see above). Both were read through
  before installing: no network, no shell. Their buttons in More do nothing if they're missing.

## 6. Kindle system tweaks (rootfs, over SSH)

These change files outside `/mnt/us`. Each one has an undo.

**a. Boot straight into KOReader.** `system/koreader-autostart.conf` is an upstart job. Once the stock
home screen is up, it starts KOReader with Amazon's framework stopped, once per boot. That frees about
130 MB of RAM.
```sh
# Mac
scp -P 2222 system/koreader-autostart.conf root@KINDLE_IP:/tmp/
ssh -p 2222 root@KINDLE_IP 'mntroot rw && cp /tmp/koreader-autostart.conf /etc/upstart/ && sync; mntroot ro'
```
- **Kill switch, no SSH needed:** create an empty file `NO_KOREADER_AUTOSTART` in the USB drive's root.
- **Undo:** `mntroot rw; rm /etc/upstart/koreader-autostart.conf; mntroot ro`.

**b. Fix the clock (if it's off).** On this Kindle the stock timezone was a broken fixed
`GMT+01:46`, which put the clock 46 minutes off. The fix: copy a proper zone file from the Mac,
plus its POSIX rule. Example for Central Europe (`Europe/Berlin`, `Europe/Paris`, …):
```sh
# Mac
ssh -p 2222 root@KINDLE_IP 'cp /var/local/system/tz /mnt/us/koreader/tz.bak; cp /var/local/system/tzVar /mnt/us/koreader/tzVar.bak'
scp -P 2222 /var/db/timezone/zoneinfo/Europe/Berlin root@KINDLE_IP:/var/local/system/tz
ssh -p 2222 root@KINDLE_IP 'echo "KINDLE_TZ=CET-1CEST,M3.5.0,M10.5.0/3" > /var/local/system/tzVar'
```
- **Undo:** copy the two `.bak` files back.
- **Other timezones:** use `/var/db/timezone/zoneinfo/<Zone>` and that zone's POSIX string (the last line of `tail -1 /var/db/timezone/zoneinfo/<Zone>`).

**c. Open MOBI and PDF from the stock library in KOReader** (through KOmpanion). This backs up
`appreg.db` and `cc.db` to `/mnt/us/appreg-backup/` first, then restarts are needed.
```sh
# Mac
ssh -p 2222 root@KINDLE_IP sh -s < system/route-to-koreader.sh
COPYFILE_DISABLE=1 scp -P 2222 "system/Retag for KOReader.sh" "root@KINDLE_IP:/mnt/us/documents/"
```
- Then restart the Kindle.
- **After sideloading new MOBI/PDF**, tap "Retag for KOReader" in the stock library.
- `.azw`/`.kfx` (store books) are left alone. They're DRM-locked and won't open in KOReader anyway.
- **Undo:** copy the backups back over `/var/local/appreg.db` and `/var/local/cc.db`.

## 7. Check it all

After a reboot:
- [ ] The Kindle boots into the home screen with "Jump back in" (not the Amazon home).
- [ ] `ssh -p 2222 root@KINDLE_IP` works without a password, and `date` shows the right local time.
- [ ] A book opens in Bookerly, and page turns don't flash.
- [ ] Swiping down from the top-right in a book opens quick settings.
- [ ] A manga volume reads right-to-left, and its series shows up as a collection.
- [ ] No new errors at the end of `/mnt/us/koreader/crash.log`.

## 8. Daily backup to a Raspberry Pi (optional)

Every 15 minutes the Pi checks whether the Kindle is awake on Wi-Fi. If it's been at least 20 hours
since the last backup, it pulls a `tar.gz` of settings, reading stats, highlights, history, patches
and the home plugin, and keeps the newest 30. The Pi's key can only run that one backup script, with
no shell (a forced command in `authorized_keys`).

```sh
# Mac, with `ssh <pi>` working and the Kindle on Wi-Fi.
# First set the Kindle's IP at the top of backup/pi-backup.sh.
KINDLE_IP=192.168.1.50 PI=pi@raspberrypi sh backup/setup-kindle-backup.sh
```

- **Restore:** copy a tarball to the Kindle, quit KOReader, then
  `cd /mnt/us && /mnt/us/koreader/tar xzf kindle-DATE.tar.gz`.
- With Wi-Fi off, backups simply wait until the next time it's on.

## 9. Adding manga

```sh
# Mac (needs Pillow: pip3 install --user Pillow)
python3 tools/manga_convert.py "in.cbz" "Series, Vol. 1 - Author.cbz"
# from a PDF: extract the pages first and check the count matches
pdfimages -j vol.pdf pages/p && python3 tools/manga_convert.py pages "Series, Vol. N - Author.cbz"
```
- **What the converter does:** greyscale pages fitted to the 1236×1648 screen, in proper chapter
  order, with two-page spreads rotated 90° (turn the Kindle clockwise to read them).
- **Where files go:** `documents/Manga/<Series>/Series, Vol. N - Author.cbz`.
- **Uploading:** use a staging folder (`/mnt/us/manga-incoming`), then `mv` each volume into place,
  so half-copied files never show up.
- **Keep it awake during big uploads:** `lipc-set-prop com.lab126.powerd preventScreenSaver 1`, and
  set it back to `0` afterwards.
- **Before big uploads:** check free space and make a backup (see step 0).
- **Volumes already on the Kindle:** `KINDLE_IP=… python3 tools/scan_spreads.py spreads.json` finds wide pages over SSH, and
  `tools/rotate_spreads.py spreads.json` rotates them in place.

## Good to know / troubleshooting

- **Restart vs exit:** while KOReader runs, Amazon's framework is stopped.
  - USB drive mode and Kindle-store books need ☰ → Exit → "Exit to Kindle" first (takes 30–60 s).
  - The stock power menu doesn't show; reboot with ☰ → Exit → Reboot.
- **Frozen screen** usually means KOReader crashed. Look at the end of `/mnt/us/koreader/crash.log`.
  Restart it remotely with `setsid /mnt/us/koreader/koreader.sh --framework_stop &`. If it then
  says "startup script has been updated", tap Ignore.
- **Updating KOReader:** the update guard asks first. A new version can break the home screen or
  patches, so test it (see AGENTS.md), then bump `TESTED` in `2-update-guard.lua`.
- **Plugins** each add a module directory to Lua's search path, so give your own modules unique names.
  Avoid plugins that write the settings file often (`G_reader_settings:flush()`); one that did it every few pages made page turns visibly laggy.
- **Battery:** nothing here costs noticeable battery. Wi-Fi is the big drain, so turn it off
  when you don't need SSH or backups.
- **Amazon updates** stay blocked as long as `/usr/bin/otaupd.bck` and `/usr/bin/otav3.bck` keep
  their `.bck` names. Never rename them back.
