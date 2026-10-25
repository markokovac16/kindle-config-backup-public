package.path = arg[1] .. "/?.lua;" .. package.path
local Class = {}
function Class:extend(o) o = o or {}; o.__index = o; return setmetatable(o, { __index = self }) end
function Class:new(o) o = o or {}; setmetatable(o, { __index = self }); if o.init then o:init() end; return o end
function Class:getSize() return { w = 100, h = 40 } end
function Class:getHeight() return 80 end
function Class:setText(t) self.text = t end
local function cls() return Class:extend{} end
local tasks, shown, dialogs = {}, {}, {}
local store = {}
local stubs = {
    ["ffi/blitbuffer"] = setmetatable({}, { __index = function() return {} end }),
    ["ui/widget/buttondialog"] = Class:extend{ init = function(self) table.insert(dialogs, self) end },
    ["ui/widget/buttontable"] = cls(), ["ui/widget/container/centercontainer"] = cls(),
    ["ui/widget/container/framecontainer"] = cls(), ["ui/widget/container/inputcontainer"] = cls(),
    ["ui/widget/textwidget"] = cls(), ["ui/widget/titlebar"] = cls(), ["ui/widget/verticalgroup"] = cls(),
    ["ui/widget/verticalspan"] = cls(), ["ui/widget/infomessage"] = cls(),
    ["ui/geometry"] = cls(), ["ui/gesturerange"] = cls(),
    ["datastorage"] = { getSettingsDir = function() return "/x" end },
    ["device"] = { hasKeys = function() return false end, screen = { getSize = function() return { w = 1236, h = 1648 } end, scaleBySize = function(_, v) return v * 2 end } },
    ["ui/font"] = { getFace = function(_, n, s) return { size = s } end },
    ["luasettings"] = { open = function() return { readSetting = function(_, k) return store[k] end, saveSetting = function(_, k, v) store[k] = v end, flush = function() end } end },
    ["ui/rendertext"] = {}, ["ui/size"] = { padding = { large = 10 }, border = { thin = 1 } },
    ["ui/uimanager"] = { show = function(_, w) table.insert(shown, w) end, close = function() end, setDirty = function() end,
        scheduleIn = function(_, _, f) table.insert(tasks, f) end },
    ["util"] = { tableDeepCopy = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end },
    ["gettext"] = function(s) return s end,
}
for name, mod in pairs(stubs) do package.loaded[name] = mod end
local function runTasks() while #tasks > 0 do table.remove(tasks, 1)() end end
local E = require("chess_engine")
local W = require("chess_widget")
local fails = 0
local function check(n, c, x) print((c and "OK   " or "FAIL ") .. n .. (x and ("  " .. tostring(x)) or "")); if not c then fails = fails + 1 end end
local function S(name) return E.sq(name:byte(1) - 97, name:byte(2) - 49) end
local function clickDialog(label) local d = dialogs[#dialogs]; for _, row in ipairs(d.buttons) do for _, b in ipairs(row) do if b.text:find(label, 1, true) then b.callback(); return true end end end end

local w = W:new{}
w:onShow(); runTasks()
check("new game: white to move, no moves", #w.moves == 0 and w.pos.side == 1 and w.player == 1)
w:onSquare(S"e2"); check("select e2 shows 2 targets", w.targets and w.targets[S"e3"] and w.targets[S"e4"] and true)
w:onSquare(S"e4"); check("thinking after player move", w.thinking == true, w:statusText())
runTasks()
check("computer replied", #w.moves == 2 and w.pos.side == 1 and not w.thinking, w.sans[1] .. " " .. tostring(w.sans[2]))
check("status mentions computer move", w:statusText():find("computer played", 1, true) ~= nil, w:statusText())
w:onSquare(S"e4"); w:onSquare(S"e4"); check("tap selected again deselects", w.selected == nil)
w:onSquare(S"a7"); check("can't select enemy piece", w.selected == nil)
w:onSquare(S"g1"); w:onSquare(S"f3"); runTasks()
check("second exchange", #w.moves == 4)
check("move list", w:moveListText():match("^1%. e4 %S+ 2%. Nf3 %S+$") ~= nil, w:moveListText())
-- Resume from save
local w2 = W:new{}; check("save/resume restores moves", #w2.moves == 4 and w2:moveListText() == w:moveListText())
w:undo(); runTasks(); check("undo takes back a full move", #w.moves == 2 and w.pos.side == 1, #w.moves)
w:undo(); w:undo(); runTasks(); check("undo to start", #w.moves == 0)
-- Play black
w:askNewGame(); clickDialog("Play black"); runTasks()
check("as black: computer opens", w.player == -1 and #w.moves == 1 and w.pos.side == -1 and w.flipped, w.sans[1])
w:undo(); runTasks(); check("undo as black lets computer replay its first move", #w.moves == 1 and w.pos.side == -1)
-- Level change persists
w:askLevel(); clickDialog("Expert"); check("level saved", store.level == 4)
w:askLevel(); clickDialog("Easy")
-- Promotion via dialog
w:loadGame(1, {}); w.pos = E.newPosition("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"); w.keys = { w.pos:key() }
w:onSquare(S"b7"); check("promotion square offers 4 moves", w.targets[S"b8"] and #w.targets[S"b8"] == 4)
w:onSquare(S"b8"); check("promotion dialog shown", dialogs[#dialogs].title == "Promote to")
clickDialog("Knight"); check("underpromotion to knight", w.pos.b[S"b8"] == E.N, w.sans[#w.sans]); runTasks()
-- Game-over detection
w.pos = E.newPosition("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1"); w.keys = { w.pos:key() }; w:updateOutcome()
check("checkmate, you win", w.over == "Checkmate. You win!", w.over)
w.pos = E.newPosition("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"); w:updateOutcome(); check("stalemate", w.over and w.over:find("Stalemate") ~= nil, w.over)
w.pos = E.newPosition("7k/8/6K1/8/8/8/8/8 b - - 0 1"); w:updateOutcome(); check("insufficient material", w.over and w.over:find("not enough") ~= nil, w.over)
w.pos = E.newPosition("7k/8/6K1/8/8/8/8/R7 b - - 100 80"); w:updateOutcome(); check("fifty-move", w.over and w.over:find("fifty") ~= nil, w.over)
w.pos = E.newPosition("7k/8/6K1/8/8/8/8/R7 b - - 0 1"); local k = w.pos:key(); w.keys = { k, "x", k, "y", k }; w:updateOutcome(); check("threefold", w.over and w.over:find("threefold") ~= nil, w.over)
w:onSquare(S"h8"); check("no moves accepted after game over", w.selected == nil)
-- Repetition: replaying knight moves draws by threefold
w:loadGame(1, {})
local seq = { "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" }
local ms = {}
for _, mv in ipairs(seq) do
    for _, l in ipairs(w.pos:legalMoves()) do if E.from(l) == S(mv:sub(1, 2)) and E.to(l) == S(mv:sub(3, 4)) then w:applyMove(l, true); break end end
end
w:updateOutcome(); check("knight shuffle = threefold repetition", w.over and w.over:find("threefold") ~= nil, w.over)
print(fails == 0 and "ALL WIDGET TESTS OK" or (fails .. " FAILURES"))
