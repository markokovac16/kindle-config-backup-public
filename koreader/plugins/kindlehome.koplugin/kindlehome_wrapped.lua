--[[--
Reading Wrapped: a Spotify Wrapped-style story of your reading, from the statistics plugin's DB.
Tap the right of the screen (or swipe left) for the next card, the left for the previous one.

@module koplugin.KindleHome.Wrapped
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local Data = require("kindlehome_wrapped_data")

local WHITE = Blitbuffer.COLOR_WHITE
local BLACK = Blitbuffer.COLOR_BLACK
local GRAY = Blitbuffer.COLOR_DARK_GRAY
local LIGHT = Blitbuffer.COLOR_GRAY_D

local function pxToSize(px)
    return math.max(7, math.floor(px * 100 / Screen:scaleBySize(100)))
end
local function sans(px, bold)
    return Font:getFace(bold and "NotoSans-Bold.ttf" or "NotoSans-Regular.ttf", pxToSize(px))
end
local function serif(px)
    return Font:getFace("NotoSerif-Bold.ttf", pxToSize(px))
end

local function thousands(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

local function duration(secs)
    local mins = math.floor(secs / 60 + 0.5)
    if mins < 60 then return string.format(_("%d min"), mins) end
    local h, m = math.floor(mins / 60), mins % 60
    if m == 0 then return string.format(_("%d h"), h) end
    return string.format(_("%d h %d min"), h, m)
end

local function prettyDay(key)
    local y, m, d = key:match("(%d+)-(%d+)-(%d+)")
    local t = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    return (os.date("%A, %d %B", t):gsub(" 0", " "))
end

local WEEKDAYS = { _("Sunday"), _("Monday"), _("Tuesday"), _("Wednesday"), _("Thursday"), _("Friday"), _("Saturday") }
local TYPE_BLURB = {
    ["Early bird"] = _("Most of your pages turned before 9 in the morning."),
    ["Daytime reader"] = _("You do most of your reading in broad daylight."),
    ["Evening reader"] = _("Evenings are your reading time."),
    ["Night owl"] = _("Most of your pages turned after 10 at night."),
}

local function shortTitle(title)
    if #title > 42 then
        local head = title:match("^(.-):%s") or title:match("^(.-)%s%(")
        if head and #head >= 4 then return head end
    end
    return title
end

---------------------------------------------------------------- data loading

local function queryRows(from)
    local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(path, "mode") ~= "file" then return {}, {} end
    local conn = require("lua-ljsqlite3/init").open(path, "ro")
    local rows, books = {}, {}
    local res = conn:exec("SELECT id_book, page, start_time, duration, total_pages FROM page_stat_data WHERE start_time >= " .. math.floor(from))
    if res then
        for i = 1, #res[1] do
            rows[i] = { book = tonumber(res[1][i]), page = tonumber(res[2][i]), start = tonumber(res[3][i]),
                        dur = tonumber(res[4][i]), total = tonumber(res[5][i]) }
        end
    end
    res = conn:exec("SELECT id, title, authors, md5 FROM book")
    if res then
        for i = 1, #res[1] do
            books[tonumber(res[1][i])] = { title = res[2][i], authors = res[3][i], md5 = res[4][i] }
        end
    end
    conn:close()
    return rows, books
end

-- Map the statistics plugin's book ids to files on the device (it identifies books by partial MD5).
local function resolver(books, helpers)
    local by_md5 = {}
    for _, file in ipairs(helpers.files()) do
        local md5 = util.partialMD5(file)
        if md5 then by_md5[md5] = file end
    end
    local BookList = require("ui/widget/booklist")
    return function(id)
        local b = books[id]
        if not b then return nil end
        local file = b.md5 and by_md5[b.md5]
        local info = { title = b.title, file = file }
        if b.authors and b.authors ~= "N/A" and b.authors ~= "Unknown" then info.author = b.authors:match("^[^\n]+") end
        if file then
            local m = helpers.meta(file)
            info.meta = m
            info.title, info.author = m.title or info.title, m.author or info.author
            local ext = util.getFileNameSuffix(file):lower()
            info.comic = ext == "cbz" or ext == "cbr" or file:find("/Manga/", 1, true) ~= nil
            info.series = file:match("/Manga/([^/]+)/")
            local ok, book = pcall(BookList.getBookInfo, file)
            if ok and book and book.status == "complete" then info.finished = true end
        end
        info.title = (info.title or "?"):gsub(" %- [^%-]+$", "")
        if not info.series then info.series = info.title:match("^(.-),%s*Vol%.") end
        if info.series and not info.comic and info.title:match(",%s*Vol%.%s*%d") and not file then info.comic = true end
        return info
    end
end

---------------------------------------------------------------- pieces

-- Simple bar chart: values drawn as bars from the baseline, with a few labels underneath.
local BarChart = Widget:extend{ values = nil, labels = nil, highlight = nil, width = 0, height = 0 }

function BarChart:getSize() return Geom:new{ w = self.width, h = self.height } end

function BarChart:paintTo(bb, x, y)
    local n = #self.values
    local max = 0
    for i = 1, n do max = math.max(max, self.values[i]) end
    local label_face = sans(self.height * 0.09)
    local label_h = math.floor(self.height * 0.16)
    local chart_h = self.height - label_h
    local slot = self.width / n
    local bar_w = math.max(2, math.floor(slot * 0.72))
    for i = 1, n do
        local v = self.values[i]
        local h = max > 0 and math.floor(chart_h * v / max + 0.5) or 0
        if v > 0 and h < 3 then h = 3 end
        local bx = x + math.floor((i - 1) * slot + (slot - bar_w) / 2)
        bb:paintRect(bx, y + chart_h - 1, bar_w, 1, GRAY)
        if h > 0 then bb:paintRect(bx, y + chart_h - h, bar_w, h, i == self.highlight and BLACK or GRAY) end
        local label = self.labels[i]
        if label then
            local t = TextWidget:new{ text = label, face = label_face, fgcolor = BLACK }
            local tw = t:getSize().w
            t:paintTo(bb, bx + math.floor((bar_w - tw) / 2), y + chart_h + math.floor(label_h * 0.2))
            t:free()
        end
    end
end

---------------------------------------------------------------- the story

local Wrapped = InputContainer:extend{
    name = "kindlehome_wrapped",
    modal = true,
    covers_fullscreen = true,
    helpers = nil, -- { files = fn, meta = fn(file), cover = fn(meta, w, h) }
    kind = "year",
}

function Wrapped:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.W, self.H = self.dimen.w, self.dimen.h
    self.margin = math.floor(self.W * 0.08)
    self.text_w = self.W - 2 * self.margin
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:load()
end

function Wrapped:load()
    local from, label = Data.period(self.kind)
    self.label = label
    local ok, err = pcall(function()
        local rows, books = queryRows(from)
        self.stats = Data.compute(rows, resolver(books, self.helpers))
    end)
    if not ok then
        logger.warn("KindleHome: wrapped failed:", err)
        self.stats = Data.compute({}, function() end)
    end
    self:buildCards()
    self.index = 1
    self:render()
end

-- Text helpers, all centred in the text column.
function Wrapped:line(text, face, color)
    return TextBoxWidget:new{ text = text, face = face, width = self.text_w, alignment = "center", fgcolor = color or BLACK }
end
function Wrapped:big(text, px) return self:line(text, serif(px or self.H * 0.085)) end
function Wrapped:kicker(text) return self:line(text, sans(self.H * 0.022, true), GRAY) end
function Wrapped:body(text) return self:line(text, sans(self.H * 0.021)) end
function Wrapped:gap(f) return VerticalSpan:new{ width = math.floor(self.H * (f or 0.03)) } end

function Wrapped:cover(book, w, h)
    if book and book.meta and self.helpers.cover then
        local ok, widget = pcall(self.helpers.cover, book.meta, w, h)
        if ok and widget then return CenterContainer:new{ dimen = Geom:new{ w = self.W, h = h }, widget } end
    end
end

function Wrapped:card(...)
    local group = VerticalGroup:new{ align = "center" }
    for _, w in ipairs({ ... }) do if w then table.insert(group, w) end end
    return group
end

function Wrapped:buildCards()
    local s = self.stats
    local cards = {}
    local function add(fn) cards[#cards + 1] = fn end
    local whose = self.kind == "year" and _("Your year in reading") or self.kind == "month" and _("Your month in reading") or _("Everything you've read on this Kindle")

    add(function()
        return self:card(
            self:kicker(_("READING WRAPPED")), self:gap(0.02),
            self:big(self.label, self.H * 0.12), self:gap(0.015),
            self:body(whose), self:gap(0.06),
            self:body(s.secs > 0 and _("Tap to begin →") or _("Nothing here yet. Read a little, then come back.")))
    end)
    if s.secs == 0 then self.cards = cards return end

    add(function()
        local films = math.floor(s.secs / 7200 + 0.5)
        return self:card(
            self:kicker(_("YOU SPENT")), self:gap(0.02),
            self:big(duration(s.secs)), self:gap(0.02),
            self:body(string.format(_("reading, on %d different days."), s.days_read)), self:gap(0.04),
            films >= 2 and self:body(string.format(_("That's about %d films' worth of time."), films)) or nil)
    end)

    add(function()
        local split = s.comic_pages > 0 and s.prose_pages > 0
            and string.format(_("%s in books and %s in manga"), thousands(s.prose_pages), thousands(s.comic_pages)) or nil
        local done = {}
        if s.finished_books > 0 then done[#done + 1] = string.format(s.finished_books == 1 and _("%d book") or _("%d books"), s.finished_books) end
        if s.finished_comics > 0 then done[#done + 1] = string.format(s.finished_comics == 1 and _("%d manga volume") or _("%d manga volumes"), s.finished_comics) end
        return self:card(
            self:kicker(_("YOU TURNED")), self:gap(0.02),
            self:big(thousands(s.pages), self.H * 0.12),
            self:body(s.pages == 1 and _("page") or _("pages")), self:gap(0.03),
            split and self:body(split) or nil, self:gap(0.03),
            #done > 0 and self:body(string.format(_("You finished %s."), table.concat(done, _(" and ")))) or nil)
    end)

    local top = s.top[1]
    if top then
        add(function()
            local cover_h = math.floor(self.H * 0.42)
            return self:card(
                self:kicker(_("YOUR #1")), self:gap(0.025),
                self:cover(top, math.floor(cover_h * 0.72), cover_h), self:gap(0.03),
                self:line(shortTitle(top.title), serif(self.H * 0.034)),
                top.author and self:line(top.author, sans(self.H * 0.02), GRAY) or nil, self:gap(0.025),
                self:body(string.format(_("%s together, %s pages."), duration(top.secs), thousands(top.pages))))
        end)
    end

    if #s.top >= 3 then
        add(function()
            local group = self:card(self:kicker(_("YOUR TOP BOOKS")), self:gap(0.03))
            local row_h = math.floor(self.H * 0.11)
            for i = 1, math.min(5, #s.top) do
                local b = s.top[i]
                local num = TextWidget:new{ text = tostring(i), face = serif(row_h * 0.45) }
                local cover = b.meta and self.helpers.cover and select(2, pcall(self.helpers.cover, b.meta, math.floor(row_h * 0.7), row_h))
                local text_w = self.text_w - row_h * 0.5 - row_h * 0.7 - self.margin * 0.6
                local texts = VerticalGroup:new{ align = "left",
                    TextWidget:new{ text = shortTitle(b.title), face = sans(row_h * 0.2, true), max_width = text_w },
                    TextWidget:new{ text = duration(b.secs), face = sans(row_h * 0.17), fgcolor = GRAY, max_width = text_w },
                }
                local row = HorizontalGroup:new{ align = "center",
                    CenterContainer:new{ dimen = Geom:new{ w = math.floor(row_h * 0.5), h = row_h }, num },
                    HorizontalSpan:new{ width = math.floor(self.margin * 0.3) },
                    type(cover) == "table" and cover or HorizontalSpan:new{ width = math.floor(row_h * 0.7) },
                    HorizontalSpan:new{ width = math.floor(self.margin * 0.3) },
                    texts,
                }
                table.insert(group, LeftContainer:new{ dimen = Geom:new{ w = self.text_w, h = row_h }, row })
                table.insert(group, self:gap(0.012))
            end
            return group
        end)
    end

    if s.volumes > 0 then
        add(function()
            local main = s.series[1]
            local cover_h = math.floor(self.H * 0.3)
            local binge = s.binge and s.binge.volumes >= 2
                and string.format(_("Biggest binge: %d volumes of %s on %s."), s.binge.volumes, s.binge.series, prettyDay(s.binge.day)) or nil
            return self:card(
                self:kicker(_("MANGA MODE")), self:gap(0.02),
                self:big(string.format(s.volumes == 1 and _("%d volume") or _("%d volumes"), s.volumes)),
                self:body(#s.series == 1 and _("from one series") or string.format(_("across %d series"), #s.series)), self:gap(0.03),
                self:cover(main.first, math.floor(cover_h * 0.72), cover_h), self:gap(0.02),
                self:body(string.format(_("Top series: %s, %s."), main.name, duration(main.secs))), self:gap(0.015),
                binge and self:body(binge) or nil,
                s.comic_pace and self:body(string.format(_("You fly through manga at %d pages an hour."), s.comic_pace)) or nil)
        end)
    end

    add(function()
        local values, labels = {}, {}
        for h = 0, 23 do
            values[h + 1] = s.hours[h]
            if h % 6 == 0 then labels[h + 1] = string.format("%02d", h) end
        end
        local week_values, week_labels = {}, {}
        for i = 1, 7 do
            local d = i % 7 + 1 -- Monday first
            week_values[i] = s.wdays[d]
            week_labels[i] = WEEKDAYS[d]:sub(1, 2)
        end
        local monday_index = (s.peak_wday + 5) % 7 + 1
        return self:card(
            self:kicker(_("YOU'RE A")), self:gap(0.015),
            self:big(s.reader_type, self.H * 0.06), self:gap(0.015),
            self:body(TYPE_BLURB[s.reader_type]), self:gap(0.04),
            BarChart:new{ values = values, labels = labels, highlight = s.peak_hour + 1, width = self.text_w, height = math.floor(self.H * 0.16) },
            self:gap(0.015),
            self:body(string.format(_("Favourite hour: %02d:00"), s.peak_hour)), self:gap(0.04),
            BarChart:new{ values = week_values, labels = week_labels, highlight = monday_index, width = self.text_w, height = math.floor(self.H * 0.12) },
            self:gap(0.015),
            self:body(string.format(_("Favourite day: %s"), WEEKDAYS[s.peak_wday])))
    end)

    add(function()
        local function stat(kicker, value, detail)
            return self:card(self:kicker(kicker), self:gap(0.008), self:big(value, self.H * 0.05),
                detail and self:line(detail, sans(self.H * 0.019), GRAY) or nil, self:gap(0.04))
        end
        local sit = s.longest_sitting
        return self:card(
            stat(_("LONGEST STREAK"), string.format(s.streak == 1 and _("%d day") or _("%d days"), s.streak),
                s.streak > 1 and string.format(_("ending %s"), prettyDay(s.streak_end)) or _("of reading in a row")),
            stat(_("BUSIEST DAY"), duration(s.busiest.secs), prettyDay(s.busiest.day)),
            sit and stat(_("LONGEST SITTING"), duration(sit.secs), sit.book and string.format(_("with %s"), shortTitle(sit.book.title))) or nil,
            s.prose_pace and stat(_("BOOK PACE"), string.format(_("%d pages/h"), s.prose_pace)) or nil)
    end)

    add(function()
        local cells = {
            { _("Time read"), duration(s.secs) },
            { _("Pages"), thousands(s.pages) },
            { _("Finished"), tostring(s.finished_books + s.finished_comics) },
            { _("Streak"), string.format(_("%d d"), s.streak) },
        }
        local cell_w = math.floor(self.text_w / 2)
        local grid = VerticalGroup:new{ align = "center" }
        for i = 1, #cells, 2 do
            local row = HorizontalGroup:new{}
            for j = i, i + 1 do
                row[#row + 1] = CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = math.floor(self.H * 0.1) },
                    VerticalGroup:new{ align = "center",
                        TextWidget:new{ text = cells[j][1]:upper(), face = sans(self.H * 0.017, true), fgcolor = GRAY },
                        TextWidget:new{ text = cells[j][2], face = serif(self.H * 0.035), max_width = cell_w },
                    } }
            end
            grid[#grid + 1] = row
        end
        local cover_h = math.floor(self.H * 0.22)
        local card = self:card(
            self:kicker(string.format(_("%s · WRAPPED"), self.label:upper())), self:gap(0.02),
            top and self:cover(top, math.floor(cover_h * 0.72), cover_h) or nil, self:gap(0.015),
            top and self:line(string.format(_("#1: %s"), shortTitle(top.title)), sans(self.H * 0.021, true)) or nil,
            self:gap(0.02),
            grid, self:gap(0.02),
            self:line(s.reader_type, serif(self.H * 0.03)))
        return FrameContainer:new{ bordersize = Size.border.thick, radius = math.floor(self.W * 0.03),
            padding = math.floor(self.margin * 0.4), color = BLACK, background = WHITE, card }
    end)
    self.cards = cards
end

function Wrapped:progressBar()
    local n = #self.cards
    local gap = math.floor(self.W * 0.008)
    local w = math.floor((self.text_w - gap * (n - 1)) / n)
    local h = math.max(3, math.floor(self.H * 0.004))
    local bar = HorizontalGroup:new{}
    for i = 1, n do
        bar[#bar + 1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, width = w, height = h,
            background = i <= self.index and BLACK or LIGHT, VerticalSpan:new{ width = h } }
        if i < n then bar[#bar + 1] = HorizontalSpan:new{ width = gap } end
    end
    return bar
end

function Wrapped:render()
    local top_h = math.floor(self.H * 0.09)
    local close = TextWidget:new{ text = "✕", face = sans(self.H * 0.03, true) }
    local header = OverlapGroup:new{ dimen = Geom:new{ w = self.W, h = top_h },
        CenterContainer:new{ dimen = Geom:new{ w = self.W, h = top_h }, self:progressBar() },
    }
    close.overlap_offset = { self.W - self.margin * 0.5 - close:getSize().w, math.floor((top_h - close:getSize().h) / 2) }
    table.insert(header, close)
    local body = self.cards[self.index]()
    local footer
    if self.index == 1 then
        local function pick(kind, text)
            return { text = (self.kind == kind and "✓ " or "") .. text, callback = function()
                if self.kind ~= kind then self.kind = kind; self:load() end
            end }
        end
        footer = ButtonTable:new{ width = self.text_w, buttons = {{ pick("year", _("This year")), pick("month", _("This month")), pick("all", _("All time")) }} }
    end
    local footer_h = footer and footer:getSize().h + math.floor(self.H * 0.05) or math.floor(self.H * 0.05)
    self[1] = FrameContainer:new{
        width = self.W, height = self.H, padding = 0, bordersize = 0, background = WHITE,
        VerticalGroup:new{ align = "center",
            header,
            CenterContainer:new{ dimen = Geom:new{ w = self.W, h = self.H - top_h - footer_h }, body },
            footer or VerticalSpan:new{ width = 0 },
            VerticalSpan:new{ width = footer and math.floor(self.H * 0.05) or footer_h },
        },
    }
    self.close_zone = Geom:new{ x = self.W - top_h * 1.5, y = 0, w = top_h * 1.5, h = top_h }
    UIManager:setDirty(self, "flashui")
end

function Wrapped:go(delta)
    local i = self.index + delta
    if i < 1 then return end
    if i > #self.cards then return self:onClose() end
    self.index = i
    self:render()
end

function Wrapped:onTap(_, ges)
    if self.close_zone and ges.pos:intersectWith(self.close_zone) then return self:onClose() end
    self:go(ges.pos.x < self.W / 3 and -1 or 1)
    return true
end

function Wrapped:onSwipe(_, ges)
    if ges.direction == "west" then self:go(1)
    elseif ges.direction == "east" then self:go(-1)
    elseif ges.direction == "south" then self:onClose() end
    return true
end

function Wrapped:onClose()
    UIManager:close(self, "flashui")
    return true
end

local M = {}

function M.show(helpers, kind)
    local msg = InfoMessage:new{ text = _("Wrapping up your reading…") }
    UIManager:show(msg)
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        UIManager:close(msg)
        UIManager:show(Wrapped:new{ helpers = helpers, kind = kind or "year" })
    end)
end

return M
