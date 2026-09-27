-- MinidoracatUI Widgets/ItemPicker — 「挑一個物品」疊層（API rev 11，CAPABILITIES.itemPicker）。
-- 收編自 Economy ECItemPicker 的通用部分；英文名索引、上架政策、索引載入提示留在 consumer，
-- 以 items／filter／revision／note 注入。
--
--   UI.ItemPicker.universe() -> { items = { record, ... }, byType = { [fullType] = record } }
--       本 session 載入的全部物品 script（原版與 MOD），record = { fullType, name, category, script,
--       search }；整個 session 共用，consumer 唯讀。只跳過 hidden／obsolete。不排序（數千筆，
--       排序交給 consumer）。空結果不快取：script manager 還沒準備好時不能讓 session 永遠拿到空宇宙。
--
--   UI.ItemPicker.new(opts) -> picker（已 initialise 的 ISPanel，尚未 addChild）
--       opts: x?, y?, width?, height?, theme?, font?, title?, placeholder?,
--             items?（function() -> array；預設 universe().items；record 至少要有 fullType／name／
--             category／search，選用 original＝右側淡字、script＝圖示來源）、
--             filter?（function(rec) -> bool）、revision?（function() -> any；開著時值變了就重搜）、
--             note?（function() -> string|nil；提示列前綴）、maxResults?（預設 200）、
--             target?, onPick(target, rec, picker)（疊層先關再回呼）、onCancel?(target, picker)
--       consumer 最後才 addChild（畫在頁面內容之上），並 resize 成整頁大小。
--       方法：open()、close()、isOpen()、cancel()、resize(w, h)、keyboardTargets()、dispose()。
--       放在框架 Window 裡時 consumer 覆寫 win.keyboardTargets：isOpen() 時回 picker:keyboardTargets()，
--       否則回 Focus.collectTargets(win)。
--
-- 引擎出處（快照 42.20.4-20260826）：
--   getScriptManager            LuaManager.java:5497-5499（回 ScriptManager.instance）
--   getAllItems                 ScriptManager.java:715-717（ArrayList<Item>）
--   FindItem                    ScriptManager.java:1413-1415（record 沒帶 script 時找圖示）
--   isHidden／getDisplayCategory Item.java:501-503／505-507
--   getNormalTexture            Item.java:525-527
--   getFullName                 Item.java:882-884
--   getObsolete                 Item.java:3123-3125
--   getItemNameFromFullType     LuaManager.java:8582-8584
--   getTextOrNull               LuaManager.java:8558-8560
--   類別翻譯 IGUI_ItemCat_<cat>  原版 ISInventoryPane.lua:2532-2535
--
-- 載入自檢：同 Window——需要 controls 與 table，缺任一就 return，旗標維持 false。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text) or not ISPanel then
    return
end

if not UI.CAPABILITIES.controls then
    pcall(require, "MinidoracatUI/Widgets/Controls")
end
if not UI.CAPABILITIES.table then
    pcall(require, "MinidoracatUI/Widgets/Table")
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
if not (UI.CAPABILITIES.controls and UI.CAPABILITIES.table) then
    return -- 缺 Controls 或 Table：不掛能力（consumer 以 CAPABILITIES.itemPicker 探測）
end

local Skin = UI.Skin
local fit = UI.Text.fit
local Focus = UI.Focus

local PAD = 12
local CARD_TITLE_H = 36
local DEBOUNCE_MS = 120
local MAX_RESULTS = 200
local SEPARATOR = "  /  "

local function tr(key)
    return getText(key)
end

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text)
end

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function drawColorText(el, text, x, y, color, font)
    el:drawText(text, x, y, color.r, color.g, color.b, color.a or 1, font)
end

-- ============================================================
-- 宇宙
-- ============================================================

local ItemPicker = {}
local universe = nil

-- pcall 包具名 Lua 函式（不新建 closure）
local function allItems()
    return getScriptManager():getAllItems()
end

local function listSize(list)
    return list:size()
end

local function listGet(list, i)
    return list:get(i)
end

-- 回 fullType, category；hidden／obsolete 回 nil
local function describe(script)
    if script:isHidden() or script:getObsolete() then
        return nil
    end
    return script:getFullName(), script:getDisplayCategory()
end

local function itemName(fullType)
    local ok, name = pcall(getItemNameFromFullType, fullType)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return fullType
end

function ItemPicker.universe()
    if universe then
        return universe
    end
    local uni = { items = {}, byType = {} }
    local ok, all = pcall(allItems)
    local count = 0
    if ok and all ~= nil then
        local okSize, n = pcall(listSize, all)
        if okSize and type(n) == "number" then
            count = n
        end
    end
    for i = 0, count - 1 do
        local okGet, script = pcall(listGet, all, i)
        if okGet and script ~= nil then
            local okDesc, fullType, category = pcall(describe, script)
            if okDesc and type(fullType) == "string" and fullType ~= "" and uni.byType[fullType] == nil then
                if type(category) ~= "string" or category == "" then
                    category = "Item"
                end
                local name = itemName(fullType)
                local rec = {
                    fullType = fullType, name = name, category = category, script = script,
                    search = string.lower(name .. " " .. fullType),
                }
                uni.byType[fullType] = rec
                uni.items[#uni.items + 1] = rec
            end
        end
    end
    if #uni.items > 0 then
        universe = uni
    end
    return uni
end

-- ============================================================
-- 結果列
-- ============================================================

-- fullType -> 貼圖；false＝問過、沒有或畫失敗（session 內不再重試）
local icons = {}
-- category -> 顯示文字
local categoryTexts = {}

local function scriptTexture(script)
    return script:getNormalTexture()
end

local function findScript(fullType)
    return getScriptManager():FindItem(fullType)
end

local function iconOf(rec)
    local cached = icons[rec.fullType]
    if cached ~= nil then
        return cached or nil
    end
    local script = rec.script
    if script == nil then
        local ok, found = pcall(findScript, rec.fullType)
        script = ok and found or nil
    end
    local tex = nil
    if script ~= nil then
        local ok, t = pcall(scriptTexture, script)
        tex = ok and t or nil
    end
    icons[rec.fullType] = tex or false
    return tex
end

local function categoryText(category)
    local text = categoryTexts[category]
    if text == nil then
        text = getTextOrNull("IGUI_ItemCat_" .. category) or category
        categoryTexts[category] = text
    end
    return text
end

local PickCell = ISPanel:derive("MinidoracatUIItemPickCell")

-- 綁定時一次算好截字與幾何（render 只畫）；cell 寬度由 VirtualList 在 bind 前設好
function PickCell:onBind()
    local rec = self.entry
    local picker = self.list.picker
    local font, lh = picker.font, picker._lineH
    local width = self.width - PAD
    local size = math.min(math.max(12, self.height - 12), 28)
    local nameX = PAD + size + 8
    local original = rec.original
    local alt = type(original) == "string" and original ~= "" and original ~= rec.name
    local nameW = math.max(40, math.floor((width - nameX) * (alt and 0.55 or 1)))
    self._icon = iconOf(rec)
    self._iconSize = size
    self._iconY = math.max(0, math.floor(4 + lh - size / 2))
    self._nameX = nameX
    self._line2Y = 4 + lh
    self._name = fit(rec.name, nameW, font)
    if alt then
        self._altX = nameX + nameW + 8
        self._alt = fit(original, math.max(0, width - self._altX), font)
    else
        self._alt = nil
    end
    self._meta = fit(rec.fullType .. SEPARATOR .. categoryText(rec.category), math.max(20, width - nameX), font)
end

function PickCell:onUnbind()
    self._icon, self._name, self._alt, self._meta = nil, nil, nil, nil
end

function PickCell:render()
    local rec = self.entry
    if rec == nil or self._name == nil then
        return
    end
    local lit = UI.Table.rowBackground(self)
    local colors = self.theme.colors
    local faint = lit and colors.text or colors.textFaint
    local font = self.list.picker.font
    local icon = self._icon
    if icon then
        local size = self._iconSize
        if not pcall(self.drawTextureScaled, self, icon, PAD, self._iconY, size, size, 1, 1, 1, 1) then
            icons[rec.fullType] = false
            self._icon = nil
        end
    end
    drawColorText(self, self._name, self._nameX, 4, colors.text, font)
    if self._alt then
        drawColorText(self, self._alt, self._altX, 4, faint, font)
    end
    drawColorText(self, self._meta, self._nameX, self._line2Y, faint, font)
end

-- ============================================================
-- 疊層
-- ============================================================

local Picker = ISPanel:derive("MinidoracatUIItemPicker")

-- 頂層祖先（Focus.invalidate 只接受 root）
local function rootOf(el)
    for _ = 1, 32 do
        if el.parent == nil then
            return el
        end
        el = el.parent
    end
    return el
end

local function onRowSelect(list, rec)
    list.picker:choose(rec)
end

function Picker:rebuild()
    local query = string.lower(string.match(self.search:getText(), "^%s*(.-)%s*$") or "")
    local items = self._items and self._items() or ItemPicker.universe().items
    local filter = self._filter
    local limit = self.maxResults
    local rows = self._rows
    local shown, total = 0, 0
    for i = 1, #items do
        local rec = items[i]
        if (query == "" or string.find(rec.search, query, 1, true) ~= nil) and (filter == nil or filter(rec)) then
            total = total + 1
            if shown < limit then
                shown = shown + 1
                rows[shown] = rec
            end
        end
    end
    for i = #rows, shown + 1, -1 do
        rows[i] = nil
    end
    self.total, self.shown = total, shown
    if self._revision then
        self._rev = self._revision()
    end
    self.list:setItems(rows)
    self.list:setSelectedIndex(nil)
    local count
    if total == 0 then
        count = tr("IGUI_MinidoracatUI_ItemPicker_Empty")
    elseif total > shown then
        count = getText("IGUI_MinidoracatUI_ItemPicker_More", tostring(shown), tostring(total))
    else
        count = getText("IGUI_MinidoracatUI_ItemPicker_Count", tostring(total))
    end
    local note = self._note and self._note()
    if type(note) == "string" and note ~= "" then
        count = note .. "  " .. count
    end
    self.hintText = count
    self._hintFit = fit(count, math.max(0, self.width - PAD * 4), self.font)
end

function Picker:layout()
    local w, h = self.width, self.height
    local lh = self._lineH
    local eh = math.max(26, self._fontH + 12)
    local ch = math.max(20, self._fontH + 6)
    local top = PAD + CARD_TITLE_H + 4
    local cancel = self.cancelButton
    local cancelW = math.min(self._cancelW, math.max(48, math.floor(w * 0.3)))
    cancel:setWidth(cancelW)
    cancel:setHeight(ch)
    cancel:setX(w - PAD * 2 - cancelW)
    cancel:setY(top)
    local search = self.search
    search:setX(PAD * 2)
    search:setY(top)
    search:setWidth(math.max(80, w - PAD * 5 - cancelW))
    search:setHeight(eh)
    self.hintY = top + math.max(eh, ch) + 6
    local listY = self.hintY + lh + 4
    local list = self.list
    list:setX(PAD * 2)
    list:setY(listY)
    local lw, lh2 = math.max(80, w - PAD * 4), math.max(lh, h - PAD * 2 - listY)
    if list.width ~= lw or list.height ~= lh2 then
        list:resize(lw, lh2)
    end
    self._titleFit = fit(self.title, math.max(0, w - PAD * 4), UIFont.Medium)
    if self:getIsVisible() then
        self:rebuild()
    end
end

function Picker:resize(width, height)
    if self.width ~= width then
        self:setWidth(width)
    end
    if self.height ~= height then
        self:setHeight(height)
    end
    self:layout()
end

function Picker:isOpen()
    return self:getIsVisible() == true
end

function Picker:open()
    if self:getIsVisible() then
        return
    end
    self.search:setText("")
    self._seen, self._searchAt = "", nil
    self:setVisible(true)
    self:layout()
    -- 疊層開著時鍵盤屬於它：輸入框是打字的地方，焦點框不留在頁面不再提供的控制項上
    if Focus then
        Focus.focusControl(self.search._entry, true)
        Focus.invalidate(rootOf(self))
    end
end

function Picker:close()
    if not self:getIsVisible() then
        return
    end
    self.search._entry:unfocus()
    self:setVisible(false)
    if Focus then
        Focus.invalidate(rootOf(self))
    end
end

-- 選取是給開啟者的答覆：疊層先關，頁面拿回鍵盤與畫面後才決定怎麼用這筆 record。關著時不回呼
-- （同一次點擊或 Enter 的第二個來源不會選兩次）。
function Picker:choose(rec)
    if rec == nil or not self:getIsVisible() then
        return
    end
    self:close()
    if self.onPick then
        self.onPick(self.target, rec, self)
    end
end

function Picker:cancel()
    self:close()
    if self.onCancel then
        self.onCancel(self.target, self)
    end
end

function Picker:keyboardTargets()
    if not self:getIsVisible() then
        return self._noTargets
    end
    return self._targets
end

function Picker:dispose()
    self:close()
    self.onPick, self.onCancel = nil, nil
    self.list:setItems({})
end

-- 打字只重設計時器：宇宙有數千筆，每次停頓才掃一次；revision 變了（例如 consumer 的索引剛載好）
-- 同一個查詢重問一次。每幀只做字串比較與數值運算。
function Picker:prerender()
    if self.isCollapsed then
        return
    end
    local text = self.search:getText()
    if text ~= self._seen then
        self._seen = text
        self._searchAt = getTimestampMs()
    end
    if self._searchAt ~= nil then
        if getTimestampMs() - self._searchAt >= DEBOUNCE_MS then
            self._searchAt = nil
            self:rebuild()
        end
    elseif self._revision and self._revision() ~= self._rev then
        self:rebuild()
    end

    local w, h = self.width, self.height
    local colors = self.theme.colors
    local chrome = chromeAlpha(self.theme)
    -- 不透明背板：疊層只對著自己讀，不透出底下的列（不乘 theme.alpha）
    Skin.fill(self, 0, 0, w, h, colors.surface, nil, 1)
    local cw, cardH = math.max(1, w - PAD * 2), math.max(1, h - PAD * 2)
    Skin.fill(self, PAD, PAD, cw, cardH, colors.hover, nil, (2 / 3) * chrome)
    Skin.border(self, PAD, PAD, cw, cardH, colors.border, nil, chrome)
    drawColorText(self, self._titleFit, PAD * 2, PAD + math.floor((CARD_TITLE_H - self._titleH) / 2),
        colors.text, UIFont.Medium)
    local border = colors.border
    self:drawRect(PAD + 1, PAD + CARD_TITLE_H, cw - 2, 1, (border.a or 1) * chrome, border.r, border.g, border.b)
    if self._hintFit then
        drawColorText(self, self._hintFit, PAD * 2, self.hintY, colors.textFaint, self.font)
    end
end

function Picker:render()
end

-- 疊層開著時背後什麼都點不到：傳到背板的滑鼠事件都停在這裡（子元件先問，搜尋框與清單照常）
function Picker:onMouseDown() return true end
function Picker:onMouseUp() return true end
function Picker:onRightMouseDown() return true end
function Picker:onRightMouseUp() return true end
function Picker:onMouseMove() return true end
function Picker:onMouseWheel() return true end

function ItemPicker.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local theme = opts.theme or UI.Theme.create()
    local o = ISPanel.new(Picker, opts.x or 0, opts.y or 0, opts.width or 600, opts.height or 400)
    o.background = false -- 背板由 prerender 畫
    o.theme = theme
    o.font = font
    o._fontH = fontHeight(font)
    o._lineH = o._fontH + 6
    o._titleH = fontHeight(UIFont.Medium)
    o.title = opts.title or tr("IGUI_MinidoracatUI_ItemPicker_Title")
    o.placeholder = opts.placeholder or tr("IGUI_MinidoracatUI_ItemPicker_Search")
    o._items, o._filter, o._revision, o._note = opts.items, opts.filter, opts.revision, opts.note
    o.maxResults = opts.maxResults or MAX_RESULTS
    o.target, o.onPick, o.onCancel = opts.target, opts.onPick, opts.onCancel
    o.total, o.shown = 0, 0
    o._rows = {}
    o._seen = ""
    o:initialise()

    o.search = UI.TextField.new{ placeholder = o.placeholder, maxLength = 48, clearButton = true,
        theme = theme, font = font }
    o:addChild(o.search)
    o.list = UI.Table.new{ x = 0, y = 0, width = 80, height = o._lineH, rowHeight = o._lineH * 2 + 10,
        cell = PickCell, theme = theme, onSelect = onRowSelect }
    o.list.picker = o
    o:addChild(o.list)
    local cancel = tr("IGUI_MinidoracatUI_Cancel")
    o._cancelW = measure(font, cancel) + 24
    o.cancelButton = UI.Button.new{ title = cancel, style = "chip", theme = theme, font = font,
        target = o, onClick = Picker.cancel }
    o:addChild(o.cancelButton)

    o._targets = {
        { kind = "entry", control = o.search._entry, frame = o.search, label = o.placeholder },
        { kind = "list", control = o.list, label = o.title },
        { kind = "button", control = o.cancelButton, label = cancel },
    }
    o._noTargets = {}
    o:setVisible(false)
    o:layout()
    return o
end

UI.ItemPicker = ItemPicker
UI.CAPABILITIES.itemPicker = true

return ItemPicker
