-- Comics / manga (CBZ etc.): a full refresh every 2 pages while one is open, so dark areas
-- don't ghost into the next page. Books keep their no-flash page turns.
-- Right-to-left reading + dithering for /mnt/us/documents/Manga come from settings/directory_defaults.lua.
-- Finishing a comic marks it read and opens the next volume in its folder.
local ReaderStatus = require("apps/reader/modules/readerstatus")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local util = require("util")

local COMIC = { cbz = true, cbr = true, cb7 = true, cbt = true }
local COMIC_REFRESH = 2
local comic_open = false

local function isComic(file)
    return file and COMIC[util.getFileNameSuffix(file):lower()] or false
end

-- Natural order, so "Vol. 10" comes after "Vol. 9".
local function natKey(name)
    return name:lower():gsub("%d+", function(d) return string.format("%012d", tonumber(d)) end)
end

local function nextVolume(file)
    local dir, name = file:match("^(.*)/([^/]+)$")
    local list = {}
    for f in require("libs/libkoreader-lfs").dir(dir) do
        if f:sub(1, 1) ~= "." and isComic(f) then table.insert(list, f) end
    end
    table.sort(list, function(a, b) return natKey(a) < natKey(b) end)
    for i, f in ipairs(list) do
        if f == name then return list[i + 1] and dir .. "/" .. list[i + 1] end
    end
end

local orig_end = ReaderStatus.onEndOfBook
function ReaderStatus:onEndOfBook(...)
    local next_file = self.document and isComic(self.document.file) and nextVolume(self.document.file)
    if not next_file then return orig_end(self, ...) end -- books, and the last volume of a series
    self:markBook(true)
    local name = util.splitFileNameSuffix(next_file:match("[^/]+$")):gsub(" %- [^%-]+$", "")
    UIManager:show(require("ui/widget/infomessage"):new{ text = name, timeout = 2 })
    UIManager:nextTick(function()
        require("apps/filemanager/filemanagerutil").openFile(self.ui, next_file)
    end)
    return true
end

local orig_init = ReaderUI.init
function ReaderUI:init(...)
    orig_init(self, ...)
    comic_open = self.document ~= nil and isComic(self.document.file)
    if comic_open then
        UIManager.FULL_REFRESH_COUNT = COMIC_REFRESH
        UIManager.refresh_count = 0
    end
end

local orig_close = ReaderUI.onClose
function ReaderUI:onClose(...)
    if comic_open then
        comic_open = false
        UIManager:ToggleNightMode(G_reader_settings:isTrue("night_mode")) -- back to the book rate
    end
    return orig_close(self, ...)
end

-- Night mode switching (e.g. auto warmth at dusk) resets the rate; keep the comic one.
local orig_night = UIManager.ToggleNightMode
function UIManager:ToggleNightMode(...)
    orig_night(self, ...)
    if comic_open then self.FULL_REFRESH_COUNT = COMIC_REFRESH end
end
