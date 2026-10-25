# AGENTS.md: working on this repo

These notes are for whoever takes this over, person or coding agent. Read INSTALL.md first for
what's installed and why. This file covers how the code works, how to change it safely, and the
traps that cost time before.

## Step 1, every time: check which Kindle is connected

Jailbreaks, firmware tricks and even the KOReader build differ by Kindle model and firmware version.
This repo was made and tested on **one** combination:
- Kindle Paperwhite 5 (11th gen)
- firmware 5.18.6
- KOReader v2026.07.1

Before you suggest or run anything, find out what the user actually has:

```sh
python3 tools/check-device.py                          # Kindle plugged in over USB (Mac)
KINDLE_IP=192.168.1.50 python3 tools/check-device.py   # over SSH, once KOReader's SSH server runs
```

It changes nothing on the Kindle. It prints:
- the model, from the serial number's model code (the same table KOReader uses);
- the firmware, whether it's jailbroken, and whether Amazon's updater is blocked (over SSH);
- the KOReader version and which plugins and patches are installed;
- the free space.
If the Kindle isn't jailbroken yet, it also lists the jailbreaks that
[kindlemodding.org](https://kindlemodding.org/jailbreaks.json) currently says fit that model
and firmware.

If the script isn't available or can't read something, ask the user, or read it yourself:
- **On the Kindle:** Settings → Device Options → Device Info shows the firmware version and serial number.
- **Firmware over USB:** `cat /Volumes/Kindle/system/version.txt`, e.g. `Kindle 5.18.6 (458618 041)`.
- **Over SSH:**
  - firmware: `cat /etc/prettyversion.txt`
  - model code: `cut -c4-6 /proc/usid` (serials starting with B or 9: `cut -c3-4`)
  - KOReader version: `cat /mnt/us/koreader/git-rev`
- **Model codes:** look them up in KOReader's `frontend/device/kindle/device.lua`.
- **Privacy:** never print, paste or commit the full serial number. The model code is enough.

What to do with the result:
- **Every line OK:** follow INSTALL.md as written.
- **Different firmware or model:** don't use INSTALL.md's jailbreak steps (SpiderCat) unless the
  check lists SpiderCat for this Kindle.
  - Follow the current page on kindlemodding.org for a jailbreak that fits, and tell the user which
    one and why.
  - Don't guess. A jailbreak run on the wrong firmware can fail, or worse.
  - Until it's jailbroken, keep the Kindle in airplane mode so Amazon doesn't update it out of range.
- **Different model:** the KOReader parts mostly carry over, but check them on the device:
  - The home screen and patches assume a 1236×1648, 300 dpi touch screen with a warmth light.
  - The swipe zones, layout sizes and the light/warmth sliders may need changes.
  - Kindles with page-turn buttons, or without a warm light (the Basic models), have never been tested.
  - Say what's untested before deploying.
- **Newer KOReader:** see "Updating KOReader" below before deploying anything.
- **Jailbroken, but Amazon's updater is ACTIVE:** stop and block it first. An update can remove
  the jailbreak.

## The shape of it

- **No build step.** Everything is Lua that KOReader loads at runtime. The repo mirrors where files
  live on the Kindle (see the README table), so deploying means copying a file and restarting KOReader.
- **`koreader/plugins/kindlehome.koplugin/`** is the home screen:
  - `main.lua` has these parts:
    - `HomeScreen` is the widget. It has Home and Library tabs and the More menu, and it is shown on
      top of KOReader's FileManager every time that opens.
    - `QuickSettings` is the pull-down panel.
    - `KindleHome` is the plugin. It handles events, shows the home screen, starts goal tracking in
      books, and catches the swipe down from the top-right in books.
  - `kindlehome_wrapped_data.lua` holds the Reading Wrapped numbers. It is pure Lua, so you can test
    it off the device.
  - `kindlehome_wrapped.lua` holds the Reading Wrapped screens.
  - Covers, titles and authors come from **Project: Title**'s `PT_bookinfo_cache.sqlite3`
    (bookinfomanager). Reading stats come from the statistics plugin's `statistics.sqlite3`.
  - Caches keep home builds around 75 ms:
    - Folder listings are keyed by the folder's mtime. A 2 s guard handles the whole-second mtimes.
    - Book metadata is kept between builds.
    - Scaled covers are kept, up to 60 entries.
    - Cached cover blitbuffers are **never freed by hand**: a widget on screen may still use one.
      Drop the reference and let the GC free it.
  - Look for the `KindleHome: built in N ms` line in `crash.log`.
- **`koreader/plugins/chess.koplugin/`** is a chess game:
  - `chess_engine.lua` is a pure-Lua engine: move generation, search and SAN.
  - `chess_widget.lua` is the board UI.
  - Tests are in `tools/chess-tests/` (see below).
- **`koreader/patches/2-*.lua`** are user patches. KOReader runs every `patches/2-*.lua` at startup,
  in alphabetical order, after settings are loaded.
- **`system/`** has the parts outside KOReader: the upstart autostart job and the appreg.db/cc.db
  routing. **`backup/`** is the optional Pi backup. **`tools/`** has the manga tools and tests.

## Rules that matter

1. **Patches must be `2-` patches.** A `1-` patch runs before `G_reader_settings` exists and
   crashes at boot ("attempt to index global 'G_reader_settings'").
2. **KOReader writes `settings.reader.lua` only on exit.** Editing it over SSH while KOReader runs
   gets overwritten. Change settings in one of two ways:
   - a patch with a one-time flag (`if not G_reader_settings:isTrue("x_applied") then … makeTrue("x_applied") end`),
   - or edit the file with KOReader closed.
   A one-time flag means users can still change the setting afterwards. Never re-apply a user-facing
   setting on every boot. The exceptions are in-memory defaults like `G_defaults` swipe zones.
3. **Never fight the user.** Automatic behaviour gets applied once and then leaves manual changes
   alone. A scheduled dark mode that kept flipping back was removed for this reason. `2-bedtime.lua`
   is the model: dim once per night, and only restore in the morning if the level is still the dimmed one.
4. **Don't call `G_reader_settings:flush()` often.** It rewrites the whole settings file on slow
   flash storage. A plugin that did it every 5 pages made page turns visibly laggy.
5. **Everything must be removable.** Deleting a plugin folder or patch file must leave KOReader
   working. If a feature leaves settings behind, a later patch can clean them up once.
6. **Every plugin's folder goes on Lua's module path.** Give modules unique names
   (`kindlehome_*`, `chess_*`), or another plugin's `config.lua` can shadow yours.
7. **Keep the user's storage safe.** Make a backup before anything big. Low free space made the
   Kindle firmware delete books on its own once.

## Lua/KOReader traps that already bit

- **Don't name a loop variable `_`** in a file that uses `_` for gettext (`local _ = require("gettext")`).
  `for _, x in ipairs(t)` shadows it, and the next `_("text")` call crashes.
- **`a and f() or g()` truncates `f()` to one return value.** That broke `lfs.dir`, which returns an
  iterator *and* a state. Use a plain `if`.
- **`VerticalGroup:getSize()` caches the layout.** Call `resetLayout()` before inserting more
  children, or KOReader crashes at boot.
- **Don't redeclare FFI types or functions.** `ffi.cdef` of something KOReader already declared
  (for example `clock_gettime`) is an error. Use `require("ui/time")` for timing.
- **Define a local helper before the code that calls it.** A `local function` used before its
  definition is a nil global at runtime, and only crashes when that path runs.
- **Rebuilding a widget tree mid-gesture:** do it from `UIManager:nextTick` (see `HomeScreen:later()` in
  `main.lua`), not inside the tap handler you're dispatching into.
- **E-ink refresh modes:** `einkMode()` and `pageMode()` in `main.lua` copy Amazon's approach. Big
  updates flash, small ones add up to a flash later. Use `"ui"` or `"partial"` for small regions
  and `"flashui"` for full redraws.
- **Events:** widgets get broadcast events through `on<Event>` methods, for example
  `onNetworkConnected` / `onNetworkDisconnected` (the home status bar uses these). Plugins see reader events
  like `onPageUpdate`, `onResume`, `onCloseDocument`.

## Working on the device

- **SSH:** `ssh -p 2222 root@KINDLE_IP`. SSH only runs while KOReader runs and Wi-Fi is on.
  - The userland is BusyBox: `grep` has no `--include`, there's no rsync, and GNU tar is at
    `/mnt/us/koreader/tar`. Pass `-n` to `ssh` in scripts.
  - Modern `scp` doesn't want backslash-escaped spaces in remote paths.
- **Deploy one file:** `scp -P 2222 koreader/plugins/kindlehome.koplugin/main.lua root@KINDLE_IP:/mnt/us/koreader/plugins/kindlehome.koplugin/`,
  then restart KOReader. Use the Restart tile in quick settings, or ☰ → Exit → Restart KOReader.
- **Restarting from SSH works, but it's clumsy:** `setsid /mnt/us/koreader/koreader.sh --framework_stop &`
  after KOReader has exited. It can show a "startup script has been updated" dialog (tap Ignore).
  **Restarting KOReader kills your SSH session**, so never do it during a transfer.
- **Logs:** `/mnt/us/koreader/crash.log`. Before a test, note the line count
  (`wc -l < crash.log > /tmp/mark`). Afterwards, read only the new lines.
- **Screenshot over SSH:** KOReader's own screenshot gesture doesn't work on top of the home
  screen. Read `/dev/fb0` instead:
  - The visible area is 1236×1648, 8-bit grey, with a line stride of 1248.
  - The y offset is in `/sys/class/graphics/fb0/pan`.
- **Check syntax before deploying:** `luajit -bl file.lua >/dev/null`. A syntax error in a patch
  or in `main.lua` means KOReader won't start.
- **Test risky code on the device before installing it.** Run it with the Kindle's own
  `/mnt/us/koreader/luajit`:
  - Set `package.path` to `common/` and `frontend/`, and `package.cpath` to `libs/`.
  - Stub the modules that need the full UI (`util`, `device`, `ui/uimanager`).
  - It costs a minute and saves a boot loop.

## Tests

From the repo root, with LuaJIT:

```sh
luajit tools/chess-tests/perft_test.lua koreader/plugins/chess.koplugin    # move generation (perft)
luajit tools/chess-tests/engine_test.lua koreader/plugins/chess.koplugin   # search, SAN, game rules
luajit tools/chess-tests/widget_test.lua koreader/plugins/chess.koplugin   # board UI logic, stubbed
luajit tools/wrapped-tests/wrapped_test.lua koreader/plugins/kindlehome.koplugin dump.lua
```

`dump.lua` is a stats export from your own Kindle, returning `{ books = { [id] = { title = … } },
rows = { … } }`. The rows are `page_stat_data` rows from `statistics.sqlite3`. It isn't in the repo
because it's personal reading data.

The home screen has no automated tests. After any change, check it on the device:
- the home build time line in `crash.log`;
- every tab and the More menu;
- the quick settings panel, both on home and in a book;
- opening and closing a book.

## Updating KOReader

The setup was tested on **KOReader v2026.07.1**. `2-update-guard.lua` asks before KOReader
updates itself. To move to a new version:
1. Back up `/mnt/us/koreader`.
2. Update, then check `crash.log` and test the home screen and patches.
   - The parts most likely to break are internals that patches override: `ReaderMenu` gesture zones,
     `ReaderUI` hooks, `UIManager` refresh, and Project: Title's DB schema.
3. Bump `TESTED` in `2-update-guard.lua`.

## Style

- Comments explain *why*, briefly, in plain sentences. Match the surrounding code.
- Keep it Kindle-like: big tap targets, no clutter, and as few e-ink flashes as possible.
- Keep personal data out of this repo: no book lists, reading stats, IPs, keys or names.
