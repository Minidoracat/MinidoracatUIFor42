-- MinidoracatUI Widgets/Dock -- shared collapsible family toolbar (API rev 13, CAPABILITIES.dock).
--
-- Contract (binding for the framework and every consumer): docs/ARCHITECTURE.md section 3.16.
-- Consumers register entries with UI.Dock.register(spec); one dock panel for player 0 shows every
-- available entry in (order, id) order. 0 entries: hidden. 1 entry: that button alone, no handle.
-- 2+ entries: mascot handle on top (click = collapse/expand) and a vertical strip of 40x40 buttons.
--
-- Proven pieces reused from Widgets/FloatButton.lua (same constants and semantics):
--   * setCapture drag with an absolute-mouse 4px threshold; pressing the handle or any entry
--     moves the whole dock, release under the threshold = click, release after a drag = save
--   * right-click down/up pairing with an 800ms expiry; no right-click while left-dragging
--   * one ISToolTip, rebuilt at most every 500ms, hidden while pressing
--   * per-frame clamp to the screen; hides itself without player 0 (main menu)
--   * alwaysOnTop = false through the native setter after addToUIManager (ARCHITECTURE 3.4)
-- Position and collapsed state persist through ISLayoutManager key "MinidoracatUIDock": the funcs
-- table is RegisterWindow's 2nd argument, called as funcs.RestoreLayout(target, name, layout)
-- (ISLayoutManager.lua:6-13,99-113); OnPostSave writes layout.ini (:191-229).
-- Default position: left of the vanilla moodle column (MoodlesUI.getTextureSizeForOption,
-- MoodlesUI.java:72-86; column x = screenW - (10 + size), UIManager.java:417).
--
-- Keyboard: keyBinding MinidoracatUI_Dock. Pressing it expands (remembering a collapsed state)
-- and makes the dock a UI.Focus root: arrows move between entries, Enter activates, Esc gives
-- focus back and re-collapses. Pressing it again gives focus back. Without UI.Focus the key only
-- toggles collapse. Joypad: "open family toolbar" in the world context menu (joypad players
-- only) hands joypad focus to the dock; B gives it back; activating an entry gives it back first.
--
-- Hot paths (prerender/render, keyboardTargets, toast avoid fn) allocate no tables or closures;
-- consumer callbacks are called through pcall with arguments. String literals are ASCII only
-- (Kahlua truncates non-ASCII); every visible text comes from Translate.

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Icons) or not ISPanel or not ISButton then
    return -- core or native bases missing: no capability (consumers probe CAPABILITIES.dock)
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
local Focus = UI.Focus -- optional: without it the hotkey only toggles collapse
local Skin, Icons = UI.Skin, UI.Icons

local Dock = {}
local DockPanel = ISPanel:derive("MinidoracatUIDock")
local DockButton = ISButton:derive("MinidoracatUIDockButton")

local CELL = 40
local GAP = 4
local PAD = 4
local ICON = 28
local MASCOT = 32
local CHEVRON = 20
local ACTIVE_BAR = 3
local CHIP = 14
local DOT = 8
local DRAG_THRESHOLD = 4
local RIGHT_CLICK_EXPIRE_MS = 800
local TOOLTIP_THROTTLE_MS = 500
local POLL_MS = 250
local DEFAULT_Y = 120
local MOODLE_EDGE = 10 -- UIManager.java:417 setX(sw - (10 + width))
local MOODLE_GAP = 12
local MOODLE_SIZES = { 32, 48, 64, 80, 96, 128 } -- MoodlesUI.textureSizes, option 1-6
local LAYOUT_KEY = "MinidoracatUIDock"
local BIND = "MinidoracatUI_Dock"
local MASCOT_SLEEP = "media/ui/MinidoracatUI/mui_mascot_sleep.png"
local MASCOT_AWAKE = "media/ui/MinidoracatUI/mui_mascot_awake.png"

local records = {} -- id -> { spec, button, tex, badgeN, badgeText, badgeW }
local sorted = {}  -- every record, (order, id)
local shown = {}   -- available records, same order; rebuilt in place
local panel = nil
local dirty = true
local nextPoll = 0
local mascotProbed, mascotSleep, mascotAwake = false, nil, nil
local fontH = nil
local endFocus -- forward: entry activation ends a joypad session before calling onClick

-- ---------- consumer callbacks (pcall; an error counts as nil/false) ----------

local function truthy(fn, default)
    if fn == nil then return default end
    local ok, v = pcall(fn)
    return ok and v ~= nil and v ~= false
end

local function stateOf(spec)
    if spec.getState == nil then return nil end
    local ok, v = pcall(spec.getState)
    if ok and (v == "on" or v == "warn") then return v end
    return nil
end

local function badgeOf(spec)
    if spec.getBadge == nil then return 0 end
    local ok, v = pcall(spec.getBadge)
    if ok and type(v) == "number" then return v end
    return 0
end

local function pending(badge)
    return badge >= 1 or badge == -1
end

local function textOf(fn)
    if fn == nil then return nil end
    local ok, v = pcall(fn)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

local function nameOf(spec)
    return textOf(spec.label) or spec.id
end

-- ---------- registry ----------

local function optional(v, kind)
    return v == nil or type(v) == kind
end

local function valid(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then return false end
    if type(spec.order) ~= "number" or type(spec.label) ~= "function" or type(spec.onClick) ~= "function" then
        return false
    end
    if spec.icon == nil and spec.iconKey == nil and spec.drawIcon == nil then return false end
    return optional(spec.icon, "string") and optional(spec.iconKey, "string")
        and optional(spec.drawIcon, "function") and optional(spec.bind, "string")
        and optional(spec.getStatus, "function") and optional(spec.onRightClick, "function")
        and optional(spec.isActive, "function") and optional(spec.getState, "function")
        and optional(spec.getBadge, "function") and optional(spec.isAvailable, "function")
end

local function before(a, b)
    if a.spec.order ~= b.spec.order then return a.spec.order < b.spec.order end
    return a.spec.id < b.spec.id
end

-- insertion sort (family rule: no table.sort); a handful of entries, only on register/unregister
local function resort()
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for _, rec in pairs(records) do
        local j = #sorted
        while j >= 1 and before(rec, sorted[j]) do
            sorted[j + 1] = sorted[j]
            j = j - 1
        end
        sorted[j + 1] = rec
    end
end

-- rebuild `shown` in place; true = the visible set or its order changed
local function evaluate()
    local n, changed = 0, false
    for i = 1, #sorted do
        local rec = sorted[i]
        if truthy(rec.spec.isAvailable, true) then
            n = n + 1
            if shown[n] ~= rec then
                shown[n] = rec
                changed = true
            end
        end
    end
    for i = #shown, n + 1, -1 do
        shown[i] = nil
        changed = true
    end
    return changed
end

-- ---------- helpers ----------

local function fontHeight()
    if fontH == nil then fontH = getTextManager():getFontHeight(UIFont.Small) end
    return fontH
end

local function loadTexture(path)
    if type(getTexture) ~= "function" then return false end
    local ok, tex = pcall(getTexture, path)
    if ok and tex then return tex end
    return false
end

local function drawTex(el, tex, x, y, size, a, r, g, b)
    el:drawTextureScaled(tex, x, y, size, size, a, r, g, b)
end

-- vertical flip; drawTextureAllPoint takes absolute screen points (UIElement.DrawTexture 9-point form)
local function drawFlipped(el, tex, x, y, size, r, g, b, a)
    local ax = math.floor(el:getAbsoluteX() + x)
    local ay = math.floor(el:getAbsoluteY() + y)
    el:drawTextureAllPoint(tex, ax, ay + size, ax + size, ay + size, ax + size, ay, ax, ay, r, g, b, a)
end

local function clamp(p)
    local core = getCore()
    local x = math.max(0, math.min(p:getX(), core:getScreenWidth() - p.width))
    local y = math.max(0, math.min(p:getY(), core:getScreenHeight() - p.height))
    if x ~= p:getX() then p:setX(x) end
    if y ~= p:getY() then p:setY(y) end
end

local function readMoodleOption() return getCore():getOptionMoodleSize() end
local function readFontOption() return getCore():getOptionFontSizeReal() end

-- MoodlesUI.getTextureSizeForOption (MoodlesUI.java:72-86): option 1-6 -> size table,
-- 7 -> font size option into the same table, anything else 32
local function moodleSize()
    local ok, option = pcall(readMoodleOption)
    if ok and type(option) == "number" then
        if MOODLE_SIZES[option] then return MOODLE_SIZES[option] end
        if option == 7 then
            local okFont, font = pcall(readFontOption)
            if okFont and type(font) == "number" and MOODLE_SIZES[font] then return MOODLE_SIZES[font] end
        end
    end
    return 32
end

local function applyDefault(p)
    p:setX(getCore():getScreenWidth() - (MOODLE_EDGE + moodleSize()) - MOODLE_GAP - p.width)
    p:setY(DEFAULT_Y)
end

local function layoutRegistered()
    local LM = ISLayoutManager
    return LM ~= nil and type(LM.windows) == "table" and LM.windows[LAYOUT_KEY] ~= nil
end

-- write layout.ini now (the same path the game runs on every save)
local function persist()
    if layoutRegistered() and ISLayoutManager.OnPostSave then pcall(ISLayoutManager.OnPostSave) end
end

-- ---------- layout ----------

local function activateEntry(rec, btn)
    local p = btn and btn.parent
    if p and p._joy then endFocus(p) end -- launcher: the opened UI gets the joypad, not the dock
    pcall(rec.spec.onClick, rec.spec)
end

local function newButton(p, rec, onclick)
    local b = ISButton.new(DockButton, 0, 0, CELL, CELL, "", rec or p, onclick)
    b._rec = rec
    b:initialise()
    p:addChild(b)
    return b
end

local function relayout(p)
    local n = #shown
    for i = 1, #sorted do
        local b = sorted[i].button
        if b then b:setVisible(false) end
    end
    if n == 1 then
        p.handle:setVisible(false)
        local rec = shown[1]
        if rec.button == nil then rec.button = newButton(p, rec, activateEntry) end
        rec.button:setX(0)
        rec.button:setY(0)
        rec.button:setVisible(true)
        p:setWidth(CELL)
        p:setHeight(CELL)
        return
    end
    p.handle:setX(PAD)
    p.handle:setY(PAD)
    p.handle:setVisible(n >= 2)
    local y = PAD + CELL
    if not p.collapsed then
        for i = 1, n do
            local rec = shown[i]
            if rec.button == nil then rec.button = newButton(p, rec, activateEntry) end
            y = y + GAP
            rec.button:setX(PAD)
            rec.button:setY(y)
            rec.button:setVisible(true)
            y = y + CELL
        end
    end
    p:setWidth(PAD + CELL + PAD)
    p:setHeight(y + PAD)
end

local function setCollapsed(p, value, temporary)
    p.collapsed = value
    relayout(p)
    clamp(p)
    if not temporary then persist() end
end

local function toggleCollapsed(p)
    p._wasCollapsed = nil -- an explicit choice replaces any focus-session memory
    setCollapsed(p, not p.collapsed, false)
end

-- ---------- focus sessions (keyboard hotkey / joypad menu) ----------

local function beginFocus(p)
    if #shown >= 2 and p.collapsed then
        p._wasCollapsed = true
        setCollapsed(p, false, true)
    end
end

endFocus = function(p)
    if not (p._kb or p._joy) then return end
    local was = p._wasCollapsed
    p._kb, p._joy, p._wasCollapsed = nil, nil, nil
    if Focus then
        Focus.releaseJoypad(p)
        if Focus.root == p then Focus.clear(p) end
        -- otherwise the dock stays the active root and the next window would not own Tab
        if Focus.activeRoot == p then Focus.activeRoot = nil end
    end
    if was and not p.collapsed then setCollapsed(p, true, true) end
end

-- ---------- tooltip ----------

local function bindKeyTextRaw(bind)
    local opts = MainOptions
    if opts and type(opts.keyText) == "table" then
        for _, v in ipairs(opts.keyText) do
            if not v.value and v.txt and v.txt:getName() == bind then
                if not v.keyCode or v.keyCode == 0 then return nil end
                local prefix = opts.getKeyPrefix and opts.getKeyPrefix(v) or ""
                return prefix .. getKeyName(v.keyCode)
            end
        end
    end
    local code = getCore():getKey(bind)
    if not code or code == 0 then return nil end
    return getKeyName(code)
end

-- current key text for a binding (options screen first, it knows modifier prefixes); nil = unbound
local function bindKeyText(bind)
    local ok, text = pcall(bindKeyTextRaw, bind)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

local function entryTip(rec)
    local spec = rec.spec
    local name = nameOf(spec)
    local key = spec.bind and bindKeyText(spec.bind)
    local text = name
    if key then text = getText("IGUI_MinidoracatUI_Dock_EntryHotkey", name, key) end
    local status = textOf(spec.getStatus)
    if status then text = text .. "\n" .. status end
    return text
end

local function handleTip(p)
    local count = tostring(#shown)
    if not p.collapsed then return getText("IGUI_MinidoracatUI_Dock_Collapse", count) end
    local text = getText("IGUI_MinidoracatUI_Dock_Expand", count)
    for i = 1, #shown do
        local spec = shown[i].spec
        if pending(badgeOf(spec)) or stateOf(spec) == "warn" then
            local status = textOf(spec.getStatus)
            local line = nameOf(spec)
            if status then line = getText("IGUI_MinidoracatUI_Dock_StatusLine", line, status) end
            text = text .. "\n" .. line
        end
    end
    return text
end

local function hideTip(p)
    local tip = p._tip
    if tip and tip:getIsVisible() then
        tip:setVisible(false)
        tip:removeFromUIManager()
    end
    p._tipFor = nil
end

local function tipTarget(p)
    if p._down then return nil end
    local h = p.handle
    if h:getIsVisible() and h:isMouseOver() then return h end
    for i = 1, #shown do
        local b = shown[i].button
        if b and b:getIsVisible() and b:isMouseOver() then return b end
    end
    if Focus and (p._kb or p._joy) and Focus.root == p then
        local f = Focus.focused()
        if f and f.parent == p and f:getIsVisible() then return f end
    end
    return nil
end

local function updateTip(p)
    if ISToolTip == nil then return end
    local target = tipTarget(p)
    if target == nil then
        hideTip(p)
        return
    end
    local tip = p._tip
    if tip == nil then
        tip = ISToolTip:new()
        tip:setOwner(p)
        tip:setVisible(false)
        tip:setAlwaysOnTop(true)
        p._tip = tip
    end
    local firstShow = not tip:getIsVisible()
    if firstShow then
        tip:addToUIManager()
        tip:setVisible(true)
    end
    local now = getTimestampMs()
    if firstShow or target ~= p._tipFor or now >= (p._tipNextMs or 0) then
        p._tipFor, p._tipNextMs = target, now + TOOLTIP_THROTTLE_MS
        local text = target._rec and entryTip(target._rec) or handleTip(p)
        tip.description = text
        tip.maxLineWidth = string.find(text, "\n", 1, true) and 1000 or 300 -- ISButton.lua:326-330
    end
    local below = target:getAbsoluteY() + target.height + 8
    if target:isMouseOver() then
        tip:setDesiredPosition(getMouseX(), below)
    else
        tip:setDesiredPosition(target:getAbsoluteX(), below)
    end
end

-- ---------- drawing ----------

local function drawWarnChip(el, h, c)
    local y = h - CHIP - 1
    Skin.fill(el, 1, y, CHIP, CHIP, c.errorText)
    local s = c.surface
    el:drawTextCentre("!", 1 + CHIP / 2, y + (CHIP - fontHeight()) / 2, s.r, s.g, s.b, 1)
end

local function drawBadge(btn, rec, c)
    local n = badgeOf(rec.spec)
    if n == -1 then
        Skin.dot(btn, btn.width - DOT - 2, 2, DOT, c.errorText, c.surface)
        return
    end
    if n < 1 then return end
    n = math.floor(n)
    if rec.badgeN ~= n then
        rec.badgeN = n
        rec.badgeText = n > 99 and "99+" or tostring(n)
        rec.badgeW = math.max(CHIP + 2, getTextManager():MeasureStringX(UIFont.Small, rec.badgeText) + 8)
    end
    local h = math.max(CHIP + 2, fontHeight())
    local x = btn.width - rec.badgeW
    Skin.fill(btn, x, 0, rec.badgeW, h, c.errorText)
    local s = c.surface
    btn:drawTextCentre(rec.badgeText, x + rec.badgeW / 2, (h - fontHeight()) / 2, s.r, s.g, s.b, 1)
end

local function drawIcon(btn, rec, c)
    local spec = rec.spec
    local off = (btn.width - ICON) / 2
    if spec.icon then
        if rec.tex == nil then rec.tex = loadTexture(spec.icon) end
        if rec.tex then pcall(drawTex, btn, rec.tex, off, off, ICON, 1, 1, 1, 1) end
    elseif spec.iconKey then
        Icons.draw(btn, spec.iconKey, off, off, ICON, c.text)
    else
        pcall(spec.drawIcon, btn, off, off, ICON)
    end
end

local function probeMascot()
    if mascotProbed then return end
    mascotProbed = true
    local sleep, awake = loadTexture(MASCOT_SLEEP), loadTexture(MASCOT_AWAKE)
    if sleep and awake then mascotSleep, mascotAwake = sleep, awake end
end

local function drawHandle(btn, p, c)
    local w, h = btn.width, btn.height
    if btn:isMouseOver() or p._down == btn then Skin.fill(btn, 0, 0, w, h, c.hover) end
    probeMascot()
    if mascotSleep then
        local off = (w - MASCOT) / 2
        local tex = p.collapsed and mascotSleep or mascotAwake
        if pcall(drawTex, btn, tex, off, off, MASCOT, 1, 1, 1, 1) then return end
    end
    local t = c.text
    local chevron = Icons.get("chevronDown")
    if chevron then
        local off = (w - CHEVRON) / 2
        local ok
        if p.collapsed then
            ok = pcall(drawTex, btn, chevron, off, off, CHEVRON, t.a or 1, t.r, t.g, t.b)
        else
            ok = pcall(drawFlipped, btn, chevron, off, off, CHEVRON, t.r, t.g, t.b, t.a or 1)
        end
        if ok then return end
    end
    Skin.arrow(btn, math.floor((w - Skin.ARROW_W) / 2), math.floor((h - Skin.ARROW_H) / 2), not p.collapsed, t)
end

function DockButton:prerender()
    local p = self.parent
    if p == nil or p.theme == nil then return end
    local c = p.theme.colors
    if self._rec == nil then
        drawHandle(self, p, c)
        return
    end
    local w, h = self.width, self.height
    local spec = self._rec.spec
    if truthy(spec.isActive, false) then
        Skin.fill(self, 0, 0, w, h, c.selected)
        local a = c.accent
        self:drawRect(0, 4, ACTIVE_BAR, h - 8, a.a or 1, a.r, a.g, a.b)
    end
    if self:isMouseOver() or p._down == self then Skin.fill(self, 0, 0, w, h, c.hover) end
    drawIcon(self, self._rec, c)
    local state = stateOf(spec)
    if state == "on" then
        Skin.border(self, 0, 0, w, h, c.accent)
    elseif state == "warn" then
        Skin.border(self, 0, 0, w, h, c.errorText)
        drawWarnChip(self, h, c)
    end
    drawBadge(self, self._rec, c)
end

function DockButton:render() end -- replaces ISButton:render (title / joypad glyph drawing)

-- arrows move between entries (cycling); keyboard handle() and joypad dirs ask this first
function DockButton:onFocusKey(key)
    if self._rec == nil or Focus == nil then return false end
    local delta
    if key == Keyboard.KEY_UP or key == Keyboard.KEY_LEFT then
        delta = -1
    elseif key == Keyboard.KEY_DOWN or key == Keyboard.KEY_RIGHT then
        delta = 1
    else
        return false
    end
    local n = #shown
    local index = 0
    for i = 1, n do
        if shown[i] == self._rec then index = i end
    end
    if index == 0 or n < 2 then return true end
    index = index + delta
    if index < 1 then index = n end
    if index > n then index = 1 end
    local target = shown[index].button
    if target then Focus.focusControl(target, true) end
    return true
end

-- ---------- mouse: drag the whole dock from any button ----------

function DockButton:onMouseDown(x, y)
    local p = self.parent
    if p == nil or not self:getIsVisible() then return false end
    p._down, p._dragged = self, nil
    p._downX, p._downY = getMouseX(), getMouseY()
    p._origX, p._origY = p:getX(), p:getY()
    self:setCapture(true)
    p:bringToTop()
    return true
end

local function moveDock(btn)
    local p = btn.parent
    if p == nil or p._down ~= btn then return false end
    local mx, my = getMouseX(), getMouseY()
    if not p._dragged then
        if math.abs(mx - p._downX) <= DRAG_THRESHOLD and math.abs(my - p._downY) <= DRAG_THRESHOLD then
            return true
        end
        p._dragged = true
    end
    p:setX(p._origX + (mx - p._downX))
    p:setY(p._origY + (my - p._downY))
    return true
end

local function releaseDock(btn)
    local p = btn.parent
    if p == nil or p._down ~= btn then return false end
    p._down = nil
    btn:setCapture(false)
    if p._dragged then
        p._dragged = nil
        clamp(p)
        persist()
    else
        btn:forceClick()
    end
    return true
end

function DockButton:onMouseMove(dx, dy) return moveDock(self) end
function DockButton:onMouseMoveOutside(dx, dy) return moveDock(self) end
function DockButton:onMouseUp(x, y) return releaseDock(self) end
function DockButton:onMouseUpOutside(x, y) return releaseDock(self) end

function DockButton:onRightMouseDown(x, y)
    local p = self.parent
    if self._rec and self._rec.spec.onRightClick and p and not p._down then
        self._rDown, self._rDownAt = true, getTimestampMs()
    end
    return true
end

function DockButton:onRightMouseUp(x, y)
    local rec = self._rec
    if rec and rec.spec.onRightClick and self._rDown
        and getTimestampMs() - (self._rDownAt or 0) < RIGHT_CLICK_EXPIRE_MS then
        self._rDown = nil
        pcall(rec.spec.onRightClick, rec.spec)
    end
    self._rDown = nil
    return true
end

function DockButton:onRightMouseUpOutside(x, y)
    self._rDown = nil
end

-- ---------- panel ----------

local function hide(p)
    hideTip(p)
    endFocus(p)
    if p:getIsVisible() then p:setVisible(false) end
end

local function avoidRect()
    local p = panel
    if p == nil or not p:getIsVisible() then return nil end
    return p:getAbsoluteX(), p:getAbsoluteY(), p.width, p.height
end

local function createPanel()
    local p = ISPanel.new(DockPanel, 0, DEFAULT_Y, CELL, CELL)
    p.background = false
    p.moveWithMouse = false
    p.alwaysOnTop = false
    p.theme = UI.Theme.create()
    p.collapsed = false -- first run: expanded
    p._focusControls = {}
    p._focusList = { { kind = "group", controls = p._focusControls, captionSide = "none" } }
    if Focus then p:setWantKeyEvents(true) end -- key hooks only act during a hotkey session
    p:initialise()
    p:addToUIManager()
    p:setAlwaysOnTop(false) -- the Lua field alone does not reach the engine (ARCHITECTURE 3.4)
    p.handle = newButton(p, nil, toggleCollapsed)
    panel = p
    if UI.CAPABILITIES.toastAvoid and UI.Toast and UI.Toast.setAvoid then
        UI.Toast.setAvoid(LAYOUT_KEY, avoidRect)
    end
    return p
end

local function poll(force)
    local now = getTimestampMs()
    if not (force or dirty or now >= nextPoll) then return end
    nextPoll = now + POLL_MS
    dirty = false
    if getSpecificPlayer(0) == nil then
        if panel then hide(panel) end
        return
    end
    local created = panel == nil
    if created then createPanel() end
    if evaluate() or force or created then relayout(panel) end
    if created then
        applyDefault(panel)
        if ISLayoutManager and ISLayoutManager.RegisterWindow then
            pcall(ISLayoutManager.RegisterWindow, LAYOUT_KEY, DockPanel, panel)
        end
        clamp(panel)
    end
    if #shown == 0 then
        hide(panel)
    elseif not panel:getIsVisible() then
        panel:setVisible(true)
    end
end

function DockPanel:prerender()
    if getSpecificPlayer(0) == nil then
        hide(self) -- back at the main menu the UIManager element survives
        return
    end
    poll(false)
    if not self:getIsVisible() then return end
    clamp(self)
    if self._kb and (Focus == nil or Focus.root ~= self) then endFocus(self) end
    if self._joy and not Focus.holdsJoypad(self) then endFocus(self) end
    updateTip(self)
    local c = self.theme.colors
    Skin.fill(self, 0, 0, self.width, self.height, c.surface)
    Skin.border(self, 0, 0, self.width, self.height, c.border)
end

-- collapsed shell: one dot if anything is pending (counts are never summed), warn frame + chip
function DockPanel:render()
    if #shown >= 2 and self.collapsed then
        local anyPending, anyWarn = false, false
        for i = 1, #shown do
            local spec = shown[i].spec
            if not anyPending and pending(badgeOf(spec)) then anyPending = true end
            if not anyWarn and stateOf(spec) == "warn" then anyWarn = true end
        end
        local c = self.theme.colors
        if anyWarn then
            Skin.border(self, 0, 0, self.width, self.height, c.errorText)
            drawWarnChip(self, self.height, c)
        end
        if anyPending then Skin.dot(self, self.width - DOT - 2, 2, DOT, c.errorText, c.surface) end
    end
    if Focus and Focus.root == self then Focus.render(self, self.theme) end
end

function DockPanel:SaveLayout(name, layout)
    layout.x = self:getX()
    layout.y = self:getY()
    -- a focus session expands temporarily; save the state the player chose
    layout.collapsed = tostring((self._wasCollapsed or self.collapsed) == true)
end

function DockPanel:RestoreLayout(name, layout)
    local x, y = tonumber(layout.x), tonumber(layout.y)
    if x and y then
        self:setX(x)
        self:setY(y)
    end
    if layout.collapsed == "true" or layout.collapsed == "false" then
        self.collapsed = layout.collapsed == "true"
        relayout(self)
    end
    clamp(self)
end

-- UI.Focus root: one group of the visible entry buttons (the handle is not a target)
function DockPanel:keyboardTargets()
    local controls, n = self._focusControls, 0
    for i = 1, #shown do
        local b = shown[i].button
        if b and b:getIsVisible() then
            n = n + 1
            controls[n] = b
        end
    end
    for i = #controls, n + 1, -1 do controls[i] = nil end
    if n == 0 then return nil end
    return self._focusList
end

-- presses only during a hotkey session (else Tab would start a ring on the dock); releases and
-- isKeyConsumed always answer the shared ledger so the Esc that ended a session never leaks
function DockPanel:onKeyPress(key) if Focus and self._kb then Focus.onKeyPress(self, key) end end
function DockPanel:onKeyRepeat(key) if Focus and self._kb then Focus.onKeyRepeat(self, key) end end
function DockPanel:onKeyRelease(key) if Focus then Focus.onKeyRelease(self, key) end end
function DockPanel:isKeyConsumed(key) return Focus ~= nil and Focus.isKeyConsumed(self, key) end

-- Esc (keyboard) and B (joypad) both end the session; always true so Focus never closes the dock
function DockPanel:onEscape()
    endFocus(self)
    return true
end

function DockPanel:onJoypadDown(button, joypadData) if Focus then Focus.onJoypadDown(self, button, joypadData) end end
function DockPanel:onJoypadDirUp(joypadData) if Focus then Focus.onJoypadDir(self, "up", joypadData) end end
function DockPanel:onJoypadDirDown(joypadData) if Focus then Focus.onJoypadDir(self, "down", joypadData) end end
function DockPanel:onJoypadDirLeft(joypadData) if Focus then Focus.onJoypadDir(self, "left", joypadData) end end
function DockPanel:onJoypadDirRight(joypadData) if Focus then Focus.onJoypadDir(self, "right", joypadData) end end
function DockPanel:onJoypadBeforeDeactivate(joypadData) endFocus(self) end

-- ---------- public API ----------

function Dock.register(spec)
    if not valid(spec) then return false end
    local rec = records[spec.id]
    if rec == nil then
        rec = {}
        records[spec.id] = rec
    end
    rec.spec = spec
    rec.tex, rec.badgeN = nil, nil -- icon or badge source may have changed
    resort()
    dirty = true
    return true
end

function Dock.unregister(id)
    local rec = records[id]
    if rec == nil then return end
    records[id] = nil
    resort()
    for i = #shown, 1, -1 do
        if shown[i] == rec then table.remove(shown, i) end
    end
    if rec.button then
        rec.button:setVisible(false)
        if panel then panel:removeChild(rec.button) end
        rec.button = nil
    end
    if panel then
        relayout(panel)
        if #shown == 0 then hide(panel) end
    end
    dirty = true
end

function Dock.refresh()
    dirty = true
end

function Dock.isDocked(id)
    local rec = records[id]
    return rec ~= nil and panel ~= nil and getSpecificPlayer(0) ~= nil and truthy(rec.spec.isAvailable, true)
end

function Dock._resetForTests()
    if panel then
        hideTip(panel)
        panel:removeFromUIManager()
    end
    records, sorted, shown, panel = {}, {}, {}, nil
    dirty, nextPoll = true, 0
    mascotProbed, mascotSleep, mascotAwake, fontH = false, nil, nil, nil
end

-- ---------- events ----------

-- Default key: . (PERIOD). Four checks, all clear: unbound in vanilla keyBinding.lua (also not
-- ISSearchManager's END bind); no raw-key test in vanilla Lua or the decompiled Java; no family mod
-- uses it (MiniMap / ' ;, Economy [, DevProfiler \); the only local Workshop hit is an inert dev tool.
-- HOME/END/PRIOR/NEXT stay free: they are in-panel Focus navigation keys.
local function initBinds()
    if type(keyBinding) ~= "table" then return end
    table.insert(keyBinding, { value = "[MinidoracatUI]" })
    table.insert(keyBinding, { value = BIND, key = Keyboard.KEY_PERIOD })
end

local function boundKey()
    return getCore():getKey(BIND)
end

local function onKeyPressed(key)
    if key == nil or key == 0 then return end
    local ok, bound = pcall(boundKey)
    if not ok or key ~= bound then return end
    local p = panel
    if p == nil or not p:getIsVisible() or #shown == 0 then return end
    if Focus == nil then
        if #shown >= 2 then toggleCollapsed(p) end
        return
    end
    if p._kb then
        endFocus(p)
        return
    end
    endFocus(p) -- a joypad session, if any
    beginFocus(p)
    p._kb = true
    Focus.onFocus(p)
    local first = shown[1].button
    if first then Focus.focusControl(first, true) end
end

local function openForJoypad(playerNum)
    local p = panel
    if Focus == nil or p == nil or not p:getIsVisible() or #shown == 0 then return end
    endFocus(p) -- a keyboard session, if any
    beginFocus(p)
    p._joy = true
    Focus.takeJoypad(p, playerNum)
end

-- Joypad entry: joypad players open the world context menu with X (ISButtonPrompt.lua:166-191,
-- which probes with test=true first, :1115); the event fires at ISWorldObjectContextMenu.lua:213.
-- Only joypad players see the option (JoypadState pattern of ISVehicleMenu.lua:23-24).
local function onFillWorldMenu(playerNum, context, worldobjects, test)
    if playerNum ~= 0 or Focus == nil then return end
    if not (JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]) then return end
    if panel == nil or not panel:getIsVisible() or #shown == 0 then return end
    if test then return ISWorldObjectContextMenu.setTest() end -- ISBBQMenu.lua:9
    context:addOption(getText("IGUI_MinidoracatUI_Dock_Open"), playerNum, openForJoypad)
end

local function onTick()
    poll(false)
end

local function onGameStart()
    poll(true)
end

-- default first, then the layout saved for the new resolution (if any)
local function onResolutionChange()
    local p = panel
    if p == nil then return end
    applyDefault(p)
    if layoutRegistered() and ISLayoutManager.TryRestore then pcall(ISLayoutManager.TryRestore, LAYOUT_KEY) end
    clamp(p)
end

local function on(name, fn)
    local event = Events and Events[name]
    if event and event.Add then event.Add(fn) end
end

on("OnGameBoot", initBinds)
on("OnKeyPressed", onKeyPressed)
on("OnFillWorldObjectContextMenu", onFillWorldMenu)
on("OnTick", onTick)
on("OnGameStart", onGameStart)
on("OnResolutionChange", onResolutionChange)

UI.Dock = Dock
UI.CAPABILITIES.dock = true

return Dock
