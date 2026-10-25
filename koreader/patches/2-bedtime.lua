-- Bedtime dimming: the first time the light is on after 21:00, it's lowered once, to 60% of
-- what it was. Nothing else happens that night, whatever brightness gets picked after that.
-- In the morning the old level comes back, but only if the light is still exactly where the
-- dimming left it (a level chosen by hand is never undone).
local Device = require("device")
local UIManager = require("ui/uimanager")
local logger = require("logger")

if not Device:hasFrontlight() then return end
local powerd = Device.powerd

local EVENING, MORNING = 21, 6 -- hours
local FACTOR = 0.6
local TICK = 300 -- seconds between checks while awake

local function tick()
    local now = os.time()
    local hour = os.date("*t", now).hour
    local st = G_reader_settings:readSetting("bedtime_dimming") or {}
    if powerd:isFrontlightOff() then return end -- asleep or switched off; check again later
    local cur = powerd:frontlightIntensity()
    if hour >= EVENING or hour < MORNING then
        -- An evening and the early hours after it are one night.
        local night = os.date("%Y-%m-%d", now - MORNING * 3600)
        if st.night == night then return end
        local target = math.max(1, math.floor(cur * FACTOR + 0.5))
        if target < cur then powerd:setIntensity(target) end
        G_reader_settings:saveSetting("bedtime_dimming",
            { night = night, base = cur, dimmed = powerd:frontlightIntensity() })
    elseif st.night then
        if cur == st.dimmed and st.base > cur then powerd:setIntensity(st.base) end
        G_reader_settings:delSetting("bedtime_dimming")
    end
end

local function safeTick()
    local ok, err = pcall(tick)
    if not ok then logger.warn("bedtime dimming:", err) end
end

local function loop()
    safeTick()
    UIManager:scheduleIn(TICK, loop)
end
UIManager:scheduleIn(5, loop)

-- Waking up at night should dim straight away rather than at the next check.
local afterResume = Device._afterResume
Device._afterResume = function(self, ...)
    afterResume(self, ...)
    UIManager:scheduleIn(2, safeTick)
end
