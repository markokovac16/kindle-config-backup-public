-- Every book looks the same, like the Kindle's global Aa settings.
--
-- KOReader snapshots all display options (copt_*, font_face) into each book's sidecar on close,
-- so books opened under older defaults (or tweaked once) keep looking different forever.
-- Here a book's display options are moved into the global defaults whenever its sidecar is
-- saved: no book keeps its own look, and changing e.g. the font size in any book changes it
-- for all of them. Progress, highlights, language and hyphenation stay per book.
local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local function isLookKey(k)
    return type(k) == "string" and (k:sub(1, 5) == "copt_" or k == "font_face" or k == "font_family_fonts")
end

local function globalKey(k)
    if k == "font_face" then return "cre_font" end
    if k == "font_family_fonts" then return "cre_font_family_fonts" end
    return k
end

local orig_flush = DocSettings.flush
function DocSettings:flush(data, ...)
    data = data or self.data
    if data and data.doc_path then
        for k, v in pairs(data) do
            if isLookKey(k) then
                G_reader_settings:saveSetting(globalKey(k), v)
                data[k] = nil
            end
        end
    end
    return orig_flush(self, data, ...)
end

-- One-time cleanup: drop the snapshots already sitting in sidecars, and set the shared look.
if not G_reader_settings:isTrue("uniform_books_applied") then
    local cleaned = 0
    local function walk(dir)
        for f in lfs.dir(dir) do
            if f ~= "." and f ~= ".." and not f:find("^%._") then
                local path = dir .. "/" .. f
                if lfs.attributes(path, "mode") == "directory" then
                    walk(path)
                elseif dir:find("%.sdr$") and f:find("^metadata%..+%.lua$") then
                    local s = LuaSettings:open(path)
                    local changed = false
                    for k in pairs(s.data) do
                        if isLookKey(k) or k == "style_tweaks" or k == "style_tweaks_enabled" then
                            s.data[k] = nil
                            changed = true
                        end
                    end
                    if changed then
                        s:flush()
                        cleaned = cleaned + 1
                    end
                end
            end
        end
    end
    local ok, err = pcall(walk, "/mnt/us/documents")
    logger.info("uniform-books: cleaned", cleaned, "sidecars", ok and "" or err)

    -- Publisher-embedded fonts off, so every book uses the reading font.
    G_reader_settings:saveSetting("copt_embedded_fonts", 0)
    local tweaks = G_reader_settings:readSetting("style_tweaks") or {}
    tweaks["Black_text.css"] = nil -- superseded by the built-in tweak below
    tweaks["pure_black_and_white"] = true     -- black text, no grey/coloured text or backgrounds
    tweaks["text_align_most_justify"] = true  -- justified body text, as on Kindle
    tweaks["lineheight_all_inherit"] = true   -- KOReader's line spacing everywhere
    G_reader_settings:saveSetting("style_tweaks", tweaks)
    G_reader_settings:makeTrue("uniform_books_applied")
end

-- Bookerly, the Kindle's own reading font, for every book (applied once; change it in any book).
if not G_reader_settings:isTrue("bookerly_default_applied") then
    G_reader_settings:saveSetting("cre_font", "Bookerly")
    G_reader_settings:makeTrue("bookerly_default_applied")
end
