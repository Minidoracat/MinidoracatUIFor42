-- MinidoracatUI Widgets/Autocomplete — 非同步候選輸入框（API rev 11，CAPABILITIES.autocomplete）。
--
-- 移植自 MinidoracatEconomyFor42 ECPlayerPicker 的通用部分：一個 UI.TextField 加上從它下方展開的
-- 候選清單。本元件不擁有傳輸：查詢經 opts.onQuery 交給 consumer 送出，結果由 consumer 以
-- setResults 交回；指令名稱、requestId、context 比對都留在 consumer。
--
--   local ac = UI.Autocomplete.new{ x?, y?, width?, theme?, font?, placeholder?, maxLength?=64,
--       clearButton?=true, debounceMs?=250, rows?=8, minListWidth?=260, target?,
--       onQuery,   -- function(target, text, picker) -> bool；false＝現在送不出，下一幀再試
--       labelOf?,  -- function(row) -> string；預設 tostring(row.label or row.name)
--       tagOf?,    -- function(row) -> string|nil；右側 accent 標籤（空間不夠時不畫）
--       onPick,    -- function(target, row, picker)：寫入文字、blur、close 之後才回呼（只一次）
--       onEnter?,  -- function(target, text, picker)：輸入框內按 Enter（內層 entry.onCommandEntered）
--   }
--   ac.field                    UI.TextField 子類；prerender 裡順便跑 debounce／查詢／下拉幾何
--   ac.list                     繪製型下拉，`_focusKind="list"`，帶 Focus「list」描述讀的
--                               items／rowHeight／padding／height／getSelectedIndex／
--                               setSelectedIndex／onSelect
--   ac:addTo(parent)            輸入框先加、下拉後加：要在所有需要被它蓋住的兄弟之後呼叫
--   ac:setText(s) / :getText()  setText 靜默並清掉已送出的查詢；文字變了丟掉舊候選、聚焦中排 debounce；
--                               getText 去頭尾空白
--   ac:setVisible(b) / :setEnabled(b)   隱藏或停用都會收起下拉
--   ac:layout(x, y, w, maxH)    擺輸入框，再 anchorList(maxH)
--   ac:anchorList(maxH?)        下拉掛到輸入框正下方，高度不超過 maxH（省略＝沿用上次；
--                               從未指定時只受 rows 限制）
--   ac:setResults(text, rows, total?, truncated?) -> bool   text 不是最後送出且仍是目前輸入的查詢
--                               時丟棄（回 false），等下一次查詢
--   ac:queryFailed(retry)       逾時 retry=true（聚焦或下拉開著時重新計時）；被拒 false（只清掉
--                               已送出的查詢）
--   ac:isOpen() / :close() / :blur() / :dispose()
--   ac:appendTargets(out, fieldLabel, listLabel) -> out   手動 keyboardTargets 用；描述 table 重用
--
-- 下拉可見＝有列可畫、開啟中、可見，且（輸入框聚焦、滑鼠在下拉上、或
-- Focus.isKeyboardFocused(list)）。第一次聚焦（還沒有結果時）立刻查一次目前文字（通常是空字串）。
-- 標籤字串在 setResults 時取好並依寬度截字快取，每幀只做數值運算與繪製，不配置 table／closure。
--
-- 引擎出處（快照 42.20.4-20260826）：
--   getTimestampMs          LuaManager.java:9268-9271（debounce 時鐘）
--   getText(key, args...)   LuaManager.java:8550（「還有 N 個」以字串傳 %1，免得 Double 印成 3.0）
--   ISTextEntryBox          ISTextEntryBox.lua:146-156（focus／unfocus／isFocused）、
--                           :16（onCommandEntered 預設空）← UITextBox2.java:841-845 以 table 呼叫
--   ISUIElement             isMouseOver :414-419、getMouseY :346、setVisible :657、drawText :1293
--   ISBaseObject:derive     shared/ISBaseObject.lua:9-15 不設子類自己的 __index → Field 手動補
--
-- 字串字面值只含 ASCII；顯示文字走 Translate（IGUI_MinidoracatUI_Autocomplete_*）。預設零 log。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.autocomplete 探測）
end
if not (UI.TextField and UI.CAPABILITIES.controls) then
    pcall(require, "MinidoracatUI/Widgets/Controls")
end
if not (UI.TextField and UI.CAPABILITIES.controls) then
    return -- 需要 controls
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus") -- 選用：缺席時下拉只能用滑鼠
end

local Skin = UI.Skin
local Text = UI.Text
local TextField = UI.TextField

local PAD = 8          -- 同 TextField 文字起點（FIELD_PAD 6＋UITextBox2 inset 2）
local ROW_EXTRA = 12   -- 列高＝字高＋12
local UNBOUNDED = 100000
local EMPTY = {}
local MORE_KEY = "IGUI_MinidoracatUI_Autocomplete_More"

-- rev 11 theme.alpha：chrome（fill／border）乘它，文字不乘（約定見 V1.lua Theme 段）
local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function drawColorText(el, text, x, y, color, font)
    el:drawText(text, x, y, color.r, color.g, color.b, color.a or 1, font)
end

local function defaultLabel(row)
    return tostring(row.label or row.name)
end

local function trim(s)
    return string.match(s or "", "^%s*(.-)%s*$")
end

local Autocomplete = {}
Autocomplete.__index = Autocomplete

local tick -- 前置宣告：Field:prerender 呼叫

-- ============================================================
-- 下拉
-- ============================================================

local List = ISPanel:derive("MinidoracatUIAutocompleteList")

local function rowIndexAt(list, y)
    local i = math.floor((y - 1) / list.rowHeight) + 1
    if i < 1 or i > list.shown then return nil end
    return i
end

function List:getSelectedIndex()
    return self.selectedIndex
end

function List:setSelectedIndex(index)
    if type(index) ~= "number" or index < 1 or self.shown < 1 then
        self.selectedIndex = nil
    else
        self.selectedIndex = math.min(math.floor(index), self.shown)
    end
end

function List:prerender()
    if self.isCollapsed then return end
    local ac = self._ac
    local colors = ac.theme.colors
    local ca = chromeAlpha(ac.theme)
    local font = ac.font
    local w, h, rh = self.width, self.height, self.rowHeight
    Skin.fill(self, 0, 0, w, h, colors.surface, nil, ca)
    Skin.border(self, 0, 0, w, h, colors.accent, nil, ca)
    local hover = 0
    if self:isMouseOver() then hover = rowIndexAt(self, self:getMouseY()) or 0 end
    local dy = math.floor((rh - fontHeight(font)) / 2)
    local fits, tags, tagW, showTag = self._fits, self._tags, self._tagW, self._showTag
    local y = 1
    for i = 1, self.shown do
        if hover == i or self.selectedIndex == i then
            Skin.fill(self, 1, y, w - 2, rh, colors.selected, "rect", ca)
        end
        drawColorText(self, fits[i], PAD, y + dy, colors.text, font)
        if showTag[i] then
            drawColorText(self, tags[i], w - PAD - tagW[i], y + dy, colors.accent, font)
        end
        y = y + rh
    end
    if self._note then
        drawColorText(self, self._note, PAD, y + dy, colors.textFaint, font)
    end
end

function List:render() end

-- 程式寫入輸入框的唯一入口：同步快取的去空白查詢（TextField:setText 不觸發 onChange）。
-- 回傳查詢是否真的變了
local function writeText(ac, text)
    ac.field:setText(text)
    local query = trim(ac.field:getText())
    if query == ac.query then return false end
    ac.query = query
    return true
end

local function pick(ac, row)
    if type(row) ~= "table" then return end
    writeText(ac, tostring(ac.labelOf(row)))
    ac:blur()
    ac:close()
    ac.onPick(ac.target, row, ac)
end

function List:onMouseDown(x, y)
    local i = rowIndexAt(self, y)
    if i then pick(self._ac, self.items[i]) end
    return true
end

function List:onMouseUp(x, y)
    return true
end

-- Focus 的 Enter／手把 A 與點擊走同一個 pick
local function onListSelect(list, item)
    pick(list._ac, item)
end

-- 標籤依目前寬度截字；只在結果、提示列或寬度變了時跑
local function refit(ac)
    local list = ac.list
    local font = ac.font
    local avail = list.width - PAD * 2
    local minRoom = fontHeight(font) * 3
    local labels, tagW, showTag, fits = list._labels, list._tagW, list._showTag, list._fits
    for i = 1, list._labelCount do
        local room = avail - tagW[i] - PAD
        local show = tagW[i] > 0 and room >= minRoom
        showTag[i] = show
        fits[i] = Text.fit(labels[i], show and room or avail, font)
    end
    list._note = list._noteRaw and Text.fit(list._noteRaw, avail, font) or nil
    list._fitW = list.width
end

-- 列規劃與幾何。每幀從 tick 呼叫：只做數值運算（提示字串只在種類或數字變了才重取）
local function refresh(ac)
    local list = ac.list
    local rh = fontHeight(ac.font) + ROW_EXTRA
    local cap = math.min(ac.rowsMax, math.floor(ac.listMaxH / rh))
    local rows = ac.candidates
    local shown, more, empty = 0, false, false
    if rows and cap > 0 then
        local n = #rows
        if n == 0 then
            empty = ac.sentQuery ~= nil and ac.sentQuery ~= ""
        else
            shown = math.min(n, cap)
            more = shown < n or ac.total > n or ac.truncated
            if more and shown >= cap then
                -- 提示列讓出最後一格；只剩一格時留給第一筆候選（否則沒有任何一筆可選）
                if cap > 1 then shown = cap - 1 else more = false end
            end
        end
    end
    local kind, count = nil, 0
    if more then
        if ac.truncated then kind = "partial" else kind, count = "more", math.max(0, ac.total - shown) end
    elseif empty then
        kind = "empty"
    end
    if kind ~= list._noteKind or count ~= list._noteCount then
        list._noteKind, list._noteCount = kind, count
        if kind == "more" then list._noteRaw = getText(MORE_KEY, tostring(count))
        elseif kind == "partial" then list._noteRaw = ac.partialText
        elseif kind == "empty" then list._noteRaw = ac.emptyText
        else list._noteRaw = nil end
        list._fitW = -1
    end
    list.rowHeight = rh
    list.items = rows or EMPTY
    list.shown = shown
    if list.selectedIndex ~= nil and list.selectedIndex > shown then list.selectedIndex = nil end
    if list._fitW ~= list.width then refit(ac) end
    local lines = shown + (kind and 1 or 0)
    local Focus = UI.Focus
    local visible = lines > 0 and ac.open and ac.visible
        and (ac.focused or list:isMouseOver() == true or (Focus ~= nil and Focus.isKeyboardFocused(list)))
    if visible ~= (list:getIsVisible() == true) then list:setVisible(visible) end
    if visible and list.height ~= lines * rh + 2 then list:setHeight(lines * rh + 2) end
end

-- ============================================================
-- 輸入框
-- ============================================================

local Field = TextField:derive("MinidoracatUIAutocompleteField")
Field.__index = Field

function Field:prerender()
    TextField.prerender(self) -- 內含每幀文字比對（IME 送出也抓得到）→ onFieldChange
    if not self.isCollapsed then tick(self._ac) end
end

-- 按鍵只重設 debounce；查詢由 tick 送出，快速打字每 debounceMs 最多一次。
-- 去空白的查詢只在文字變動時算一次並快取，tick 每幀只比對快取（不產生新字串）
local function onFieldChange(field, text)
    local ac = field._ac
    ac.query = trim(text)
    ac.queryAt = getTimestampMs()
    ac.open = true
    if ac.query ~= ac.sentQuery then
        ac.candidates, ac.total, ac.truncated = nil, nil, nil
        ac.list.selectedIndex = nil
    end
end

tick = function(ac)
    if not ac.visible then return end
    local now = getTimestampMs()
    local raw = ac.query
    -- 停用的輸入框即使被點到聚焦（UITextBox2 點擊直接聚焦，不經 Lua）也不開啟、不查詢
    local focused = ac.enabled and ac.field:isFocused()
    if focused and not ac.focused then
        ac.open = true
        if ac.candidates == nil then ac.queryAt = now - ac.debounceMs end -- 第一次聚焦立刻查
    end
    ac.focused = focused
    local at = ac.queryAt
    if at and now - at >= ac.debounceMs then
        if raw == ac.sentQuery and ac.candidates ~= nil then
            ac.queryAt = nil
        else
            -- 先記下再問：consumer 在 onQuery 裡同步 setResults 也對得上
            local previous = ac.sentQuery
            ac.sentQuery = raw
            if ac.onQuery(ac.target, raw, ac) == true then
                ac.queryAt = nil
            else
                ac.sentQuery = previous
            end
        end
    end
    refresh(ac)
end

-- ============================================================
-- 公開方法
-- ============================================================

function Autocomplete:addTo(parent)
    parent:addChild(self.field)
    parent:addChild(self.list)
    self:anchorList()
end

function Autocomplete:getText()
    return trim(self.field:getText())
end

-- 靜默（不呼叫文字回呼）；文字真的變了就丟掉舊候選，聚焦中並為新文字排 debounce
-- （沒聚焦時不排：下次聚焦沒有候選會立刻查）
function Autocomplete:setText(text)
    local changed = writeText(self, text or "")
    self.sentQuery = nil
    if changed then
        self.candidates, self.total, self.truncated = nil, nil, nil
        self.list.selectedIndex = nil
        if self.focused then self.queryAt = getTimestampMs() end
        refresh(self)
    end
end

function Autocomplete:setVisible(visible)
    visible = visible ~= false
    self.visible = visible
    self.field:setVisible(visible)
    if not visible then
        self:blur()
        self:close()
    end
end

function Autocomplete:setEnabled(enabled)
    enabled = enabled ~= false
    self.enabled = enabled
    self.field:setEnabled(enabled)
    if not enabled then self:close() end
end

function Autocomplete:layout(x, y, w, maxH)
    local field = self.field
    field:setX(x)
    field:setY(y)
    field:setWidth(w)
    self:anchorList(maxH)
end

function Autocomplete:anchorList(maxH)
    if maxH ~= nil then self.listMaxH = math.max(0, maxH) end
    local field, list = self.field, self.list
    list:setX(field.x)
    list:setY(field.y + field.height)
    list:setWidth(math.max(self.minListWidth, field.width))
    refresh(self)
end

function Autocomplete:setResults(text, rows, total, truncated)
    if self.sentQuery == nil or text ~= self.sentQuery or text ~= self:getText() then
        return false
    end
    rows = type(rows) == "table" and rows or EMPTY
    self.candidates = rows
    self.total = tonumber(total) or #rows
    self.truncated = truncated == true
    local list = self.list
    local labels, tags, tagW = list._labels, list._tags, list._tagW
    local n = math.min(#rows, self.rowsMax)
    for i = 1, n do
        local row = rows[i]
        labels[i] = tostring(self.labelOf(row))
        local tag = self.tagOf and self.tagOf(row) or nil
        if type(tag) == "string" and tag ~= "" then
            tags[i], tagW[i] = tag, getTextManager():MeasureStringX(self.font, tag)
        else
            tags[i], tagW[i] = false, 0
        end
    end
    for k = n + 1, list._labelCount do
        labels[k], tags[k], tagW[k], list._fits[k], list._showTag[k] = nil, nil, nil, nil, nil
    end
    list._labelCount = n
    list._fitW = -1
    refresh(self)
    return true
end

function Autocomplete:queryFailed(retry)
    self.sentQuery = nil
    if retry == true and self.open and self.visible and self.enabled and (self.focused or self:isOpen()) then
        self.queryAt = getTimestampMs()
    end
end

function Autocomplete:isOpen()
    return self.list:getIsVisible() == true
end

-- 收起並忘掉結果：pick、Esc、換頁、失去權限都讓候選失效，下次聚焦重查
function Autocomplete:close()
    self.open = false
    self.candidates, self.total, self.truncated = nil, nil, nil
    self.sentQuery, self.queryAt = nil, nil
    local list = self.list
    list.items = EMPTY
    list.shown = 0
    list.selectedIndex = nil
    list:setVisible(false)
end

-- 隱藏期間 tick 不跑：這裡直接歸零聚焦狀態，重新顯示後的第一次聚焦才會再查
function Autocomplete:blur()
    local field = self.field
    if field:isFocused() then field._entry:unfocus() end
    self.focused = false
end

function Autocomplete:dispose()
    self:close()
    self:blur()
end

function Autocomplete:appendTargets(out, fieldLabel, listLabel)
    local t = self._fieldTarget
    t.label = fieldLabel
    out[#out + 1] = t
    if self.list:getIsVisible() then
        t = self._listTarget
        t.label = listLabel
        out[#out + 1] = t
    end
    return out
end

function Autocomplete.new(opts)
    opts = opts or {}
    if type(opts.onQuery) ~= "function" or type(opts.onPick) ~= "function" then
        error("MinidoracatUI.Autocomplete.new: onQuery and onPick are required")
    end
    local o = setmetatable({}, Autocomplete)
    o.theme = opts.theme or UI.Theme.create()
    o.font = opts.font or UIFont.Small
    o.target = opts.target
    o.onQuery, o.onPick = opts.onQuery, opts.onPick
    o.labelOf = opts.labelOf or defaultLabel
    o.tagOf = opts.tagOf
    o.debounceMs = opts.debounceMs or 250
    o.rowsMax = math.max(1, math.floor(opts.rows or 8))
    o.minListWidth = opts.minListWidth or 260
    o.listMaxH = UNBOUNDED
    o.visible, o.enabled, o.open, o.focused = true, true, false, false
    o.query = "" -- 去空白後的目前文字快取（輸入框初始為空）
    o.emptyText = getText("IGUI_MinidoracatUI_Autocomplete_Empty")
    o.partialText = getText("IGUI_MinidoracatUI_Autocomplete_Partial")

    local field = TextField.new{
        x = opts.x, y = opts.y, width = opts.width, theme = o.theme, font = o.font,
        placeholder = opts.placeholder, maxLength = opts.maxLength or 64,
        clearButton = opts.clearButton ~= false, onChange = onFieldChange,
    }
    setmetatable(field, Field)
    field._ac = o
    o.field = field
    local onEnter = opts.onEnter
    if onEnter then
        field._entry.onCommandEntered = function()
            onEnter(o.target, o:getText(), o)
        end
    end

    local list = ISPanel.new(List, 0, 0, o.minListWidth, fontHeight(o.font) + ROW_EXTRA)
    list.background = false
    list._ac = o
    list._focusKind = "list"
    list.items = EMPTY
    list.shown = 0
    list.rowHeight = fontHeight(o.font) + ROW_EXTRA
    list.padding = 0
    list.onSelect = onListSelect
    list._labels, list._tags, list._tagW, list._fits, list._showTag = {}, {}, {}, {}, {}
    list._labelCount = 0
    list._fitW = -1
    list:initialise()
    list:setVisible(false)
    o.list = list

    o._fieldTarget = { kind = "entry", control = field._entry, frame = field }
    o._listTarget = { kind = "list", control = list }
    return o
end

UI.Autocomplete = Autocomplete
UI.CAPABILITIES.autocomplete = true

return Autocomplete
