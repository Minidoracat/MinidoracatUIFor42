-- MinidoracatUI Widgets/Controls — 現代控制元件（API rev 7）：Button／TextField／Checkbox／Tabs；
-- rev 8 加 ColorPicker（CAPABILITIES.colorPicker）；rev 9 加 Slider（CAPABILITIES.slider），
-- ColorPicker 的 R/G/B 改用 Slider；rev 12 停用標籤改 textDisabled、Tabs 可停用（CAPABILITIES.tabsEnabled）。
--
-- 外觀全由框架自繪（theme token＋Skin 圓角，貼圖缺失退直角），原生 class 只當輸入／事件基底：
--   * Button 以 ISButton 為基底：保留原生 pressed／enable／onclick(target, button)／tooltip／
--     搖桿語意（ISButton.lua:33-64,316-346），prerender/render 整段自繪
--   * TextField 內含透明、無邊框的原生 ISTextEntryBox：IME、游標、選取維持原生
--     （ISTextEntryBox.lua:40-58）；文字變化以每幀比對偵測，因 IME 組字送出不觸發 onTextChange
--     （pz-family-docs pitfalls.md UI 節）
--   * Checkbox 用 Skin.toggle 畫開關；Tabs 為分段式頁籤列；Slider 用 Skin.slider 畫、自接拖曳
--     與滾輪（§3.9）；ColorPicker 組合 Slider＋TextField（§3.8）
--   * rev 10：各元件帶 `_focusKind` 供 Focus 自動找目標（Button／Checkbox／Tabs／Slider＝button、
--     TextField＝entry）；Checkbox:forceClick、Tabs／Slider:onFocusKey 讓鍵盤與手把操作
--   * rev 11：chrome（fill／border）乘 `theme.alpha or 1`，文字與 icon 不乘；Button 加 chip 樣式、
--     setActive／isActive、標題依寬度自動截字＋自動 tooltip；TextField 的 setWidth／setHeight 重排
--     內層 entry、opts.clearButton
--
-- 共通契約（docs/ARCHITECTURE.md §3.7）：.new(opts) 回傳已 initialise() 的元素；
-- opts.theme 省略＝UI.Theme.create()、opts.font 省略＝UIFont.Small；`internal` 欄位留給
-- consumer；所有 setter 對相同值是 no-op。per-frame 路徑零 table／closure 配置。
--
-- 載入自檢：同 FloatButton——核心或原生基底缺席就 return，CAPABILITIES.controls 維持 false。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end
if not ISButton then
    pcall(require, "ISUI/ISButton")
end
if not ISTextEntryBox then
    pcall(require, "ISUI/ISTextEntryBox")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Icons and UI.Text)
    or not (ISPanel and ISButton and ISTextEntryBox) then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.controls 探測）
end

local Skin = UI.Skin
local Icons = UI.Icons

local PAD_X = 10
local ICON_SIZE = 16
local ICON_GAP = 6
local DISABLED_ALPHA = 0.45 -- 停用時只淡化 chrome；標籤與圖樣改用 textDisabled、不淡化
-- primary 的深色字：theme 不是 Theme.create 建的（缺 rev 14 的 onAccent）時的退回值，與 onAccent 預設相同
local PRIMARY_TEXT = { r = 0.1, g = 0.08, b = 0.02, a = 1 }

local function themeOf(opts)
    return opts.theme or UI.Theme.create()
end

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text or "")
end

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function drawColorText(el, text, x, y, color, alpha, font)
    el:drawText(text, x, y, color.r, color.g, color.b, (color.a or 1) * (alpha or 1), font)
end

-- rev 11 theme.alpha：chrome（fill／border）乘它，文字與 icon 不乘（約定見 V1.lua Theme 段）
local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

-- rev 12 停用標籤色：theme 不是 Theme.create 建的（缺 textDisabled）時退回 textFaint，不 nil 炸
local function disabledColor(colors)
    return colors.textDisabled or colors.textFaint
end

-- rev 14：icon 是 Icons key（字串，以字色染色）或 consumer 的 Texture（原色，例如物品圖示）。
-- 回可畫的貼圖；未知 key／缺圖回 nil（只畫文字）。
local function iconTexture(icon)
    if icon == nil then
        return nil
    end
    if type(icon) == "string" then
        return Icons.get(icon)
    end
    return icon
end

-- pcall 具名函式＋傳參（不建 per-frame closure）；原色＝頂點色全白
local function drawTextureIcon(el, texture, x, y, size, a)
    el:drawTextureScaled(texture, x, y, size, size, a, 1, 1, 1)
end

-- ============================================================
-- Button
-- ============================================================

local Button = ISButton:derive("MinidoracatUIButton")

local STYLES = { normal = true, primary = true, danger = true, ghost = true, chip = true }

-- 標題可用寬＝寬度減 12（同 Economy U.setButtonTitle），有 icon 再扣 icon＋間距
local FIT_INSET = 12

-- 標題或寬度變了才重算（每幀只比兩個值）。截到字時沒有手動 tooltip 就用全標題當 tooltip
-- （_autoTip 標記是自己設的），寬度恢復後收掉；手動 tooltip 永不覆寫。
local function refitTitle(btn)
    local title, width = btn.title, btn.width
    if title == btn._fitSrc and width == btn._fitWidth then
        return
    end
    btn._fitSrc, btn._fitWidth = title, width
    local avail = width - FIT_INSET
    if iconTexture(btn.icon) ~= nil then
        avail = avail - ICON_SIZE - ICON_GAP
    end
    local fitted = UI.Text.fit(title, avail, btn.font)
    btn._fitTitle = fitted
    btn._fitW = fitted == title and btn._titleW or measure(btn.font, fitted)
    if fitted ~= title then
        if btn.tooltip == nil or btn._autoTip then
            btn.tooltip = title
            btn._autoTip = true
        end
    elseif btn._autoTip then
        btn.tooltip = nil
        btn._autoTip = nil
    end
end

local function buttonWidth(btn)
    local width = btn._titleW + PAD_X * 2
    if btn.icon then
        width = width + ICON_SIZE + (btn._titleW > 0 and ICON_GAP or 0)
    end
    return width
end

function Button:prerender()
    if self.isCollapsed then
        return
    end
    refitTitle(self)
    -- 原版 ISButton:prerender 在 :176 跑 tooltip；整段覆寫後自己呼叫。
    -- updateTooltip 只在 hover／搖桿焦點時才建 ISToolTip（ISButton.lua:316-346）。
    if self.tooltip or self.tooltipUI then
        self:updateTooltip()
    end

    local colors = self.theme.colors
    local w, h = self.width, self.height
    local enabled = self.enable
    local alpha = enabled and 1 or DISABLED_ALPHA -- 只乘 chrome；字與圖樣停用時改 textDisabled
    local ca = chromeAlpha(self.theme)
    local chrome = alpha * ca
    local hovered = enabled and self:isMouseOver()
    local pressed = hovered and self.pressed
    local style = self.style
    local shape = nil
    local textColor

    if style == "primary" and enabled then
        Skin.fill(self, 0, 0, w, h, colors.accent, nil, chrome)
        Skin.border(self, 0, 0, w, h, colors.accent, nil, chrome)
        textColor = colors.onAccent or PRIMARY_TEXT
    elseif style == "danger" then
        Skin.fill(self, 0, 0, w, h, colors.errorSurface, nil, chrome)
        Skin.border(self, 0, 0, w, h, colors.errorText, nil, chrome)
        textColor = colors.errorText
    elseif style == "ghost" then
        textColor = colors.text
    elseif style == "chip" then
        -- pill 太小時 Skin.fill／border 自己退直角（Skin.fits）；hover 底由本分支畫
        shape = "pill"
        if self._active then
            Skin.fill(self, 0, 0, w, h, colors.selected, shape, chrome)
            Skin.border(self, 0, 0, w, h, colors.accent, shape, chrome)
            -- 選中不只靠顏色（框與字跟閒置只差色相與亮度）：同 Tabs 的 2px accent 底線；
            -- 內縮避開 pill 圓角，正方形 chip（DatePicker 日曆鈕，圖樣在 [5, h-5)）縮 w/4
            local inset = math.min(math.floor(h / 2), math.floor(w / 4))
            local accent = colors.accent
            self:drawRect(inset, h - 4, w - inset * 2, 2, (accent.a or 1) * chrome, accent.r, accent.g, accent.b)
            textColor = colors.accent
        else
            if hovered then
                Skin.fill(self, 0, 0, w, h, colors.hover, shape, chrome)
            end
            Skin.border(self, 0, 0, w, h, colors.border, shape, chrome)
            textColor = hovered and colors.text or colors.textMuted
        end
    else -- normal；停用的 primary 也畫成 normal：淡化琥珀底上的 textDisabled 對比只有 1.04:1
        Skin.fill(self, 0, 0, w, h, colors.well, nil, chrome)
        Skin.border(self, 0, 0, w, h, colors.border, nil, chrome)
        textColor = colors.text
    end
    if pressed then
        Skin.fill(self, 0, 0, w, h, colors.selected, shape, ca)
    elseif hovered and style ~= "chip" then
        Skin.fill(self, 0, 0, w, h, colors.hover, nil, ca)
    end
    if not enabled then
        textColor = disabledColor(colors)
    end
    if self.joypadFocused then
        Skin.border(self, 1, 1, w - 2, h - 2, colors.accent, nil, ca)
    end

    local titleW = self._fitW
    local texture = iconTexture(self.icon)
    local contentW = titleW
    if texture then
        contentW = contentW + ICON_SIZE + (titleW > 0 and ICON_GAP or 0)
    end
    local x = math.floor((w - contentW) / 2)
    if texture then
        local iy = math.floor((h - ICON_SIZE) / 2)
        if type(self.icon) == "string" then
            Icons.draw(self, self.icon, x, iy, ICON_SIZE, textColor, textColor.a or 1)
        else
            -- 原色貼圖無法改成 textDisabled，停用時改以 DISABLED_ALPHA 淡化
            pcall(drawTextureIcon, self, texture, x, iy, ICON_SIZE, enabled and 1 or DISABLED_ALPHA)
        end
        x = x + ICON_SIZE + ICON_GAP
    end
    if titleW > 0 then
        drawColorText(self, self._fitTitle, x, math.floor((h - self._fontH) / 2), textColor, 1, self.font)
    end
end

function Button:render()
end

function Button:setTitle(title)
    title = title or ""
    if title == self.title then
        return
    end
    self.title = title
    self._titleW = measure(self.font, title)
    if self._autoWidth then
        self:fitWidth()
    end
end

function Button:fitWidth()
    local width = buttonWidth(self)
    if width ~= self.width then
        self:setWidth(width)
    end
end

function Button:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self.enable then
        return
    end
    self.enable = enabled
    if not enabled then
        self.pressed = false
    end
end

function Button:isEnabled()
    return self.enable == true
end

-- 手動 tooltip 優先：之後截字不再覆寫；nil＝交回自動（下一幀依截字狀態重判）
function Button:setTooltip(text)
    self._autoTip = nil
    self._fitSrc = nil
    if text == self.tooltip then
        return
    end
    self.tooltip = text -- nil：下一幀 updateTooltip 收掉已顯示的 ISToolTip
end

function Button:setStyle(style)
    if not STYLES[style] then
        style = "normal"
    end
    self.style = style
end

-- 只有 chip 樣式會畫出 active 狀態（selected 底、accent 框與字、accent 底線）
function Button:setActive(active)
    self._active = active == true
end

function Button:isActive()
    return self._active == true
end

-- rev 14：換圖示（Icons key、Texture 或 nil）。自動寬度時重算寬度；截字下一幀依新的可用寬重算
function Button:setIcon(icon)
    if icon == self.icon then
        return
    end
    self.icon = icon
    self._fitSrc = nil
    if self._autoWidth then
        self:fitWidth()
    end
end

-- opts: x, y, width?, height?, title, icon?（Icons key 或 Texture，rev 14）, style?（normal／primary／danger／ghost／chip）,
-- active?, theme?, font?, target?, onClick?, tooltip?
-- onClick(target, button)；disabled 時原生 onMouseUp 不觸發（ISButton.lua:45）。
-- 標題放不下時自動截字（見 refitTitle），self.title 仍是全標題。
function Button.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local title = opts.title or ""
    local fontH = fontHeight(font)
    local o = ISButton.new(Button, opts.x or 0, opts.y or 0, opts.width or 1,
        opts.height or (fontH + 10), title, opts.target, opts.onClick)
    o.theme = themeOf(opts)
    o.font = font
    o.icon = opts.icon
    o._active = opts.active == true
    o.style = STYLES[opts.style] and opts.style or "normal"
    o.tooltip = opts.tooltip
    o._fontH = fontH
    o._titleW = measure(font, title)
    o._focusKind = "button"
    o._autoWidth = opts.width == nil
    -- ISButton:new 會把過窄的寬度撐到標題寬＋10（ISButton.lua:493-495）；明示寬度以 consumer 為準
    o.width = opts.width or buttonWidth(o)
    o:initialise()
    return o
end

-- ============================================================
-- TextField
-- ============================================================

local TextField = ISPanel:derive("MinidoracatUITextField")

local FIELD_PAD = 6
local TEXTBOX_INSET = 2 -- UITextBox2.getInset() 無框時為 2（UITextBox2.java:547-550）

-- 內層 entry 跟著外框：x＝FIELD_PAD、寬＝外框寬減兩側內距、垂直置中
local function layoutEntry(field)
    local entry = field._entry
    if not entry then
        return -- 建構中（entry 尚未建立）
    end
    entry:setX(FIELD_PAD)
    entry:setWidth(field.width - FIELD_PAD * 2)
    entry:setY(math.floor((field.height - entry.height) / 2))
end

-- 原生 entry 保持透明、無邊框：setEditable 會重設 borderColor（ISTextEntryBox.lua:64-71），
-- 每次都要改回 alpha 0。prerender 裡 alpha 非 1 的分支畫 alpha 0 邊框＝不可見。
local function hideEntryChrome(entry)
    entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
end

local function applyEntryTextColor(field)
    local colors = field.theme.colors
    local c = field._enabled and colors.text or disabledColor(colors)
    field._entry:setTextRGBA(c.r, c.g, c.b, c.a or 1)
end

-- placeholder 依可用寬截字（放不下畫「前綴＋...」，不再畫出框外壓到旁邊的元件）；placeholder 或寬度變了才重算
-- （每幀只比兩個值）。截到字時沒有手動 tooltip 就用全文當 tooltip，放得下時收掉；手動 tooltip 永不覆寫
-- （同 Button refitTitle）。原生清除鈕只在有文字時出現（UITextBox2.java:188），不必扣它的寬
local function refitPlaceholder(field)
    local placeholder, width = field.placeholder, field.width
    if placeholder == field._phSrc and width == field._phWidth then
        return
    end
    field._phSrc, field._phWidth = placeholder, width
    local fitted = placeholder and UI.Text.fit(placeholder, width - (FIELD_PAD + TEXTBOX_INSET) * 2, field.font)
    field._phFit = fitted
    if fitted and fitted ~= placeholder then
        if field._tooltip == nil or field._autoTip then
            field._autoTip = true
            field._tooltip = placeholder
            field._entry:setTooltip(placeholder)
        end
    elseif field._autoTip then
        field._autoTip = nil
        field._tooltip = nil
        field._entry:setTooltip(nil)
    end
end

function TextField:prerender()
    if self.isCollapsed then
        return
    end
    local entry = self._entry
    -- IME 組字送出不觸發原生 onTextChange：每幀比對（字串比較，不配置）
    local text = entry:getInternalText() or ""
    if text ~= self._lastText then
        self._lastText = text
        if self.onChange then
            self.onChange(self, text)
        end
    end

    local colors = self.theme.colors
    local alpha = self._enabled and 1 or DISABLED_ALPHA
    local chrome = alpha * chromeAlpha(self.theme)
    local focused = entry:isFocused()
    Skin.fill(self, 0, 0, self.width, self.height, colors.well, nil, chrome)
    Skin.border(self, 0, 0, self.width, self.height, focused and colors.accent or colors.border, nil, chrome)
    refitPlaceholder(self)
    if text == "" and not focused and self._phFit then
        drawColorText(self, self._phFit, FIELD_PAD + TEXTBOX_INSET, entry.y + TEXTBOX_INSET,
            self._enabled and colors.textFaint or disabledColor(colors), 1, self.font)
    end
end

-- 點到 entry 外的內距也聚焦
function TextField:onMouseDown(x, y)
    if self._enabled then
        self._entry:focus()
    end
    return true
end

function TextField:getText()
    return self._entry:getInternalText() or ""
end

-- 不觸發 onChange：同步比對基準
function TextField:setText(text)
    text = text or ""
    if text == self:getText() then
        return
    end
    self._entry:setText(text)
    self._lastText = text
end

-- 外框改尺寸時內層 entry 一起重排（原版 setWidth／setHeight 只動外框）
function TextField:setWidth(width)
    ISPanel.setWidth(self, width)
    layoutEntry(self)
end

function TextField:setHeight(height)
    ISPanel.setHeight(self, height)
    layoutEntry(self)
end

function TextField:focus()
    if self._enabled then
        self._entry:focus()
    end
end

function TextField:isFocused()
    return self._entry:isFocused() == true
end

function TextField:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self._enabled then
        return
    end
    self._enabled = enabled
    local entry = self._entry
    entry:setEditable(enabled)
    hideEntryChrome(entry)
    if not enabled then
        entry:unfocus()
    end
    applyEntryTextColor(self)
end

-- 手動 tooltip 優先：之後 placeholder 截字不再覆寫；nil＝交回自動（下一幀依截字狀態重判）
function TextField:setTooltip(text)
    self._autoTip = nil
    self._phSrc = nil
    if text == self._tooltip then
        return
    end
    self._tooltip = text
    self._entry:setTooltip(text) -- 原生 prerender 負責 hover 顯示與收掉（ISTextEntryBox.lua:205-230）
end

-- opts: x, y, width, height?, text?, placeholder?, theme?, font?, onlyNumbers?, maxLength?, clearButton?,
-- onChange?。onChange(field, text)。clearButton＝原生輸入框右側的清除鈕（ISTextEntryBox.lua:101-103
-- → UITextBox2.setClearButton:918）
function TextField.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = fontHeight(font)
    local width = opts.width or 160
    local height = opts.height or (fontH + 10)
    local o = ISPanel.new(TextField, opts.x or 0, opts.y or 0, width, height)
    o.background = false
    o.theme = themeOf(opts)
    o.font = font
    o.placeholder = opts.placeholder
    o.onChange = opts.onChange
    o._enabled = true
    o:initialise()
    o._focusKind = "entry" -- Focus 以內層原生 entry 聚焦，焦點框畫在本元件外框

    local text = opts.text or ""
    local entryH = fontH + TEXTBOX_INSET * 2
    local entry = ISTextEntryBox:new(text, FIELD_PAD, math.floor((height - entryH) / 2),
        width - FIELD_PAD * 2, entryH)
    entry.font = font
    entry:initialise()
    entry:instantiate()
    hideEntryChrome(entry)
    if opts.onlyNumbers then
        entry:setOnlyNumbers(true)
    end
    if opts.maxLength then
        entry:setMaxTextLength(opts.maxLength)
    end
    if opts.clearButton then
        entry:setClearButton(true)
    end
    o._entry = entry
    o._lastText = entry:getInternalText() or text
    applyEntryTextColor(o)
    o:addChild(entry)
    return o
end

-- ============================================================
-- Checkbox
-- ============================================================

local Checkbox = ISPanel:derive("MinidoracatUICheckbox")

local TOGGLE_WIDTH = 36
local LABEL_GAP = 8

local function drawFallbackBox(box, alpha, colors)
    local size = math.min(14, box.height)
    local y = math.floor((box.height - size) / 2)
    local border = colors.border
    box:drawRectBorder(0, y, size, size, (border.a or 1) * alpha, border.r, border.g, border.b)
    if box.checked then
        local on = colors.accent
        box:drawRect(3, y + 3, size - 6, size - 6, (on.a or 1) * alpha, on.r, on.g, on.b)
    end
end

function Checkbox:prerender()
    if self.isCollapsed then
        return
    end
    local colors = self.theme.colors
    local alpha = self._enabled and 1 or DISABLED_ALPHA
    local ca = chromeAlpha(self.theme)
    if self._enabled and self:isMouseOver() then
        Skin.fill(self, 0, 0, self.width, self.height, colors.hover, nil, ca)
    end
    -- toggle 幾何不足（height < 20）回 false：退回方框
    if not Skin.toggle(self, 0, 0, TOGGLE_WIDTH, self.height, self.checked, self._toggleColors, alpha * ca) then
        drawFallbackBox(self, alpha * ca, colors)
    end
    drawColorText(self, self.label, TOGGLE_WIDTH + LABEL_GAP, math.floor((self.height - self._fontH) / 2),
        self._enabled and colors.text or disabledColor(colors), 1, self.font)
end

function Checkbox:onMouseDown(x, y)
    self._down = self._enabled
    return true
end

function Checkbox:onMouseUp(x, y)
    if self._down then
        self._down = false
        self:setChecked(not self.checked)
    end
    return true
end

function Checkbox:onMouseUpOutside(x, y)
    self._down = false
end

function Checkbox:getChecked()
    return self.checked
end

-- 鍵盤 Enter／Space、手把 A（Focus 的 activate）：與點擊同一條路徑，disabled 不動
function Checkbox:forceClick()
    if self._enabled then
        self:setChecked(not self.checked)
    end
end

function Checkbox:setChecked(checked, silent)
    checked = checked == true
    if checked == self.checked then
        return
    end
    self.checked = checked
    if not silent and self.onChange then
        self.onChange(self.target, checked, self)
    end
end

function Checkbox:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self._enabled then
        return
    end
    self._enabled = enabled
    self._down = false
end

function Checkbox:setLabel(label)
    self.label = label or ""
end

-- opts: x, y, width, height?, label, checked?, theme?, font?, target?, onChange?
-- onChange(target, checked, box)
function Checkbox.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = fontHeight(font)
    local label = opts.label or ""
    local width = opts.width or (TOGGLE_WIDTH + LABEL_GAP + measure(font, label))
    local o = ISPanel.new(Checkbox, opts.x or 0, opts.y or 0, width, opts.height or math.max(20, fontH + 4))
    o.background = false
    o.theme = themeOf(opts)
    o.font = font
    o.label = label
    o.checked = opts.checked == true
    o.target = opts.target
    o.onChange = opts.onChange
    o._enabled = true
    o._focusKind = "button"
    o._fontH = fontH
    local colors = o.theme.colors
    -- 建構時一次組好（prerender 不配置）；knob 省略＝Skin 預設白
    o._toggleColors = { off = colors.well, on = colors.accent, border = colors.border }
    o:initialise()
    return o
end

-- ============================================================
-- Tabs
-- ============================================================

local Tabs = ISPanel:derive("MinidoracatUITabs")

local TAB_PAD_X = 12
local TAB_GAP = 2
local TAB_INSET = 2

local function findItem(tabs, id)
    local items = tabs._items
    for i = 1, #items do
        if items[i].id == id then
            return items[i]
        end
    end
    return nil
end

local function layoutTabs(tabs)
    local items = tabs._items
    local x = TAB_INSET
    local any = false
    for i = 1, #items do
        local item = items[i]
        if item.visible then
            item.x = x
            item.width = item.labelWidth + TAB_PAD_X * 2
            x = x + item.width + TAB_GAP
            any = true
        end
    end
    local width = any and (x - TAB_GAP + TAB_INSET) or TAB_INSET * 2
    if tabs._autoWidth and width ~= tabs.width then
        tabs:setWidth(width)
    end
end

local function itemAt(tabs, x)
    local items = tabs._items
    for i = 1, #items do
        local item = items[i]
        if item.visible and x >= item.x and x < item.x + item.width then
            return item
        end
    end
    return nil
end

-- 停用（整列 setEnabled(false) 或單項 setItemEnabled）：標籤 textDisabled、不 hover、點不動；整列停用時
-- chrome 另乘 DISABLED_ALPHA。選中項仍畫底與底線（停用不改選取）
function Tabs:prerender()
    if self.isCollapsed then
        return
    end
    local colors = self.theme.colors
    local h = self.height
    local enabled = self._enabled
    local ca = chromeAlpha(self.theme) * (enabled and 1 or DISABLED_ALPHA)
    Skin.fill(self, 0, 0, self.width, h, colors.well, nil, ca)
    Skin.border(self, 0, 0, self.width, h, colors.border, nil, ca)

    local hovered = enabled and self:isMouseOver() and itemAt(self, self:getMouseX()) or nil
    local textY = math.floor((h - self._fontH) / 2)
    local items = self._items
    for i = 1, #items do
        local item = items[i]
        if item.visible then
            local textColor = colors.textMuted
            if item.id == self.selected then
                Skin.fill(self, item.x, TAB_INSET, item.width, h - TAB_INSET * 2, colors.selected, nil, ca)
                local accent = colors.accent
                self:drawRect(item.x + 6, h - TAB_INSET - 2, item.width - 12, 2,
                    (accent.a or 1) * ca, accent.r, accent.g, accent.b)
                textColor = colors.text
            elseif item == hovered and item.enabled then
                Skin.fill(self, item.x, TAB_INSET, item.width, h - TAB_INSET * 2, colors.hover, nil, ca)
                textColor = colors.text
            end
            if not (enabled and item.enabled) then
                textColor = disabledColor(colors)
            end
            drawColorText(self, item.label, item.x + math.floor((item.width - item.labelWidth) / 2),
                textY, textColor, 1, self.font)
        end
    end
end

function Tabs:onMouseDown(x, y)
    local item = self._enabled and itemAt(self, x)
    if item and item.enabled then
        self:setSelected(item.id)
    end
    return true
end

function Tabs:setSelected(id, silent)
    if id == self.selected or not findItem(self, id) then
        return
    end
    self.selected = id
    if not silent and self.onSelect then
        self.onSelect(self.target, id, self)
    end
end

function Tabs:getSelected()
    return self.selected
end

-- 往前／後切到下一個可見且可用的頁籤（不循環；手把 LB／RB 與焦點框上的左右鍵）。回 true＝有切換
function Tabs:selectRelative(delta)
    if not self._enabled then
        return false
    end
    local items = self._items
    local at = nil
    for i = 1, #items do
        if items[i].id == self.selected then at = i end
    end
    local i = (at or 0) + delta
    while i >= 1 and i <= #items do
        if items[i].visible and items[i].enabled then
            self:setSelected(items[i].id)
            return true
        end
        i = i + delta
    end
    return false
end

function Tabs:onFocusKey(key)
    if key == Keyboard.KEY_LEFT then return self:selectRelative(-1) or true end
    if key == Keyboard.KEY_RIGHT then return self:selectRelative(1) or true end
    return false
end

-- 隱藏選中項不自動切換（由 consumer 決定）
function Tabs:setItemVisible(id, visible)
    local item = findItem(self, id)
    visible = visible ~= false
    if not item or item.visible == visible then
        return
    end
    item.visible = visible
    layoutTabs(self)
end

function Tabs:setItemLabel(id, label)
    local item = findItem(self, id)
    label = label or ""
    if not item or item.label == label then
        return
    end
    item.label = label
    item.labelWidth = measure(self.font, label)
    layoutTabs(self)
end

-- rev 12：整列停用（Focus 跳過它）。程式呼叫 setSelected 不受停用限制
function Tabs:setEnabled(enabled)
    self._enabled = enabled ~= false
end

function Tabs:isEnabled()
    return self._enabled
end

-- rev 12：單項停用：照樣顯示、標籤 textDisabled，點擊與左右鍵跳過；停用選中項不自動切換
function Tabs:setItemEnabled(id, enabled)
    local item = findItem(self, id)
    if item then
        item.enabled = enabled ~= false
    end
end

function Tabs:isItemEnabled(id)
    local item = findItem(self, id)
    return item ~= nil and item.enabled
end

-- opts: x, y, width?, height?, items={ {id=, label=}, ... }, selected?, theme?, font?, target?, onSelect?
-- onSelect(target, id, tabs)；點已選中的不觸發
function Tabs.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = fontHeight(font)
    local o = ISPanel.new(Tabs, opts.x or 0, opts.y or 0, opts.width or 0, opts.height or (fontH + 12))
    o.background = false
    o.theme = themeOf(opts)
    o.font = font
    o.target = opts.target
    o.onSelect = opts.onSelect
    o._fontH = fontH
    o._autoWidth = opts.width == nil
    o._items = {}
    local source = opts.items or {}
    for i = 1, #source do
        local label = source[i].label or ""
        o._items[i] = { id = source[i].id, label = label, labelWidth = measure(font, label),
            visible = true, enabled = true, x = 0, width = 0 }
    end
    o.selected = opts.selected
    o._enabled = true
    o._focusKind = "button"
    layoutTabs(o)
    o:initialise()
    return o
end

-- ============================================================
-- Slider（rev 9）
-- ============================================================

local Slider = ISPanel:derive("MinidoracatUISlider")

local SLIDER_KNOB = 12 -- 同 Skin.slider 的 knob 直徑；track 左右內縮半顆，knob 在兩端不出界
local SLIDER_INSET = SLIDER_KNOB / 2
local VALUE_GAP = 6

-- 夾限＋以 min 為基準依 step 四捨五入；浮點誤差或 step 除不盡時最多只到 max
local function quantize(slider, v)
    local min, max, step = slider.min, slider.max, slider.step
    if v < min then v = min elseif v > max then v = max end
    v = min + math.floor((v - min) / step + 0.5) * step
    if v > max then v = max end
    return v
end

-- 元素座標 x → 未量化值（setValue 負責夾限與量化）
local function sliderValueAt(slider, x)
    return slider.min + (x - SLIDER_INSET) / slider._trackW * (slider.max - slider.min)
end

function Slider:prerender()
    if self.isCollapsed then
        return
    end
    local enabled = self._enabled
    local alpha = enabled and 1 or DISABLED_ALPHA
    local tc = self.theme.colors
    local colors = self._colors -- 建構時建好，這裡只換欄位不配置
    colors.track = (enabled and (self._drag or self:isMouseOver())) and tc.hover or tc.well
    local range = self.max - self.min
    local ratio = range > 0 and (self._value - self.min) / range or 0
    Skin.slider(self, SLIDER_INSET, 0, self._trackW, self.height, ratio, colors, alpha * chromeAlpha(self.theme))
    if self._text then
        drawColorText(self, self._text, self._textX, self._textY, tc.text, alpha, self.font)
    end
end

-- 按在 track（含兩端半顆 knob）上：跳到該值並開始拖曳；setCapture 讓拖出元件外仍收 move/up
function Slider:onMouseDown(x, y)
    if self._enabled and x < self._trackW + SLIDER_KNOB then
        self._drag = true
        self:setCapture(true)
        self:setValue(sliderValueAt(self, x))
    end
    return true
end

local function dragSlider(slider)
    if not slider._drag then
        return false
    end
    slider:setValue(sliderValueAt(slider, slider:getMouseX()))
    return true
end

local function releaseSlider(slider)
    if not slider._drag then
        return false
    end
    slider._drag = nil
    slider:setCapture(false)
    return true
end

function Slider:onMouseMove(dx, dy) return dragSlider(self) end
function Slider:onMouseMoveOutside(dx, dy) return dragSlider(self) end
function Slider:onMouseUp(x, y) return releaseSlider(self) end
function Slider:onMouseUpOutside(x, y) return releaseSlider(self) end

-- 滾輪往上（del < 0，同 ISScrollingListBox.lua:353）＝加一步；disabled 不吃事件，讓父層捲動
function Slider:onMouseWheel(del)
    if not self._enabled then
        return false
    end
    self:setValue(self._value + (del < 0 and self.step or -self.step))
    return true
end

function Slider:getValue()
    return self._value
end

-- 夾限＋量化；量化後相同值 no-op；silent 不呼叫 onChange
function Slider:setValue(value, silent)
    value = tonumber(value)
    if not value or value ~= value then
        return
    end
    value = quantize(self, value)
    if value == self._value then
        return
    end
    self._value = value
    if self.format then
        self._text = self.format(value) -- 只在值變時格式化，prerender 不呼叫
    end
    if not silent and self.onChange then
        self.onChange(self.target, value, self)
    end
end

function Slider:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self._enabled then
        return
    end
    self._enabled = enabled
    if not enabled then
        releaseSlider(self)
    end
end

function Slider:isEnabled()
    return self._enabled
end

-- 焦點框上的左右鍵（手把方向同）±step、Home／End 到兩端；disabled 不吃，讓焦點移開
function Slider:onFocusKey(key)
    if not self._enabled then
        return false
    end
    if key == Keyboard.KEY_LEFT then
        self:setValue(self._value - self.step)
    elseif key == Keyboard.KEY_RIGHT then
        self:setValue(self._value + self.step)
    elseif key == Keyboard.KEY_HOME then
        self:setValue(self.min)
    elseif key == Keyboard.KEY_END then
        self:setValue(self.max)
    else
        return false
    end
    return true
end

-- opts: x, y, width, height?, min, max, step?, value?, theme?, font?, target?, onChange?, format?
-- onChange(target, value, slider)：值實際改變才呼叫。format(value) → string：有給就在右側畫值，
-- 文字寬以 format(max) 建構時量一次並從 track 扣掉。
function Slider.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = fontHeight(font)
    local width = opts.width or 160
    local height = opts.height or math.max(20, fontH + 4)
    local min = tonumber(opts.min) or 0
    local max = tonumber(opts.max) or 1
    if max < min then
        max = min
    end
    local step = tonumber(opts.step)
    if not step or step <= 0 then
        step = (max - min) / 20
        if step <= 0 then
            step = 1
        end
    end
    local o = ISPanel.new(Slider, opts.x or 0, opts.y or 0, width, height)
    o.background = false
    o.theme = themeOf(opts)
    o.font = font
    o.min, o.max, o.step = min, max, step
    o.target = opts.target
    o.onChange = opts.onChange
    o.format = opts.format
    o._focusKind = "button"
    o._enabled = true
    local textW = 0
    if o.format then
        textW = measure(font, o.format(max)) + VALUE_GAP
    end
    o._trackW = math.max(1, width - SLIDER_KNOB - textW)
    o._textX = o._trackW + SLIDER_KNOB + VALUE_GAP
    o._textY = math.floor((height - fontH) / 2)
    local colors = o.theme.colors
    o._colors = { track = colors.well, fill = colors.accent, knob = colors.text, border = colors.border }
    o:setValue(opts.value or min, true)
    o:initialise()
    return o
end

-- ============================================================
-- ColorPicker（rev 8；rev 9 起 R/G/B 為 Slider）
-- ============================================================

local ColorPicker = ISPanel:derive("MinidoracatUIColorPicker")

local SWATCH = 20
local SWATCH_GAP = 6
local RING = 2 -- 選中／hover 外框離色塊的距離；格子四周預留同寬
local SECTION_GAP = 8
local ROW_GAP = 4
local FIELD_GAP = 8
local CHANNEL_LABELS = { "R", "G", "B", "#" }
-- R/G/B 滑桿的 fill：各自通道色，一眼分得出哪條是哪個通道
local CHANNEL_FILLS = {
    { r = 0.90, g = 0.25, b = 0.25, a = 1 },
    { r = 0.30, g = 0.80, b = 0.35, a = 1 },
    { r = 0.30, g = 0.50, b = 1.00, a = 1 },
}
local HEX_DIGITS = "0123456789ABCDEF"

-- 24 色：鮮色／深色／淡色＋中性色三列（寬度足夠時一列 8 格）
local DEFAULT_SWATCHES = {
    { r = 0.90, g = 0.20, b = 0.20 }, -- red
    { r = 0.95, g = 0.55, b = 0.10 }, -- orange
    { r = 0.98, g = 0.85, b = 0.15 }, -- yellow
    { r = 0.25, g = 0.70, b = 0.30 }, -- green
    { r = 0.15, g = 0.75, b = 0.85 }, -- cyan
    { r = 0.20, g = 0.45, b = 0.90 }, -- blue
    { r = 0.60, g = 0.30, b = 0.80 }, -- purple
    { r = 0.95, g = 0.45, b = 0.65 }, -- pink
    { r = 0.55, g = 0.08, b = 0.08 }, -- dark red
    { r = 0.50, g = 0.30, b = 0.15 }, -- brown
    { r = 0.85, g = 0.65, b = 0.13 }, -- gold
    { r = 0.10, g = 0.40, b = 0.15 }, -- dark green
    { r = 0.05, g = 0.45, b = 0.50 }, -- teal
    { r = 0.10, g = 0.15, b = 0.45 }, -- navy
    { r = 0.30, g = 0.20, b = 0.65 }, -- indigo
    { r = 0.00, g = 0.00, b = 0.00 }, -- black
    { r = 1.00, g = 0.75, b = 0.50 }, -- peach
    { r = 1.00, g = 0.95, b = 0.60 }, -- light yellow
    { r = 0.60, g = 0.90, b = 0.55 }, -- light green
    { r = 0.55, g = 0.75, b = 1.00 }, -- light blue
    { r = 0.80, g = 0.65, b = 0.95 }, -- lavender
    { r = 0.75, g = 0.75, b = 0.78 }, -- silver
    { r = 0.45, g = 0.45, b = 0.45 }, -- gray
    { r = 1.00, g = 1.00, b = 1.00 }, -- white
}

-- 0-1 → 0-255 整數（四捨五入、夾限）；非數字視為 0
local function toByte(v)
    local n = math.floor((tonumber(v) or 0) * 255 + 0.5)
    if n < 0 then return 0 end
    if n > 255 then return 255 end
    return n
end

-- 不依賴 string.format 的 %02X 與 tonumber 的 base 參數：查表最保守
local function hexByte(n)
    local hi = math.floor(n / 16)
    local lo = n - hi * 16
    return string.sub(HEX_DIGITS, hi + 1, hi + 1) .. string.sub(HEX_DIGITS, lo + 1, lo + 1)
end

local function parseHexByte(s)
    local hi = string.find(HEX_DIGITS, string.upper(string.sub(s, 1, 1)), 1, true)
    local lo = string.find(HEX_DIGITS, string.upper(string.sub(s, 2, 2)), 1, true)
    return (hi - 1) * 16 + (lo - 1)
end

local function swatchAt(picker, x, y)
    local swatches = picker._swatches
    for i = 1, #swatches do
        local s = swatches[i]
        if x >= s.x and x < s.x + SWATCH and y >= s.y and y < s.y + SWATCH then
            return i
        end
    end
    return nil
end

local function matchSwatch(picker)
    local swatches = picker._swatches
    for i = 1, #swatches do
        local s = swatches[i]
        if s.br == picker._r and s.bg == picker._g and s.bb == picker._b then
            return i
        end
    end
    return nil
end

-- 寫回其他控制項：Slider:setValue silent 與 TextField:setText 都不會再觸發回呼；
-- 來源滑桿已是新值（setValue 相同值 no-op），skip 只用來不覆寫正在輸入的 hex 欄
local function syncFields(picker, skip)
    local sliders = picker._sliders
    local r, g, b = picker._r, picker._g, picker._b
    sliders[1]:setValue(r, true)
    sliders[2]:setValue(g, true)
    sliders[3]:setValue(b, true)
    if picker._hex ~= skip then
        picker._hex:setText("#" .. hexByte(r) .. hexByte(g) .. hexByte(b))
    end
end

-- 唯一改色入口；相同值 no-op。skip＝正在輸入的欄位（不覆寫使用者游標所在處）
local function applyColor(picker, r, g, b, silent, skip)
    if r == picker._r and g == picker._g and b == picker._b then
        return
    end
    picker._r, picker._g, picker._b = r, g, b
    local preview = picker._preview
    preview.r, preview.g, preview.b = r / 255, g / 255, b / 255
    picker._selected = matchSwatch(picker)
    syncFields(picker, skip)
    if not silent and picker.onChange then
        picker.onChange(picker.target, picker:getColor(), picker)
    end
end

-- R／G／B 滑桿的 onChange(target=picker, value, slider)；slider._channel 指出通道
local function onChannelSlide(picker, value, slider)
    local r, g, b = picker._r, picker._g, picker._b
    local channel = slider._channel
    if channel == 1 then r = value elseif channel == 2 then g = value else b = value end
    applyColor(picker, r, g, b, false, slider)
end

local function formatByte(v)
    return tostring(math.floor(v + 0.5))
end

local function onHexText(field, text)
    local hex = string.match(text, "^#?(%x%x%x%x%x%x)$")
    if not hex then
        return
    end
    applyColor(field._picker, parseHexByte(string.sub(hex, 1, 2)), parseHexByte(string.sub(hex, 3, 4)),
        parseHexByte(string.sub(hex, 5, 6)), false, field)
end

function ColorPicker:prerender()
    if self.isCollapsed then
        return
    end
    local colors = self.theme.colors
    local enabled = self._enabled
    local alpha = enabled and 1 or DISABLED_ALPHA
    local chrome = alpha * chromeAlpha(self.theme)
    local hovered = enabled and self:isMouseOver() and swatchAt(self, self:getMouseX(), self:getMouseY()) or nil
    local swatches = self._swatches
    for i = 1, #swatches do
        local s = swatches[i]
        -- 色塊與預覽是內容（使用者挑的顏色），不乘 theme.alpha；框線與選取環是 chrome
        Skin.fill(self, s.x, s.y, SWATCH, SWATCH, s, nil, alpha)
        Skin.border(self, s.x, s.y, SWATCH, SWATCH, colors.border, nil, chrome)
        if i == self._selected then
            Skin.border(self, s.x - RING, s.y - RING, SWATCH + RING * 2, SWATCH + RING * 2, colors.accent, nil, chrome)
            Skin.border(self, s.x - 1, s.y - 1, SWATCH + 2, SWATCH + 2, colors.accent, nil, chrome)
        elseif i == hovered then
            Skin.border(self, s.x - RING, s.y - RING, SWATCH + RING * 2, SWATCH + RING * 2, colors.text, nil, chrome)
        end
    end
    local px, py, pw, ph = self._previewX, self._hexY, self._previewW, self._hex.height
    Skin.fill(self, px, py, pw, ph, self._preview, nil, alpha)
    Skin.border(self, px, py, pw, ph, colors.border, nil, chrome)
    local labels = self._labels
    for i = 1, #labels do
        local l = labels[i]
        drawColorText(self, l.text, l.x, l.y, colors.textMuted, alpha, self.font)
    end
end

function ColorPicker:onMouseDown(x, y)
    local i = self._enabled and swatchAt(self, x, y)
    if i then
        local s = self._swatches[i]
        applyColor(self, s.br, s.bg, s.bb, false, nil)
    end
    return true
end

function ColorPicker:getColor()
    return { r = self._r / 255, g = self._g / 255, b = self._b / 255 }
end

function ColorPicker:setColor(color, silent)
    if type(color) ~= "table" then
        return
    end
    applyColor(self, toByte(color.r), toByte(color.g), toByte(color.b), silent, nil)
end

function ColorPicker:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self._enabled then
        return
    end
    self._enabled = enabled
    local sliders = self._sliders
    for i = 1, #sliders do
        sliders[i]:setEnabled(enabled)
    end
    self._hex:setEnabled(enabled)
end

-- opts: x, y, width, color?={r,g,b}, swatches?, theme?, font?, target?, onChange?
-- onChange(target, color, picker)；color 為新 table {r,g,b}（0-1，8-bit 量化）。
-- 高度依寬度與色卡數自動計算（getHeight() 即內容高度）。
function ColorPicker.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local theme = themeOf(opts)
    local width = opts.width or 240

    -- 色卡格：依寬度換行；色塊用量化後的值，顯示色＝選中後回報的色
    local source = opts.swatches or DEFAULT_SWATCHES
    local cols = math.max(1, math.floor((width - RING * 2 + SWATCH_GAP) / (SWATCH + SWATCH_GAP)))
    local swatches = {}
    for i = 1, #source do
        local br, bg, bb = toByte(source[i].r), toByte(source[i].g), toByte(source[i].b)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        swatches[i] = { r = br / 255, g = bg / 255, b = bb / 255, a = 1, br = br, bg = bg, bb = bb,
            x = RING + col * (SWATCH + SWATCH_GAP), y = RING + row * (SWATCH + SWATCH_GAP) }
    end
    local rows = math.ceil(#swatches / cols)
    local lowerY = 0
    if rows > 0 then
        lowerY = RING * 2 + rows * SWATCH + (rows - 1) * SWATCH_GAP + SECTION_GAP
    end

    -- 下半部：R／G／B 三列滑桿（左側標籤），最後一列 # hex 欄＋右側長方形預覽
    local fontH = fontHeight(font)
    local sliderH = math.max(20, fontH + 4) -- 同 Slider 預設高
    local fieldH = fontH + 10 -- 同 TextField 預設高
    local labelW = 0
    for i = 1, #CHANNEL_LABELS do
        labelW = math.max(labelW, measure(font, CHANNEL_LABELS[i]))
    end
    local controlX = labelW + 4
    local controlW = math.max(1, width - controlX)
    local hexY = lowerY + 3 * (sliderH + ROW_GAP)
    local previewW = fieldH * 2

    local o = ISPanel.new(ColorPicker, opts.x or 0, opts.y or 0, width, hexY + fieldH)
    o.background = false
    o.theme = theme
    o.font = font
    o.target = opts.target
    o.onChange = opts.onChange
    o._enabled = true
    o._swatches = swatches
    o._hexY = hexY
    o._previewX = width - previewW
    o._previewW = previewW
    o._labels = {}
    o._sliders = {}
    o:initialise()

    for i = 1, 3 do
        local y = lowerY + (i - 1) * (sliderH + ROW_GAP)
        o._labels[i] = { text = CHANNEL_LABELS[i], x = 0, y = y + math.floor((sliderH - fontH) / 2) }
        local slider = Slider.new{ x = controlX, y = y, width = controlW, height = sliderH, min = 0, max = 255,
            step = 1, theme = theme, font = font, target = o, onChange = onChannelSlide, format = formatByte }
        slider._colors.fill = CHANNEL_FILLS[i]
        slider._channel = i
        o._sliders[i] = slider
        o:addChild(slider)
    end
    o._labels[4] = { text = CHANNEL_LABELS[4], x = 0, y = hexY + math.floor((fieldH - fontH) / 2) }
    local hex = TextField.new{ x = controlX, y = hexY, width = math.max(1, o._previewX - FIELD_GAP - controlX),
        height = fieldH, theme = theme, font = font, maxLength = 7, onChange = onHexText }
    hex._picker = o
    o._hex = hex
    o:addChild(hex)

    local c = opts.color
    o._r, o._g, o._b = -1, -1, -1 -- 讓首次 applyColor 必定寫入
    o._preview = { r = 1, g = 1, b = 1, a = 1 }
    if type(c) == "table" then
        applyColor(o, toByte(c.r), toByte(c.g), toByte(c.b), true, nil)
    else
        applyColor(o, 255, 255, 255, true, nil)
    end
    return o
end

ColorPicker.DEFAULT_SWATCHES = DEFAULT_SWATCHES

UI.Button = Button
UI.TextField = TextField
UI.Checkbox = Checkbox
UI.Tabs = Tabs
UI.Slider = Slider
UI.ColorPicker = ColorPicker
UI.CAPABILITIES.controls = true
UI.CAPABILITIES.colorPicker = true
UI.CAPABILITIES.slider = true
UI.CAPABILITIES.tabsEnabled = true

return Button
