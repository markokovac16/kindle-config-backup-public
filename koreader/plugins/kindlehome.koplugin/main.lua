--[[--
Kindle-style home screen for KOReader.

Shows on top of the file manager whenever it opens (startup, closing a book):
a "Jump back in" card, recent books, collections, and a paged cover-grid library.
Covers come from Project: Title's cover cache (bookinfomanager) when available.

@module koplugin.KindleHome
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local Notification = require("ui/widget/notification")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local ReadCollection = require("readcollection")
local ReadHistory = require("readhistory")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local RenderImage = require("ui/renderimage")
local Screen = Device.screen

local WHITE = Blitbuffer.COLOR_WHITE
local BLACK = Blitbuffer.COLOR_BLACK
local GRAY = Blitbuffer.COLOR_DARK_GRAY
local LIGHT = Blitbuffer.COLOR_GRAY_E

-- Book formats shown in the library (KFX can't be opened by KOReader).
local BOOK_EXT = {
    epub = true, pdf = true, mobi = true, azw = true, azw3 = true, fb2 = true,
    djvu = true, cbz = true, cbr = true, docx = true, rtf = true,
}

-- Font sizes are logical sizes (Font:getFace scales them by DPI).
local function sans(size, bold)
    return Font:getFace(bold and "NotoSans-Bold.ttf" or "NotoSans-Regular.ttf", size)
end
local function serif(size)
    return Font:getFace("NotoSerif-Bold.ttf", size)
end
-- Convert a pixel height into a logical font size.
local function pxToSize(px)
    return math.max(7, math.floor(px * 100 / Screen:scaleBySize(100)))
end

---------------------------------------------------------------- data

local bim -- Project: Title's BookInfoManager, false if unavailable
local function getBIM()
    if bim == nil then
        local ok, mod = pcall(require, "bookinfomanager")
        bim = ok and mod or false
        if not ok then logger.warn("KindleHome: no cover cache:", mod) end
    end
    return bim or nil
end

local meta_cache = {}

-- Calibre names files "Title - Author.ext".
local function metaFromFilename(file)
    local _, name = util.splitFilePathName(file)
    name = util.splitFileNameSuffix(name)
    local title, author = name:match("^(.-) %- ([^%-]+)$")
    if not title then
        return name, nil
    end
    if author == "Unknown" then author = nil end
    return title, author
end

local function bookMeta(file)
    local m = meta_cache[file]
    if m then return m end
    local title, author = metaFromFilename(file)
    m = { file = file, title = title, author = author }
    local b = getBIM()
    local info = b and b:getBookInfo(file, false)
    if info then
        m.cached = true
        m.has_cover = info.has_cover and not info.ignore_cover
        if info.title and info.title ~= "" then m.title = info.title end
        if info.authors and info.authors ~= "" then
            local author = info.authors:match("^[^\n]+")
            if author ~= "Unknown" then m.author = author end
        end
    end
    meta_cache[file] = m
    return m
end

local function bookProgress(file)
    local info = BookList.getBookInfo(file)
    return info.percent_finished, info.status
end

-- Folder listings are kept while the folder's modification time stays the same (adding,
-- moving or deleting a file in it changes that), so going home only re-lists what changed.
-- Times are whole seconds, so a listing made within 2 s of a change isn't trusted.
local scan_cache = {}
local function scanBooks(dir, out)
    local mtime = lfs.attributes(dir, "modification")
    if not mtime then return out end
    local c = scan_cache[dir]
    if not c or c.mtime ~= mtime or c.listed - mtime < 2 then
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok then return out end
        c = { mtime = mtime, listed = os.time(), files = {}, dirs = {} }
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                local path = dir .. "/" .. name
                local mode = lfs.attributes(path, "mode")
                if mode == "directory" then
                    if not name:match("%.sdr$") and name ~= "dictionaries" then
                        table.insert(c.dirs, path)
                    end
                elseif mode == "file" then
                    local ext = util.getFileNameSuffix(name):lower()
                    if BOOK_EXT[ext] and not name:find("Dictionary") and not name:lower():match("^spidercat") then
                        table.insert(c.files, path)
                    end
                end
            end
        end
        scan_cache[dir] = c
    end
    for _, f in ipairs(c.files) do table.insert(out, f) end
    for _, d in ipairs(c.dirs) do scanBooks(d, out) end
    return out
end

local function lastReadText(t)
    if not t then return nil end
    local today = os.date("*t")
    today.hour, today.min, today.sec = 0, 0, 0
    local midnight = os.time(today)
    if t >= midnight then return _("today") end
    if t >= midnight - 86400 then return _("yesterday") end
    local days = math.floor((midnight - t) / 86400) + 1
    if days < 7 then return string.format(_("%d days ago"), days) end
    return os.date("%d %b", t)
end

-- Minutes a day that count towards the streak.
local function dailyGoal() return G_reader_settings:readSetting("kindlehome_daily_goal_min") or 30 end

-- Today's reading time, pages read since Monday and the streak of days that met the daily goal,
-- from the statistics plugin's DB.
local function readingStats()
    local ok, res = pcall(function()
        local path = require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
        if lfs.attributes(path, "mode") ~= "file" then return nil end
        local now = os.date("*t")
        now.hour, now.min, now.sec = 0, 0, 0
        local today = os.time(now)
        local monday = os.date("*t", today)
        monday.day = monday.day - (monday.wday + 5) % 7
        local week = os.time(monday)
        local conn = require("lua-ljsqlite3/init").open(path, "ro")
        local secs = tonumber(conn:rowexec(
            "SELECT coalesce(sum(duration), 0) FROM page_stat_data WHERE start_time >= " .. today))
        local pages = tonumber(conn:rowexec(
            "SELECT count(*) FROM (SELECT DISTINCT id_book, page FROM page_stat_data WHERE start_time >= " .. week .. ")"))
        -- A day counts once it meets the daily goal.
        local days = conn:exec("SELECT date(start_time, 'unixepoch', 'localtime') AS d FROM page_stat_data"
            .. " WHERE start_time >= " .. (today - 400 * 86400) .. " GROUP BY d HAVING sum(duration) >= "
            .. dailyGoal() * 60)
        conn:close()
        local read = {}
        for _, d in ipairs(days and days[1] or {}) do read[d] = true end
        -- The streak survives until the end of today even if today has no reading yet.
        local day = os.date("*t")
        day.hour = 12
        if not read[os.date("%Y-%m-%d", os.time(day))] then day.day = day.day - 1 end
        local streak = 0
        while read[os.date("%Y-%m-%d", os.time(day))] do
            streak = streak + 1
            day.day = day.day - 1
        end
        return { today = secs, week_pages = pages, streak = streak }
    end)
    if not ok then logger.warn("KindleHome: reading stats failed:", res) end
    return ok and res or nil
end

local function durationText(secs)
    local mins = math.floor(secs / 60)
    if mins < 60 then return string.format(_("%d min"), mins) end
    return string.format(_("%dh %02dm"), math.floor(mins / 60), mins % 60)
end

---------------------------------------------------------------- e-ink

-- Amazon's display library ("sensitivity" in libIGLdisplay) flashes any update that covers a big
-- part of the screen, and lets small ones accrue until they add up to a flash. Same here.
local accrued = 0

local function einkMode(region)
    local frac = region and (region.w * region.h) / (Screen:getWidth() * Screen:getHeight()) or 1
    if frac >= 0.35 then
        accrued = 0
        return "flashui"
    end
    accrued = accrued + frac
    if accrued >= 1.5 then
        accrued = 0
        return "flashui"
    end
    return "ui"
end

-- Paging through a grid: REAGL ("partial" on this device, what the stock reader turns pages with)
-- cleans up without a flash; every 5th page still flashes.
local function pageMode()
    accrued = accrued + 0.3
    if accrued >= 1.5 then
        accrued = 0
        return "flashui"
    end
    return "partial"
end

---------------------------------------------------------------- widgets

-- Tap/hold target; its dimen is filled in on first paint.
local Tappable = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
    drag_callback = nil, -- (x, done): finger x while dragging, done on lift
}

function Tappable:init()
    local range = function() return self.dimen end
    self.ges_events = {
        TapItem = { GestureRange:new{ ges = "tap", range = range } },
        HoldItem = { GestureRange:new{ ges = "hold", range = range } },
    }
    if self.drag_callback then
        self.ges_events.DragItem = { GestureRange:new{ ges = "pan", range = range } }
        self.ges_events.DragEnd = { GestureRange:new{ ges = "pan_release", range = range } }
        self.ges_events.DragSwipe = { GestureRange:new{ ges = "swipe", range = range } }
    end
end

function Tappable:onDragItem(_, ges)
    self.drag_callback(ges.pos.x, false)
    return true
end

function Tappable:onDragEnd(_, ges)
    self.drag_callback(ges.pos.x, true)
    return true
end

-- A quick flick arrives as a swipe from its start point; only sideways ones are drags.
function Tappable:onDragSwipe(_, ges)
    local dir = ges.direction
    if dir ~= "east" and dir ~= "west" then return end
    self.drag_callback(ges.pos.x + (dir == "east" and ges.distance or -ges.distance), true)
    return true
end

function Tappable:onTapItem(_, ges)
    if self.callback then
        self.callback(ges)
        return true
    end
end

function Tappable:onHoldItem()
    if self.hold_callback then
        self.hold_callback()
        return true
    end
end

local function placeholderCover(m, w, h)
    local b = Size.border.thin
    local inner_w = w - 2 * b
    local pad = math.floor(w * 0.1)
    local group = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = m.title,
            face = serif(pxToSize(w / 10)),
            width = inner_w - 2 * pad,
            height = math.floor(h * 0.55),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "center",
        },
    }
    if m.author then
        table.insert(group, VerticalSpan:new{ width = pad })
        table.insert(group, TextWidget:new{
            text = m.author,
            face = sans(pxToSize(w / 16)),
            max_width = inner_w - 2 * pad,
            fgcolor = GRAY,
        })
    end
    return FrameContainer:new{
        width = w, height = h,
        bordersize = b, padding = 0, margin = 0,
        background = LIGHT,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = h - 2 * b }, group },
    }
end

-- Cover scaled to fit w x h, bottom aligned like the Kindle grid.
-- `badge` (e.g. "42%") is drawn in the cover's bottom-right corner, like the Kindle library.
-- Covers scaled for a tile, kept between home screen builds so they aren't decompressed and
-- scaled again every time. Cleared when it grows past a few library pages, or when new covers
-- have been extracted. Never freed by hand: a widget still on screen may be using one, and the
-- garbage collector frees a blitbuffer once nothing references it.
local cover_cache, cover_count = {}, 0
local function clearCoverCache()
    cover_cache, cover_count = {}, 0
end

local function scaledCover(file, w, h)
    local key = file .. "|" .. w .. "x" .. h
    local bb = cover_cache[key]
    if bb then return bb end
    local b = getBIM()
    local info = b and b:getBookInfo(file, true)
    if not (info and info.cover_bb) then return nil end
    local cw, ch = info.cover_bb:getWidth(), info.cover_bb:getHeight()
    local scale = math.min(w / cw, h / ch)
    local border = Size.border.thin
    bb = RenderImage:scaleBlitBuffer(info.cover_bb,
        math.floor(cw * scale + 0.5) - 2 * border, math.floor(ch * scale + 0.5) - 2 * border, true)
    if cover_count >= 60 then clearCoverCache() end
    cover_cache[key] = bb
    cover_count = cover_count + 1
    return bb
end

local function coverWidget(m, w, h, badge)
    local bb = m.has_cover and scaledCover(m.file, w, h)
    local inner
    if bb then
        inner = FrameContainer:new{
            bordersize = Size.border.thin, padding = 0, margin = 0,
            ImageWidget:new{
                image = bb,
                image_disposable = false,
                width = bb:getWidth(),
                height = bb:getHeight(),
            },
        }
    else
        inner = placeholderCover(m, math.floor(h * 0.68 < w and h * 0.68 or w), h)
    end
    local cover = BottomContainer:new{ dimen = Geom:new{ w = w, h = h }, inner }
    if not badge then return cover end
    local label = TextWidget:new{ text = badge, face = sans(pxToSize(Screen:getHeight() * 0.0105), true) }
    local lh = label:getSize().h
    local tag = FrameContainer:new{
        bordersize = Size.border.thin, radius = math.floor(lh / 2), margin = 0,
        padding = 0, padding_left = math.floor(lh * 0.45), padding_right = math.floor(lh * 0.45),
        color = BLACK, background = WHITE,
        label,
    }
    local ts, iw = tag:getSize(), inner:getSize().w
    local inset = math.floor(lh * 0.3)
    tag.overlap_offset = { math.floor((w + iw) / 2) - ts.w - inset, h - ts.h - inset }
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, cover, tag }
end

local function progressBar(pct, w, h)
    return ProgressWidget:new{
        width = w, height = h,
        percentage = pct,
        margin_h = 0, margin_v = 0, radius = 0,
        bordersize = Size.border.thin,
        bordercolor = BLACK, bgcolor = WHITE, fillcolor = BLACK,
    }
end

---------------------------------------------------------------- home screen widget

local HomeScreen_row -- defined with HomeScreen below
local QuickSettings -- defined after HomeScreen

local HomeScreen = InputContainer:extend{
    covers_fullscreen = true,
    ui = nil,
    tab = "home",       -- "home" | "library"
    filter = "all",     -- "all" | "collections" | "reading" | "finished"
    sort = "recent",    -- "recent" | "title" | "author"
    collection = nil,   -- collection being browsed in the library
    page = 1,
}

local SORT_LABELS = { recent = _("Recent"), title = _("Title"), author = _("Author") }
local SORT_NEXT = { recent = "title", title = "author", author = "recent" }

function HomeScreen:init()
    local sort = G_reader_settings:readSetting("kindlehome_sort")
    if SORT_LABELS[sort] then self.sort = sort end -- the last sort chosen sticks
    self.width, self.height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.pad = math.floor(self.width * 0.045)
    self.cw = self.width - 2 * self.pad
    self.gap = math.floor(self.width * 0.025)
    self.status_h = math.floor(self.height * 0.04)
    self.hdr_h = math.floor(self.height * 0.045)
    self.nav_h = math.floor(self.height * 0.075)
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local t0 = time.now()
    self:loadData()
    self:render()
    logger.info("KindleHome: built in", time.to_ms(time.now() - t0), "ms")
    UIManager:nextTick(function() self:extractMissing() end)
    self:scheduleClock()
end

function HomeScreen:onResume()
    -- Time moved on while asleep.
    self:updateStatus()
    self:scheduleClock()
    if self.stats_day ~= os.date("%Y-%m-%d") and UIManager:isWidgetShown(self) then
        self:loadStats()
        if self.tab == "home" then self:refresh() end
    end
end

function HomeScreen:loadStats()
    self.stats = readingStats()
    self.stats_day = os.date("%Y-%m-%d")
end

-- Each series folder under Manga/ gets its own collection, linked to that folder so new volumes
-- join it. Done once per folder: a series collection deleted by hand stays deleted.
-- (The manga reading settings come from the folder itself, see settings/directory_defaults.lua.)
local MANGA_DIR = "/mnt/us/documents/Manga"
local function syncSeriesCollections()
    if lfs.attributes(MANGA_DIR, "mode") ~= "directory" then return false end
    local made = G_reader_settings:readSetting("kindlehome_series_collections") or {}
    local changed = false
    for f in lfs.dir(MANGA_DIR) do
        local path = MANGA_DIR .. "/" .. f
        if f:sub(1, 1) ~= "." and not f:find("%.sdr$") and not made[path]
                and lfs.attributes(path, "mode") == "directory" then
            if not ReadCollection.coll[f] then ReadCollection:addCollection(f) end
            local cs = ReadCollection.coll_settings[f]
            cs.folders = cs.folders or {}
            cs.folders[path] = { subfolders = true, scan_on_show = true }
            ReadCollection:updateCollectionFromFolder(f)
            made[path] = true
            changed = true
        end
    end
    if changed then G_reader_settings:saveSetting("kindlehome_series_collections", made) end
    return changed
end

function HomeScreen:loadData()
    -- Titles and authors only change when Project: Title extracts a book; keep the known ones.
    for f, m in pairs(meta_cache) do
        if not m.cached then meta_cache[f] = nil end
    end
    self:loadStats()
    local home_dir = G_reader_settings:readSetting("home_dir")
        or (Device:isKindle() and "/mnt/us/documents") or lfs.currentdir()
    self.books = scanBooks(home_dir, {})
    self.mtime = {}
    for _, f in ipairs(self.books) do
        self.mtime[f] = lfs.attributes(f, "modification") or 0
    end
    self.last_read = {}
    self.recent = {}
    for _, item in ipairs(ReadHistory.hist) do
        if not self.last_read[item.file] and lfs.attributes(item.file, "mode") == "file" then
            self.last_read[item.file] = item.time
            table.insert(self.recent, item.file)
        end
    end
    ReadCollection:_read()
    if syncSeriesCollections() then ReadCollection:write() end
    -- Folder-linked collections (e.g. manga series) only rescan when collection.lua changes; pick up
    -- books that arrived since (Calibre, USB) every time the home screen builds.
    local updated = {}
    for name in pairs(ReadCollection.coll) do
        if ReadCollection:updateCollectionFromFolder(name) > 0 then updated[name] = true end
    end
    if next(updated) then ReadCollection:write(updated) end
    self.collections = {}
    for name, coll in pairs(ReadCollection.coll) do
        local files = {}
        for file in pairs(coll) do
            if lfs.attributes(file, "mode") == "file" then table.insert(files, file) end
        end
        -- KOReader's built-in empty "favorites" stays hidden; user collections show even when empty.
        if #files > 0 or name ~= ReadCollection.default_collection_name then
            self:sortFiles(files, "recent")
            table.insert(self.collections, {
                name = name,
                display = name == ReadCollection.default_collection_name and _("Favorites") or name,
                files = files,
                last = files[1] and self.last_read[files[1]] or 0,
            })
        end
    end
    table.sort(self.collections, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.display:lower() < b.display:lower()
    end)
end

function HomeScreen:sortFiles(files, mode)
    local lr, mt = self.last_read, self.mtime or {}
    local function key(f) return bookMeta(f).title:lower() end
    if mode == "title" then
        table.sort(files, function(a, b) return key(a) < key(b) end)
    elseif mode == "author" then
        table.sort(files, function(a, b)
            local aa, ab = (bookMeta(a).author or "~"):lower(), (bookMeta(b).author or "~"):lower()
            if aa ~= ab then return aa < ab end
            return key(a) < key(b)
        end)
    else
        table.sort(files, function(a, b)
            local ta, tb = lr[a] or 0, lr[b] or 0
            if ta ~= tb then return ta > tb end
            local ma, mb = mt[a] or 0, mt[b] or 0
            if ma ~= mb then return ma > mb end
            return key(a) < key(b)
        end)
    end
    return files
end

-- Fill the cover cache for books Project: Title hasn't seen yet, then redraw.
function HomeScreen:extractMissing()
    local b = getBIM()
    if not b or b:isExtractingInBackground() then return end
    local missing = {}
    for _, f in ipairs(self.books) do
        if not bookMeta(f).cached then
            table.insert(missing, { filepath = f, cover_specs = { max_cover_w = 600, max_cover_h = 600 } })
        end
    end
    if #missing == 0 or not b:extractInBackground(missing) then return end
    local function poll()
        if not UIManager:isWidgetShown(self) then return end
        if b:isExtractingInBackground() then
            UIManager:scheduleIn(3, poll)
        else
            meta_cache = {}
            clearCoverCache()
            self:refresh(pageMode())
        end
    end
    UIManager:scheduleIn(3, poll)
end

function HomeScreen:render()
    if self[1] then self[1]:free() end
    local content = self.tab == "home" and self:buildHome() or self:buildLibrary()
    local size = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height,
        bordersize = 0, padding = 0, margin = 0,
        background = WHITE,
        OverlapGroup:new{
            dimen = size,
            FrameContainer:new{
                bordersize = 0, margin = 0, padding = 0,
                padding_left = self.pad, padding_right = self.pad,
                content,
            },
            BottomContainer:new{ dimen = size, self:navBar() },
        },
    }
end

function HomeScreen:refresh(mode)
    self:render()
    UIManager:setDirty(self, function() return mode or einkMode(self.dimen), self.dimen end)
end

-- Run an action after the current gesture is done (we rebuild the tree we're dispatching into).
function HomeScreen:later(fn)
    return function() UIManager:nextTick(fn) end
end

-- The Wi-Fi icon only shows while Wi-Fi is on; redraw the status bar when that changes.
function HomeScreen:onNetworkConnected()
    if not UIManager:isWidgetShown(self) then return end
    UIManager:nextTick(function()
        if not UIManager:isWidgetShown(self) then return end
        self:render()
        local region = Geom:new{ x = 0, y = 0, w = self.width, h = self.status_h }
        UIManager:setDirty(self, function() return einkMode(region), region end)
    end)
end
HomeScreen.onNetworkDisconnected = HomeScreen.onNetworkConnected

function HomeScreen:onShowingReader()
    UIManager:close(self)
end

function HomeScreen:onClose()
    UIManager:close(self)
    return true
end

function HomeScreen:onCloseWidget()
    UIManager:unschedule(self.clock_tick)
    if self[1] then self[1]:free() end
end

function HomeScreen:onSwipe(_, ges)
    if ges.direction == "south" and ges.pos.y < self.status_h * 4 then
        self:showQuickSettings()
        return true
    end
    if self.tab ~= "library" then return end
    if ges.direction == "west" then
        self:setPage(self.page + 1)
    elseif ges.direction == "east" then
        self:setPage(self.page - 1)
    end
    return true
end

function HomeScreen:setPage(page)
    page = math.max(1, math.min(page, self.pages or 1))
    if page == self.page then return end
    self.page = page
    self:refresh(pageMode())
end

function HomeScreen:showTab(tab, filter)
    self.tab = tab
    self.filter = filter or (tab == "library" and "collections" or "all") -- Library opens on Collections
    self.collection = nil
    self.page = 1
    self:refresh("flashui")
end

function HomeScreen:openBook(file)
    UIManager:close(self)
    self.ui:openFile(file)
end

function HomeScreen:showBookMenu(file)
    local m = bookMeta(file)
    local dialog
    local close = function() UIManager:close(dialog) end
    local buttons = {
        {{ text = _("Open"), callback = function()
            close()
            self:openBook(file)
        end }},
        {{ text = _("Book details"), callback = function()
            close()
            self.ui.bookinfo:show(file)
        end }},
        {self.ui.collections:genAddToCollectionButton(file, close, function()
            ReadCollection:write() -- save now rather than when the file manager closes
            self:reload()
        end)},
    }
    if self.collection then
        local coll = self.collection
        table.insert(buttons, {{ text = string.format(_("Remove from %s"), coll.display), callback = function()
            close()
            ReadCollection:removeItem(file, coll.name)
            self:reload()
        end }})
    end
    table.insert(buttons, {{ text = _("Show in file browser"), callback = function()
        close()
        UIManager:close(self)
        self.ui.file_chooser:changeToPath(util.splitFilePathName(file), file)
    end }})
    dialog = ButtonDialog:new{
        title = m.author and (m.title .. "\n" .. m.author) or m.title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Re-read books and collections after an edit, keeping the current view.
function HomeScreen:reload()
    local coll_name = self.collection and self.collection.name
    self:loadData()
    self.collection = nil
    for _, c in ipairs(self.collections) do
        if c.name == coll_name then self.collection = c end
    end
    self:refresh()
end

function HomeScreen:showCollectionMenu(coll)
    local manager = self.ui.collections
    local dialog
    dialog = ButtonDialog:new{
        title = coll.display,
        title_align = "center",
        buttons = {
            {{ text = _("Rename"), callback = function()
                UIManager:close(dialog)
                manager:editCollectionName(function(new_name)
                    ReadCollection:renameCollection(coll.name, new_name)
                    ReadCollection:write()
                    self:reload()
                end, coll.name)
            end }},
            {{ text = _("Delete collection"), callback = function()
                UIManager:close(dialog)
                UIManager:show(require("ui/widget/confirmbox"):new{
                    text = string.format(_("Delete the collection \"%s\"?\nThe books stay on your Kindle."), coll.display),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        ReadCollection:removeCollection(coll.name)
                        ReadCollection:write()
                        if self.collection and self.collection.name == coll.name then self.collection = nil end
                        self:reload()
                    end,
                })
            end }},
        },
    }
    UIManager:show(dialog)
end

function HomeScreen:newCollection()
    self.ui.collections:editCollectionName(function(name)
        ReadCollection:addCollection(name)
        ReadCollection:write()
        self:reload()
    end)
end

function HomeScreen:showMoreMenu()
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{ text = _("File browser"), callback = function()
                UIManager:close(dialog)
                UIManager:close(self)
            end }},
            {{ text = _("Reading stats"), callback = function()
                UIManager:close(dialog)
                if self.ui.statistics then self.ui.statistics:onShowCalendarView() end
            end },
             { text = _("Reading Wrapped"), callback = function()
                UIManager:close(dialog)
                -- Make sure the statistics plugin has written its latest pages.
                if self.ui.statistics and self.ui.statistics.insertDB then pcall(self.ui.statistics.insertDB, self.ui.statistics) end
                require("kindlehome_wrapped").show({
                    files = function() return self.books or {} end,
                    meta = bookMeta,
                    cover = coverWidget,
                })
            end }},
            {{ text = _("Sudoku"), callback = function()
                UIManager:close(dialog)
                if self.ui.sudokuplus then self.ui.sudokuplus:onOpenSudokuPlus() end
            end },
             { text = _("2048"), callback = function()
                UIManager:close(dialog)
                if self.ui["2048"] then self.ui["2048"]:startGame() end
            end },
             { text = _("Chess"), callback = function()
                UIManager:close(dialog)
                if self.ui.chess then self.ui.chess:startGame() end
            end }},
            {{ text = _("KOReader menu"), callback = function()
                UIManager:close(dialog)
                self.ui.menu:onShowMenu()
            end }},
            {{ text = _("Exit to Kindle"), callback = function()
                UIManager:close(dialog)
                UIManager:close(self)
                self.ui.menu:exitOrRestart()
            end }},
        },
    }
    UIManager:show(dialog)
end

---------------------------------------------------------------- pieces

function HomeScreen:statusBar()
    local h = self.status_h
    local face = sans(pxToSize(h * 0.42))
    local right = HorizontalGroup:new{ align = "center" }
    local ok, wifi_on = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    if ok and wifi_on then
        table.insert(right, IconWidget:new{ icon = "wifi.open.100", width = math.floor(h * 0.5), height = math.floor(h * 0.5) })
        table.insert(right, HorizontalSpan:new{ width = math.floor(h * 0.25) })
    end
    self.batt_widget = nil
    if Device:hasBattery() then
        self.batt_widget = TextWidget:new{ text = Device:getPowerDevice():getCapacity() .. "%", face = face }
        table.insert(right, self.batt_widget)
    end
    self.time_widget = TextWidget:new{ text = os.date("%H:%M"), face = sans(pxToSize(h * 0.42), true) }
    local dimen = Geom:new{ w = self.cw, h = h }
    return Tappable:new{
        callback = self:later(function() self:showQuickSettings() end),
        OverlapGroup:new{
            dimen = dimen,
            CenterContainer:new{ dimen = dimen, self.time_widget },
            RightContainer:new{ dimen = dimen, right },
        },
    }
end

function HomeScreen:showQuickSettings()
    UIManager:show(QuickSettings:new{ home = self }, "ui")
end

-- Clock and battery tick once a minute while the home screen is up.
function HomeScreen:updateStatus()
    if not UIManager:isWidgetShown(self) then return end
    if self.time_widget then self.time_widget:setText(os.date("%H:%M")) end
    if self.batt_widget then self.batt_widget:setText(Device:getPowerDevice():getCapacity() .. "%") end
    UIManager:setDirty(self, function()
        local region = Geom:new{ x = 0, y = 0, w = self.width, h = self.status_h }
        return einkMode(region), region
    end)
end

function HomeScreen:scheduleClock()
    UIManager:unschedule(self.clock_tick)
    self.clock_tick = self.clock_tick or function()
        self:updateStatus()
        self:scheduleClock()
    end
    UIManager:scheduleIn(61 - os.date("*t").sec, self.clock_tick)
end

function HomeScreen:searchBar()
    local h = math.floor(self.height * 0.05)
    local b = Size.border.thin
    local icon = math.floor(h * 0.5)
    return Tappable:new{
        callback = self:later(function() self.ui.filesearcher:onShowFileSearch() end),
        FrameContainer:new{
            width = self.cw, height = h,
            bordersize = b, radius = math.floor(h / 2), padding = 0, margin = 0,
            color = GRAY, background = WHITE,
            LeftContainer:new{
                dimen = Geom:new{ w = self.cw - 2 * b, h = h - 2 * b },
                HorizontalGroup:new{
                    align = "center",
                    HorizontalSpan:new{ width = math.floor(h * 0.4) },
                    IconWidget:new{ icon = "appbar.search", width = icon, height = icon },
                    HorizontalSpan:new{ width = math.floor(h * 0.25) },
                    TextWidget:new{ text = _("Search Kindle"), face = sans(pxToSize(h * 0.36)), fgcolor = GRAY },
                },
            },
        },
    }
end

function HomeScreen:sectionHeader(text, action_text, action)
    local dimen = Geom:new{ w = self.cw, h = self.hdr_h }
    local og = OverlapGroup:new{
        dimen = dimen,
        LeftContainer:new{ dimen = dimen, TextWidget:new{ text = text, face = sans(pxToSize(self.hdr_h * 0.42), true) } },
    }
    if action_text then
        table.insert(og, RightContainer:new{
            dimen = dimen,
            Tappable:new{
                callback = self:later(action),
                FrameContainer:new{
                    bordersize = 0, margin = 0,
                    padding = math.floor(self.hdr_h * 0.2),
                    padding_right = 0,
                    TextWidget:new{ text = action_text, face = sans(pxToSize(self.hdr_h * 0.32)) },
                },
            },
        })
    end
    return og
end

-- One book: cover plus a reading-progress footer.
-- Two lines of title under a library cover; its fixed height keeps the rows aligned.
function HomeScreen:tileTitle(text, w)
    return TextBoxWidget:new{
        text = text or "",
        face = sans(pxToSize(self.height * 0.0125)),
        width = w,
        height = self:tileTitleHeight(),
        height_overflow_show_ellipsis = true,
    }
end

function HomeScreen:tileTitleHeight()
    if not self.tile_title_h then
        local probe = TextBoxWidget:new{ text = "Ag\nAg", face = sans(pxToSize(self.height * 0.0125)), width = 100 }
        self.tile_title_h = probe:getSize().h
        probe:free()
    end
    return self.tile_title_h
end

function HomeScreen:bookTile(file, w, h, titled)
    local foot_h = math.floor(w * 0.08)
    local pct, status = bookProgress(file)
    local footer
    if status == "complete" then
        footer = TextWidget:new{ text = _("Finished"), face = sans(pxToSize(foot_h * 0.75)), fgcolor = GRAY }
    elseif pct and pct > 0 then
        footer = progressBar(pct, w, math.max(4, math.floor(foot_h * 0.35)))
    else
        footer = VerticalSpan:new{ width = 0 }
    end
    return Tappable:new{
        callback = self:later(function() self:openBook(file) end),
        hold_callback = self:later(function() self:showBookMenu(file) end),
        VerticalGroup:new{
            align = "left",
            coverWidget(bookMeta(file), w, h, titled and (status == "complete" and _("Read")
                or pct and pct > 0 and string.format("%d%%", math.floor(pct * 100 + 0.5)) or nil)),
            VerticalSpan:new{ width = math.floor(foot_h * 0.4) },
            -- Library tiles show the title instead of progress.
            titled and self:tileTitle(bookMeta(file).title, w)
                or LeftContainer:new{ dimen = Geom:new{ w = w, h = foot_h }, footer },
        },
    }
end

-- Collection: a small stack of its covers, then its name and size.
function HomeScreen:collectionTile(coll, w, h)
    local off = math.floor(w * 0.06)
    local fh = h - 2 * off
    local fw = math.min(math.floor(fh * 0.7), w - 2 * off)
    local stack = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h } }
    local n = math.min(3, #coll.files)
    for i = n, 1, -1 do
        local cover = coverWidget(bookMeta(coll.files[i]), fw, fh)
        cover.overlap_offset = { (i - 1) * off, (n - i) * off }
        table.insert(stack, cover)
    end
    if n == 0 then
        local empty = FrameContainer:new{
            width = fw, height = fh, bordersize = Size.border.thin, padding = 0, margin = 0,
            color = Blitbuffer.COLOR_LIGHT_GRAY, background = WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = fw, h = fh },
                TextWidget:new{ text = _("Empty"), face = sans(pxToSize(w * 0.05)), fgcolor = GRAY },
            },
        }
        empty.overlap_offset = { 0, 2 * off }
        table.insert(stack, empty)
    end
    local name_h = math.floor(w * 0.11)
    return Tappable:new{
        callback = self:later(function()
            self.tab, self.filter, self.collection, self.page = "library", "collections", coll, 1
            self:refresh("flashui")
        end),
        hold_callback = self:later(function() self:showCollectionMenu(coll) end),
        VerticalGroup:new{
            align = "left",
            stack,
            VerticalSpan:new{ width = math.floor(off * 0.6) },
            TextWidget:new{ text = coll.display, face = sans(pxToSize(name_h * 0.5), true), max_width = w },
            TextWidget:new{
                text = #coll.files == 1 and _("1 book") or string.format(_("%d books"), #coll.files),
                face = sans(pxToSize(name_h * 0.4)), fgcolor = GRAY,
            },
        },
    }
end

-- How many rows of tiles like `probe` fit in `avail` pixels.
function HomeScreen:fitRows(avail, vgap, probe)
    if not probe then return 1 end
    local tile_h = probe:getSize().h
    probe:free()
    return math.max(1, math.floor((avail + vgap) / (tile_h + vgap)))
end

function HomeScreen:heroCard(file)
    local m = bookMeta(file)
    local h = math.floor(self.height * 0.22)
    local w = math.floor(h * 0.7)
    local text_w = self.cw - w - self.gap * 2
    local pct, status = bookProgress(file)
    local col = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = m.title,
            face = sans(pxToSize(self.height * 0.019), true),
            width = text_w,
            height = math.floor(self.height * 0.075),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
    if m.author then
        table.insert(col, VerticalSpan:new{ width = math.floor(self.gap * 0.4) })
        table.insert(col, TextWidget:new{ text = m.author, face = sans(pxToSize(self.height * 0.015)), fgcolor = GRAY, max_width = text_w })
    end
    table.insert(col, VerticalSpan:new{ width = self.gap * 2 })
    local info
    if status == "complete" then
        info = _("Finished")
    elseif pct then
        info = string.format(_("%d%% read"), math.floor(pct * 100 + 0.5))
    else
        info = _("Not started")
    end
    local when = lastReadText(self.last_read[file])
    if when then info = info .. "  ·  " .. string.format(_("Last read %s"), when) end
    table.insert(col, TextWidget:new{ text = info, face = sans(pxToSize(self.height * 0.0145)), max_width = text_w })
    table.insert(col, VerticalSpan:new{ width = math.floor(self.gap * 0.6) })
    table.insert(col, progressBar(status == "complete" and 1 or pct or 0, text_w, math.floor(self.height * 0.008)))
    -- Stats sit at the bottom of the card so it stays as tall as the cover.
    if self.stats then
        local stats = self:statsRow(text_w)
        local room = h - col:getSize().h - stats:getSize().h
        col:resetLayout() -- getSize() cached offsets for the children so far
        if room >= self.gap then
            table.insert(col, VerticalSpan:new{ width = room })
            table.insert(col, stats)
        else
            stats:free()
        end
    end
    return Tappable:new{
        callback = self:later(function() self:openBook(file) end),
        hold_callback = self:later(function() self:showBookMenu(file) end),
        HorizontalGroup:new{
            align = "top",
            coverWidget(m, w, h),
            HorizontalSpan:new{ width = self.gap * 2 },
            col,
        },
    }
end

-- Today / streak / this week. Part of the hero card, so a tap opens the book; the calendar is under More.
function HomeScreen:statsRow(w)
    local st = self.stats
    local cell_w = math.floor(w / 3)
    local cell = function(value, label)
        return LeftContainer:new{
            dimen = Geom:new{ w = cell_w, h = math.floor(self.height * 0.045) },
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = value, face = sans(pxToSize(self.height * 0.018), true), max_width = cell_w - self.gap },
                TextWidget:new{ text = label, face = sans(pxToSize(self.height * 0.012)), fgcolor = GRAY, max_width = cell_w - self.gap },
            },
        }
    end
    return HorizontalGroup:new{
        align = "top",
        cell(st.today >= dailyGoal() * 60 and "✓ " .. durationText(st.today)
            or string.format(_("%d / %d min"), math.floor(st.today / 60), dailyGoal()), _("Daily goal")),
        cell(st.streak == 1 and _("1 day") or string.format(_("%d days"), st.streak), _("Streak")),
        cell(tostring(st.week_pages), _("Pages this week")),
    }
end

function HomeScreen_row(widgets, gap)
    local hg = HorizontalGroup:new{ align = "top" }
    for i, wdg in ipairs(widgets) do
        if i > 1 then table.insert(hg, HorizontalSpan:new{ width = gap }) end
        table.insert(hg, wdg)
    end
    return hg
end

function HomeScreen:row(widgets, gap)
    return HomeScreen_row(widgets, gap)
end

function HomeScreen:navBar()
    local h = self.nav_h
    local item_w = math.floor(self.width / 3)
    local icon = math.floor(h * 0.38)
    local items = {
        { id = "home", label = _("Home"), icon = "home", action = function() self:showTab("home") end },
        { id = "library", label = _("Library"), icon = "book.opened", action = function() self:showTab("library") end },
        { id = "more", label = _("More"), icon = "appbar.menu", action = function() self:showMoreMenu() end },
    }
    local hg = HorizontalGroup:new{ align = "top" }
    for _, it in ipairs(items) do
        local active = it.id == self.tab
        local bar_h = math.max(3, math.floor(h * 0.05))
        table.insert(hg, Tappable:new{
            callback = self:later(it.action),
            VerticalGroup:new{
                align = "center",
                LineWidget:new{
                    dimen = Geom:new{ w = math.floor(item_w * 0.5), h = bar_h },
                    background = active and BLACK or WHITE,
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = item_w, h = h - bar_h },
                    VerticalGroup:new{
                        align = "center",
                        IconWidget:new{ icon = it.icon, width = icon, height = icon },
                        VerticalSpan:new{ width = math.floor(h * 0.05) },
                        TextWidget:new{ text = it.label, face = sans(pxToSize(h * 0.2), active) },
                    },
                },
            },
        })
    end
    return VerticalGroup:new{
        align = "center",
        LineWidget:new{ dimen = Geom:new{ w = self.width, h = Size.line.medium }, background = Blitbuffer.COLOR_LIGHT_GRAY },
        FrameContainer:new{ width = self.width, height = h, bordersize = 0, padding = 0, margin = 0, background = WHITE, hg },
    }
end

---------------------------------------------------------------- home tab

function HomeScreen:buildHome()
    local vg = VerticalGroup:new{
        align = "left",
        self:statusBar(),
        self:searchBar(),
        VerticalSpan:new{ width = self.gap },
    }
    local hero = self.recent[1]
    if hero then
        table.insert(vg, self:sectionHeader(_("Jump back in")))
        table.insert(vg, self:heroCard(hero))
        table.insert(vg, VerticalSpan:new{ width = self.gap })
    end

    -- Recent books after the hero, then the most recently added ones.
    local cols = 5
    local seen, list = { [hero or ""] = true }, {}
    for _, f in ipairs(self:sortFiles(util.tableDeepCopy(self.books), "recent")) do
        if not seen[f] then
            seen[f] = true
            table.insert(list, f)
            if #list == cols then break end
        end
    end
    if #list > 0 then
        local w = math.floor((self.cw - (cols - 1) * self.gap) / cols)
        local tiles = {}
        for _, f in ipairs(list) do table.insert(tiles, self:bookTile(f, w, math.floor(w * 1.45))) end
        table.insert(vg, self:sectionHeader(_("Your library"), _("See all ›"), function() self:showTab("library", "all") end))
        table.insert(vg, self:row(tiles, self.gap))
        table.insert(vg, VerticalSpan:new{ width = self.gap })
    end

    local filled = {}
    for _, c in ipairs(self.collections) do
        if #c.files > 0 then table.insert(filled, c) end
    end
    if #filled > 0 then
        local ccols = 3
        local w = math.floor((self.cw - (ccols - 1) * self.gap * 2) / ccols)
        local header = self:sectionHeader(_("Collections"), _("See all ›"), function() self:showTab("library", "collections") end)
        -- Shrink the stacks to whatever is left above the nav bar; drop the section if that's too little.
        local avail = self.height - self.nav_h - self.gap - vg:getSize().h - header:getSize().h
        vg:resetLayout()
        local make = function(stack_h)
            local tiles = {}
            for i = 1, math.min(ccols, #filled) do
                table.insert(tiles, self:collectionTile(filled[i], w, stack_h))
            end
            return self:row(tiles, self.gap * 2)
        end
        local stack_h = math.floor(self.height * 0.13)
        local row = make(stack_h)
        local over = row:getSize().h - avail
        if over > 0 then
            row:free()
            stack_h = stack_h - over
            row = stack_h >= math.floor(self.height * 0.07) and make(stack_h) or nil
        end
        if row then
            table.insert(vg, header)
            table.insert(vg, row)
        else
            header:free()
        end
    end
    return vg
end

---------------------------------------------------------------- library tab

function HomeScreen:chips()
    local h = math.floor(self.height * 0.038)
    local face = sans(pxToSize(h * 0.42))
    local hg = HorizontalGroup:new{ align = "center" }
    local chips = {
        { "all", _("All") }, { "collections", _("Collections") },
        { "reading", _("Reading") }, { "finished", _("Finished") },
    }
    for i, c in ipairs(chips) do
        local active = self.filter == c[1]
        if i > 1 then table.insert(hg, HorizontalSpan:new{ width = math.floor(self.gap * 0.6) }) end
        table.insert(hg, Tappable:new{
            callback = self:later(function()
                self.filter, self.collection, self.page = c[1], nil, 1
                self:refresh("flashui")
            end),
            FrameContainer:new{
                bordersize = Size.border.thin, radius = math.floor(h / 2),
                margin = 0, padding = 0,
                padding_left = math.floor(h * 0.5), padding_right = math.floor(h * 0.5),
                color = BLACK, background = active and BLACK or WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = TextWidget:new{ text = c[2], face = face }:getSize().w, h = h - 2 * Size.border.thin },
                    TextWidget:new{ text = c[2], face = face, fgcolor = active and WHITE or BLACK },
                },
            },
        })
    end
    local dimen = Geom:new{ w = self.cw, h = h }
    local og = OverlapGroup:new{ dimen = dimen, LeftContainer:new{ dimen = dimen, hg } }
    if self.filter == "collections" and not self.collection then
        table.insert(og, RightContainer:new{
            dimen = dimen,
            Tappable:new{
                callback = self:later(function() self:newCollection() end),
                TextWidget:new{ text = _("+ New collection"), face = face },
            },
        })
    else
        table.insert(og, RightContainer:new{
            dimen = dimen,
            Tappable:new{
                callback = self:later(function()
                    self.sort, self.page = SORT_NEXT[self.sort], 1
                    G_reader_settings:saveSetting("kindlehome_sort", self.sort)
                    self:refresh(pageMode())
                end),
                TextWidget:new{ text = string.format(_("Sort: %s"), SORT_LABELS[self.sort]), face = face },
            },
        })
    end
    return og
end

function HomeScreen:pager(h)
    local dimen = Geom:new{ w = self.cw, h = h }
    if (self.pages or 1) <= 1 then return VerticalSpan:new{ width = h } end
    local face = sans(pxToSize(h * 0.4))
    local arrow = function(text, delta, enabled)
        return Tappable:new{
            callback = self:later(function() self:setPage(self.page + delta) end),
            FrameContainer:new{
                bordersize = 0, margin = 0, padding = math.floor(h * 0.2),
                padding_left = self.gap * 2, padding_right = self.gap * 2,
                TextWidget:new{ text = text, face = sans(pxToSize(h * 0.5), true), fgcolor = enabled and BLACK or Blitbuffer.COLOR_LIGHT_GRAY },
            },
        }
    end
    return CenterContainer:new{
        dimen = dimen,
        HorizontalGroup:new{
            align = "center",
            arrow("‹", -1, self.page > 1),
            TextWidget:new{ text = string.format(_("%d of %d"), self.page, self.pages), face = face },
            arrow("›", 1, self.page < self.pages),
        },
    }
end

function HomeScreen:buildLibrary()
    local title = _("Library")
    if self.collection then title = "‹ " .. self.collection.display end
    local title_h = math.floor(self.height * 0.06)
    local title_widget = TextWidget:new{ text = title, face = sans(pxToSize(title_h * 0.5), true), max_width = self.cw }
    if self.collection then
        title_widget = Tappable:new{
            callback = self:later(function()
                self.collection, self.page = nil, 1
                self:refresh("flashui")
            end),
            title_widget,
        }
    end
    local vg = VerticalGroup:new{
        align = "left",
        self:statusBar(),
        LeftContainer:new{ dimen = Geom:new{ w = self.cw, h = title_h }, title_widget },
        self:chips(),
        VerticalSpan:new{ width = self.gap },
    }
    local pager_h = math.floor(self.height * 0.04)
    local avail = self.height - vg:getSize().h - self.nav_h - pager_h
    vg:resetLayout()

    if self.filter == "collections" and not self.collection then
        local cols = 3
        local w = math.floor((self.cw - (cols - 1) * self.gap * 2) / cols)
        local stack_h = math.floor(self.height * 0.115)
        local make = function(c) return self:collectionTile(c, w, stack_h) end
        local rows = self:fitRows(avail, self.gap, self.collections[1] and make(self.collections[1]))
        self:addGrid(vg, self.collections, cols, rows, make, self.gap * 2, self.gap)
    else
        local files
        if self.collection then
            files = util.tableDeepCopy(self.collection.files)
        else
            files = {}
            for _, f in ipairs(self.books) do
                local pct, status = bookProgress(f)
                if self.filter == "all"
                    or (self.filter == "reading" and status ~= "complete" and pct and pct > 0)
                    or (self.filter == "finished" and status == "complete") then
                    table.insert(files, f)
                end
            end
        end
        self:sortFiles(files, self.sort)
        local cols = 4
        local w = math.floor((self.cw - (cols - 1) * self.gap) / cols)
        local foot = math.floor(math.floor(w * 0.08) * 0.4) + self:tileTitleHeight()
        local h = math.min(math.floor(w * 1.45), math.floor((avail - 2 * self.gap) / 3) - foot)
        local make = function(f) return self:bookTile(f, w, h, true) end
        -- Shrink the covers by whatever a real tile overshoots a third of the space (title metrics vary).
        if files[1] then
            local probe = make(files[1])
            local over = probe:getSize().h - math.floor((avail - 2 * self.gap) / 3)
            probe:free()
            if over > 0 then h = h - over end
        end
        local rows = self:fitRows(avail, self.gap, files[1] and make(files[1]))
        if #files == 0 then
            table.insert(vg, CenterContainer:new{
                dimen = Geom:new{ w = self.cw, h = avail },
                TextBoxWidget:new{
                    text = self.collection
                        and _("No books here yet.\nHold a book in All and choose Collections… to add it.")
                        or _("No books here yet"),
                    face = sans(pxToSize(self.height * 0.016)), fgcolor = GRAY,
                    width = math.floor(self.cw * 0.8), alignment = "center",
                },
            })
            self.pages = 1
        else
            self:addGrid(vg, files, cols, rows, make, self.gap, self.gap)
        end
    end

    -- Pin the pager just above the nav bar.
    local fill = self.height - self.nav_h - pager_h - vg:getSize().h
    if fill > 0 then table.insert(vg, VerticalSpan:new{ width = fill }) end
    table.insert(vg, self:pager(pager_h))
    vg:resetLayout() -- getSize() above cached offsets for fewer children
    return vg
end

function HomeScreen:addGrid(vg, items, cols, rows, make, hgap, vgap)
    local per_page = cols * rows
    self.pages = math.max(1, math.ceil(#items / per_page))
    self.page = math.min(self.page, self.pages)
    local first = (self.page - 1) * per_page + 1
    for r = 0, rows - 1 do
        local tiles = {}
        for c = 0, cols - 1 do
            local item = items[first + r * cols + c]
            if item then table.insert(tiles, make(item)) end
        end
        if #tiles == 0 then break end
        if r > 0 then table.insert(vg, VerticalSpan:new{ width = vgap }) end
        table.insert(vg, self:row(tiles, hgap))
    end
end


---------------------------------------------------------------- quick settings

-- Kindle-style pull-down panel: toggles plus brightness / warmth sliders.
QuickSettings = InputContainer:extend{
    home = nil, -- the HomeScreen we drop down over
}

function QuickSettings:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.width = W
    self.pad = math.floor(W * 0.045)
    self.cw = W - 2 * self.pad
    self.gap = math.floor(W * 0.025)
    self.unit = math.floor(H * 0.01)
    local full = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = full } },
        SwipeAway = { GestureRange:new{ ges = "swipe", range = full } },
    }
    self:build()
end

function QuickSettings:build()
    if self[1] then self[1]:free() end
    local powerd = Device:getPowerDevice()
    local NetworkMgr = require("ui/network/manager")
    local calibre_wireless = package.loaded["wireless"]
    local calibre_on = calibre_wireless and calibre_wireless.calibre_socket ~= nil
    local wifi_on = NetworkMgr:isWifiOn()
    local night = G_reader_settings:isTrue("night_mode")

    local toggles = {
        self:toggle("wifi.open.100", _("Wi-Fi"), wifi_on, wifi_on and _("On") or _("Off"), function()
            local done = function() UIManager:nextTick(function() self:update() end) end
            if NetworkMgr:isWifiOn() then NetworkMgr:toggleWifiOff(done) else NetworkMgr:toggleWifiOn(done) end
        end),
        self:toggle("appbar.contrast", _("Dark mode"), night, night and _("On") or _("Off"), function()
            UIManager:nextTick(function()
                self.home.ui:handleEvent(Event:new("ToggleNightMode"))
                self:update()
            end)
        end),
        self:toggle("appbar.filebrowser", _("Calibre"), calibre_on, calibre_on and _("Connected") or _("Connect"), function()
            UIManager:nextTick(function()
                if not self.home.ui.calibre then return end
                if calibre_on then
                    self.home.ui.calibre:onCloseWirelessConnection()
                else
                    self.home.ui.calibre:onStartWirelessConnection()
                end
                UIManager:scheduleIn(1, function() self:update() end)
            end)
        end),
        self:toggle("cre.render.reload", _("Refresh screen"), false, _("Clear ghosting"), function()
            UIManager:nextTick(function() UIManager:setDirty(nil, "full") end)
        end),
        self:toggle("exit", _("Restart"), false, "KOReader", function()
            UIManager:nextTick(function()
                self:onClose()
                UIManager:broadcastEvent(Event:new("Restart"))
            end)
        end),
        self:toggle("appbar.settings", _("All settings"), false, "", function()
            UIManager:nextTick(function()
                self:onClose()
                self.home.ui.menu:onShowMenu()
            end)
        end),
    }
    local vg = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = self.home.status_h },
        HomeScreen_row({ toggles[1], toggles[2], toggles[3] }, self.gap),
        VerticalSpan:new{ width = self.gap },
        HomeScreen_row({ toggles[4], toggles[5], toggles[6] }, self.gap),
        VerticalSpan:new{ width = self.unit * 3 },
    }
    if Device:hasFrontlight() then
        table.insert(vg, self:slider(_("Brightness"), powerd:frontlightIntensity(), powerd.fl_min, powerd.fl_max, 1,
            function(v) powerd:setIntensity(v) end))
    end
    if Device:hasNaturalLight() then
        table.insert(vg, VerticalSpan:new{ width = self.unit * 2 })
        -- powerd's warmth API is 0-100; the slider shows the Kindle's own 0-24 steps.
        table.insert(vg, self:slider(_("Warmth"), powerd:toNativeWarmth(powerd:frontlightWarmth()), powerd.fl_warmth_min, powerd.fl_warmth_max, 1,
            function(v) powerd:setWarmth(powerd:fromNativeWarmth(v)) end))
    end
    table.insert(vg, VerticalSpan:new{ width = self.unit * 3 })
    self[1] = VerticalGroup:new{
        align = "center",
        FrameContainer:new{
            width = self.width, bordersize = 0, margin = 0, padding = 0,
            padding_left = self.pad, padding_right = self.pad,
            background = WHITE,
            vg,
        },
        LineWidget:new{ dimen = Geom:new{ w = self.width, h = Size.line.thick }, background = BLACK },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self[1]:getSize().h }
end

-- `quick`: redraws while dragging a slider never flash.
function QuickSettings:update(quick)
    if not UIManager:isWidgetShown(self) then return end
    self:build()
    UIManager:setDirty(self, function() return quick and "ui" or einkMode(self.dimen), self.dimen end)
    self.home:updateStatus()
end

function QuickSettings:toggle(icon, label, active, state, callback)
    local w = math.floor((self.cw - 2 * self.gap) / 3)
    local b = Size.border.thin
    local inner = w - 2 * b
    local fg = active and WHITE or BLACK
    local is = self.unit * 4
    local group = VerticalGroup:new{
        align = "center",
        IconWidget:new{ icon = icon, width = is, height = is, invert = active },
        VerticalSpan:new{ width = self.unit },
        TextWidget:new{ text = label, face = sans(pxToSize(self.unit * 2.1), true), fgcolor = fg, max_width = inner - 2 * self.unit },
        -- Always present (blank if no state) so every tile has the same height.
        TextWidget:new{ text = state ~= "" and state or " ", face = sans(pxToSize(self.unit * 1.8)),
                        fgcolor = active and LIGHT or GRAY, max_width = inner - 2 * self.unit },
    }
    local h = group:getSize().h + 4 * self.unit
    return Tappable:new{
        callback = callback,
        FrameContainer:new{
            width = w, height = h, bordersize = b, radius = Size.radius.window,
            padding = 0, margin = 0, background = active and BLACK or WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = h - 2 * b }, group },
        },
    }
end

-- Label, then [-] [=====bar=====] [+]; tap or drag along the bar to set the level.
function QuickSettings:slider(label, value, min, max, step, set)
    local btn = self.unit * 6
    local bar_w = self.cw - 2 * btn - 2 * self.gap
    local bar_h = math.floor(self.unit * 1.6)
    local apply = function(v)
        v = math.max(min, math.min(max, v))
        set(v)
        UIManager:nextTick(function() self:update() end)
    end
    local button = function(text, delta)
        return Tappable:new{
            callback = function() apply(value + delta) end,
            FrameContainer:new{
                width = btn, height = btn, bordersize = Size.border.thin, radius = math.floor(btn / 2),
                padding = 0, margin = 0, background = WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = btn - 2 * Size.border.thin, h = btn - 2 * Size.border.thin },
                    TextWidget:new{ text = text, face = sans(pxToSize(btn * 0.5), true) },
                },
            },
        }
    end
    local bar
    local at = function(x)
        local d = bar.dimen
        local frac = (x - d.x) / d.w
        return math.max(min, math.min(max, min + math.floor(frac * (max - min) + 0.5)))
    end
    -- While dragging the light follows the finger; the panel redraws at most 4x a second.
    local last, pending = value, false
    local redraw = function()
        pending = false
        self:update(true)
    end
    bar = Tappable:new{
        callback = function(ges)
            if ges and bar.dimen then apply(at(ges.pos.x)) end
        end,
        drag_callback = function(x, done)
            if not bar.dimen then return end
            local v = at(x)
            if v ~= last then
                last = v
                set(v)
            end
            if done then
                UIManager:unschedule(redraw)
                pending = false
                UIManager:nextTick(function() self:update() end)
            elseif not pending then
                pending = true
                UIManager:scheduleIn(0.25, redraw)
            end
        end,
        CenterContainer:new{
            dimen = Geom:new{ w = bar_w, h = btn },
            progressBar((value - min) / (max - min), bar_w, bar_h),
        },
    }
    return VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = string.format("%s   %d", label, value), face = sans(pxToSize(self.unit * 2)) },
        VerticalSpan:new{ width = self.unit },
        HorizontalGroup:new{
            align = "center",
            button("−", -step),
            HorizontalSpan:new{ width = self.gap },
            bar,
            HorizontalSpan:new{ width = self.gap },
            button("+", step),
        },
    }
end

function QuickSettings:onTapOutside(_, ges)
    if ges.pos.y > self.dimen.h then self:onClose() end
    return true
end

function QuickSettings:onSwipeAway(_, ges)
    if ges.direction == "north" then self:onClose() end
    return true
end

function QuickSettings:onClose()
    UIManager:close(self, einkMode(self.dimen), self.dimen)
    return true
end

---------------------------------------------------------------- plugin

local KindleHome = WidgetContainer:extend{
    name = "kindlehome",
    is_doc_only = false,
}

function KindleHome:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindlehome_show", {
        category = "none", event = "ShowKindleHome", title = _("Kindle home screen"), general = true,
    })
end

function KindleHome:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if not self.ui.document and G_reader_settings:nilOrTrue("kindlehome_autoshow") then
        -- Show the home screen in the same call that shows the file manager,
        -- so the file browser never gets painted on its own.
        local orig_show = UIManager.show
        UIManager.show = function(um, widget, ...)
            local ret = orig_show(um, widget, ...)
            if widget == self.ui then
                UIManager.show = orig_show
                self:showHome()
            end
            return ret
        end
    end
end

-- In a book, swiping down from the top edge opens the same quick settings panel, as on a stock
-- Kindle; a tap up there still opens KOReader's menu.
function KindleHome:onReaderReady()
    if not self.ui.document then return end
    -- Right half of the top edge only; the left half keeps KOReader's own menu swipe.
    local area = { ratio_x = 1 / 2, ratio_y = 0, ratio_w = 1 / 2, ratio_h = 1 / 8 }
    self.ui:registerTouchZones({
        {
            id = "kindlehome_quicksettings",
            ges = "swipe",
            screen_zone = area,
            overrides = { "readermenu_swipe", "readermenu_ext_swipe" },
            handler = function(ges)
                if ges.direction ~= "south" then return end
                -- The panel only needs these few things from its host.
                local host = { ui = self.ui, status_h = math.floor(Screen:getHeight() * 0.04), updateStatus = function() end }
                UIManager:show(QuickSettings:new{ home = host }, "ui")
                return true
            end,
        },
        {
            -- Swallow the drag, or KOReader's pan zones open its menus mid-swipe.
            id = "kindlehome_quicksettings_pan",
            ges = "pan",
            screen_zone = area,
            overrides = { "readermenu_pan", "readermenu_ext_pan" },
            handler = function(ges) return ges.direction == "south" or nil end,
        },
    })
    self:startGoalTracking()
end

-- Daily goal while reading: today's time so far comes from the stats DB when the book opens, then
-- each page turn adds the time spent on the page the way the statistics plugin counts it
-- (under 5 s is skipped, over 2 min counts as 2 min). Crossing the goal shows a short note, once a day.
function KindleHome:startGoalTracking()
    self.goal = nil
    local today = os.date("%Y-%m-%d")
    if G_reader_settings:readSetting("kindlehome_goal_done") == today then return end
    if self.ui.statistics and self.ui.statistics.insertDB then pcall(self.ui.statistics.insertDB, self.ui.statistics) end
    local st = readingStats()
    if not st or st.today >= dailyGoal() * 60 then return end
    self.goal = { day = today, secs = st.today, streak = st.streak, last = os.time() }
end

function KindleHome:onPageUpdate()
    local g = self.goal
    if not g then return end
    local now = os.time()
    if os.date("%Y-%m-%d", now) ~= g.day then return self:startGoalTracking() end
    local spent = now - g.last
    g.last = now
    if spent < 5 then return end
    g.secs = g.secs + math.min(spent, 120)
    if g.secs < dailyGoal() * 60 then return end
    self.goal = nil
    G_reader_settings:saveSetting("kindlehome_goal_done", g.day)
    local streak = g.streak + 1
    Notification:notify(string.format(_("Daily goal reached · %s"),
        streak == 1 and _("1-day streak") or string.format(_("%d-day streak"), streak)),
        Notification.SOURCE_ALWAYS_SHOW)
end

function KindleHome:onResume()
    -- Time asleep isn't reading; a new day starts the count again.
    if self.ui.document then self:startGoalTracking() end
end

function KindleHome:showHome(tab)
    if KindleHome.widget and UIManager:isWidgetShown(KindleHome.widget) then
        UIManager:close(KindleHome.widget)
    end
    KindleHome.widget = HomeScreen:new{ ui = self.ui, tab = tab or "home" }
    UIManager:show(KindleHome.widget, "flashui")
end

function KindleHome:onShowKindleHome()
    if self.ui.document then
        -- Closing the book returns to the file manager, which shows the home screen.
        self.ui:onHome()
    else
        self:showHome()
    end
    return true
end

function KindleHome:addToMainMenu(menu_items)
    menu_items.kindle_home = {
        text = _("Kindle home screen"),
        sorting_hint = "main",
        sub_item_table = {
            {
                text = _("Open home screen"),
                callback = function() self:onShowKindleHome() end,
            },
            {
                text = _("Show on start and after closing a book"),
                checked_func = function() return G_reader_settings:nilOrTrue("kindlehome_autoshow") end,
                callback = function() G_reader_settings:flipNilOrTrue("kindlehome_autoshow") end,
            },
        },
    }
end

return KindleHome
