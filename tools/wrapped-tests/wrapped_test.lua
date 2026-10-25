package.path = arg[1] .. "/?.lua;" .. package.path
local D = require("kindlehome_wrapped_data")
local dump = dofile(arg[2])
local function resolve(id)
    local t = dump.books[id].title
    local series = t:match("^(.-),%s*Vol%.")
    return { title = (t:gsub(" %- [^%-]+$", "")), comic = series ~= nil, series = series }
end
for _, kind in ipairs({ "year", "month", "all" }) do
    local from, label = D.period(kind)
    local rows = {}
    for _, r in ipairs(dump.rows) do if r.start >= from then rows[#rows + 1] = r end end
    local s = D.compute(rows, resolve)
    print(string.format("[%s] %d min, %d pages (%d prose/%d manga), days %d, streak %d (to %s)", label, math.floor(s.secs / 60), s.pages, s.prose_pages, s.comic_pages, s.days_read, s.streak, tostring(s.streak_end)))
end
local s = D.compute(dump.rows, resolve)
print("busiest", s.busiest.day, s.busiest.secs, "sitting", s.longest_sitting.secs, s.longest_sitting.book.title)
for i, b in ipairs(s.top) do print("top", i, b.title, b.secs, b.pages, b.finished) end
print("volumes", s.volumes, "series", #s.series, s.series[1] and s.series[1].name, "binge", s.binge and (s.binge.day .. " " .. s.binge.volumes))
print("type", s.reader_type, "peak hour", s.peak_hour, "wday", s.peak_wday, "pace", s.prose_pace, s.comic_pace, "finished", s.finished_books, s.finished_comics)
local e = D.compute({}, resolve); print("empty ok", e.secs, e.busiest, #e.top, e.reader_type)
