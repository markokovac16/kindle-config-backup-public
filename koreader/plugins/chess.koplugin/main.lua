local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Chess = WidgetContainer:extend{
    name = "chess",
    is_doc_only = false,
}

function Chess:init()
    Dispatcher:registerAction("chess_start", { category = "none", event = "StartChess", title = _("Chess"), general = true })
    self.ui.menu:registerToMainMenu(self)
end

function Chess:onStartChess()
    self:startGame()
    return true
end

function Chess:addToMainMenu(menu_items)
    menu_items.chess = {
        text = _("Chess"),
        sorting_hint = "tools",
        callback = function() self:startGame() end,
    }
end

function Chess:startGame()
    -- Loaded on first use, so the engine costs nothing at startup.
    local ChessWidget = require("chess_widget")
    UIManager:show(ChessWidget:new{})
end

return Chess
