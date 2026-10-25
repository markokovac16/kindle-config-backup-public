-- Auto warmth follows the sun (applied once; change later under Settings -> Auto warmth).
-- Dark mode is never switched on by itself: warmth only, dark mode stays manual.
-- Set LOCATION to where you are; until then this patch does nothing.
local LOCATION = nil -- e.g. { name = "London", lat = 51.51, lon = -0.13, alt = 11 }

if LOCATION and not G_reader_settings:isTrue("night_light_applied") then
    G_reader_settings:saveSetting("autowarmth_activate", 1) -- follow the sun
    G_reader_settings:makeFalse("autowarmth_easy_mode")
    G_reader_settings:saveSetting("autowarmth_location", LOCATION.name)
    G_reader_settings:saveSetting("autowarmth_latitude", LOCATION.lat)
    G_reader_settings:saveSetting("autowarmth_longitude", LOCATION.lon)
    G_reader_settings:saveSetting("autowarmth_altitude", LOCATION.alt or 0)
    -- Warmth points: midnight, astro/nautical/civil dawn, sunrise, noon, sunset, civil/nautical/astro dusk, midnight.
    G_reader_settings:saveSetting("autowarmth_warmth", { 100, 100, 75, 50, 25, 0, 25, 50, 75, 100, 100 })
    G_reader_settings:makeTrue("autowarmth_control_warmth")
    G_reader_settings:makeFalse("autowarmth_control_nightmode")
    -- The quick settings Dark mode tile is a manual override, so no nag dialog on it.
    G_reader_settings:makeTrue("autowarmth_hide_nightmode_warning")
    G_reader_settings:makeTrue("night_light_applied")
end
