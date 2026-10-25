-- Kindle-like reading footer, 10 min sleep, Calibre wireless into documents/ (applied once).
if not G_reader_settings:isTrue("qol_tweaks_applied") then
    local f = G_reader_settings:readSetting("footer") or {}
    -- "X min left in chapter" on the left, percentage on the right, nothing else.
    for _, k in ipairs{ "page_progress", "pages_left", "pages_left_book", "time", "battery",
                        "book_time_to_read", "frontlight", "wifi_status", "book_title",
                        "book_chapter", "book_author", "bookmark_count", "chapter_progress", "mem_usage" } do
        f[k] = false
    end
    f.chapter_time_to_read = true
    f.percentage = true
    f.dynamic_filler = true
    f.all_at_once = true
    f.disable_progress_bar = true
    f.hide_empty_generators = true
    f.text_font_size = 12
    f.order = { [0] = "chapter_time_to_read", "dynamic_filler", "percentage" }
    G_reader_settings:saveSetting("footer", f)
    G_reader_settings:saveSetting("reader_footer_mode", 0) -- first item in `order`, i.e. footer on
    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", 600)
    G_reader_settings:saveSetting("autoshutdown_timeout_seconds", -1)
    G_reader_settings:saveSetting("inbox_dir", "/mnt/us/documents")
    G_reader_settings:makeTrue("qol_tweaks_applied")
end

-- Brightness (left edge) and warmth (right edge) swipes only in the lower half,
-- so swipes down from the top corners always reach the menus. Applied in memory every boot.
G_defaults:saveSetting("DSWIPE_ZONE_LEFT_EDGE", { x = 0, y = 1/2, w = 1/8, h = 1/2 })
G_defaults:saveSetting("DSWIPE_ZONE_RIGHT_EDGE", { x = 7/8, y = 1/2, w = 1/8, h = 1/2 })
