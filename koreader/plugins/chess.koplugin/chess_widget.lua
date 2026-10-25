local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local Engine = require("chess_engine")

local LEVELS = {
    { name = _("Easy"), opts = { max_depth = 1, noise = 200 } },
    { name = _("Medium"), opts = { max_depth = 2, noise = 40 } },
    { name = _("Hard"), opts = { time = 2.5 } },
    { name = _("Expert"), opts = { time = 8 } },
}

-- Outline glyphs for white, filled for black (FreeSerif has a clean set).
local OUTLINE = { 0x2659, 0x2658, 0x2657, 0x2656, 0x2655, 0x2654 }
local FILLED = { 0x265F, 0x265E, 0x265D, 0x265C, 0x265B, 0x265A }

local LIGHT = Blitbuffer.COLOR_WHITE
local DARK = Blitbuffer.COLOR_GRAY
local MARK = Blitbuffer.COLOR_GRAY_4

------------------------------------------------------------------------------

local Board = InputContainer:extend{
    game = nil, -- the ChessWidget
    size = nil,
}

function Board:init()
    self.sq = math.floor(self.size / 8)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sq * 8, h = self.sq * 8 }
    local px = math.floor(self.sq * 0.86)
    -- getFace scales by screen DPI; undo that so glyphs are a fixed share of the square.
    self.piece_face = Font:getFace("freefont/FreeSerif.ttf", math.floor(px * 100 / Screen:scaleBySize(100)))
    self.coord_face = Font:getFace("cfont", 11)
    self.ges_events = {
        TapBoard = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Board:squareAt(x, y)
    local col = math.floor((x - self.dimen.x) / self.sq)
    local row = math.floor((y - self.dimen.y) / self.sq)
    if col < 0 or col > 7 or row < 0 or row > 7 then return end
    if self.game.flipped then
        return Engine.sq(7 - col, row)
    end
    return Engine.sq(col, 7 - row)
end

function Board:origin(s)
    local f, r = Engine.fileOf(s), Engine.rankOf(s)
    local col, row
    if self.game.flipped then col, row = 7 - f, r else col, row = f, 7 - r end
    return self.dimen.x + col * self.sq, self.dimen.y + row * self.sq
end

function Board:blitGlyph(bb, x, y, codepoint, color)
    local glyph = RenderText:getGlyph(self.piece_face, codepoint)
    local w, h = glyph.bb:getWidth(), glyph.bb:getHeight()
    bb:colorblitFrom(glyph.bb, x + math.floor((self.sq - w) / 2), y + math.floor((self.sq - h) / 2), 0, 0, w, h, color)
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local g = self.game
    local pos, s = g.pos, self.sq
    local check_sq = pos:inCheck() and pos.kings[pos.side]
    local last_from, last_to
    if g.last then last_from, last_to = Engine.from(g.last), Engine.to(g.last) end
    local hint_from, hint_to
    if g.hint then hint_from, hint_to = Engine.from(g.hint), Engine.to(g.hint) end
    for r = 0, 7 do
        for f = 0, 7 do
            local q = Engine.sq(f, r)
            local qx, qy = self:origin(q)
            bb:paintRect(qx, qy, s, s, (f + r) % 2 == 1 and LIGHT or DARK)
            if q == last_from or q == last_to then
                bb:paintBorder(qx, qy, s, s, math.max(3, math.floor(s / 30)), MARK)
            end
            if q == hint_from or q == hint_to then
                bb:paintBorder(qx + 2, qy + 2, s - 4, s - 4, math.max(4, math.floor(s / 22)), Blitbuffer.COLOR_BLACK)
            end
            if q == g.selected then
                bb:paintBorder(qx, qy, s, s, math.max(6, math.floor(s / 16)), Blitbuffer.COLOR_BLACK)
            end
            if q == check_sq then
                bb:paintCircle(qx + s / 2, qy + s / 2, math.floor(s * 0.47), Blitbuffer.COLOR_BLACK, math.max(4, math.floor(s / 24)))
            end
            local p = pos.b[q]
            if p > 0 then
                self:blitGlyph(bb, qx, qy, FILLED[p], Blitbuffer.COLOR_WHITE)
                self:blitGlyph(bb, qx, qy, OUTLINE[p], Blitbuffer.COLOR_BLACK)
            elseif p < 0 then
                self:blitGlyph(bb, qx, qy, FILLED[-p], Blitbuffer.COLOR_BLACK)
            end
            if g.targets and g.targets[q] then
                if p ~= 0 then
                    bb:paintCircle(qx + s / 2, qy + s / 2, math.floor(s * 0.46), MARK, math.max(4, math.floor(s / 26)))
                else
                    bb:paintCircle(qx + s / 2, qy + s / 2, math.floor(s / 7), MARK)
                end
            end
        end
    end
    -- File letters along the bottom edge, rank numbers along the left edge.
    local pad = math.max(2, math.floor(s / 30))
    for i = 0, 7 do
        local f = g.flipped and 7 - i or i
        local fx, fy = self:origin(Engine.sq(f, g.flipped and 7 or 0))
        local letter = string.char(97 + f)
        local w = RenderText:sizeUtf8Text(0, s, self.coord_face, letter).x
        RenderText:renderUtf8Text(bb, fx + s - w - pad, fy + s - pad * 2, self.coord_face, letter, false, false, Blitbuffer.COLOR_GRAY_4)
        local r = g.flipped and i or 7 - i
        local rx, ry = self:origin(Engine.sq(g.flipped and 7 or 0, r))
        RenderText:renderUtf8Text(bb, rx + pad, ry + self.coord_face.size + pad, self.coord_face, tostring(r + 1), false, false, Blitbuffer.COLOR_GRAY_4)
    end
    bb:paintBorder(x, y, s * 8, s * 8, Size.border.thin, Blitbuffer.COLOR_BLACK)
end

function Board:onTapBoard(_, ges)
    local q = self:squareAt(ges.pos.x, ges.pos.y)
    if q then self.game:onSquare(q) end
    return true
end

------------------------------------------------------------------------------

local ChessWidget = InputContainer:extend{
    name = "chess",
    modal = true,
    covers_fullscreen = true,
}

function ChessWidget:init()
    self.dimen = Screen:getSize()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/chess.lua")
    self.level = self.settings:readSetting("level") or 2
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local saved = self.settings:readSetting("game")
    if saved and saved.moves then
        self:loadGame(saved.player or 1, saved.moves)
    else
        self:loadGame(1, {})
    end
    self:buildUI()
end

function ChessWidget:loadGame(player, moves)
    self.player = player
    self.flipped = player == -1
    self.pos = Engine.newPosition()
    self.moves, self.sans = {}, {}
    self.keys = { self.pos:key() }
    self.selected, self.targets, self.hint, self.last = nil, nil, nil, nil
    for _, m in ipairs(moves) do
        if not self:applyMove(m, true) then break end
    end
    self:updateOutcome()
end

-- Plays a move if it is legal in the current position.
function ChessWidget:applyMove(m, quiet)
    local legal = self.pos:legalMoves()
    local ok = false
    for _, l in ipairs(legal) do if l == m then ok = true break end end
    if not ok then return false end
    self.sans[#self.sans + 1] = self.pos:san(m, legal)
    self.pos:make(m)
    self.moves[#self.moves + 1] = m
    self.keys[#self.keys + 1] = self.pos:key()
    self.last = m
    if not quiet then self:save() end
    return true
end

function ChessWidget:save()
    self.settings:saveSetting("game", { player = self.player, moves = self.moves })
    self.settings:saveSetting("level", self.level)
    self.settings:flush()
end

function ChessWidget:updateOutcome()
    local pos = self.pos
    self.over = nil
    if #pos:legalMoves() == 0 then
        if pos:inCheck() then
            self.over = pos.side == self.player and _("Checkmate. The computer wins.") or _("Checkmate. You win!")
        else
            self.over = _("Stalemate. It's a draw.")
        end
    elseif pos.half >= 100 then
        self.over = _("Draw by the fifty-move rule.")
    elseif pos:insufficientMaterial() then
        self.over = _("Draw: not enough pieces to mate.")
    else
        local current, count = self.keys[#self.keys], 0
        for _, k in ipairs(self.keys) do if k == current then count = count + 1 end end
        if count >= 3 then self.over = _("Draw by threefold repetition.") end
    end
end

function ChessWidget:statusText()
    if self.over then return self.over end
    if self.thinking then return _("Computer is thinking…") end
    if self.pos.side ~= self.player then return "" end
    local text = _("Your move")
    if self.pos:inCheck() then text = _("Check! Your move") end
    if self.last and #self.moves > 0 then
        text = text .. "  ·  " .. _("computer played") .. " " .. self.sans[#self.sans]
    end
    return text
end

function ChessWidget:moveListText()
    local parts = {}
    local first = math.max(1, #self.sans - 7)
    if first % 2 == 0 then first = first - 1 end -- start on a white move
    for i = first, #self.sans do
        if i % 2 == 1 then parts[#parts + 1] = ((i + 1) / 2) .. "." end
        parts[#parts + 1] = self.sans[i]
    end
    return table.concat(parts, " ")
end

function ChessWidget:buildUI()
    local w, h = self.dimen.w, self.dimen.h
    self.title_bar = TitleBar:new{
        width = w,
        title = _("Chess"),
        subtitle = string.format(_("You play %s  ·  %s"), self.player == 1 and _("white") or _("black"), LEVELS[self.level].name),
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
    }
    self.status = TextWidget:new{ text = self:statusText(), face = Font:getFace("cfont", 20), bold = true, max_width = w - 2 * Size.padding.large }
    self.move_list = TextWidget:new{ text = self:moveListText(), face = Font:getFace("cfont", 16), fgcolor = Blitbuffer.COLOR_GRAY_4, max_width = w - 2 * Size.padding.large }
    self.buttons = ButtonTable:new{
        width = w - 2 * Size.padding.large,
        buttons = {{
            { text = _("New game"), callback = function() self:askNewGame() end },
            { text = _("Undo"), callback = function() self:undo() end },
            { text = _("Hint"), callback = function() self:showHint() end },
            { text = _("Level"), callback = function() self:askLevel() end },
        }},
    }
    local gap = Size.padding.large
    local fixed = self.title_bar:getHeight() + self.status:getSize().h + self.move_list:getSize().h + self.buttons:getSize().h + gap * 5
    local board_size = math.min(w - 2 * gap, h - fixed)
    self.board = Board:new{ game = self, size = board_size }
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.title_bar,
            VerticalSpan:new{ width = gap },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.status:getSize().h }, self.status },
            VerticalSpan:new{ width = gap },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.board.dimen.h }, self.board },
            VerticalSpan:new{ width = gap },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.move_list:getSize().h }, self.move_list },
            VerticalSpan:new{ width = gap },
            self.buttons,
        },
    }
end

function ChessWidget:refresh(mode)
    self.status:setText(self:statusText())
    self.move_list:setText(self:moveListText())
    UIManager:setDirty(self, mode or "ui")
end

function ChessWidget:onShow()
    UIManager:setDirty(self, "full")
    self:maybeComputerMove()
end

function ChessWidget:onSquare(q)
    if self.thinking or self.over or self.pos.side ~= self.player then return end
    local pos = self.pos
    if self.selected and self.targets and self.targets[q] then
        local options = self.targets[q]
        if #options > 1 then
            self:askPromotion(options)
        else
            self:playerMove(options[1])
        end
        return
    end
    local p = pos.b[q]
    if p ~= 0 and p * self.player > 0 and q ~= self.selected then
        self.selected, self.targets = q, {}
        for _, m in ipairs(pos:legalMoves()) do
            if Engine.from(m) == q then
                local to = Engine.to(m)
                self.targets[to] = self.targets[to] or {}
                table.insert(self.targets[to], m)
            end
        end
    else
        self.selected, self.targets = nil, nil
    end
    self:refresh()
end

function ChessWidget:askPromotion(options)
    local dialog
    local names = { [Engine.Q] = _("Queen"), [Engine.R] = _("Rook"), [Engine.B] = _("Bishop"), [Engine.N] = _("Knight") }
    local row = {}
    for _, kind in ipairs({ Engine.Q, Engine.R, Engine.B, Engine.N }) do
        for _, m in ipairs(options) do
            if Engine.promo(m) == kind then
                row[#row + 1] = { text = names[kind], callback = function()
                    UIManager:close(dialog)
                    self:playerMove(m)
                end }
            end
        end
    end
    dialog = ButtonDialog:new{ title = _("Promote to"), title_align = "center", buttons = { row } }
    UIManager:show(dialog)
end

function ChessWidget:playerMove(m)
    self.selected, self.targets, self.hint = nil, nil, nil
    self:applyMove(m)
    self:updateOutcome()
    if self.over then
        self:refresh()
        UIManager:show(InfoMessage:new{ text = self.over })
        return
    end
    self:maybeComputerMove()
end

function ChessWidget:maybeComputerMove()
    if self.over or self.pos.side == self.player then
        self:refresh()
        return
    end
    self.thinking = true
    self:refresh()
    -- Let the screen show the player's move before the search blocks the UI.
    UIManager:scheduleIn(0.3, function()
        if not self.thinking then return end -- closed or undone meanwhile
        local opts = util.tableDeepCopy(LEVELS[self.level].opts)
        opts.history = { unpack(self.keys, 1, #self.keys - 1) }
        local m = Engine.think(self.pos, opts)
        self.thinking = false
        if m then self:applyMove(m) end
        self:updateOutcome()
        self:refresh()
        if self.over then UIManager:show(InfoMessage:new{ text = self.over }) end
    end)
end

function ChessWidget:undo()
    if self.thinking then return end
    local moves = { unpack(self.moves) }
    if #moves == 0 then return end
    -- Take back to the previous position where it was your move.
    table.remove(moves)
    if #moves > 0 and (#moves % 2 == 0) ~= (self.player == 1) then table.remove(moves) end
    self:loadGame(self.player, moves)
    self:save()
    self:maybeComputerMove()
end

function ChessWidget:showHint()
    if self.thinking or self.over or self.pos.side ~= self.player then return end
    self.status:setText(_("Looking for a good move…"))
    UIManager:setDirty(self, "ui")
    UIManager:scheduleIn(0.3, function()
        self.hint = Engine.think(self.pos, { time = 2.5, history = { unpack(self.keys, 1, #self.keys - 1) } })
        self.selected, self.targets = nil, nil
        self:refresh()
    end)
end

function ChessWidget:askNewGame()
    if self.thinking then return end
    local dialog
    local function start(player)
        UIManager:close(dialog)
        if player == 0 then player = math.random(2) == 1 and 1 or -1 end
        self:loadGame(player, {})
        self:save()
        self:rebuild()
        self:maybeComputerMove()
    end
    dialog = ButtonDialog:new{
        title = _("New game"), title_align = "center",
        buttons = {
            { { text = _("Play white"), callback = function() start(1) end },
              { text = _("Play black"), callback = function() start(-1) end } },
            { { text = _("Random side"), callback = function() start(0) end } },
        },
    }
    UIManager:show(dialog)
end

function ChessWidget:askLevel()
    if self.thinking then return end
    local dialog
    local row = {}
    for i, level in ipairs(LEVELS) do
        row[#row + 1] = { text = (i == self.level and "✓ " or "") .. level.name, callback = function()
            UIManager:close(dialog)
            self.level = i
            self:save()
            self:rebuild()
        end }
    end
    dialog = ButtonDialog:new{ title = _("Computer strength"), title_align = "center", buttons = { row } }
    UIManager:show(dialog)
end

function ChessWidget:rebuild()
    self:buildUI()
    UIManager:setDirty(self, "full")
end

function ChessWidget:onClose()
    self.thinking = false
    self:save()
    UIManager:close(self, "full")
    return true
end

return ChessWidget
