-- MinidoracatUI Widgets/DatePicker — 日期（API rev 11，CAPABILITIES.datePicker）：UI.Date／UI.DateField／
-- UI.DatePicker。收編自 MinidoracatEconomyFor42 的 ECDatePicker＋EC.parseDay／daysInMonth／utcDate＋
-- U.localOffsetMinutes。
--
--   UI.Date        純函式的曆法（Hinnant days-from-civil）：不用 os.time／os.date——Kahlua 的 os.date 固定 UTC、
--                  標準 Lua 是當地時間，兩邊算出來會不同（家族 pitfalls.md）。Kahlua 的 % 對負數往零截斷，
--                  所以 1970 年前的星期一律用 floor 除法。
--   UI.DateField   ISPanel：UI.TextField（"YYYY-MM-DD"）＋日曆按鈕（chip 樣式的 UI.Button，向量畫日曆圖樣）。
--                  文字框是唯一的真相：日曆只把選到的日寫回文字框。onChange(target, text, field) 在文字實際
--                  改變時呼叫一次：打字（TextField 每幀比對，涵蓋 IME）、日曆選日／清除、失焦正規化。
--   UI.DatePicker  整個 session 共用一個月曆 popup，第一次開啟才建立；42 個日格是畫出來的，不是子元件。
--                  close(scope?)：scope 省略＝關掉開著的；否則只在 popup 所屬欄位是 scope 或其子孫時關。
--
-- 引擎出處（快照 42.20.4-20260826）：
--   setText 不通知          ISTextEntryBox.lua:109-115 → UITextBox2.java:780-802；update :398-471 也不呼叫
--                           onTextChange——所以日曆寫回後由本檔自己回呼 onChange
--   失焦                    UITextBox2.java:657-664、:1018-1022（unfocus／setDoingTextEntry(false) 呼叫
--                           onLostFocus）、:860-864（轉 Lua 表的 onLostFocus）；ISTextEntryBox.lua:25-26 預設空函式
--   popup 模式              ISComboBox.lua:185-215（setAlwaysOnTop＋setCapture＋add/removeFromUIManager）、
--                           :123-157（capture 中的 popup 在外面按下時關閉）、:37-42（anchor 不見就收掉）、
--                           :159-179（錨在元件下方、靠近螢幕底邊時翻到上方）
--   capture 路由            UIManager.java:472-492（capture 中的元素 isOverElement 回 1，先被問）、:661-704
--                           （點擊停在第一個回 true 的元素）
--   實例化                  ISUIElement.lua:588（setCapture 自己 instantiate）、:1319-1322（setAlwaysOnTop 只作用
--                           於已實例化的元件，所以在 addToUIManager 之後呼叫）、:1365-1376、:1828-1835
--   key 派送                UIManager.java:1435-1466（只派 top-level，倒序走 UI 清單：popup 先於視窗被問）→
--                           UIElement.java:2185-2214（先 onKeyPress、後 isKeyConsumed：答案來自 Focus 帳本）
--   手把                    JoyPadSetup.lua:431-458（持有焦點的 UI 收 onJoypadDown／onJoypadDir*）、:678-680、
--                           :1056-1064（onJoypadBeforeDeactivate）
--   可見判定                ISUIElement.lua:690（isReallyVisible）
--   按鈕                    ISButton.lua:70-79（forceClick 檢查 visible＋enable，只呼叫一次 onclick）、
--                           :316-346（tooltip）
--   本地時差                LuaManager.java:8993-8998 → :1569（getHourMinute＝JVM 當地時間的 "H:MM"）
--   key 名稱                Keyboard.KEY_ESCAPE/RETURN（ISHandcraftWindow.lua:290、ISUI/ISTextBox.lua）、
--                           KEY_LEFT/RIGHT/UP/DOWN（DebugUIs/AnimationClipViewer.lua:693+）、KEY_PRIOR/KEY_NEXT
--                           （DebugUIs/StreamMapWindow.lua:180-183）、KEY_TAB（ISUI/ISMPEditServer.lua:245-260）、
--                           KEY_HOME/KEY_DELETE（Core.java:2056-2076）
--
-- 鍵盤與手把只在 CAPABILITIES.focus 為 true 時接上；沒有 Focus 時日曆只能用滑鼠。
-- 字串字面值只含 ASCII（Kahlua 載入會截斷非 ASCII）；顯示文字走 Translate。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.datePicker 探測）
end
if not (UI.Button and UI.TextField) then
    pcall(require, "MinidoracatUI/Widgets/Controls")
end
if not (UI.Button and UI.TextField) then
    return -- DateField 由 Controls 組成
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
local Focus = UI.Focus

local Skin = UI.Skin
local Button = UI.Button
local TextField = UI.TextField

local T = "IGUI_MinidoracatUI_Date_"
local DAY_MS = 86400000
local MIN_YEAR, MAX_YEAR = 1, 9999 -- 欄位只有四位數年份，月曆不離開這個範圍

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text or "")
end

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function drawText(el, text, x, y, color, alpha, font)
    el:drawText(text, x, y, color.r, color.g, color.b, (color.a or 1) * (alpha or 1), font)
end

local function drawTextCentre(el, text, x, y, color, font)
    el:drawTextCentre(text, x, y, color.r, color.g, color.b, color.a or 1, font)
end

-- ============================================================
-- Date
-- ============================================================

local Date = {}

local function pad2(n)
    return n < 10 and ("0" .. n) or tostring(n)
end

local function pad4(y)
    if y >= 1000 then return tostring(y) end
    if y >= 100 then return "0" .. y end
    if y >= 10 then return "00" .. y end
    return "000" .. y
end

-- 格里曆：四年一閏、百年不閏、四百年再閏
function Date.daysInMonth(y, m)
    if m == 2 then
        return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) and 29 or 28
    end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end

-- "YYYY-MM-DD" 或 "YYYY/M/D"（前後空白可）；年份 1..9999、月日要合法，否則 nil
function Date.parse(text)
    if type(text) ~= "string" then return nil end
    local y, m, d = string.match(text, "^%s*(%d%d%d%d)[-/](%d%d?)[-/](%d%d?)%s*$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y < MIN_YEAR or m < 1 or m > 12 or d < 1 or d > Date.daysInMonth(y, m) then return nil end
    return y, m, d
end

function Date.format(y, m, d)
    return pad4(y) .. "-" .. pad2(m) .. "-" .. pad2(d)
end

-- 1970-01-01 起算的日數（Hinnant days_from_civil）
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = m > 2 and m - 3 or m + 9
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- 某個比 UTC 快 offsetMin 分鐘的時鐘上，該日 00:00 對應的 UTC 毫秒；格式不合法回 nil
function Date.dayStart(text, offsetMin)
    local y, m, d = Date.parse(text)
    if not y then return nil end
    return daysFromCivil(y, m, d) * DAY_MS - (tonumber(offsetMin) or 0) * 60000
end

-- ms＋offsetMin 分鐘的曆日（Hinnant civil_from_days）
function Date.fromMs(ms, offsetMin)
    local days = math.floor((ms + (tonumber(offsetMin) or 0) * 60000) / DAY_MS)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- 本地時差（分鐘）：getHourMinute() 的當地時分減 UTC 時分，夾進 -12h..+14h 並取 15 分鐘倍數（吸收秒差）
function Date.localOffsetMinutes()
    local ok, hm = pcall(getHourMinute)
    if not ok or type(hm) ~= "string" then return 0 end
    local h, m = string.match(hm, "^(%d+):(%d+)$")
    if not h then return 0 end
    local utcMin = math.floor((getTimestampMs() % DAY_MS) / 60000)
    local diff = (tonumber(h) * 60 + tonumber(m)) - utcMin
    if diff > 840 then diff = diff - 1440 elseif diff < -720 then diff = diff + 1440 end
    return math.floor((diff + 7) / 15) * 15
end

-- 0＝週日。1970-01-01 是週四，所以 +4；floor 除法讓 1970 年前也落在 0..6
local function weekday(y, m, d)
    local n = daysFromCivil(y, m, d) + 4
    return n - math.floor(n / 7) * 7
end

-- ============================================================
-- DateField
-- ============================================================

local DateField = ISPanel:derive("MinidoracatUIDateField")
local DateButton = Button:derive("MinidoracatUIDateButton")
local DatePicker = {}
local active     -- 開著的共用 popup（關閉時 nil）
local openPicker -- 定義在 DatePicker 段

local BUTTON_GAP = 4
local SAMPLE = "0000-00-00"

local function fire(field, text)
    if field.onChange then
        field.onChange(field.target, text, field)
    end
end

-- 靜默寫入文字框，實際改變時回呼一次
local function commit(field, value)
    local text = field._text
    if text:getText() == value then return end
    text:setText(value)
    fire(field, value)
end

-- TextField 每幀比對到的變化（打字、IME）
local function onTextChanged(textField, text)
    fire(textField._dateField, text)
end

-- 失焦正規化："2026/9/7" → "2026-09-07"；不合法的文字原樣留著
local function onEntryLostFocus(entry)
    local field = entry._dateField
    local y, m, d = Date.parse(field._text:getText())
    if y then commit(field, Date.format(y, m, d)) end
end

local function layoutField(field)
    local text, button = field._text, field._button
    if not (text and button) then return end
    local w, h = field.width, field.height
    text:setX(0)
    text:setY(0)
    text:setWidth(math.max(1, w - BUTTON_GAP - h))
    text:setHeight(h)
    button:setX(w - h)
    button:setY(0)
    button:setWidth(h)
    button:setHeight(h)
end

function DateField:setWidth(width)
    ISPanel.setWidth(self, width)
    layoutField(self)
end

function DateField:setHeight(height)
    ISPanel.setHeight(self, height)
    layoutField(self)
end

function DateField:getText()
    return self._text:getText()
end

-- 靜默：不觸發 onChange
function DateField:setText(text)
    self._text:setText(text or "")
end

function DateField:getDate()
    return Date.parse(self._text:getText())
end

function DateField:dayStart(offsetMin)
    if offsetMin == nil then offsetMin = Date.localOffsetMinutes() end
    return Date.dayStart(self._text:getText(), offsetMin)
end

function DateField:setEnabled(enabled)
    enabled = enabled ~= false
    if enabled == self._enabled then return end
    self._enabled = enabled
    self._text:setEnabled(enabled)
    self._button:setEnabled(enabled)
    if not enabled then DatePicker.close(self) end
end

function DateField:isEnabled()
    return self._enabled == true
end

function DateField:focus()
    self._text:focus()
end

-- 取消輸入焦點（觸發失焦正規化），並關掉自己的日曆
function DateField:blur()
    self._text._entry:unfocus()
    DatePicker.close(self)
end

-- 原生 root 的 host 用：寫入兩個快取的描述（輸入框、日曆按鈕），不另外配置
function DateField:appendTargets(out, label)
    local targets = self._targets
    targets[1].label = label
    out[#out + 1] = targets[1]
    out[#out + 1] = targets[2]
    return out
end

-- 日曆圖樣（Icons 沒有日曆貼圖）：裝訂環、表頭色帶、2×3 點陣。圖樣屬 icon，不乘 theme.alpha
local function drawGlyph(el, x, y, size, c, alpha)
    local a = (c.a or 1) * alpha
    local top = y + 3
    el:drawRectBorder(x, top, size, size - 3, a, c.r, c.g, c.b)
    el:drawRect(x, top, size, 3, a, c.r, c.g, c.b)
    el:drawRect(x + 3, y, 2, 4, a, c.r, c.g, c.b)
    el:drawRect(x + size - 5, y, 2, 4, a, c.r, c.g, c.b)
    local step = math.floor((size - 4) / 3)
    if step < 2 then return end
    for row = 0, 1 do
        for col = 0, 2 do
            el:drawRect(x + 3 + col * step, top + 6 + row * step, 2, 2, a, c.r, c.g, c.b)
        end
    end
end

function DateButton:render()
    Button.render(self)
    local size = math.min(self.width, self.height) - 10
    if size < 9 then size = 9 end
    local colors = self.theme.colors
    local c = colors.textDisabled or colors.textFaint -- rev 12：停用圖樣同停用標籤，不另外淡化
    if self.enable then
        c = (self:isActive() or self:isMouseOver()) and colors.accent or colors.textMuted
    end
    drawGlyph(self, math.floor((self.width - size) / 2), math.floor((self.height - size) / 2), size, c, 1)
end

-- 同一個欄位再按一次＝關閉
local function onButtonClick(field)
    if active ~= nil and active.field == field then
        DatePicker.close()
    else
        openPicker(field)
    end
end

-- opts: x?, y?, width?, height?, text?, placeholder?, theme?, font?, target?, onChange?, opaque?
-- （rev 18：月曆不透明；省略＝看欄位所在頂層視窗的 opaque）
-- onChange(target, text, field)。height 預設字高＋10；width 預設容得下 "0000-00-00" 與 placeholder
-- 的輸入框＋4px 間距＋正方形日曆按鈕。
function DateField.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local theme = opts.theme or UI.Theme.create()
    local height = opts.height or (fontHeight(font) + 10)
    local placeholder = opts.placeholder or getText(T .. "Hint")
    local width = opts.width
    if width == nil then
        width = math.max(measure(font, SAMPLE), measure(font, placeholder)) + 24 + BUTTON_GAP + height
    end
    local o = ISPanel.new(DateField, opts.x or 0, opts.y or 0, width, height)
    o.background = false
    o.theme, o.font = theme, font
    o.target, o.onChange = opts.target, opts.onChange
    o._popupOpaque = opts.opaque == true
    o._enabled = true
    o:initialise()

    local text = TextField.new{ x = 0, y = 0, width = math.max(1, width - BUTTON_GAP - height), height = height,
        text = opts.text, placeholder = placeholder, theme = theme, font = font, onChange = onTextChanged }
    text._dateField = o
    local entry = text._entry
    entry._dateField = o
    entry.onLostFocus = onEntryLostFocus
    o._text = text
    o:addChild(text)

    local openLabel = getText(T .. "Open")
    local button = Button.new{ x = width - height, y = 0, width = height, height = height, title = "",
        style = "chip", theme = theme, font = font, target = o, onClick = onButtonClick, tooltip = openLabel }
    setmetatable(button, DateButton)
    button._focusLabel = openLabel
    o._button = button
    o:addChild(button)

    o._targets = {
        { kind = "entry", control = entry, frame = text },
        { kind = "button", control = button, label = openLabel },
    }
    return o
end

-- ============================================================
-- DatePicker（共用 popup）
-- ============================================================

local PAD = 8
local GAP = 6
local ROWS = 6 -- 一個月最多 31 天＋6 天前導，六列就夠
local WEEK_KEYS = { "WeekSun", "WeekMon", "WeekTue", "WeekWed", "WeekThu", "WeekFri", "WeekSat" }
local NAV_SPECS = { { "<<", -12, "PrevYear" }, { "<", -1, "PrevMonth" }, { ">", 1, "NextMonth" }, { ">>", 12, "NextYear" } }
local DAY_TEXT = {}
for d = 1, 31 do DAY_TEXT[d] = tostring(d) end

local Popup = ISPanel:derive("MinidoracatUIDatePicker")
local popup  -- 唯一的實例，第一次開啟才建立

-- 焦點停靠：0＝日格（游標格就是焦點框），其後依序是可用的導覽 chip 與 Today／Clear／Close。
-- 快取陣列只在 setMonth（導覽鈕啟用狀態唯一會變的時機）原地重建，render 不配置。
local function rebuildStops(self)
    local stops, n = self.stops, 0
    local keep = false
    for i = 1, #self.navButtons do
        local b = self.navButtons[i]
        if b.enable then
            n = n + 1
            stops[n] = b
            if b == self.kbButton then keep = true end
        end
    end
    for i = 1, #self.footButtons do
        local b = self.footButtons[i]
        n = n + 1
        stops[n] = b
        if b == self.kbButton then keep = true end
    end
    for i = #stops, n + 1, -1 do stops[i] = nil end
    if not keep then self.kbButton = nil end
end

local function stepFocus(self, delta)
    local stops = self.stops
    local count = #stops + 1
    local i = 0
    local cur = self.kbButton
    if cur ~= nil then
        for k = 1, #stops do
            if stops[k] == cur then i = k; break end
        end
    end
    i = i + delta
    i = i - math.floor(i / count) * count
    self.kbButton = stops[i] -- stops[0]＝nil＝回到日格
end

-- 超出 1..9999 年回 false（呼叫端停在原處）
function Popup:setMonth(y, m)
    if y < MIN_YEAR or y > MAX_YEAR then return false end
    self.year, self.month = y, m
    self.days = Date.daysInMonth(y, m)
    self.lead = weekday(y, m, 1)
    self.title = pad4(y) .. "-" .. pad2(m)
    if self.cursor and self.cursor > self.days then self.cursor = self.days end
    for i = 1, #self.navButtons do
        local b = self.navButtons[i]
        local target = y * 12 + m - 1 + b._delta
        b:setEnabled(target >= MIN_YEAR * 12 and target < (MAX_YEAR + 1) * 12)
    end
    rebuildStops(self)
    return true
end

local function shiftMonths(self, delta)
    local total = self.year * 12 + (self.month - 1) + delta
    local y = math.floor(total / 12)
    self:setMonth(y, total - y * 12 + 1)
end

function Popup:moveCursor(delta)
    local d = self.cursor + delta
    for _ = 1, 4 do
        if d < 1 then
            local y, m = self.year, self.month - 1
            if m < 1 then y, m = y - 1, 12 end
            if not self:setMonth(y, m) then d = 1; break end
            d = d + self.days
        elseif d > self.days then
            d = d - self.days
            local y, m = self.year, self.month + 1
            if m > 12 then y, m = y + 1, 1 end
            if not self:setMonth(y, m) then d = self.days; break end
        else
            break
        end
    end
    if d < 1 then d = 1 elseif d > self.days then d = self.days end
    self.cursor = d
end

-- 先關再寫：欄位的 onChange 若重排頁面，看到的是已關閉的 popup
function Popup:write(y, m, d)
    local field = self.field
    DatePicker.close()
    commit(field, Date.format(y, m, d))
end

local function onNav(self, b) shiftMonths(self, b._delta) end
local function onToday(self) self:write(self.todayY, self.todayM, self.todayD) end
local function onClear(self)
    local field = self.field
    DatePicker.close()
    commit(field, "")
end
local function onClose() DatePicker.close() end

-- 量測在開啟時做：大字型或 CJK 星期標頭會撐寬格子，不會重疊
function Popup:relayout()
    local small = UIFont.Small
    local fh = fontHeight(small)
    local navH = fh + 10
    local cellH = math.max(20, fh + 8)
    local cellW = math.max(22, measure(small, "00") + 12)
    for i = 1, 7 do
        local w = measure(small, self.weekLabels[i]) + 6
        if w > cellW then cellW = w end
    end
    local gridW = cellW * 7
    local navW = math.max(navH, measure(small, "<<") + 12)
    local titleW = measure(UIFont.Medium, "0000-00") + 12
    local footW = GAP * (#self.footButtons - 1)
    for i = 1, #self.footButtons do
        footW = footW + measure(small, self.footButtons[i].title) + 20
    end
    local contentW = math.max(gridW, navW * 4 + titleW + GAP * 2, footW)

    self.cellW, self.cellH = cellW, cellH
    self.gridX = PAD + math.floor((contentW - gridW) / 2)
    self.navY, self.navH = PAD, navH
    self.titleY = PAD + math.floor((navH - fontHeight(UIFont.Medium)) / 2)
    self.weekY = PAD + navH + GAP
    self.gridY = self.weekY + fh + 4
    self.cellTextY = math.floor((cellH - fh) / 2)
    local footY = self.gridY + cellH * ROWS + GAP
    self:setWidth(contentW + PAD * 2)
    self:setHeight(footY + navH + PAD)

    local x = PAD
    for i, b in ipairs(self.navButtons) do
        if i == 3 then x = PAD + contentW - navW * 2 end
        b:setX(x); b:setY(PAD); b:setWidth(navW); b:setHeight(navH)
        x = x + navW
    end
    x = PAD + math.floor((contentW - footW) / 2)
    for _, b in ipairs(self.footButtons) do
        local w = measure(small, b.title) + 20
        b:setX(x); b:setY(footY); b:setWidth(w); b:setHeight(navH)
        x = x + w + GAP
    end
end

-- anchor 決定 popup 的生死：分頁切走、視窗收合、欄位停用、按鈕隱藏或停用都帶走日曆
function Popup:anchorAlive()
    local field = self.field
    if not field then return false end
    local entry = field._text._entry
    if not entry.javaObject or not entry:isReallyVisible() then return false end
    local el = field
    for _ = 1, 32 do
        if el == nil then break end
        if el.isCollapsed then return false end
        el = el.parent
    end
    if not field._enabled then return false end
    local b = field._button
    return b:isReallyVisible() and b.enable == true
end

-- 錨在欄位下方；放不下翻到上方，再夾回螢幕內
function Popup:place()
    local field = self.field
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local x, ay = field:getAbsoluteX(), field:getAbsoluteY()
    local y = ay + field.height + 2
    if y + self.height > sh then y = ay - self.height - 2 end
    if y + self.height > sh then y = sh - self.height end
    if y < 0 then y = 0 end
    if x + self.width > sw then x = sw - self.width end
    if x < 0 then x = 0 end
    self:setX(x)
    self:setY(y)
end

function Popup:prerender()
    if not self:anchorAlive() then DatePicker.close(); return end
    self:place() -- 視窗拖曳或重排時跟著走

    local colors = self.theme.colors
    local ca = chromeAlpha(self.theme)
    local w, h = self.width, self.height
    if self.opaque then -- rev 18：開啟時決定（欄位所在視窗不透明或 opts.opaque）
        Skin.solidFill(self, 0, 0, w, h, colors.surface, Skin.shapeOf(self.theme, "control"))
    else
        Skin.fill(self, 0, 0, w, h, colors.surface, Skin.shapeOf(self.theme, "control"), ca)
    end
    Skin.border(self, 0, 0, w, h, colors.border, Skin.shapeOf(self.theme, "control"), ca)
    drawTextCentre(self, self.title, w / 2, self.titleY, colors.text, UIFont.Medium)

    local cw, ch = self.cellW, self.cellH
    local gx, gy = self.gridX, self.gridY
    for i = 1, 7 do
        drawTextCentre(self, self.weekLabels[i], gx + (i - 1) * cw + cw / 2, self.weekY, colors.textFaint, UIFont.Small)
    end

    local selHere = self.selY == self.year and self.selM == self.month
    local todayHere = self.todayY == self.year and self.todayM == self.month
    for i = 0, ROWS * 7 - 1 do
        local d = i - self.lead + 1
        if d >= 1 and d <= self.days then
            local col = i - math.floor(i / 7) * 7
            local cx = gx + col * cw
            local cy = gy + math.floor(i / 7) * ch
            local c = (col == 0 or col == 6) and colors.textMuted or colors.text
            if selHere and d == self.selD then
                Skin.fill(self, cx + 1, cy + 1, cw - 2, ch - 2, colors.selected, "rect", ca)
                Skin.border(self, cx + 1, cy + 1, cw - 2, ch - 2, colors.accent, "rect", ca)
                c = colors.accent
            end
            if todayHere and d == self.todayD then
                c = colors.accent
                Skin.fill(self, cx + math.floor(cw / 4), cy + ch - 3, math.floor(cw / 2), 1, colors.accent, "rect", ca)
            end
            if d == self.cursor then
                Skin.border(self, cx, cy, cw, ch, colors.accent, "rect", ca)
            end
            drawTextCentre(self, DAY_TEXT[d], cx + cw / 2, cy + self.cellTextY, c, UIFont.Small)
        end
    end
end

-- chip 是子元件、先畫完了：焦點框疊在上面。"<<" 之類的字說不清用途，所以 tooltip 當說明；
-- tooltip 就是畫出來的標題時不重複。
function Popup:render()
    local b = self.kbButton
    if b == nil or Focus == nil then return end
    local caption = b.tooltip
    if caption == b._fitTitle then caption = nil end
    Focus.drawRing(self, b.x, b.y, b.width, b.height, self.theme)
    Focus.drawCaption(self, b.x, b.y, b.width, b.height, caption, self.theme)
end

function Popup:onMouseDown(x, y)
    if self:isMouseOver() then return true end -- 裡面：不漏到頁面
    local b = self.field and self.field._button
    if b and b:isReallyVisible() and b:isMouseOver() then
        return false -- 自己的日曆按鈕：交給它的 click 切換開關
    end
    DatePicker.close()
    return false
end

function Popup:onMouseUp(x, y)
    if not self:isMouseOver() then return false end
    local col = math.floor((x - self.gridX) / self.cellW)
    local row = math.floor((y - self.gridY) / self.cellH)
    if col >= 0 and col < 7 and row >= 0 and row < ROWS then
        local d = row * 7 + col - self.lead + 1
        if d >= 1 and d <= self.days then self:write(self.year, self.month, d) end
    end
    return true
end

-- ---------- 鍵盤 ----------
-- popup 自己是 top-level，比視窗先被問（UIManager.java:1435-1466）。按下時動作（才能連發），
-- 同一次按住的 release 由 Focus 帳本消耗——包括關掉 popup 的 Escape（popup 已離開 UI 清單，release 由視窗回答）。

local function popupKey(self, key)
    local k = Keyboard
    if key == k.KEY_TAB then
        local _, shift = Focus.modifiers()
        stepFocus(self, shift and -1 or 1)
        return true
    end
    if key == k.KEY_ESCAPE then DatePicker.close(); return true end
    if key == k.KEY_PRIOR then shiftMonths(self, -1); return true end
    if key == k.KEY_NEXT then shiftMonths(self, 1); return true end
    if key == k.KEY_HOME then onToday(self); return true end
    if key == k.KEY_DELETE then onClear(self); return true end
    local b = self.kbButton
    if key == k.KEY_RETURN or key == k.KEY_NUMPADENTER or key == k.KEY_SPACE then
        if b == nil then
            self:write(self.year, self.month, self.cursor)
        else
            pcall(b.forceClick, b) -- ISButton:forceClick：檢查可見與啟用，只呼叫一次 onclick
        end
        return true
    end
    if b ~= nil then
        -- 焦點在 chip：左右換 chip，上下回到日格
        if key == k.KEY_LEFT then stepFocus(self, -1); return true end
        if key == k.KEY_RIGHT then stepFocus(self, 1); return true end
        if key == k.KEY_UP or key == k.KEY_DOWN then self.kbButton = nil; return true end
        return false
    end
    if key == k.KEY_LEFT then self:moveCursor(-1); return true end
    if key == k.KEY_RIGHT then self:moveCursor(1); return true end
    if key == k.KEY_UP then self:moveCursor(-7); return true end
    if key == k.KEY_DOWN then self:moveCursor(7); return true end
    return false
end

function Popup:onKeyPress(key)
    if active ~= self then return end
    Focus.pressed(key) -- 新的按住：連發延遲從這裡起算
    if popupKey(self, key) then Focus.eat(key) end
end

-- 只有方向鍵與換月鍵連發（按住 Esc／Enter 只作用一次）；引擎每幀都派 repeat，repeatDue 照作業系統節奏放行
function Popup:onKeyRepeat(key)
    if active ~= self then return end
    local k = Keyboard
    if key ~= k.KEY_LEFT and key ~= k.KEY_RIGHT and key ~= k.KEY_UP and key ~= k.KEY_DOWN
        and key ~= k.KEY_PRIOR and key ~= k.KEY_NEXT then
        return
    end
    if not Focus.repeatDue(key) then return end
    if popupKey(self, key) then Focus.eat(key) end
end

function Popup:onKeyRelease(key)
    Focus.release(key)
end

function Popup:isKeyConsumed(key)
    return Focus.consumed(key)
end

-- 手把：A＝Enter、B＝Esc、十字鍵＝方向鍵，LB／RB＝Shift+Tab／Tab（手把沒有 Tab）
function Popup:onJoypadDown(button, joypadData)
    if active ~= self or Joypad == nil then return end
    if button == Joypad.AButton then popupKey(self, Keyboard.KEY_RETURN)
    elseif button == Joypad.BButton then popupKey(self, Keyboard.KEY_ESCAPE)
    elseif button == Joypad.LBumper then stepFocus(self, -1)
    elseif button == Joypad.RBumper then stepFocus(self, 1) end
end
function Popup:onJoypadDirUp() if active == self then popupKey(self, Keyboard.KEY_UP) end end
function Popup:onJoypadDirDown() if active == self then popupKey(self, Keyboard.KEY_DOWN) end end
function Popup:onJoypadDirLeft() if active == self then popupKey(self, Keyboard.KEY_LEFT) end end
function Popup:onJoypadDirRight() if active == self then popupKey(self, Keyboard.KEY_RIGHT) end end
function Popup:onJoypadBeforeDeactivate() DatePicker.close() end

local function newChip(o, title, onClick, tooltip)
    local b = Button.new{ width = 24, height = 24, title = title, style = "chip", target = o, onClick = onClick,
        tooltip = tooltip }
    o:addChild(b)
    return b
end

local function ensurePopup()
    if popup then return popup end
    local o = ISPanel.new(Popup, 0, 0, 100, 100)
    o.background = false
    o:initialise()
    o.stops = {}
    o.weekLabels = {}
    for i = 1, 7 do o.weekLabels[i] = getText(T .. WEEK_KEYS[i]) end
    o.navButtons = {}
    for i, spec in ipairs(NAV_SPECS) do
        local b = newChip(o, spec[1], onNav, getText(T .. spec[3]))
        b._delta = spec[2]
        o.navButtons[i] = b
    end
    o.footButtons = {
        newChip(o, getText(T .. "Today"), onToday),
        newChip(o, getText(T .. "Clear"), onClear),
        newChip(o, getText(T .. "Close"), onClose),
    }
    o:setCapture(true)                   -- 外面的點擊先到這裡，才能關閉
    o:setWantKeyEvents(Focus ~= nil)     -- key 事件只派給 top-level
    o:setVisible(false)
    popup = o
    return o
end

-- 元素掛在哪個頂層 root 下（持有手把焦點的那一個）
local function rootOf(el)
    for _ = 1, 32 do
        if type(el) ~= "table" or el.parent == nil then break end
        el = el.parent
    end
    return el
end

local function within(el, scope)
    for _ = 1, 32 do
        if el == nil then return false end
        if el == scope then return true end
        el = el.parent
    end
    return false
end

openPicker = function(field)
    DatePicker.close()
    field._text._entry:unfocus() -- 也跑失焦正規化，月曆打開在正規化後的日期上
    local p = ensurePopup()
    p.field = field
    p.theme = field.theme
    -- rev 18：欄位所在頂層視窗不透明或 opts.opaque＝月曆也不透明（只在開啟時沿 parent 找一次）
    p.opaque = field._popupOpaque or rootOf(field).opaque == true
    for _, b in ipairs(p.navButtons) do b.theme = field.theme end
    for _, b in ipairs(p.footButtons) do b.theme = field.theme end
    field._button:setActive(true)
    local ty, tm, td = Date.fromMs(getTimestampMs(), Date.localOffsetMinutes())
    p.todayY, p.todayM, p.todayD = ty, tm, td
    local y, m, d = field:getDate()
    p.selY, p.selM, p.selD = y, m, d
    -- 從日格開始；記住是不是鍵盤開的：只有那樣關閉時才把焦點框還給按鈕
    p.kbButton = nil
    p.kbReturn = Focus ~= nil and Focus.focused() == field._button
    p.cursor = nil
    p:setMonth(y or ty, m or tm)
    p.cursor = d or ((ty == p.year and tm == p.month) and td or 1)
    p:relayout()
    p:place()
    p:setVisible(true)
    p:addToUIManager()
    p:setAlwaysOnTop(true) -- 實例化（addToUIManager）之後才有效
    p:bringToTop()
    active = p
    -- 欄位所在的視窗正持有手把焦點：popup 借走，關閉時歸還
    if Focus ~= nil and Focus.holdsJoypad(rootOf(field)) then Focus.takeJoypad(p, 0) end
    return p
end

function DatePicker.close(scope)
    local p = active
    if not p then return end
    if scope ~= nil and not within(p.field, scope) then return end
    active = nil
    local button, back = p.field._button, p.kbReturn
    button:setActive(false)
    p.field, p.kbButton, p.kbReturn = nil, nil, nil
    p:setVisible(false)
    p:removeFromUIManager()
    if Focus ~= nil then
        Focus.releaseJoypad(p)
        if back then Focus.refocus(button) end
    end
end

-- 測試鉤子：共用 popup 實例（尚未開過為 nil）
function DatePicker._popupForTests()
    return popup
end

UI.Date = Date
UI.DateField = DateField
UI.DatePicker = DatePicker
UI.CAPABILITIES.datePicker = true
UI.CAPABILITIES.opaquePopup = true -- rev 18：月曆跟著不透明視窗或 opts.opaque

return DatePicker
