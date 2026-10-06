-- MinidoracatUI Widgets/Dropdown — 通用單選下拉（API rev 14，CAPABILITIES.dropdown）：UI.Dropdown。
-- 取代原版 ISComboBox 的外觀：收合狀態像 normal Button（well 底＋border，左側標籤、右側 Skin.arrow），
-- 點開是整個 session 共用的清單 popup（同 DatePicker／FilterBar 類型下拉的 popup 模式）。
--
--   UI.Dropdown.new{ x?, y?, width?, height?, options = { {id, label}, ... }, selected?, placeholder?, maxRows?=8,
--                    theme?, font?, target?, onChange?, tooltip? } -> 已 initialise() 的元素（consumer addChild）
--   方法：setOptions(options)、setSelected(id, silent)、getSelected()、setEnabled(b)／isEnabled()、isOpen()、
--         open()、close()；模組函式 UI.Dropdown.close(scope?)（dd:close() 就是 scope＝自己）
--   回呼：onChange(target, id, dropdown)——選取實際改變時一次（點列、Enter／Space、手把 A）；先關清單再回呼；
--         setSelected 非 silent 也回呼；setOptions 把消失的選取清成 nil 時不回呼（程式改動）
--
-- 出處（原版 Lua，快照 42.21.0）：
--   共用 popup              ISComboBox.lua:185-198（SharedPopup：整個 session 一個，setAlwaysOnTop＋setCapture）、
--                           :200-215（showPopup／hidePopup＝add/removeFromUIManager）
--   外面按下即關           ISComboBox.lua:123-131（capture 中的 popup 在外面按下時關閉）、:133-157（點列：
--                           先 hidePopup 再 onChange）
--   錨點                    ISComboBox.lua:37-42（parentCombo 不見就收掉）、:159-179（錨在元件下方，放不下翻上方）
--   自然寬                  ISComboBox.lua:534-542（setWidthToOptions：最長選項＋左右內距＋箭頭）
--   標籤裁切                ISComboBox.lua:283-300 用 stencil 裁標籤；本檔改用 UI.Text.fit 截字，不碰 stencil
--   capture 路由            UIManager.java:472-492、:661-704（capture 中的元素先被問；點擊停在第一個回 true 的元素）
--   實例化                  ISUIElement.lua:588（setCapture 自己 instantiate）、:1319-1322（setAlwaysOnTop 只作用
--                           於已實例化的元件，所以在 addToUIManager 之後呼叫）
--   可見判定                ISUIElement.lua:690-695（isReallyVisible＝javaObject:isReallyVisible，含祖先）
--   按鈕基底                ISButton.lua:33-79（onMouseDown 記 pressed、onMouseUp 只在 pressed＋enable 時呼叫
--                           onclick(target, button)；forceClick 檢查 visible＋enable、只呼叫一次 onclick）、
--                           :111-176（原版 prerender 在 :176 跑 updateTooltip；整段覆寫後自己呼叫）、:316-346（tooltip）
--   key 派送                UIManager.java:1435-1466（只派 top-level，倒序：popup 先於視窗被問）→
--                           UIElement.java:2185-2214（先 onKeyPress、後 isKeyConsumed：答案來自 Focus 帳本）
--   手把                    JoyPadSetup.lua:431-458（持有焦點的 UI 收 onJoypadDown／onJoypadDir*）、
--                           :1056-1064（onJoypadBeforeDeactivate）
--
-- 鍵盤與手把只在 CAPABILITIES.focus 為 true 時接上；沒有 Focus 時清單只能用滑鼠。收合元件不接左右鍵
-- （手把十字鍵左右照常移到別的目標，瀏覽時不會誤改值）。字串字面值只含 ASCII；本檔沒有自己的顯示文字。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text) or not (ISPanel and ISButton) then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.dropdown 探測）
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
local Focus = UI.Focus -- 選用：缺席時清單只能用滑鼠

local Skin = UI.Skin
local Text = UI.Text

local PAD_X = 10           -- 標籤左內距＝箭頭右內距（同 Button）
local ARROW_GAP = 6        -- 標籤與箭頭之間
local DISABLED_ALPHA = 0.45 -- 停用只淡化 chrome；字與箭頭改 textDisabled、不淡化（同 Controls）
local MENU_PAD = 4         -- 清單上下內距
local ROW_PAD_X = 10       -- 列文字左內距
local MARK_W = 2           -- 選中列左側的 accent 記號（選中不只靠顏色）
local SCROLL_W = 3         -- 細捲軸寬；選項多於可見列才畫，並從列寬扣掉 SCROLL_W＋MENU_PAD
local DEFAULT_ROWS = 8
local MAX_DEPTH = 32

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text or "")
end

local function drawColorText(el, text, x, y, c, font)
    el:drawText(text, x, y, c.r, c.g, c.b, c.a or 1, font)
end

local function rootOf(el)
    for _ = 1, MAX_DEPTH do
        if type(el) ~= "table" or el.parent == nil then break end
        el = el.parent
    end
    return el
end

local function within(el, scope)
    for _ = 1, MAX_DEPTH do
        if el == nil then return false end
        if el == scope then return true end
        el = el.parent
    end
    return false
end

local Dropdown = ISButton:derive("MinidoracatUIDropdown")
local Popup = ISPanel:derive("MinidoracatUIDropdownPopup")
local popup -- 唯一實例，第一次開啟才建立；popup.owner ~= nil＝開著

-- 複製選項（consumer 事後改表不影響元件）；id 為 nil 的項略過（nil 保留給「沒選」）。標籤寬在這裡量一次
local function copyOptions(list, font)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local o = list[i]
        if type(o) == "table" and o.id ~= nil then
            local label = o.label
            if label == nil then label = o.id end
            label = tostring(label)
            out[#out + 1] = { id = o.id, label = label, w = measure(font, label) }
        end
    end
    return out
end

local function indexOf(dd, id)
    if id == nil then return nil end
    local opts = dd._options
    for i = 1, #opts do
        if opts[i].id == id then return i end
    end
    return nil
end

-- 收合狀態顯示的字：選中項標籤或 placeholder（只在選取或選項改變時跑；截字由 prerender 依寬度快取）
local function refreshLabel(dd)
    local i = indexOf(dd, dd._selected)
    dd._label = i and dd._options[i].label or dd.placeholder
end

local function naturalWidth(dd)
    local w = measure(dd.font, dd.placeholder)
    local opts = dd._options
    for i = 1, #opts do
        if opts[i].w > w then w = opts[i].w end
    end
    return w + PAD_X * 2 + ARROW_GAP + Skin.ARROW_W
end

-- ============================================================
-- 清單 popup
-- ============================================================

local function closePopup()
    local p = popup
    if p == nil or p.owner == nil then return end
    local dd, back = p.owner, p.kbReturn
    p.owner, p.kbReturn = nil, nil
    p:setVisible(false)
    p:removeFromUIManager()
    if Focus ~= nil then
        Focus.releaseJoypad(p)
        if back then Focus.refocus(dd) end
    end
end

-- 游標移到第 i 列（夾在範圍內），捲動讓它看得到
local function moveCursor(p, i)
    local n = #p.owner._options
    if i > n then i = n end
    if i < 1 then i = 1 end
    p.cursor = i
    if i < p.first then
        p.first = i
    elseif i > p.first + p.rows - 1 then
        p.first = i - p.rows + 1
    end
end

-- 開啟與 setOptions 重整時跑（不是每幀）：列數、寬高、捲動位置、游標
local function layoutPopup(p, cursor)
    local dd = p.owner
    local opts = dd._options
    local n = #opts
    local rh = dd._fontH + 8
    local fit = math.floor((getCore():getScreenHeight() - MENU_PAD * 2) / rh)
    p.rowH = rh
    p.rows = math.max(1, math.min(n, dd.maxRows, fit))
    local extra = ROW_PAD_X * 2 + (n > p.rows and SCROLL_W + MENU_PAD or 0)
    local w = dd.width
    for i = 1, n do
        if opts[i].w + extra > w then w = opts[i].w + extra end
    end
    p:setWidth(w)
    p:setHeight(p.rows * rh + MENU_PAD * 2)
    local last = math.max(1, n - p.rows + 1)
    if p.first > last then p.first = last end
    moveCursor(p, cursor)
end

local function rowAt(p, y)
    if y < MENU_PAD then return nil end
    local i = p.first + math.floor((y - MENU_PAD) / p.rowH)
    if i > p.first + p.rows - 1 or i > #p.owner._options then return nil end
    return i
end

-- 先關再改：onChange 若重排頁面，看到的是已關閉的清單。選同一項 setSelected 是 no-op，不回呼
local function pick(p, i)
    local dd = p.owner
    local opt = dd._options[i]
    closePopup()
    if opt then dd:setSelected(opt.id) end
end

-- 錨點失效（元件不在畫面、祖先收合、停用、選項清空）就關
function Popup:anchorAlive()
    local dd = self.owner
    if dd == nil or not dd.enable or #dd._options == 0 or not dd:isReallyVisible() then
        return false
    end
    local el = dd
    for _ = 1, MAX_DEPTH do
        if el == nil then break end
        if el.isCollapsed then return false end
        el = el.parent
    end
    return true
end

-- 錨在元件下方；放不下翻到上方，再夾回螢幕內（同 DatePicker Popup:place）
function Popup:place()
    local dd = self.owner
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local x, ay = dd:getAbsoluteX(), dd:getAbsoluteY()
    local y = ay + dd.height + 2
    if y + self.height > sh then y = ay - self.height - 2 end
    if y + self.height > sh then y = sh - self.height end
    if y < 0 then y = 0 end
    if x + self.width > sw then x = sw - self.width end
    if x < 0 then x = 0 end
    self:setX(x)
    self:setY(y)
end

-- 只畫可見列（不用 stencil）；選中列 selected 底＋左側 accent 記號＋accent 字，游標列（鍵盤或滑鼠移動）疊 hover。
-- 選項多於可見列時右側畫細捲軸（well 軌道＋textFaint 拇指）
function Popup:prerender()
    if self.isCollapsed then return end
    if not self:anchorAlive() then
        closePopup()
        return
    end
    self:place() -- 視窗拖曳或重排時跟著走
    local dd = self.owner
    local colors = dd.theme.colors
    local ca = chromeAlpha(dd.theme)
    local w, h, rh = self.width, self.height, self.rowH
    Skin.fill(self, 0, 0, w, h, colors.surface, nil, ca)
    Skin.border(self, 0, 0, w, h, colors.border, nil, ca)
    local opts = dd._options
    local n = #opts
    local scroll = n > self.rows
    local rowW = w - 2
    if scroll then rowW = rowW - SCROLL_W - MENU_PAD end
    local ty = math.floor((rh - dd._fontH) / 2)
    local y = MENU_PAD
    for i = self.first, math.min(n, self.first + self.rows - 1) do
        local opt = opts[i]
        local color = colors.text
        if opt.id == dd._selected then
            Skin.fill(self, 1, y, rowW, rh, colors.selected, "rect", ca)
            Skin.fill(self, 1, y, MARK_W, rh, colors.accent, "rect", ca)
            color = colors.accent
        end
        if i == self.cursor then
            Skin.fill(self, 1, y, rowW, rh, colors.hover, "rect", ca)
        end
        drawColorText(self, opt.label, MENU_PAD + ROW_PAD_X, y + ty, color, dd.font)
        y = y + rh
    end
    if scroll then
        local trackH = h - MENU_PAD * 2
        local thumbH = math.max(8, math.floor(trackH * self.rows / n))
        local thumbY = MENU_PAD + math.floor((trackH - thumbH) * (self.first - 1) / (n - self.rows))
        local sx = w - MENU_PAD - SCROLL_W
        Skin.fill(self, sx, MENU_PAD, SCROLL_W, trackH, colors.well, "rect", ca)
        Skin.fill(self, sx, thumbY, SCROLL_W, thumbH, colors.textFaint, "rect", ca)
    end
end

function Popup:render()
end

function Popup:onMouseDown(x, y)
    local dd = self.owner
    if dd == nil then return false end
    if self:isMouseOver() then return true end -- 裡面：不漏到頁面
    if dd:isReallyVisible() and dd:isMouseOver() then
        return false -- 自己的元件：交給它的 click 切換開關
    end
    closePopup()
    return false
end

function Popup:onMouseUp(x, y)
    if self.owner == nil or not self:isMouseOver() then return false end
    local i = rowAt(self, y)
    if i then pick(self, i) end
    return true
end

-- 滑鼠移動帶著游標走：hover 與鍵盤游標是同一列，不會同時亮兩列
function Popup:onMouseMove(dx, dy)
    if self.owner == nil or not self:isMouseOver() then return end
    local i = rowAt(self, self:getMouseY())
    if i then self.cursor = i end
end

-- 滾輪往上（del < 0）往前捲；游標不動
function Popup:onMouseWheel(del)
    if self.owner == nil then return false end
    local last = math.max(1, #self.owner._options - self.rows + 1)
    self.first = math.max(1, math.min(last, self.first + (del < 0 and -1 or 1)))
    return true
end

-- 鍵盤：上下／PgUp／PgDn／Home／End 移游標，Enter／小鍵盤 Enter／Space 選，Esc／Tab 關（焦點框回元件）
local function popupKey(p, key)
    local k = Keyboard
    if key == k.KEY_ESCAPE or key == k.KEY_TAB then closePopup(); return true end
    if key == k.KEY_RETURN or key == k.KEY_NUMPADENTER or key == k.KEY_SPACE then pick(p, p.cursor); return true end
    if key == k.KEY_UP then moveCursor(p, p.cursor - 1); return true end
    if key == k.KEY_DOWN then moveCursor(p, p.cursor + 1); return true end
    if key == k.KEY_PRIOR then moveCursor(p, p.cursor - p.rows); return true end
    if key == k.KEY_NEXT then moveCursor(p, p.cursor + p.rows); return true end
    if key == k.KEY_HOME then moveCursor(p, 1); return true end
    if key == k.KEY_END then moveCursor(p, #p.owner._options); return true end
    return false
end

-- key 事件只在 Focus 存在時要（setWantKeyEvents）；按下時動作，同一次按住的 release 由 Focus 帳本消耗
-- （包括關掉清單的那一下：popup 已離開 UI 清單，release 由視窗回答）
function Popup:onKeyPress(key)
    if self.owner == nil then return end
    Focus.pressed(key)
    if popupKey(self, key) then Focus.eat(key) end
end

-- 只有上下與 PgUp／PgDn 連發；引擎每幀都派 repeat，repeatDue 照作業系統節奏放行
function Popup:onKeyRepeat(key)
    if self.owner == nil then return end
    local k = Keyboard
    if key ~= k.KEY_UP and key ~= k.KEY_DOWN and key ~= k.KEY_PRIOR and key ~= k.KEY_NEXT then return end
    if not Focus.repeatDue(key) then return end
    if popupKey(self, key) then Focus.eat(key) end
end

function Popup:onKeyRelease(key)
    Focus.release(key)
end

function Popup:isKeyConsumed(key)
    return Focus.consumed(key)
end

-- 手把：A＝Enter、B＝Esc、十字鍵上下＝方向鍵
function Popup:onJoypadDown(button, joypadData)
    if self.owner == nil or Joypad == nil then return end
    if button == Joypad.AButton then popupKey(self, Keyboard.KEY_RETURN)
    elseif button == Joypad.BButton then popupKey(self, Keyboard.KEY_ESCAPE) end
end
function Popup:onJoypadDirUp() if self.owner ~= nil then popupKey(self, Keyboard.KEY_UP) end end
function Popup:onJoypadDirDown() if self.owner ~= nil then popupKey(self, Keyboard.KEY_DOWN) end end
function Popup:onJoypadBeforeDeactivate() closePopup() end

-- ============================================================
-- 元件
-- ============================================================

-- 停用時 chrome 乘 DISABLED_ALPHA、字與箭頭 textDisabled；pressed／hover 疊層同 normal Button。開著時框改 accent、
-- 箭頭朝上（狀態不只靠顏色）
function Dropdown:prerender()
    if self.isCollapsed then return end
    if self.tooltip or self.tooltipUI then
        self:updateTooltip()
    end
    local w, h = self.width, self.height
    local label = self._label
    if label ~= self._fitSrc or w ~= self._fitWidth then
        self._fitSrc, self._fitWidth = label, w
        self._fitLabel = Text.fit(label, w - PAD_X * 2 - ARROW_GAP - Skin.ARROW_W, self.font)
    end
    local colors = self.theme.colors
    local enabled = self.enable
    local ca = chromeAlpha(self.theme)
    local chrome = ca * (enabled and 1 or DISABLED_ALPHA)
    local open = popup ~= nil and popup.owner == self
    local hovered = enabled and self:isMouseOver()
    Skin.fill(self, 0, 0, w, h, colors.well, nil, chrome)
    Skin.border(self, 0, 0, w, h, open and colors.accent or colors.border, nil, chrome)
    if hovered and self.pressed then
        Skin.fill(self, 0, 0, w, h, colors.selected, nil, ca)
    elseif hovered then
        Skin.fill(self, 0, 0, w, h, colors.hover, nil, ca)
    end
    if self.joypadFocused then
        Skin.border(self, 1, 1, w - 2, h - 2, colors.accent, nil, ca)
    end
    local textColor, arrowColor
    if not enabled then
        textColor = colors.textDisabled or colors.textFaint
        arrowColor = textColor
    else
        textColor = self._selected == nil and colors.textFaint or colors.text
        arrowColor = open and colors.accent or colors.textMuted
    end
    if self._fitLabel ~= "" then
        drawColorText(self, self._fitLabel, PAD_X, math.floor((h - self._fontH) / 2), textColor, self.font)
    end
    Skin.arrow(self, w - PAD_X - Skin.ARROW_W, math.floor((h - Skin.ARROW_H) / 2), open, arrowColor)
end

function Dropdown:render()
end

-- 開著時清單已有 capture：再按自己的元件由 popup 放行到這裡，切換成關閉
local function onClick(_, dd)
    if dd:isOpen() then
        closePopup()
    else
        dd:open()
    end
end

function Dropdown:open()
    if self:isOpen() or not self.enable or #self._options == 0 then return end
    closePopup()
    if popup == nil then
        popup = ISPanel.new(Popup, 0, 0, 100, 100)
        popup.background = false
        popup:initialise()
        popup:setCapture(true)                -- 外面的點擊先到這裡，才能關閉
        popup:setWantKeyEvents(Focus ~= nil)  -- key 事件只派給 top-level
    end
    local p = popup
    p.owner = self
    -- 記住是不是鍵盤開的：只有那樣關閉時才把焦點框還給元件
    p.kbReturn = Focus ~= nil and Focus.focused() == self
    p.first = 1
    layoutPopup(p, indexOf(self, self._selected) or 1)
    p:place()
    p:setVisible(true)
    p:addToUIManager()
    p:setAlwaysOnTop(true) -- 實例化（addToUIManager）之後才有效
    p:bringToTop()
    -- 元件所在的 root 正持有手把焦點：清單借走，關閉時歸還
    if Focus ~= nil and Focus.holdsJoypad(rootOf(self)) then Focus.takeJoypad(p, 0) end
end

-- 模組函式兼方法：UI.Dropdown.close() 關掉開著的；close(scope) 只在擁有者是 scope 或其子孫時關；
-- dd:close() 即 scope＝自己
function Dropdown.close(scope)
    local p = popup
    if p == nil or p.owner == nil then return end
    if scope ~= nil and not within(p.owner, scope) then return end
    closePopup()
end

function Dropdown:isOpen()
    return popup ~= nil and popup.owner == self
end

-- 複製；目前選取仍在就保留，否則靜默清成 nil。自動寬度時重算寬度；開著的清單重排（選項清空就關）
function Dropdown:setOptions(options)
    self._options = copyOptions(options, self.font)
    if indexOf(self, self._selected) == nil then
        self._selected = nil
    end
    refreshLabel(self)
    if self._autoWidth then
        self:setWidth(naturalWidth(self))
    end
    if self:isOpen() then
        if #self._options == 0 then
            closePopup()
        else
            layoutPopup(popup, popup.cursor)
        end
    end
end

-- 未知 id 忽略、nil＝清空、相同值 no-op；silent 不回呼。不受停用限制（程式呼叫）
function Dropdown:setSelected(id, silent)
    if id == self._selected or (id ~= nil and indexOf(self, id) == nil) then return end
    self._selected = id
    refreshLabel(self)
    if not silent and self.onChange then
        self.onChange(self.target, id, self)
    end
end

function Dropdown:getSelected()
    return self._selected
end

function Dropdown:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self.enable then return end
    self.enable = enabled
    if not enabled then
        self.pressed = false
        Dropdown.close(self)
    end
end

function Dropdown:isEnabled()
    return self.enable == true
end

-- 寬度省略＝最長標籤（含 placeholder）＋左右內距＋箭頭；高度省略＝字高＋10（同 Button）。
-- maxRows 省略或小於 1＝8。原生 ISButton 只當輸入基底：onclick 是開關、forceClick（Focus 的 Enter／Space／A）＝開啟
function Dropdown.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = getTextManager():getFontHeight(font)
    local o = ISButton.new(Dropdown, opts.x or 0, opts.y or 0, opts.width or 1, opts.height or (fontH + 10), "",
        opts.target, onClick)
    o.theme = opts.theme or UI.Theme.create()
    o.font = font
    o._fontH = fontH
    o.placeholder = opts.placeholder or ""
    local rows = tonumber(opts.maxRows)
    o.maxRows = (rows and rows >= 1) and math.floor(rows) or DEFAULT_ROWS
    o.onChange = opts.onChange
    o.tooltip = opts.tooltip
    o._focusKind = "button"
    o._autoWidth = opts.width == nil
    o._options = copyOptions(opts.options, font)
    if indexOf(o, opts.selected) then
        o._selected = opts.selected
    end
    refreshLabel(o)
    -- ISButton:new 會把過窄的寬度撐到標題寬＋10（ISButton.lua:493-495）；明示寬度以 consumer 為準
    o.width = opts.width or naturalWidth(o)
    o:initialise()
    return o
end

-- 測試鉤子：共用 popup 實例（尚未開過為 nil）
function Dropdown._popupForTests()
    return popup
end

UI.Dropdown = Dropdown
UI.CAPABILITIES.dropdown = true

return Dropdown
