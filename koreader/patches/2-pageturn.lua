-- Smoother, Kindle-like page turns.
-- No periodic black flash (REAGL keeps ghosting low; the Refresh tile clears it on demand).
if not G_reader_settings:isTrue("no_flash_pageturn_applied") then
    G_reader_settings:saveSetting("full_refresh_count", 0)
    G_reader_settings:saveSetting("night_full_refresh_count", 0)
    G_reader_settings:makeTrue("no_flash_pageturn_applied")
end
-- The PW5's hardware page-turn animation looked jittery, keep it off.
if not G_reader_settings:isTrue("swipe_animation_off_applied") then
    G_reader_settings:makeFalse("swipe_animations")
    G_reader_settings:makeTrue("swipe_animation_off_applied")
end
-- With Amazon's framework stopped the CPU sits on "ondemand", which ramps up too late
-- for a page render; "interactive" boosts as soon as the screen is touched.
local f = io.open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "w")
if f then
    f:write("interactive")
    f:close()
end
