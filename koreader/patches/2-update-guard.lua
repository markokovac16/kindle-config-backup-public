-- KOReader updates: ask first. The home screen and these patches are tested against one
-- KOReader version; an update can break them, so check the new version before installing.
local ConfirmBox = require("ui/widget/confirmbox")
local OTAManager = require("ui/otamanager")
local UIManager = require("ui/uimanager")
local Version = require("version")

local TESTED = "v2026.07.1"

local orig_fetch = OTAManager.fetchAndProcessUpdate
function OTAManager:fetchAndProcessUpdate(...)
    local args = { ... }
    UIManager:show(ConfirmBox:new{
        text = "This Kindle's home screen and patches were tested on KOReader " .. TESTED
            .. " (running " .. tostring(Version:getCurrentRevision()) .. ").\n\n"
            .. "An update can break them. Test the new version first.\n\nUpdate anyway?",
        ok_text = "Update anyway",
        cancel_text = "Not now",
        ok_callback = function() orig_fetch(self, unpack(args)) end,
    })
end
