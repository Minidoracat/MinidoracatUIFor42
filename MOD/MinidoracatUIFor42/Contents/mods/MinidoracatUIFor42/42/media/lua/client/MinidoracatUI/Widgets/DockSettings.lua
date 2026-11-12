-- MinidoracatUI Widgets/DockSettings -- the toolbar settings window (API rev 27, opened by Widgets/Dock.lua).
--
-- Internal module: Dock.lua requires it and hands it a model (a table of functions). It is not on the
-- facade and knows nothing about the dock's records; contract in docs/ARCHITECTURE.md section 3.16.
--   layout, idle opacity: one UI.Dropdown each (the label sits beside it, or above it when a translation is wide)
--   entries: one UI.Checkbox per available entry inside a UI.ScrollPanel, the entry's icon to its left;
--            a change takes effect at once and the window stays open
--   Show all, Reset position: the two actions that used to need the mouse
-- Every control is a UI.Focus target, so keyboard and joypad reach all of it (the dock's hotkey session
-- opens the window from the handle). The window opens beside the dock on the screen-centre side.
--
-- model: count() / name(i) / isShown(i) / setShown(i, bool) / showAll() / drawIcon(el, i, x, y, size) /
--        revision() (changes when the rows or a tick changed) / layout() / setLayout(id) / opacity() /
--        setOpacity(id) / resetPosition() / rect() -> x, y, w, h, growLeft (the dock on screen)
-- Per-frame paths allocate no tables or closures. String literals are ASCII only; visible text is from Translate.

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme) or not ISPanel then
    return nil
end
if not UI.Window then pcall(require, "MinidoracatUI/Widgets/Window") end
if not UI.Button then pcall(require, "MinidoracatUI/Widgets/Controls") end
if not UI.Dropdown then pcall(require, "MinidoracatUI/Widgets/Dropdown") end
if not UI.ScrollPanel then pcall(require, "MinidoracatUI/Widgets/ScrollPanel") end
if not (UI.Window and UI.Button and UI.Checkbox and UI.Dropdown and UI.ScrollPanel and UI.Text and UI.Text.wrap
    and UI.Text.fit) then
    return nil -- the dock keeps its menu; only the window is missing
end

local Text = UI.Text
local Focus = UI.Focus

local WIN_W = 300
local PAD = 10
local GAP = 8
local ICON = 22
local MAX_ROWS = 10
local SIDE_GAP = 8
local TOGGLE_RESERVE = 44 -- Checkbox: switch 36 + label gap 8 (Controls.lua)

local Settings = {}
local win = nil

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text)
end

local function onToggle(w, checked, box) w._model.setShown(box._index, checked) end
local function onLayout(w, id) w._model.setLayout(id) end
local function onOpacity(w, id) w._model.setOpacity(id) end
local function onShowAll(w) w._model.showAll() end
local function onReset(w) w._model.resetPosition() end

-- label beside the dropdown; above it when both do not fit one line. Returns the y of the next row.
local function placeRow(w, row, dd, y)
    row.x = PAD
    if PAD + measure(w.font, row.text) + GAP + dd.width <= WIN_W - PAD then
        dd:setX(WIN_W - PAD - dd.width)
        dd:setY(y)
        row.y = y + math.floor((dd.height - w._fontH) / 2)
        return y + dd.height + GAP
    end
    row.y = y
    dd:setX(PAD)
    dd:setY(y + w._fontH + 2)
    return y + w._fontH + 2 + dd.height + GAP
end

local function layout(w, n)
    local fontH = w._fontH
    local y = placeRow(w, w._rowLayout, w.ddLayout, w:contentTop() + PAD)
    y = placeRow(w, w._rowOpacity, w.ddOpacity, y)
    w._rowEntries.x, w._rowEntries.y = PAD, y
    y = y + fontH + 4
    local listH = math.min(n, MAX_ROWS) * w._rowH
    w.scroll:setX(PAD)
    w.scroll:setY(y)
    w.scroll:setHeight(listH)
    y = y + listH + GAP
    w.btnAll:setX(PAD)
    w.btnAll:setY(y)
    local resetX = PAD + w.btnAll.width + GAP
    if resetX + w.btnReset.width > WIN_W - PAD then
        y = y + w.btnAll.height + 4 -- long translations: the second button drops to its own line
        resetX = PAD
    end
    w.btnReset:setX(resetX)
    w.btnReset:setY(y)
    y = y + w.btnReset.height + GAP
    w._hintY = y
    y = y + fontH * #w._hintLines + PAD
    w:setHeight(y)
    w.body:setHeight(y - w.body:getY())
end

-- rows follow the model: one tick box per entry (boxes are reused, spare ones hidden)
local function rebuild(w)
    local m = w._model
    local n = m.count()
    local boxes = w._boxes
    local boxW = w.scroll:contentWidth() - (ICON + GAP)
    local shownN = 0
    for i = 1, n do
        local box = boxes[i]
        if box == nil then
            box = UI.Checkbox.new({ x = ICON + GAP, y = 0, width = boxW, height = w._rowH, label = "",
                theme = w.theme, target = w, onChange = onToggle })
            box._index = i
            w.scroll:addChild(box)
            boxes[i] = box
        end
        local name = m.name(i)
        local fitted = Text.fit(name, boxW - TOGGLE_RESERVE, w.font)
        box:setLabel(fitted)
        box:setTooltip(fitted ~= name and name or nil) -- the full name when it was cut
        local on = m.isShown(i)
        if on then shownN = shownN + 1 end
        box:setChecked(on, true)
        box:setY((i - 1) * w._rowH)
        box:setVisible(true)
    end
    for i = n + 1, #boxes do boxes[i]:setVisible(false) end
    w.icons._n = n
    w.icons:setHeight(n * w._rowH)
    w._rowEntries.text = getText("IGUI_MinidoracatUI_Dock_Entries", tostring(shownN), tostring(n))
    w.btnAll:setEnabled(shownN < n)
    w._rev = m.revision()
    layout(w, n)
end

-- static text, and the per-frame check against the model (setters are no-ops for the same value)
local Body = ISPanel:derive("MinidoracatUIDockSettingsBody")

-- rows keep window coordinates; the body starts under the title bar
local function drawRow(self, row, c)
    self:drawText(row.text, row.x, row.y - self:getY(), c.r, c.g, c.b, c.a, self.win.font)
end

function Body:prerender()
    local w = self.win
    local m = w._model
    if m.revision() ~= w._rev then rebuild(w) end
    w.ddLayout:setSelected(m.layout(), true)
    w.ddOpacity:setSelected(m.opacity(), true)
    local c = w.theme.colors
    drawRow(self, w._rowLayout, c.text)
    drawRow(self, w._rowOpacity, c.text)
    drawRow(self, w._rowEntries, c.textMuted)
    local muted, lines = c.textMuted, w._hintLines
    for i = 1, #lines do
        self:drawText(lines[i], PAD, w._hintY - self:getY() + (i - 1) * w._fontH, muted.r, muted.g, muted.b, muted.a, w.font)
    end
end

local IconColumn = ISPanel:derive("MinidoracatUIDockSettingsIcons")

function IconColumn:prerender()
    local w = self.win
    local off = math.floor((w._rowH - ICON) / 2)
    for i = 1, self._n do
        w._model.drawIcon(self, i, 0, (i - 1) * w._rowH + off, ICON)
    end
end

-- Esc while the focus ring is on the window: close when Esc is released, so the release never reaches
-- the game (pause menu); same pattern as the notification history window
local function onEscapeWindow(w)
    if Focus then Focus.close(w) else w:close() end
    return true
end

local function option(id, key)
    return { id = id, label = getText(key) }
end

local function create(model)
    local theme = UI.Theme.create()
    local w = UI.Window.new({ x = 0, y = 0, width = WIN_W, height = 200, theme = theme,
        title = getText("IGUI_MinidoracatUI_Dock_Settings") })
    w._model = model
    w._boxes = {}
    w._rowH = math.max(24, w._fontH + 6)
    w._rowLayout = { text = getText("IGUI_MinidoracatUI_Dock_SettingsLayout"), x = 0, y = 0 }
    w._rowOpacity = { text = getText("IGUI_MinidoracatUI_Dock_Opacity"), x = 0, y = 0 }
    w._rowEntries = { text = "", x = 0, y = 0 }
    w._hintLines = Text.wrap(getText("IGUI_MinidoracatUI_Dock_SettingsHint"), WIN_W - PAD * 2, w.font)
    w._hintY = 0
    w.onEscape = onEscapeWindow
    local body = ISPanel.new(Body, 0, w:contentTop(), WIN_W, 200) -- under the title bar: dragging stays the window's
    body.background = false
    body.win = w
    body:initialise()
    w:addChild(body) -- first child: everything else sits above it
    w.body = body
    w.ddLayout = UI.Dropdown.new({ theme = theme, target = w, onChange = onLayout, selected = model.layout(),
        options = { option(1, "IGUI_MinidoracatUI_Dock_LayoutColumn"), option(2, "IGUI_MinidoracatUI_Dock_LayoutRow"),
            option(3, "IGUI_MinidoracatUI_Dock_LayoutGrid") } })
    w.ddOpacity = UI.Dropdown.new({ theme = theme, target = w, onChange = onOpacity, selected = model.opacity(),
        options = { option(1, "IGUI_MinidoracatUI_Dock_Opacity100"), option(2, "IGUI_MinidoracatUI_Dock_Opacity75"),
            option(3, "IGUI_MinidoracatUI_Dock_Opacity50"), option(4, "IGUI_MinidoracatUI_Dock_Opacity25") } })
    w:addChild(w.ddLayout)
    w:addChild(w.ddOpacity)
    w.scroll = UI.ScrollPanel.new({ width = WIN_W - PAD * 2, height = w._rowH, theme = theme })
    w:addChild(w.scroll)
    local icons = ISPanel.new(IconColumn, 0, 0, ICON, w._rowH)
    icons.background = false
    icons.win, icons._n = w, 0
    icons:initialise()
    w.scroll:addChild(icons)
    w.icons = icons
    w.btnAll = UI.Button.new({ x = PAD, y = 0, title = getText("IGUI_MinidoracatUI_Dock_ShowAll"),
        theme = theme, target = w, onClick = onShowAll })
    w.btnReset = UI.Button.new({ x = PAD, y = 0, title = getText("IGUI_MinidoracatUI_Dock_ResetPosition"),
        theme = theme, target = w, onClick = onReset })
    w:addChild(w.btnAll)
    w:addChild(w.btnReset)
    rebuild(w)
    w:addToUIManager()
    return w
end

-- beside the dock on the screen-centre side, inside the screen
local function place(w)
    local core = getCore()
    local x, y, dw, _, growLeft = w._model.rect()
    if x == nil then return end
    local wx = growLeft and (x - WIN_W - SIDE_GAP) or (x + dw + SIDE_GAP)
    w:setX(math.max(0, math.min(wx, core:getScreenWidth() - WIN_W)))
    w:setY(math.max(0, math.min(y, core:getScreenHeight() - w.height)))
end

-- ring = true: the keyboard opened it, so the focus ring starts on the first control
function Settings.open(model, ring)
    if win == nil then
        win = create(model)
    else
        win._model = model
        rebuild(win)
        win:setVisible(true)
        win:bringToTop()
    end
    place(win)
    if ring and Focus then Focus.focusControl(win.ddLayout, true) end
end

function Settings.close()
    if win and win:getIsVisible() then win:close() end
end

function Settings.isOpen()
    return win ~= nil and win:getIsVisible()
end

-- tests only
function Settings._resetForTests()
    if win then win:removeFromUIManager() end
    win = nil
end
function Settings._windowForTests() return win end

return Settings
