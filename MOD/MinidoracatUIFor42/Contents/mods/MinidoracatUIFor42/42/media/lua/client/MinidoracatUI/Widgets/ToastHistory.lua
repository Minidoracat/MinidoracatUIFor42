-- MinidoracatUI Widgets/ToastHistory — 通知紀錄視窗、移動模式與 Dock 入口（API rev 21，CAPABILITIES.toastHistory）。
--
-- 紀錄本身在 Toast.lua（Toast.history，show() 時就寫入，排不進佇列的也記）；本檔只負責看紀錄與改位置：
--   * 紀錄視窗：UI.Window＋UI.ScrollPanel，最新的在最上面。每列：左側色條（通知的 border 色）、來源（title）
--     與相對時間一行，下面是完整訊息（UI.Text.wrap 換行、不截字）。開著時每幀只比 Toast.historyCount 與清單寬，
--     變了才重排（列物件重用，不每次新建）。相對時間每分鐘重算一次字串。
--   * 移動模式（Placer）：全螢幕半透明底＋可拖的範例框（一則單行通知的大小）＋「完成／恢復預設位置／取消」。
--     拖曳照 Dock：setCapture＋4px 門檻。範例框是 UI.Focus 的目標：方向鍵每次 NUDGE（Shift 每次 1px）、
--     Enter＝完成、Esc＝取消；手把十字鍵／A／B 走同一條。完成時 Toast.setAnchor（立刻寫 layout.ini）。
--     按鍵觸發的關閉走 Focus.close：等觸發鍵放開被消耗了才關，Enter／Esc 的放開不會漏給遊戲（聊天、暫停選單）。
--   * Dock 入口（id "toasthistory"、order 100、iconKey "bell"）：不給 getBadge——不顯示未讀數字，也沒有紅點
--     （2026-10-20 使用者裁定）。玩家端顯示選項在「選項 → MODS」的 MinidoracatUI 頁（2026-10-08 裁定：每個入口都要有）。
-- 缺 Toast／Window／ScrollPanel／Button／Text.wrap 任一：不掛能力（toastHistory 維持 false），紀錄照樣在 Toast.history。
-- 每幀路徑（prerender／render、Dock 回呼、keyboardTargets）不配置 table 或 closure；字串常值只有 ASCII，
-- 畫面上的字一律來自 Translate。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme) or not ISPanel then
    return -- 核心缺席：不掛能力
end

-- 檔名排序在 Window.lua／ScrollPanel 之後或之前都不一定：自己 require，不靠載入順序
if not UI.Toast then pcall(require, "MinidoracatUI/Widgets/Toast") end
if not UI.Window then pcall(require, "MinidoracatUI/Widgets/Window") end
if not UI.ScrollPanel then pcall(require, "MinidoracatUI/Widgets/ScrollPanel") end
if not UI.Button then pcall(require, "MinidoracatUI/Widgets/Controls") end
if not UI.Dock then pcall(require, "MinidoracatUI/Widgets/Dock") end
if not (UI.Toast and UI.Window and UI.ScrollPanel and UI.Button and UI.Text and UI.Text.wrap and UI.Text.fit) then
    return
end

local Toast, Skin, Text = UI.Toast, UI.Skin, UI.Text
local Focus = UI.Focus

local WIN_W, WIN_H = 400, 440
local MIN_W, MIN_H = 300, 240
local PAD = 10
local GAP = 8
local BAR_W = 3
local ROW_PAD = 6
local TIME_RESERVE = 96 -- 來源名稱最多用到列寬減掉這一段（右側的相對時間）
local LAYOUT_KEY = "MinidoracatUIToastHistory"
local OPTIONS_ID = "MinidoracatUIFor42"
local OPTION_ENTRY = "ToastHistoryEntry"
local NUDGE = 10
local DRAG_THRESHOLD = 4 -- 同 Dock／FloatButton：4px 以內放開算點擊
local DIM_ALPHA = 0.45
local HINT_W = 300
local MINUTE_MS = 60000

local History = {}
local win = nil      -- 紀錄視窗（第一次打開時才建）
local current = nil  -- 開著的移動模式

-- ---------- 玩家選項：Dock 入口顯示（選項 → MODS，預設勾選；寫法同 DevProfiler Launcher.lua） ----------
-- 頁面要在檔案載入時登記（MODS 分頁只在當下已有資料時建立）；ini 原版只在選項畫面建立時讀回，
-- 這裡第一次用到時自己補讀一次。沒有值或讀不到一律當顯示。同一個 ID 之後可以放框架的其他選項。

local modOptions = nil
local showEntry, optionsLoaded = true, false

local function createOptions()
    local M = PZAPI.ModOptions
    local o = M:getOptions(OPTIONS_ID)
    if o == nil then o = M:create(OPTIONS_ID, "UI_optionscreen_binding_MinidoracatUI") end
    o:addTickBox(OPTION_ENTRY, "IGUI_MinidoracatUI_History_DockOption", true,
        "IGUI_MinidoracatUI_History_DockOption_tooltip")
    return o
end

if type(PZAPI) == "table" and type(PZAPI.ModOptions) == "table" and type(PZAPI.ModOptions.create) == "function" then
    local ok, created = pcall(createOptions)
    if ok then modOptions = created end
end

local function readShowEntry()
    local opt = modOptions and modOptions:getOption(OPTION_ENTRY)
    showEntry = not (opt and opt:getValue() == false)
end

-- Dock 的 isAvailable 走這裡：讀過之後只回快取布林，不配置
local function syncShowEntry()
    if optionsLoaded then return showEntry end
    optionsLoaded = true
    if modOptions then
        pcall(PZAPI.ModOptions.load, PZAPI.ModOptions)
        readShowEntry()
    end
    return showEntry
end

if modOptions then
    -- MainOptions 套用時先把畫面值寫回 option.value 再呼叫 apply（MainOptions.lua:3760-3762），之後才存檔：
    -- 這裡不可重讀 ini。同一頁的其他選項若也要 apply，串在前一個後面。
    local previousApply = modOptions.apply
    function modOptions:apply()
        if previousApply then previousApply(self) end
        optionsLoaded = true
        readShowEntry()
        if UI.Dock and UI.Dock.refresh then UI.Dock.refresh() end
    end
end

-- ---------- 紀錄的一列 ----------

local Row = ISPanel:derive("MinidoracatUIToastHistoryRow")

local function relativeText(minutes)
    if minutes < 1 then return getText("IGUI_MinidoracatUI_History_JustNow") end
    if minutes < 60 then return getText("IGUI_MinidoracatUI_History_MinutesAgo", tostring(minutes)) end
    return getText("IGUI_MinidoracatUI_History_HoursAgo", tostring(math.floor(minutes / 60)))
end

local function newRow(w)
    local r = ISPanel.new(Row, 0, 0, 100, 40)
    r.background = false
    r.theme = w.theme
    r.font = w.font
    r.fontH = w._fontH
    r:initialise()
    w.scroll:addChild(r)
    return r
end

-- 換綁一筆紀錄（重排時才跑）：完整訊息依列寬換行，來源名稱放不下才截字
local function bindRow(r, e, width)
    r.entry = e
    r.bucket = nil
    r:setWidth(width)
    local textX = PAD + BAR_W + GAP
    r.lines = Text.wrap(e.message, width - textX - PAD, r.font)
    r.titleText = e.title and Text.fit(e.title, width - textX - TIME_RESERVE, r.font) or nil
    r:setHeight(ROW_PAD * 2 + r.fontH * (1 + #r.lines))
end

function Row:prerender()
    local e = self.entry
    if e == nil then return end
    local c = self.theme.colors
    local minutes = math.floor((getTimestampMs() - e.atMs) / MINUTE_MS)
    if minutes ~= self.bucket then
        self.bucket = minutes
        self.timeText = relativeText(minutes)
        self.timeW = getTextManager():MeasureStringX(self.font, self.timeText)
    end
    local b = e.border or c.border
    self:drawRect(PAD, ROW_PAD, BAR_W, self.height - ROW_PAD * 2, b.a or 1, b.r, b.g, b.b)
    local line = c.border
    self:drawRect(0, self.height - 1, self.width, 1, (line.a or 1) * 0.5, line.r, line.g, line.b)
    local textX = PAD + BAR_W + GAP
    local muted = c.textMuted
    if self.titleText then
        self:drawText(self.titleText, textX, ROW_PAD, muted.r, muted.g, muted.b, muted.a, self.font)
    end
    self:drawText(self.timeText, self.width - PAD - self.timeW, ROW_PAD, muted.r, muted.g, muted.b, muted.a, self.font)
    local t = c.text
    for i = 1, #self.lines do
        self:drawText(self.lines[i], textX, ROW_PAD + self.fontH * i, t.r, t.g, t.b, t.a, self.font)
    end
end

-- 沒有紀錄時：說明這裡會記什麼
local Empty = ISPanel:derive("MinidoracatUIToastHistoryEmpty")

function Empty:prerender()
    local c = self.theme.colors.textMuted
    for i = 1, #self.lines do
        self:drawText(self.lines[i], PAD, PAD + self.fontH * (i - 1), c.r, c.g, c.b, c.a, self.font)
    end
end

-- ---------- 紀錄視窗 ----------

-- 依目前紀錄重排（新的在最上面）。列物件重用；多出來的列隱藏，ScrollPanel 只量可見子元件的高度。
local function refresh(w)
    local list = Toast.history
    local n = #list
    local width = w.scroll:contentWidth()
    local rows = w._rows
    local y = 0
    for i = 1, n do
        local r = rows[i]
        if r == nil then
            r = newRow(w)
            rows[i] = r
        end
        bindRow(r, list[n - i + 1], width)
        r:setY(y)
        r:setVisible(true)
        y = y + r.height
    end
    for i = n + 1, #rows do
        rows[i].entry = nil
        rows[i]:setVisible(false)
    end
    w.empty:setVisible(n == 0)
    w._seen = Toast.historyCount
    w._seenWidth = width
end

-- 視窗底部一行說明；順便每幀比對要不要重排、「恢復預設位置」能不能按（setter 同值 no-op）
local Status = ISPanel:derive("MinidoracatUIToastHistoryStatus")

function Status:prerender()
    local w = self.win
    if w._seen ~= Toast.historyCount or w._seenWidth ~= w.scroll:contentWidth() then refresh(w) end
    w.btnReset:setEnabled(Toast.anchor ~= nil)
    local c = w.theme.colors.textMuted
    local lines, h = self.lines, w._fontH
    for i = 1, #lines do
        self:drawText(lines[i], 0, (i - 1) * h, c.r, c.g, c.b, c.a, w.font)
    end
end

local function layout(w)
    local top = w:contentTop() + PAD
    local fontH = w._fontH
    w.btnMove:setX(PAD)
    w.btnMove:setY(top)
    local resetX = PAD + w.btnMove.width + GAP
    if resetX + w.btnReset.width > w.width - PAD then
        -- 窄視窗或長譯文：第二顆換到下一列
        w.btnReset:setX(PAD)
        w.btnReset:setY(top + w.btnMove.height + 4)
        top = top + w.btnMove.height + 4
    else
        w.btnReset:setX(resetX)
        w.btnReset:setY(top)
    end
    local listTop = top + w.btnMove.height + PAD
    -- 說明在窄視窗或長譯文（PL、FR）放不下一行時換行，不畫出視窗外
    w.status.lines = Text.wrap(w.status.text, w.width - PAD * 2, w.font)
    local statusH = fontH * #w.status.lines + 6
    local listH = math.max(40, w.height - listTop - statusH - PAD)
    w.scroll:setX(PAD)
    w.scroll:setY(listTop)
    w.scroll:setWidth(w.width - PAD * 2)
    w.scroll:setHeight(listH)
    w.status:setX(PAD)
    w.status:setY(listTop + listH + 4)
    w.status:setWidth(w.width - PAD * 2)
    w.status:setHeight(statusH)
    local cw = w.scroll:contentWidth()
    w.empty.lines = Text.wrap(getText("IGUI_MinidoracatUI_History_Empty"), cw - PAD * 2, w.font)
    w.empty:setWidth(cw)
    w.empty:setHeight(PAD * 2 + fontH * #w.empty.lines)
    w._seenWidth = nil -- 寬度變了：下一幀依新寬度重新換行
end

local function onResize(w)
    layout(w)
end

local function onMove(w)
    History.move()
end

local function onReset(w)
    Toast.setAnchor(nil)
end

-- Esc（焦點框在視窗上時）：等 Esc 放開被消耗才關，放開不漏給遊戲開暫停選單（Focus.close）
local function onEscapeWindow(w)
    if Focus then Focus.close(w) else w:close() end
    return true
end

local function create()
    local theme = UI.Theme.create()
    local sw = getCore():getScreenWidth()
    local w = UI.Window.new({
        x = math.floor((sw - WIN_W) / 2), y = 120, width = WIN_W, height = WIN_H,
        title = getText("IGUI_MinidoracatUI_History_Title"), icon = "bell", theme = theme,
        resizable = true, minWidth = MIN_W, minHeight = MIN_H, onResize = onResize,
    })
    w._rows = {}
    w.onEscape = onEscapeWindow -- 焦點框在視窗上時 Esc 關視窗（Focus 先問 root:onEscape）
    w.btnMove = UI.Button.new({ x = PAD, y = 0, title = getText("IGUI_MinidoracatUI_History_Move"),
        theme = theme, target = w, onClick = onMove })
    w.btnReset = UI.Button.new({ x = PAD, y = 0, title = getText("IGUI_MinidoracatUI_History_Reset"),
        theme = theme, target = w, onClick = onReset })
    w:addChild(w.btnMove)
    w:addChild(w.btnReset)
    w.scroll = UI.ScrollPanel.new({ width = WIN_W - PAD * 2, height = 200, theme = theme })
    -- 清單裡沒有焦點目標：自動目標把容器本身當 kind="scroll"（方向鍵捲一行、PgUp／PgDn 一頁）
    w.scroll._focusLabel = getText("IGUI_MinidoracatUI_History_Title")
    w:addChild(w.scroll)
    local e = ISPanel.new(Empty, 0, 0, 100, 40)
    e.background = false
    e.theme, e.font, e.fontH, e.lines = theme, w.font, w._fontH, {}
    e:initialise()
    w.scroll:addChild(e)
    w.empty = e
    local s = ISPanel.new(Status, 0, 0, 100, 20)
    s.background = false
    s.win = w
    s.text = getText("IGUI_MinidoracatUI_History_Footer", tostring(Toast.MAX_HISTORY))
    s:initialise()
    w:addChild(s)
    w.status = s
    layout(w)
    refresh(w)
    w:addToUIManager()
    if ISLayoutManager and ISLayoutManager.RegisterWindow then
        pcall(ISLayoutManager.RegisterWindow, LAYOUT_KEY, UI.Window, w)
    end
    return w
end

-- 開／關紀錄視窗（Dock 入口的 onClick；consumer 也可以從自己的介面呼叫）
function History.toggle()
    if win and win:getIsVisible() then
        win:close()
        return
    end
    if win == nil then
        win = create()
    else
        win:setVisible(true)
        win:bringToTop()
    end
end

function History.isOpen()
    return win ~= nil and win:getIsVisible()
end

-- ---------- 移動模式 ----------

local Placer = ISPanel:derive("MinidoracatUIToastPlacer")
local Frame = ISPanel:derive("MinidoracatUIToastPlacerFrame")

-- 範例框夾在螢幕內；中心在下半部時第二、三格畫在上面（同 Toast 的往上疊），按鈕列與說明放在堆疊外側，
-- 放不下就換到範例框另一側
local function moveFrame(p, x, y)
    local sw, sh = p.width, p.height
    local slotW, slotH = Toast.WIDTH, Toast.HEIGHT
    x = math.max(0, math.min(math.floor(x), sw - slotW))
    y = math.max(0, math.min(math.floor(y), sh - slotH))
    p.frame:setX(x)
    p.frame:setY(y)
    p.up = y + slotH / 2 > sh / 2
    local stackH = Toast.MAX_VISIBLE * slotH + (Toast.MAX_VISIBLE - 1) * Toast.STACK_GAP
    local stackTop = p.up and (y + slotH - stackH) or y
    local barH = p.btnDone.height
    local blockH = barH + 4 + #p.hintLines * p.fontH
    local blockY = p.up and (stackTop - GAP - blockH) or (stackTop + stackH + GAP)
    if blockY < 0 or blockY + blockH > sh then
        blockY = p.up and (y + slotH + GAP) or (y - GAP - blockH)
    end
    blockY = math.max(0, math.min(blockY, sh - blockH))
    local barW = p.btnDone.width + p.btnReset.width + p.btnCancel.width + GAP * 2
    local barX = math.max(0, math.min(x + slotW - barW, sw - barW))
    p.btnDone:setX(barX)
    p.btnReset:setX(barX + p.btnDone.width + GAP)
    p.btnCancel:setX(barX + p.btnDone.width + p.btnReset.width + GAP * 2)
    p.btnDone:setY(blockY)
    p.btnReset:setY(blockY)
    p.btnCancel:setY(blockY)
    p.hintX = math.max(0, math.min(x + slotW - HINT_W, sw - HINT_W))
    p.hintY = blockY + barH + 4
end

local function finish(p, save)
    if p._finished then return end
    p._finished = true
    if save then Toast.setAnchor(p.frame:getX(), p.frame:getY()) end
    -- 按鍵觸發：等觸發鍵放開被消耗才關（Enter／Esc 的放開不漏給遊戲）；滑鼠觸發：立刻關
    if Focus then Focus.close(p) else p:setVisible(false) end
end

function Placer:setVisible(visible)
    ISPanel.setVisible(self, visible)
    if visible then return end
    if Focus then
        Focus.releaseJoypad(self)
        if Focus.root == self then Focus.clear(self) end
        if Focus.activeRoot == self then Focus.activeRoot = nil end
    end
    self:removeFromUIManager()
    if current == self then current = nil end
    if Focus and win and win:getIsVisible() then Focus.onFocus(win) end
end

function Placer:prerender()
    local sw, sh = self.width, self.height
    self:drawRect(0, 0, sw, sh, DIM_ALPHA, 0, 0, 0)
    local c = self.theme.colors
    local f = self.frame
    local x, y = f:getX(), f:getY()
    local step = Toast.HEIGHT + Toast.STACK_GAP
    for i = 1, Toast.MAX_VISIBLE - 1 do
        local gy = self.up and (y - step * i) or (y + step * i)
        Skin.border(self, x, gy, Toast.WIDTH, Toast.HEIGHT, c.textMuted, false, 0.6)
    end
    local t = c.text
    for i = 1, #self.hintLines do
        self:drawText(self.hintLines[i], self.hintX, self.hintY + self.fontH * (i - 1), t.r, t.g, t.b, t.a, self.font)
    end
end

function Placer:render()
    if Focus and Focus.root == self then Focus.render(self, self.theme) end
end

-- 模態：吃掉範例框與按鈕以外的點擊，遊戲世界收不到
function Placer:onMouseDown() return true end
function Placer:onMouseUp() return true end
function Placer:onRightMouseDown() return true end
function Placer:onRightMouseUp() return true end
function Placer:onMouseWheel() return true end

function Placer:keyboardTargets() return self._targets end
function Placer:onKeyPress(key) if Focus then Focus.onKeyPress(self, key) end end
function Placer:onKeyRepeat(key) if Focus then Focus.onKeyRepeat(self, key) end end
function Placer:onKeyRelease(key) if Focus then Focus.onKeyRelease(self, key) end end
function Placer:isKeyConsumed(key) return Focus ~= nil and Focus.isKeyConsumed(self, key) end
function Placer:onEscape()
    finish(self, false)
    return true
end
function Placer:onJoypadDown(button, joypadData) if Focus then Focus.onJoypadDown(self, button, joypadData) end end
function Placer:onJoypadDirUp(joypadData) if Focus then Focus.onJoypadDir(self, "up", joypadData) end end
function Placer:onJoypadDirDown(joypadData) if Focus then Focus.onJoypadDir(self, "down", joypadData) end end
function Placer:onJoypadDirLeft(joypadData) if Focus then Focus.onJoypadDir(self, "left", joypadData) end end
function Placer:onJoypadDirRight(joypadData) if Focus then Focus.onJoypadDir(self, "right", joypadData) end end
function Placer:onJoypadBeforeDeactivate(joypadData) finish(self, false) end

function Frame:prerender()
    local c = self.placer.theme.colors
    Skin.solidFill(self, 0, 0, self.width, self.height, c.surface, false) -- 不透明：底下正在顯示的通知不透上來
    Skin.border(self, 0, 0, self.width, self.height, c.accent, false, 1)
    Skin.border(self, 1, 1, self.width - 2, self.height - 2, c.accent, false, 1)
    local t = c.text
    self:drawTextCentre(self.sampleText, self.width / 2, (self.height - self.fontH) / 2, t.r, t.g, t.b, t.a, self.font)
end

-- 方向鍵微調（Shift＝1px）、Enter＝完成；手把十字鍵與 A 走同一條（Focus 先問控制項 onFocusKey）
function Frame:onFocusKey(key)
    local p = self.placer
    local step = (isShiftKeyDown and isShiftKeyDown()) and 1 or NUDGE
    local x, y = self:getX(), self:getY()
    if key == Keyboard.KEY_LEFT then
        moveFrame(p, x - step, y)
    elseif key == Keyboard.KEY_RIGHT then
        moveFrame(p, x + step, y)
    elseif key == Keyboard.KEY_UP then
        moveFrame(p, x, y - step)
    elseif key == Keyboard.KEY_DOWN then
        moveFrame(p, x, y + step)
    elseif key == Keyboard.KEY_RETURN then
        finish(p, true)
    else
        return false
    end
    return true
end

function Frame:forceClick()
    finish(self.placer, true)
end

function Frame:onMouseDown(x, y)
    self._down, self._dragged = true, false
    self._downX, self._downY = getMouseX(), getMouseY()
    self._origX, self._origY = self:getX(), self:getY()
    self:setCapture(true)
    return true
end

local function dragFrame(f)
    if not f._down then return false end
    local mx, my = getMouseX(), getMouseY()
    if not f._dragged then
        if math.abs(mx - f._downX) <= DRAG_THRESHOLD and math.abs(my - f._downY) <= DRAG_THRESHOLD then
            return true
        end
        f._dragged = true
    end
    moveFrame(f.placer, f._origX + (mx - f._downX), f._origY + (my - f._downY))
    return true
end

local function releaseFrame(f)
    if not f._down then return false end
    f._down = nil
    f:setCapture(false)
    return true
end

function Frame:onMouseMove(dx, dy) return dragFrame(self) end
function Frame:onMouseMoveOutside(dx, dy) return dragFrame(self) end
function Frame:onMouseUp(x, y) return releaseFrame(self) end
function Frame:onMouseUpOutside(x, y) return releaseFrame(self) end

local function onDone(p) finish(p, true) end
local function onCancel(p) finish(p, false) end
local function onResetPlacer(p)
    Toast.setAnchor(nil)
    finish(p, false)
end

-- 打開移動模式：範例框放在目前的位置（玩家放過的或自動位置的第一則）
function History.move()
    if current then return end
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local theme = UI.Theme.create()
    local p = ISPanel.new(Placer, 0, 0, sw, sh)
    p.background = false
    p.moveWithMouse = false
    p.alwaysOnTop = true
    p.theme = theme
    p.font = theme.font or UIFont.Small
    p.fontH = getTextManager():getFontHeight(p.font)
    p:initialise()
    local f = ISPanel.new(Frame, 0, 0, Toast.WIDTH, Toast.HEIGHT)
    f.background = false
    f.placer = p
    f.font = p.font
    f.fontH = p.fontH
    f.sampleText = getText("IGUI_MinidoracatUI_Placer_Sample")
    f._focusKind = "button"
    f:initialise()
    p:addChild(f)
    p.frame = f
    p.btnDone = UI.Button.new({ x = 0, y = 0, title = getText("IGUI_MinidoracatUI_Placer_Done"), style = "primary",
        theme = theme, target = p, onClick = onDone })
    p.btnReset = UI.Button.new({ x = 0, y = 0, title = getText("IGUI_MinidoracatUI_History_Reset"),
        theme = theme, target = p, onClick = onResetPlacer })
    p.btnCancel = UI.Button.new({ x = 0, y = 0, title = getText("IGUI_MinidoracatUI_Cancel"),
        theme = theme, target = p, onClick = onCancel })
    p:addChild(p.btnDone)
    p:addChild(p.btnReset)
    p:addChild(p.btnCancel)
    p._targets = {
        { kind = "button", control = f, label = f.sampleText, captionSide = "none" },
        { kind = "group", controls = { p.btnDone, p.btnReset, p.btnCancel } },
    }
    local joypad = getJoypadData ~= nil and getJoypadData(0) ~= nil
    local hint = getText(joypad and "IGUI_MinidoracatUI_Placer_HintJoypad" or "IGUI_MinidoracatUI_Placer_Hint")
    p.hintLines = Text.wrap(hint, HINT_W, p.font)
    local x, top, up = Toast.stackOrigin(Toast.WIDTH)
    moveFrame(p, x, top)
    if Focus then p:setWantKeyEvents(true) end
    p:addToUIManager()
    p:setAlwaysOnTop(true) -- 只寫 Lua 欄位不會改變引擎排序（ARCHITECTURE §3.4 置頂契約）
    p:bringToTop()
    current = p
    if Focus then
        Focus.onFocus(p)
        Focus.focusControl(f, true)
        Focus.takeJoypad(p, 0)
    end
end

-- ---------- Dock 入口 ----------

local function dockLabel()
    return getText("IGUI_MinidoracatUI_History_Title")
end

local function dockActive()
    return win ~= nil and win:getIsVisible()
end

local function dockClick()
    History.toggle()
end

if UI.CAPABILITIES.dock and UI.Dock and UI.Dock.register then
    pcall(UI.Dock.register, {
        id = "toasthistory",
        order = 100,
        iconKey = "bell",
        label = dockLabel,
        onClick = dockClick,
        isActive = dockActive,
        isAvailable = syncShowEntry,
    })
end

-- 回主選單：收掉視窗與移動模式（UIManager 的元素會留著）
local function onMainMenuEnter()
    if current then finish(current, false) end
    if win and win:getIsVisible() then win:close() end
end

if Events and Events.OnMainMenuEnter and Events.OnMainMenuEnter.Add then
    Events.OnMainMenuEnter.Add(onMainMenuEnter)
end

-- 只給測試用：丟掉視窗與移動模式的參照、重讀選項；取目前的視窗與移動模式
function History._resetForTests()
    win, current = nil, nil
    optionsLoaded, showEntry = false, true
end
function History._windowForTests() return win end
function History._placerForTests() return current end

UI.ToastHistory = History
UI.CAPABILITIES.toastHistory = true

return History
