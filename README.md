# Kindle Paperwhite 5 → KOReader with a Kindle-style home

A jailbroken Kindle Paperwhite 5 (11th gen) that boots straight into KOReader and feels like a
stock Kindle, only better:

- **Home screen** (`kindlehome.koplugin`). It has "Jump back in", recent books, collections, a cover-grid
  library, a Kindle-style pull-down quick settings panel (Wi-Fi, dark mode, Calibre, brightness and warmth),
  reading stats, a daily goal with a streak, and **Reading Wrapped** for the year or month.
- **Chess** (`chess.koplugin`): a full-rules engine (perft-verified) with 4 levels, hints and undo.
- **Patches** for Kindle-like reading:
  - Every book uses the same look, in Bookerly.
  - Darker text and no flashing page turns.
  - Warmth follows the sun, and the light dims once at bedtime.
  - Manga reads right-to-left and opens the next volume automatically.
  - KOReader can't update itself without asking first.
- **System tweaks:**
  - Boots into KOReader with Amazon's framework stopped (about 130 MB more free RAM).
  - Fixes a broken timezone.
  - Sideloaded MOBI/PDF open in KOReader from the stock library.
- **Tools:**
  - A manga converter: e-ink greyscale, pages fitted to the screen, rotated spreads.
  - An optional daily backup pulled by a Raspberry Pi.

**Start here: [INSTALL.md](INSTALL.md)**. It takes you step by step from a stock Kindle (SpiderCat
jailbreak) to this setup. **Taking it over or changing it?** Read [AGENTS.md](AGENTS.md), for
people and coding agents alike.

| Here | On the Kindle |
|---|---|
| `koreader/plugins/kindlehome.koplugin`, `chess.koplugin` | `/mnt/us/koreader/plugins/` |
| `koreader/patches/2-*.lua` | `/mnt/us/koreader/patches/` (each file's header says what it does) |
| `koreader/settings/directory_defaults.lua` | `/mnt/us/koreader/settings/` (manga folder defaults) |
| `system/koreader-autostart.conf` | `/etc/upstart/` (rootfs, `mntroot rw` first) |
| `system/route-to-koreader.sh` | run once over SSH (MOBI/PDF → KOReader via KOmpanion) |
| `system/Retag for KOReader.sh` | `/mnt/us/documents/` |
| `backup/` | Kindle + Raspberry Pi (optional daily backup) |
| `tools/` | runs on your computer (manga conversion, tests) |

**Not included, install them from their authors:** KOReader, KOmpanion (via KPM), Project: Title,
and optionally Sudoku+ and 2048. INSTALL.md has the links and tested versions.

Tested on: PW5, firmware 5.18.6, KOReader v2026.07.1, Project: Title v3.8.3. Use at your own risk:
jailbreaking can brick a Kindle, and Amazon can patch jailbreaks in firmware updates.

## License and credits

Everything in this repo is original work, © 2026 markokovac16, licensed under the
**GNU AGPL-3.0** ([LICENSE](LICENSE)), the same license as KOReader, which these plugins run inside.

This setup builds on other people's projects. They are **not included here**: INSTALL.md links to
them, and each keeps its own license.

| Project | Author | License |
|---|---|---|
| [KOReader](https://github.com/koreader/koreader) | KOReader contributors | AGPL-3.0 |
| [Project: Title](https://github.com/joshuacant/ProjectTitle) | joshuacant | AGPL-3.0 |
| [Sudoku+](https://github.com/Borisvl/sudokuplus.koplugin) (optional) | Borisvl | AGPL-3.0 |
| [2048](https://codeberg.org/anserina/2048.koplugin) (optional) | anserina | MIT |
| SpiderCat jailbreak, KPM, KOmpanion ([kindlemodding.org](https://kindlemodding.org)) | sparklerfish, notmarek and the Kindle modding community | see their pages |

The plugins also use KOReader's built-in icons at runtime (none are copied here). **Bookerly** is
Amazon's font. It's already on every Kindle and isn't distributed here. *Kindle* and *Paperwhite* are
trademarks of Amazon. This project isn't affiliated with or endorsed by Amazon.
