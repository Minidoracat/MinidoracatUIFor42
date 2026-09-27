-- MinidoracatUI Widgets/Table — 表格外殼（API rev 11，收編自 Economy ECWidgets／ECPanelWidgets）：
--   * UI.Table.new(opts)：已 initialise 的 UI.VirtualList，內建 cell 建立／綁定（onBind／onUnbind 勾子）
--   * UI.Table.rowBackground(cell)：斑馬紋／選取／hover 三態，回傳 lit（使用端拿來提亮淡字）
--   * UI.Table.TextCell：entry = { cells, tokens?, muted? } 的純文字列，依 list.cols 擺欄
--   * UI.Table.layoutColumns(specs, leftX, rightX, nameMin, pad?)：欄寬預算分配
--   * UI.TableHeader.new(opts)：可排序表頭（拉取式排序狀態、點擊回 key 或 nil）
-- chrome（fill）乘 theme.alpha，文字、刪除線與排序箭頭不乘（約定見 V1.lua Theme 段）。
-- per-frame 路徑零 table／closure 配置：TextCell 截字結果快取在 cell，綁定或欄位／寬度變了才重算。
--
-- 引擎出處（42.20.4）：ISUIElement:isMouseOver（ISUIElement.lua:414）、drawRect（:1191）、
-- drawText（:1293）；ISPanel:new（ISPanel.lua:96）、ISPanel:prerender 只在 background 時畫底（:18）、
-- ISPanel:onMouseDown（:49）。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text and UI.Skin.arrow) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.table 探測）
end
if not UI.VirtualList then
    pcall(require, "MinidoracatUI/VirtualList")
end
if not UI.VirtualList then
    return
end

local Skin = UI.Skin
local fit = UI.Text.fit

local ARROW_W, ARROW_H = Skin.ARROW_W, Skin.ARROW_H
-- 可排序欄一律在右緣預留箭頭位：排序切到它時數字才不會橫跳
local SORT_GUTTER = ARROW_W + 4
local ZEBRA = 2 / 3 -- hover×2/3：dark 主題 0.06×2/3＝0.04，等於 Economy 的 card 色
local STRIKE_INSET = 12
local DEFAULT_PAD = 12

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text)
end

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

-- rev 11 theme.alpha：chrome（fill／border）乘它，文字與 icon 不乘（約定見 V1.lua Theme 段）
local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function drawColorText(el, text, x, y, color, font)
    el:drawText(text, x, y, color.r, color.g, color.b, color.a or 1, font)
end

local Table = {}

-- ============================================================
-- rowBackground
-- ============================================================

function Table.rowBackground(cell)
    local theme = cell.theme
    local colors, ca = theme.colors, chromeAlpha(theme)
    local w, h, index = cell.width, cell.height, cell.index
    if index and index % 2 == 0 then
        Skin.fill(cell, 0, 0, w, h, colors.hover, "rect", ZEBRA * ca)
    end
    local list = cell.list
    local lit = index ~= nil and list ~= nil and list:isSelected(index)
    if lit then
        Skin.fill(cell, 0, 0, w, h, colors.selected, "rect", ca)
    end
    if cell:isMouseOver() then
        Skin.fill(cell, 0, 0, w, h, colors.hover, "rect", ca)
        lit = true
    end
    return lit
end

-- ============================================================
-- TextCell
-- ============================================================
-- entry = { cells = { string... }, tokens = { token... }?, muted = bool? }
-- list.cols[i] = { x, right?, width? }（x 相對 cell；right＝x 是右緣；width＝截字寬）

local TextCell = ISPanel:derive("MinidoracatUITableTextCell")

-- 截字快取鍵是每欄實際的 width／right：使用端常原地重算同一組 cols（清單總寬不變），
-- 只比 cols 身分會留下舊的截字。每幀只做數值比較，不配置。
local function textStale(cell, cols, n)
    if cell._textCols ~= cols or cell._textN ~= n then
        return true
    end
    local fitW, fitR = cell._fitW, cell._fitR
    for i = 1, n do
        local col = cols[i]
        if (col and col.width or false) ~= fitW[i] or ((col and col.right) and true or false) ~= fitR[i] then
            return true
        end
    end
    return false
end

-- 只讀 self 與模組 local：衍生 cell 可直接 UI.Table.TextCell.render(self)
function TextCell:render()
    local e = self.entry
    if not e then
        return
    end
    local cols = self.list.cols
    local cells = e.cells
    local n = #cells
    local w, h = self.width, self.height
    local font = UIFont.Small
    local texts, widths = self._text, self._textW
    if not texts then
        texts, widths = {}, {}
        self._text, self._textW, self._fitW, self._fitR = texts, widths, {}, {}
    end
    if textStale(self, cols, n) then
        local fitW, fitR = self._fitW, self._fitR
        for i = 1, n do
            local col = cols[i]
            local str = tostring(cells[i])
            local right = (col and col.right) and true or false
            if col and col.width then
                str = fit(str, col.width, font)
            end
            texts[i] = str
            widths[i] = right and measure(font, str) or 0
            fitW[i], fitR[i] = col and col.width or false, right
        end
        self._textCols, self._textN = cols, n
    end
    local lit = Table.rowBackground(self)
    local fh = fontHeight(font)
    local ty = math.floor((h - fh) / 2)
    local colors = self.theme.colors
    local tokens = e.tokens
    for i = 1, n do
        local col = cols[i]
        if col then
            local token = e.muted and "textFaint" or (tokens and tokens[i]) or "text"
            if lit and (token == "textFaint" or token == "textMuted") then
                token = "text"
            end
            local color = colors[token] or colors.text
            local x = col.right and (col.x - widths[i]) or col.x
            drawColorText(self, texts[i], x, ty, color, font)
        end
    end
    local first = cols[1]
    if e.muted and first then
        local c = colors.textFaint
        self:drawRect(first.x, ty + math.floor(fh / 2), w - first.x - STRIKE_INSET, 1, c.a or 1, c.r, c.g, c.b)
    end
end

-- ============================================================
-- Table.new
-- ============================================================

local function createCell(list)
    local cell = ISPanel.new(list._cellClass, 0, 0, 0, 0)
    cell.background = false -- ISPanel:prerender 會畫 0.5 黑底＋框（ISPanel.lua:18）
    cell.list = list
    cell.theme = list.theme
    return cell
end

local function bindCell(_, cell, item, index)
    cell.entry = item
    cell.index = index
    cell._textCols = nil -- 同一顆 entry 原地改過再 setItems 也要重算截字
    if cell.onBind then
        cell:onBind()
    end
end

local function unbindCell(_, cell)
    if cell.onUnbind then
        cell:onUnbind()
    end
    cell.entry = nil
end

-- opts: { x?, y?, width?, height?, rowHeight, cell?=TextCell, padding?=0, theme?, colors?,
--         onSelect?, onHighlight?, onKey? }；list.cols＝{}（欄位幾何由使用端寫入）、list.theme
function Table.new(opts)
    local theme = opts.theme or UI.Theme.create()
    local colors = opts.colors
    if not colors then
        local tc = theme.colors
        colors = { thumb = tc.textFaint, thumbHover = tc.textMuted, track = tc.selected }
    end
    local list = UI.VirtualList.new({
        x = opts.x or 0, y = opts.y or 0, width = opts.width or 100, height = opts.height or 100,
        rowHeight = opts.rowHeight, padding = opts.padding or 0,
        createCell = createCell, bindCell = bindCell, unbindCell = unbindCell,
        onSelect = opts.onSelect, onHighlight = opts.onHighlight, onKey = opts.onKey,
        colors = colors,
    })
    list._cellClass = opts.cell or TextCell
    list.theme = theme
    list.cols = {}
    list:initialise()
    return list
end

-- ============================================================
-- layoutColumns
-- ============================================================
-- specs[1] 是彈性欄（通常是名稱）；其他欄依標題／sample 量寬。輸出 x／w（表頭命中區）、
-- textR／textW（值的位置，扣掉排序箭頭預留）、wrapped（該欄縮到換行寬度）。
-- 預算 leftX..rightX 絕不超出；不夠時依序讓出：sample 型非靠右文字欄縮到「...」→ 拿掉 extra →
-- 有 wrapW 的欄縮到換行寬 → soft 欄只剩標題 → 以上都不夠就全部按比例縮。

local function sortGutter(c)
    return c.sortable ~= false and SORT_GUTTER or 0
end

-- 版面期間才呼叫（不是每幀），reclaim 用 closure 與 Economy 原碼同形
function Table.layoutColumns(specs, leftX, rightX, nameMin, pad)
    pad = pad or DEFAULT_PAD
    local font = UIFont.Small
    local budget = math.max(0, rightX - leftX)
    local ellipsis = measure(font, "...")
    -- 名稱欄是表格的主角：至少留一段可辨識的前綴，或至少它自己的標題
    local nameFloor = math.max(ellipsis, measure(font, specs[1].title) + sortGutter(specs[1]))
    local used = 0
    specs[1].wrapped = false
    for i = 2, #specs do
        local c = specs[i]
        local valueW = c.sampleW or (c.sample and measure(font, c.sample)) or 0
        c.w = pad + (c.extra or 0) + sortGutter(c) + math.max(measure(font, c.title), valueW)
        c.wrapped = false
        used = used + c.w
    end
    local nameW = budget - used
    -- 名稱欄在 nameW 低於 want 時，向每欄拿回 low(c) 允許讓出的寬度
    local function reclaim(want, low)
        for i = 2, #specs do
            if nameW >= want then
                return
            end
            local c = specs[i]
            local floor = low(c)
            if floor and floor < c.w then
                local take = math.min(want - nameW, c.w - floor)
                c.w, nameW, used = c.w - take, nameW + take, used - take
            end
        end
    end
    reclaim(nameMin, function(c) return ((c.sample or c.sampleW) and not c.right) and (pad + ellipsis) or nil end)
    reclaim(nameFloor, function(c) return c.extra and (c.w - c.extra) or nil end)
    for i = 2, #specs do
        local c = specs[i]
        if nameW < nameMin and c.wrapW then
            local wrapFloor = pad + sortGutter(c) + math.max(measure(font, c.title), c.wrapW)
            local take = math.min(nameMin - nameW, math.max(0, c.w - wrapFloor))
            c.w, nameW, used = c.w - take, nameW + take, used - take
            c.wrapped = take > 0
        end
    end
    reclaim(nameFloor, function(c) return c.soft and (measure(font, c.title) + sortGutter(c)) or nil end)
    if nameW < nameFloor and used > 0 then
        local room, total = math.max(0, budget - nameFloor), used
        used = 0
        for i = 2, #specs do
            local c = specs[i]
            c.w = math.floor(c.w * room / total)
            c.wrapped = false -- 按比例縮不再保證換行後的完整寬度
            used = used + c.w
        end
        nameW = budget - used
    end
    local x = leftX
    for i = 1, #specs do
        local c = specs[i]
        if i == 1 then
            c.w = math.max(0, nameW)
        end
        c.x = x
        c.textR = x + c.w - sortGutter(c)
        c.textW = math.max(0, c.w - sortGutter(c))
        x = x + c.w
    end
    return specs
end

-- ============================================================
-- TableHeader
-- ============================================================

local TableHeader = ISPanel:derive("MinidoracatUITableHeader")

local EMPTY = {}

function TableHeader:setColumns(specs)
    self._cols = specs or EMPTY
end

function TableHeader:isLive()
    return not self.live or self.live(self.target) == true
end

-- 每欄的截字標題、標題 x、箭頭 x 快取在 self._slots[i]；鍵是該欄的 title／x／w／textR／right／
-- sortable。使用端原地改 specs（不論有沒有再呼叫 setColumns）都在下一幀比對出來重算；
-- 幾何沒變時每幀只做欄位比較，不呼叫 Text.fit、不產生字串。slot table 每個欄位序號只建一次。
local function headerSlot(header, i, c)
    local slots = header._slots
    local s = slots[i]
    if not s then
        s = {}
        slots[i] = s
    end
    local sortable = c.sortable ~= false
    local right = c.right and true or false
    if s.title == c.title and s.x == c.x and s.w == c.w and s.textR == c.textR
            and s.right == right and s.sortable == sortable then
        return s
    end
    s.title, s.x, s.w, s.textR, s.right, s.sortable = c.title, c.x, c.w, c.textR, right, sortable
    local font = header.font
    local gutter = sortable and SORT_GUTTER or 0
    if right then
        local rx = c.textR or (c.x + c.w - gutter)
        s.label = fit(c.title, math.max(0, rx - c.x), font)
        s.labelX = rx - measure(font, s.label)
        s.arrowX = c.x + c.w - ARROW_W
    else
        s.label = fit(c.title, c.w - gutter, font)
        s.labelX = c.x
        s.arrowX = c.x + measure(font, s.label) + 4
    end
    return s
end

function TableHeader:prerender()
    local theme = self.theme
    local colors = theme.colors
    local w, h = self.width, self.height
    Skin.fill(self, 0, 0, w, h, colors.well, "rect", chromeAlpha(theme))
    local font, fh = self.font, self._fontH
    local ty = math.floor((h - fh) / 2)
    local ay = ty + math.floor((fh - ARROW_H) / 2)
    local sortKey, desc = nil, false
    if self.sort then
        sortKey, desc = self.sort(self.target)
    end
    local idle = self:isLive() and colors.textMuted or colors.textFaint
    local cols = self._cols
    for i = 1, #cols do
        local c = cols[i]
        local s = headerSlot(self, i, c)
        -- 不可排序的欄（例：自己的上架清單）永遠不亮、不預留箭頭位：只是對齊同一組邊的標題
        local active = s.sortable and sortKey ~= nil and c.key == sortKey
        local color = active and colors.accent or idle
        drawColorText(self, s.label, s.labelX, ty, color, font)
        if active then
            Skin.arrow(self, s.arrowX, ay, not desc, color)
        end
    end
end

function TableHeader:render() end

-- 點在可排序欄上回 key；欄外或不可排序欄回 nil（使用端決定預設排序）；live=false 不回呼
function TableHeader:onMouseDown(x)
    if self.onSort and self:isLive() then
        local key = nil
        local cols = self._cols
        for i = 1, #cols do
            local c = cols[i]
            if c.sortable ~= false and x >= c.x and x < c.x + c.w then
                key = c.key
            end
        end
        self.onSort(self.target, key, self)
    end
    return true
end

-- opts: { x?, y?, width?, height?=字高+10, theme?, font?, target?, sort?, live?, onSort? }
function TableHeader.new(opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fh = fontHeight(font)
    local o = ISPanel.new(TableHeader, opts.x or 0, opts.y or 0, opts.width or 100, opts.height or (fh + 10))
    o.background = false
    o.theme = opts.theme or UI.Theme.create()
    o.font, o._fontH = font, fh
    o.target = opts.target
    o.sort, o.live, o.onSort = opts.sort, opts.live, opts.onSort
    o._cols, o._slots = EMPTY, {}
    o:initialise()
    return o
end

Table.TextCell = TextCell
UI.Table = Table
UI.TableHeader = TableHeader
UI.CAPABILITIES.table = true

return Table
