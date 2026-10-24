-- MinidoracatUI Widgets/ItemPicker — 「挑一個物品」疊層（API rev 11，CAPABILITIES.itemPicker）。
-- 收編自 Economy ECItemPicker 的通用部分；英文名索引、上架政策、索引載入提示留在 consumer，
-- 以 items／filter／revision／note 注入。
--
--   UI.ItemPicker.universe() -> { items = { record, ... }, byType = { [fullType] = record } }
--       本 session 載入的全部物品 script（原版與 MOD），record = { fullType, name, category, script,
--       search }；整個 session 共用，consumer 唯讀。只跳過 hidden／obsolete。不排序（數千筆，
--       排序交給 consumer）。空結果不快取：script manager 還沒準備好時不能讓 session 永遠拿到空宇宙。
--       name＝getItemName（rev 20，CAPABILITIES.itemPickerVehicleClass）：車輛零件的三種車型共用一個
--       譯名，getItemName 才照原版背包接上車型；rev 11–19 用 getItemNameFromFullType，三種同名。
--
--   UI.ItemPicker.new(opts) -> picker（已 initialise 的 ISPanel，尚未 addChild）
--       opts: x?, y?, width?, height?, theme?, font?, title?, placeholder?,
--             items?（function() -> array；預設 universe().items；record 至少要有 fullType／name／
--             category／search，選用 original＝右側淡字、script＝圖示來源）、
--             filter?（function(rec) -> bool）、revision?（function() -> any；開著時值變了就重搜）、
--             note?（function() -> string|nil；提示列前綴）、maxResults?（預設 200）、
--             target?, onPick(target, rec, picker)（疊層先關再回呼）、onCancel?(target, picker)
--       rev 25 多選（CAPABILITIES.itemPickerMulti；multi 不為 true 時下列欄位全部忽略，畫面與行為同單選）：
--             multi = true、maxPicks?（整數 >= 1；nil＝不限）、doneTitle?、
--             onPickMany(target, recs, picker)（按「完成」：疊層先關再回呼一次；recs 依勾選先後，取自 items()，
--             找不到退 universe().byType，再找不到就略過）。choose 改成切換勾選、不關閉；達上限拒勾新列。
--       consumer 最後才 addChild（畫在頁面內容之上），並 resize 成整頁大小。
--       方法：open(picked?)（多選：預先勾好的 fullType 陣列，非字串與重複略過、超過 maxPicks 截斷；每次開啟都重設）、
--             done()（多選：等同按「完成」；關著時不做事）、close()、isOpen()、cancel()（多選時勾選作廢）、
--             resize(w, h)、keyboardTargets()、dispose()。
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
--   getItemName                 LuaManager.java:8745-8763（快照 42.21.0-20260928；腳本 VehicleType > 0
--                               時接 IGUI_ItemNameMechanicalType＋IGUI_VehicleType_<n>，同 InventoryItem.getName）
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
local BOX_SIZE = 14 -- rev 25 多選：列首勾選框邊長（同 Checkbox 的方框退回）
local FOOTER_GAP = 6 -- rev 25 多選：清單與底部計數列之間

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
    local ok, name = pcall(getItemName, fullType)
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

-- 綁定時一次算好截字與幾何（render 只畫）；cell 寬度由 VirtualList 在 bind 前設好。多選時圖示前多一個勾選框
function PickCell:onBind()
    local rec = self.entry
    local picker = self.list.picker
    local font, lh = picker.font, picker._lineH
    local width = self.width - PAD
    local size = math.min(math.max(12, self.height - 12), 28)
    local iconX = PAD
    if picker.multi then
        local box = math.min(BOX_SIZE, size)
        self._boxSize, self._boxY = box, math.floor((self.height - box) / 2)
        iconX = PAD + box + 8
    else
        self._boxSize = nil
    end
    local nameX = iconX + size + 8
    local original = rec.original
    local alt = type(original) == "string" and original ~= "" and original ~= rec.name
    local nameW = math.max(40, math.floor((width - nameX) * (alt and 0.55 or 1)))
    self._icon = iconOf(rec)
    self._iconX = iconX
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
    local box = self._boxSize
    if box then
        -- 勾選＝框內實心方塊（不只靠顏色）；框與方塊乘 theme.alpha，同 Checkbox 的方框退回
        local ca = chromeAlpha(self.theme)
        local border = colors.border
        self:drawRectBorder(PAD, self._boxY, box, box, (border.a or 1) * ca, border.r, border.g, border.b)
        if self.list.picker._picked[rec.fullType] then
            local on = colors.accent
            self:drawRect(PAD + 3, self._boxY + 3, box - 6, box - 6, (on.a or 1) * ca, on.r, on.g, on.b)
        end
    end
    if icon then
        local size = self._iconSize
        -- 照原圖比例縮進方框、置中（裁過透明邊的物品圖示不拉成正方形；同 Controls.lua drawTextureIcon）
        if not pcall(self.drawTextureScaledAspect, self, icon, self._iconX, self._iconY, size, size, 1, 1, 1, 1) then
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

-- rev 25 多選：勾選＝set（fullType -> true）＋勾選先後的陣列，原地清空（不換新表）
local function clearPicks(picker)
    local order, picked = picker._order, picker._picked
    for i = #order, 1, -1 do
        picked[order[i]] = nil
        order[i] = nil
    end
    picker._pickWarn = false
end

-- 計數字只在勾選或寬度變動時重組（prerender 只畫快取）
local function refreshPicked(picker)
    local n = tostring(#picker._order)
    local text
    if picker.maxPicks then
        text = getText("IGUI_MinidoracatUI_ItemPicker_PickedMax", n, tostring(picker.maxPicks))
    else
        text = getText("IGUI_MinidoracatUI_ItemPicker_Picked", n)
    end
    picker.pickedText = text
    picker._pickedFit = fit(text, math.max(0, picker.width - PAD * 5 - picker.doneButton.width), picker.font)
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
    local listBottom = h - PAD * 2
    if self.multi then
        local done = self.doneButton
        local doneW = math.min(self._doneW, math.max(48, math.floor(w * 0.3)))
        local footerY = h - PAD * 2 - ch
        done:setWidth(doneW)
        done:setHeight(ch)
        done:setX(w - PAD * 2 - doneW)
        done:setY(footerY)
        self._footerTextY = footerY + math.floor((ch - self._fontH) / 2)
        listBottom = footerY - FOOTER_GAP
        refreshPicked(self)
    end
    local list = self.list
    list:setX(PAD * 2)
    list:setY(listY)
    local lw, lh2 = math.max(80, w - PAD * 4), math.max(lh, listBottom - listY)
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

-- picked（rev 25 多選）：預先勾好的 fullType 陣列；每次開啟都以它重設勾選（沒給就清空），單選忽略
function Picker:open(picked)
    if self:getIsVisible() then
        return
    end
    if self.multi then
        clearPicks(self)
        if type(picked) == "table" then
            local order, set, max = self._order, self._picked, self.maxPicks
            for i = 1, #picked do
                local ft = picked[i]
                if max and #order >= max then
                    break
                end
                if type(ft) == "string" and not set[ft] then
                    set[ft] = true
                    order[#order + 1] = ft
                end
            end
        end
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
-- （同一次點擊或 Enter 的第二個來源不會選兩次）。多選（rev 25）改成切換勾選、不關閉：
-- 已達 maxPicks 時不勾新列，計數字改警示色；取消勾選或勾成功就恢復。
function Picker:choose(rec)
    if rec == nil or not self:getIsVisible() then
        return
    end
    if self.multi then
        local ft = rec.fullType
        local order, set = self._order, self._picked
        if set[ft] then
            set[ft] = nil
            for i = 1, #order do
                if order[i] == ft then
                    table.remove(order, i)
                    break
                end
            end
        elseif self.maxPicks and #order >= self.maxPicks then
            self._pickWarn = true
            return
        else
            set[ft] = true
            order[#order + 1] = ft
        end
        self._pickWarn = false
        refreshPicked(self)
        return
    end
    self:close()
    if self.onPick then
        self.onPick(self.target, rec, self)
    end
end

-- rev 25 多選的「完成」：疊層先關，再以勾選先後的 record 陣列回呼一次。record 優先取 consumer 的
-- items()（它自己的欄位），找不到退 universe().byType，再找不到就略過。關著時或單選不做事。
function Picker:done()
    if not self.multi or not self:getIsVisible() then
        return
    end
    local order = self._order
    local found = {}
    if self._items then
        local items, set = self._items(), self._picked
        for i = 1, #items do
            local rec = items[i]
            local ft = rec.fullType
            if set[ft] and found[ft] == nil then
                found[ft] = rec
            end
        end
    end
    local byType = ItemPicker.universe().byType
    local recs = {}
    for i = 1, #order do
        local rec = found[order[i]] or byType[order[i]]
        if rec ~= nil then
            recs[#recs + 1] = rec
        end
    end
    self:close()
    if self.onPickMany then
        self.onPickMany(self.target, recs, self)
    end
end

function Picker:cancel()
    self:close()
    if self.multi then
        clearPicks(self)
    end
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
    self.onPick, self.onCancel, self.onPickMany = nil, nil, nil
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
    Skin.fill(self, 0, 0, w, h, colors.surface, Skin.shapeOf(self.theme, "panel"), 1)
    local cw, cardH = math.max(1, w - PAD * 2), math.max(1, h - PAD * 2)
    Skin.fill(self, PAD, PAD, cw, cardH, colors.hover, Skin.shapeOf(self.theme, "panel"), (2 / 3) * chrome)
    Skin.border(self, PAD, PAD, cw, cardH, colors.border, Skin.shapeOf(self.theme, "panel"), chrome)
    drawColorText(self, self._titleFit, PAD * 2, PAD + math.floor((CARD_TITLE_H - self._titleH) / 2),
        colors.text, UIFont.Medium)
    local border = colors.border
    self:drawRect(PAD + 1, PAD + CARD_TITLE_H, cw - 2, 1, (border.a or 1) * chrome, border.r, border.g, border.b)
    if self._hintFit then
        drawColorText(self, self._hintFit, PAD * 2, self.hintY, colors.textFaint, self.font)
    end
    if self._pickedFit then
        -- 達上限仍想勾新列時改警示色（自訂 theme 沒有 warning 就退 errorText）
        local color = self._pickWarn and (colors.warning or colors.errorText or colors.text) or colors.textFaint
        drawColorText(self, self._pickedFit, PAD * 2, self._footerTextY, color, self.font)
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
    if opts.multi == true then
        o.multi = true
        local max = opts.maxPicks
        o.maxPicks = type(max) == "number" and max >= 1 and math.floor(max) or nil
        o.onPickMany = opts.onPickMany
        o._picked, o._order, o._pickWarn = {}, {}, false
    end
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

    local cancelTarget = { kind = "button", control = o.cancelButton, label = cancel }
    o._targets = {
        { kind = "entry", control = o.search._entry, frame = o.search, label = o.placeholder },
        { kind = "list", control = o.list, label = o.title },
    }
    if o.multi then
        local done = opts.doneTitle or tr("IGUI_MinidoracatUI_ItemPicker_Done")
        o._doneW = measure(font, done) + 24
        o.doneButton = UI.Button.new{ title = done, style = "primary", theme = theme, font = font,
            target = o, onClick = Picker.done }
        o:addChild(o.doneButton)
        o._targets[3] = { kind = "button", control = o.doneButton, label = done }
    end
    o._targets[#o._targets + 1] = cancelTarget
    o._noTargets = {}
    o:setVisible(false)
    o:layout()
    return o
end

UI.ItemPicker = ItemPicker
UI.CAPABILITIES.itemPicker = true
UI.CAPABILITIES.itemPickerVehicleClass = true
UI.CAPABILITIES.itemPickerMulti = true

return ItemPicker
