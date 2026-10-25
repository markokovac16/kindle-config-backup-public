-- Darker, Kindle-like text defaults (applied once; change freely in the UI afterwards).
-- Contrast index 25 = gamma 1.45, font weight +0.5.
if not G_reader_settings:isTrue("kindle_like_text_applied") then
    G_reader_settings:saveSetting("copt_font_gamma", 25)
    G_reader_settings:saveSetting("copt_font_base_weight", 0.5)
    G_reader_settings:makeTrue("kindle_like_text_applied")
end
-- Default font size 12 (applied once).
if not G_reader_settings:isTrue("font_size_12_applied") then
    G_reader_settings:saveSetting("copt_font_size", 12)
    G_reader_settings:makeTrue("font_size_12_applied")
end
-- Sleep screen: cover of the current book, no "Sleeping" text (applied once).
if not G_reader_settings:isTrue("cover_sleep_screen_applied") then
    G_reader_settings:saveSetting("screensaver_type", "cover")
    G_reader_settings:makeFalse("screensaver_show_message")
    G_reader_settings:saveSetting("screensaver_img_background", "white")
    G_reader_settings:makeTrue("cover_sleep_screen_applied")
end
-- Bigger rendering cache so laid-out books stay cached (applied once).
if not G_reader_settings:isTrue("cre_cache_256_applied") then
    G_reader_settings:saveSetting("cre_disk_cache_max_size", 256)
    G_reader_settings:makeTrue("cre_cache_256_applied")
end
-- Kindle-home-like library: cover grid everywhere (applied once).
if not G_reader_settings:isTrue("cover_grid_library_applied") then
    G_reader_settings:saveSetting("filemanager_display_mode", "mosaic_image")
    G_reader_settings:saveSetting("history_display_mode", "mosaic_image")
    G_reader_settings:saveSetting("collection_display_mode", "mosaic_image")
    G_reader_settings:makeTrue("cover_grid_library_applied")
end
-- SSH starts with KOReader, public-key login only (applied once).
if not G_reader_settings:isTrue("ssh_autostart_applied") then
    G_reader_settings:makeTrue("SSH_autostart")
    G_reader_settings:makeTrue("SSH_key_only_auth")
    G_reader_settings:makeTrue("ssh_autostart_applied")
end
