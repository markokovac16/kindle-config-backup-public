--[[--
Reading Wrapped: the numbers. Pure Lua over rows from the statistics plugin's page_stat_data,
so it can be tested off-device.

@module koplugin.KindleHome.WrappedData
--]]--

local Data = {}

local DAY = 86400
local SITTING_GAP = 10 * 60 -- a pause longer than this starts a new sitting

-- Start of the period and its label. kind: "year", "month" or "all".
function Data.period(kind, now)
    now = now or os.time()
    local t = os.date("*t", now)
    t.hour, t.min, t.sec = 0, 0, 0
    if kind == "month" then
        t.day = 1
        return os.time(t), os.date("%B %Y", now)
    elseif kind == "all" then
        return 0, "All time"
    end
    t.day, t.month = 1, 1
    return os.time(t), tostring(t.year)
end

local function dayKey(ts) return os.date("%Y-%m-%d", ts) end

local function noonOf(key)
    local y, m, d = key:match("(%d+)-(%d+)-(%d+)")
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

-- rows: array of { book = id, page = n, start = ts, dur = secs, total = pages }.
-- resolve(id) -> { title, author, file, comic = bool, series = name or nil, finished = bool or nil }.
function Data.compute(rows, resolve)
    table.sort(rows, function(a, b) return a.start < b.start end)
    local s = {
        secs = 0, pages = 0, hours = {}, wdays = {}, days = {}, books = {},
        comic_secs = 0, comic_pages = 0, prose_secs = 0, prose_pages = 0,
    }
    for h = 0, 23 do s.hours[h] = 0 end
    for d = 1, 7 do s.wdays[d] = 0 end
    local seen_page, book_of = {}, {}
    local day_secs, day_comics = {}, {}
    local sitting, sittings = nil, {}

    for _, r in ipairs(rows) do
        local b = s.books[r.book]
        if not b then
            local info = resolve(r.book) or {}
            b = { id = r.book, title = info.title or "?", author = info.author, file = info.file,
                  comic = info.comic, series = info.series, finished_hint = info.finished,
                  secs = 0, pages = 0, max_page = 0, total = 0, first = r.start, last = r.start }
            s.books[r.book] = b
            book_of[#book_of + 1] = b
        end
        b.secs = b.secs + r.dur
        b.last = r.start
        if r.total and r.total > 0 then b.total = r.total end
        if r.page > b.max_page then b.max_page = r.page end
        local pk = r.book .. ":" .. r.page
        local new_page = not seen_page[pk]
        if new_page then
            seen_page[pk] = true
            b.pages = b.pages + 1
            s.pages = s.pages + 1
        end
        s.secs = s.secs + r.dur
        if b.comic then
            s.comic_secs = s.comic_secs + r.dur
            if new_page then s.comic_pages = s.comic_pages + 1 end
        else
            s.prose_secs = s.prose_secs + r.dur
            if new_page then s.prose_pages = s.prose_pages + 1 end
        end
        local t = os.date("*t", r.start)
        s.hours[t.hour] = s.hours[t.hour] + r.dur
        s.wdays[t.wday] = s.wdays[t.wday] + r.dur
        local dk = dayKey(r.start)
        day_secs[dk] = (day_secs[dk] or 0) + r.dur
        if b.comic then
            day_comics[dk] = day_comics[dk] or {}
            day_comics[dk][r.book] = (day_comics[dk][r.book] or 0) + r.dur
        end
        -- Sittings span books: one continuous stretch of reading.
        if not sitting or r.start - sitting.stop > SITTING_GAP then
            sitting = { start = r.start, stop = r.start, secs = 0, by_book = {} }
            sittings[#sittings + 1] = sitting
        end
        sitting.secs = sitting.secs + r.dur
        sitting.stop = r.start + r.dur
        sitting.by_book[r.book] = (sitting.by_book[r.book] or 0) + r.dur
    end

    -- Days with at least a minute of reading.
    local day_list = {}
    for dk, secs in pairs(day_secs) do
        if secs >= 60 then day_list[#day_list + 1] = dk end
    end
    table.sort(day_list)
    s.days_read = #day_list
    s.streak, s.streak_end = 0, nil
    local run, prev = 0, nil
    for _, dk in ipairs(day_list) do
        local noon = noonOf(dk)
        if prev and math.abs(noon - prev - DAY) < 2 * 3600 then run = run + 1 else run = 1 end
        if run > s.streak then s.streak, s.streak_end = run, dk end
        prev = noon
    end
    for dk, secs in pairs(day_secs) do
        if not s.busiest or secs > s.busiest.secs or (secs == s.busiest.secs and dk < s.busiest.day) then
            s.busiest = { day = dk, secs = secs }
        end
    end

    for _, st in ipairs(sittings) do
        if not s.longest_sitting or st.secs > s.longest_sitting.secs then
            local top, top_secs = nil, -1
            for id, secs in pairs(st.by_book) do
                if secs > top_secs then top, top_secs = id, secs end
            end
            s.longest_sitting = { secs = st.secs, start = st.start, book = s.books[top] }
        end
    end

    -- Books worth listing: a couple of minutes at least.
    s.top = {}
    s.finished_books, s.finished_comics = 0, 0
    for _, b in ipairs(book_of) do
        if b.finished_hint ~= nil then
            b.finished = b.finished_hint
        else
            b.finished = b.total > 0 and b.max_page >= b.total * 0.95
        end
        if b.finished then
            if b.comic then s.finished_comics = s.finished_comics + 1 else s.finished_books = s.finished_books + 1 end
        end
        if b.secs >= 120 then s.top[#s.top + 1] = b end
    end
    table.sort(s.top, function(a, b) return a.secs > b.secs end)

    -- Manga: volumes touched, series, and the biggest single-day binge.
    local series = {}
    s.volumes = 0
    for _, b in ipairs(book_of) do
        if b.comic and b.secs >= 60 then
            s.volumes = s.volumes + 1
            local name = b.series or b.title
            local e = series[name]
            if not e then
                e = { name = name, secs = 0, volumes = 0, first = b }
                series[name] = e
            end
            e.secs = e.secs + b.secs
            e.volumes = e.volumes + 1
            if b.first < e.first.first then e.first = b end
        end
    end
    s.series = {}
    for _, e in pairs(series) do s.series[#s.series + 1] = e end
    table.sort(s.series, function(a, b) return a.secs > b.secs end)
    for dk, books in pairs(day_comics) do
        local count, top, top_secs = 0, nil, -1
        for id, secs in pairs(books) do
            if secs >= 60 then count = count + 1 end
            if secs > top_secs then top, top_secs = id, secs end
        end
        if count > 0 and (not s.binge or count > s.binge.volumes or (count == s.binge.volumes and dk < s.binge.day)) then
            local b = s.books[top]
            s.binge = { day = dk, volumes = count, series = b.series or b.title }
        end
    end

    -- When: favourite hour, a reader type from the busiest part of the day, favourite weekday.
    local best_h = 0
    for h = 1, 23 do if s.hours[h] > s.hours[best_h] then best_h = h end end
    s.peak_hour = best_h
    local parts = {
        { name = "Early bird", from = 5, to = 9 },
        { name = "Daytime reader", from = 9, to = 17 },
        { name = "Evening reader", from = 17, to = 22 },
        { name = "Night owl", from = 22, to = 29 },
    }
    local best_part, best_secs = parts[2], -1
    for _, p in ipairs(parts) do
        local secs = 0
        for h = p.from, p.to - 1 do secs = secs + s.hours[h % 24] end
        if secs > best_secs then best_part, best_secs = p, secs end
    end
    s.reader_type = best_part.name
    local best_w = 1
    for d = 2, 7 do if s.wdays[d] > s.wdays[best_w] then best_w = d end end
    s.peak_wday = best_w

    -- Pace, only when there's enough of each to mean something.
    if s.prose_secs >= 1800 then s.prose_pace = math.floor(s.prose_pages / (s.prose_secs / 3600) + 0.5) end
    if s.comic_secs >= 1800 then s.comic_pace = math.floor(s.comic_pages / (s.comic_secs / 3600) + 0.5) end
    return s
end

return Data
