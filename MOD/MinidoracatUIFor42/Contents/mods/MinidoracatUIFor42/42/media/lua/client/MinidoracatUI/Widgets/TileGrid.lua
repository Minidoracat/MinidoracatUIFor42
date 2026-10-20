-- MinidoracatUI Widgets/TileGrid — 方格清單（API rev 22，CAPABILITIES.tileGrid）：UI.TileGrid。
-- 收編自 Economy ECPanelGrid＋ECPanelWidgets（W.gridStrips／W.tileAt／W.gridFocusKey）的通用部分：
-- 固定 12px 捲軸預留、選取與 hover 高亮、游標跟隨與捲動、focusRect／focusLabel。頁面欄位、價格文字、
-- 與表格共用選取等商店邏輯留在 consumer，以 drawTile／onPick／focusLabel 注入。
--
--   UI.TileGrid.new(opts) -> grid（已 initialise 的 ISPanel，consumer addChild）
--     opts: x?, y?, width?, height?, tileW（最小格寬）, tileH（格高）, theme?, target?,
--           drawTile(target, grid, item, x, y, w, h, state)、onPick(target, item, index, grid)、
--           focusLabel?(target, item) -> string|nil、label?（焦點說明的退回）、
--           tooltip?(target, item, index) -> string|nil（滑鼠停在格上的提示）
--   每列格數＝max(1, floor((width - 12) / tileW))，多出的寬度平均分給每格（tileWidth()）；捲軸的 12px
--     一律預留，捲軸出現時不重排。
--   方法：setItems(items)（游標仍在範圍內就保留，否則清掉）、getItems()、getSelectedIndex()、
--     setSelectedIndex(i)（nil＝沒有游標；不捲動、不回呼）、getSelectedItem()、scrollToIndex(i)（捲到那格
--     完整可見，已可見不動）、resize(w, h)、perRow()、tileWidth()、indexAt(x, y)（元素座標下的格；格間空隙、
--     最後一列的空位與捲軸區回 nil）
--   繪製：每格先畫卡片底（theme 的 card token，palette 沒有就用 well）、選取＝selected 底＋1px accent 框
--     （選中不只靠顏色）、hover＝hover 底（沒有框），再呼叫 drawTile 畫內容。drawTile 的 grid 就是畫布：
--     consumer 對它呼叫 drawText／drawTextCentre／drawTextureScaledAspect 等；x, y, w, h＝卡片（格子四邊
--     內縮 2）在 grid 上的元素座標，已扣掉捲動量、畫在 grid 的 stencil 裡（超出可視區的部分被裁掉），consumer
--     不讀捲動狀態。沒有子元件（不用 cell）。state＝重用的同一張表 { picked, hover, index }，consumer 不得
--     留著。drawTile 以 pcall 傳參呼叫，出錯只少那格內容。chrome 乘 theme.alpha。
--   提示：滑鼠下的格子換了（含 setItems）才問一次 tooltip（pcall；不是字串或空字串＝沒有），走 Controls 的
--     rev 17 controlTooltips 同一條路（借原版 ISButton:updateTooltip），位置改在那格卡片下方；滑鼠離開或
--     那格沒有提示時收掉。
--   滑鼠：點卡片＝游標移到那格＋onPick；點空隙不動；滾輪一次捲一列；右側捲軸（UI.VirtualList 的）。
--   焦點（Focus 選用，本檔不 require）：整個元件是一個 `_focusKind="button"` 目標。左右＝前／後一格（跨列）；
--     上下＝同一欄的上／下一列（最後一列較短時落在它的最後一格）；Home／End；PgUp／PgDn＝一頁的列數，
--     同一欄；沒有游標時第一個導覽鍵落在第一格（End 落在最後一格）。動不了回 false（手把移到下一個目標）。
--     Enter／小鍵盤 Enter／Space／手把 A＝onPick（沒有游標時先落在第一格）。游標移動時捲到那格，並請
--     捲動容器祖先 scrollTo。focusRect() 只框游標那格的卡片：捲出本元件可視區回 nil、部分可見時裁到
--     可視區內（框不畫到元件外）。focusLabel() 回 opts.focusLabel 的結果，nil 時回 label。
--
-- 實作：繼承 UI.VirtualList（捲軸、拇指拖曳、軌道跳頁、stencil 成對、資料 revision 與選取存放），但不用
--   cell 池：items 是格子陣列、rowHeight＝tileH，contentHeight 改以「列數 × tileH」計算，格子在 prerender
--   直接畫。prerender 零 table／closure 配置。字串字面值只含 ASCII；本檔沒有自己的顯示文字。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme) or not ISPanel then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.tileGrid 探測）
end
if not UI.VirtualList then
    pcall(require, "MinidoracatUI/VirtualList")
end
local VirtualList = UI.VirtualList
if not VirtualList then
    return
end

local Skin = UI.Skin

local RESERVE = 12 -- VirtualList 捲軸 10＋間距 2；一律預留
local INSET = 2    -- 卡片在格子內四邊內縮（兩格之間 4px 空隙）
local TIP_GAP = 8 -- 提示框在卡片下緣之下（同原版 ISButton:updateTooltip 的 +8）

local TileGrid = VirtualList:derive("MinidoracatUITileGrid")

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

-- ---------- 幾何 ----------

function TileGrid:perRow()
    return math.max(1, math.floor((self.width - RESERVE) / self.tileW))
end

function TileGrid:tileWidth()
    return math.max(1, math.floor((self.width - RESERVE) / self:perRow()))
end

-- VirtualList 的捲動範圍與拇指都經它：列數 × 格高
function TileGrid:contentHeight()
    return math.ceil(#self.items / self:perRow()) * self.rowHeight
end

function TileGrid:indexAt(x, y)
    if y < 0 or y >= self.height or x < 0 then
        return nil
    end
    local per, tw, th = self:perRow(), self:tileWidth(), self.rowHeight
    local col = math.floor(x / tw)
    if col >= per then
        return nil
    end
    local cy = y + self.scrollOffset
    local row = math.floor(cy / th)
    local lx, ly = x - col * tw, cy - row * th
    if lx < INSET or lx >= tw - INSET or ly < INSET or ly >= th - INSET then
        return nil -- 卡片之間的空隙
    end
    local i = row * per + col + 1
    if i > #self.items then
        return nil
    end
    return i
end

-- 第 i 格卡片的元素座標（不檢查可見）
local function cardRect(grid, i)
    local per, tw, th = grid:perRow(), grid:tileWidth(), grid.rowHeight
    local col = (i - 1) % per
    local row = math.floor((i - 1) / per)
    return col * tw + INSET, row * th - grid.scrollOffset + INSET, tw - INSET * 2, th - INSET * 2
end

-- ---------- 捲動 ----------

function TileGrid:scrollToIndex(i)
    if type(i) ~= "number" or i < 1 or i > #self.items then
        return
    end
    -- VirtualList 以列為單位捲：rowHeight＝tileH、padding＝0，第 i 格所在的列
    VirtualList.scrollToIndex(self, math.floor((i - 1) / self:perRow()) + 1)
end

function TileGrid:onMouseWheel(del)
    self:setScrollOffset(self.scrollOffset + del * self.rowHeight)
    return true
end

-- 捲動容器祖先都捲到游標格（ScrollPanel:scrollTo 依 focusRect；同 NavList）
local function reveal(grid)
    local p = grid.parent
    for _ = 1, 32 do
        if type(p) ~= "table" then
            return
        end
        if p._scrollPanel and p.scrollTo then
            p:scrollTo(grid)
        end
        p = p.parent
    end
end

local function moveTo(grid, i)
    grid:setSelectedIndex(i)
    grid:scrollToIndex(i)
    reveal(grid)
end

local function pick(grid, i)
    if grid.onPick then
        grid.onPick(grid.target, grid.items[i], i, grid)
    end
end

-- 滑鼠下的格子換了才問 consumer（pcall 傳參）；顯示與收掉借原版 ISButton:updateTooltip（同 Controls 的
-- rev 17 tooltip：只讀 isMouseOver／joypadFocused／tooltip／tooltipUI），再把提示框移到那格卡片下方——
-- 原版放在整個元件下緣，方格很高時離游標太遠。只在有提示或還掛著 ISToolTip 時呼叫。
local function updateTip(grid, hover)
    if hover ~= grid._tipIndex then
        grid._tipIndex = hover
        local text, fn = nil, grid._tipFn
        if fn ~= nil and hover ~= nil then
            local ok, s = pcall(fn, grid.target, grid.items[hover], hover)
            if ok and type(s) == "string" and s ~= "" then
                text = s
            end
        end
        grid.tooltip = text
    end
    if not (grid.tooltip or grid.tooltipUI) or not (ISButton and ISButton.updateTooltip) then
        return
    end
    ISButton.updateTooltip(grid)
    local tip = grid.tooltipUI
    if tip ~= nil and hover ~= nil and grid.tooltip ~= nil and tip.setDesiredPosition then
        local _, y, _, h = cardRect(grid, hover)
        tip:setDesiredPosition(getMouseX(), grid:getAbsoluteY() + y + h + TIP_GAP)
    end
end

-- ---------- 繪製 ----------

function TileGrid:prerender()
    VirtualList.prerender(self) -- stencil；render 由 VirtualList 清掉並畫捲軸
    local hover = nil
    if not self._thumbDrag and self:isMouseOver() then
        hover = self:indexAt(self:getMouseX(), self:getMouseY())
    end
    updateTip(self, hover)
    local items = self.items
    local n = #items
    if n == 0 then
        return
    end
    local per, tw, th = self:perRow(), self:tileWidth(), self.rowHeight
    local scroll = self.scrollOffset
    local first = math.floor(scroll / th)
    local last = math.min(math.ceil(n / per) - 1, math.floor((scroll + self.height - 1) / th))
    local colors = self.theme.colors
    local card = colors.card or colors.well
    local ca = chromeAlpha(self.theme)
    local shape = Skin.shapeOf(self.theme, "control")
    local state, draw, target, picked = self._state, self.drawTile, self.target, self.selectedIndex
    local w, h = tw - INSET * 2, th - INSET * 2
    for row = first, last do
        local y = row * th - scroll + INSET
        for col = 0, per - 1 do
            local i = row * per + col + 1
            if i > n then
                break
            end
            local x = col * tw + INSET
            Skin.fill(self, x, y, w, h, card, shape, ca)
            if i == picked then
                Skin.fill(self, x, y, w, h, colors.selected, shape, ca)
                Skin.border(self, x, y, w, h, colors.accent, shape, ca)
            end
            if i == hover then
                Skin.fill(self, x, y, w, h, colors.hover, shape, ca)
            end
            if draw then
                state.picked, state.hover, state.index = i == picked, i == hover, i
                pcall(draw, target, self, items[i], x, y, w, h, state)
            end
        end
    end
end

-- ---------- 滑鼠 ----------

function TileGrid:onMouseDown(x, y)
    if x >= self.width - RESERVE then
        return VirtualList.onMouseDown(self, x, y) -- 捲軸：拇指拖曳／軌道跳頁
    end
    local i = self:indexAt(x, y)
    if i ~= nil then
        self:setSelectedIndex(i)
        pick(self, i)
    end
    return true
end

-- ---------- 焦點（Focus 引擎呼叫） ----------

function TileGrid:onFocusKey(key)
    local K = Keyboard
    local n = #self.items
    local cur = self.selectedIndex
    if key == K.KEY_RETURN or key == K.KEY_NUMPADENTER or key == K.KEY_SPACE then
        if n > 0 then
            local i = cur or 1
            moveTo(self, i)
            pick(self, i)
        end
        return true
    end
    if n == 0 then
        return false
    end
    local per = self:perRow()
    local to = nil
    if cur == nil then
        if key == K.KEY_END then
            to = n
        elseif key == K.KEY_LEFT or key == K.KEY_RIGHT or key == K.KEY_UP or key == K.KEY_DOWN
            or key == K.KEY_HOME or key == K.KEY_PRIOR or key == K.KEY_NEXT then
            to = 1
        end
    else
        local col = (cur - 1) % per
        local lastRowStart = math.floor((n - 1) / per) * per + 1
        local page = math.max(1, math.floor(self.height / self.rowHeight)) * per
        if key == K.KEY_LEFT then
            to = cur - 1
        elseif key == K.KEY_RIGHT then
            to = cur + 1
        elseif key == K.KEY_UP then
            to = cur - per
        elseif key == K.KEY_DOWN then
            to = cur < lastRowStart and math.min(n, cur + per) or nil
        elseif key == K.KEY_HOME then
            to = 1
        elseif key == K.KEY_END then
            to = n
        elseif key == K.KEY_PRIOR then
            to = math.max(col + 1, cur - page)
        elseif key == K.KEY_NEXT then
            to = math.min(cur + page, math.min(n, lastRowStart + col))
        end
    end
    if to == nil or to < 1 or to > n or to == cur then
        return false
    end
    moveTo(self, to)
    return true
end

-- 焦點框只框游標格的卡片；整格捲出本元件可視區回 nil，部分可見時裁到可視區內
function TileGrid:focusRect()
    local i = self.selectedIndex
    if i == nil or i > #self.items then
        return nil
    end
    local x, y, w, h = cardRect(self, i)
    if y + h <= 0 or y >= self.height then
        return nil
    end
    if y < 0 then
        h, y = h + y, 0
    end
    if y + h > self.height then
        h = self.height - y
    end
    return x, y, w, h
end

-- 游標格的說明：opts.focusLabel 回的字串，沒有就回 label（不留給 Focus 的 captionOf 退回：它會讀
-- self.tooltip，也就是滑鼠下那格的提示）
function TileGrid:focusLabel()
    local fn = self._labelFn
    local item = self.selectedIndex and self.items[self.selectedIndex]
    if fn ~= nil and item ~= nil then
        local ok, label = pcall(fn, self.target, item)
        if ok and type(label) == "string" and label ~= "" then
            return label
        end
    end
    return self._focusLabel
end

-- 換資料：同 VirtualList（游標還在範圍內就保留），並讓滑鼠下那格的提示下一幀重問
function TileGrid:setItems(items)
    VirtualList.setItems(self, items)
    self._tipIndex = false
end

function TileGrid.new(opts)
    opts = opts or {}
    local theme = opts.theme or UI.Theme.create()
    local o = ISPanel.new(TileGrid, opts.x or 0, opts.y or 0, opts.width or 100, opts.height or 100)
    o.background = false
    -- VirtualList 的狀態欄位（同 VirtualList.new；沒有 createCell，cell 池永遠是空的）
    o.items = {}
    o.revision = 0
    o.scrollOffset = 0
    o.selectedIndex = nil
    o.rowHeight = math.max(1, tonumber(opts.tileH) or 64)
    o.padding = 0
    o.pool = {}
    local tc = theme.colors
    o.colors = { thumb = tc.textFaint, thumbHover = tc.textMuted, track = tc.selected } -- 同 Table
    o.tileW = math.max(1, tonumber(opts.tileW) or 64)
    o.theme = theme
    o.target = opts.target
    o.drawTile = opts.drawTile
    o.onPick = opts.onPick
    o._labelFn = opts.focusLabel
    o._tipFn = opts.tooltip
    o._tipIndex = false -- 上次問提示時滑鼠下的格（false＝還沒問過）
    o._focusKind = "button"
    o._focusLabel = opts.label
    o._state = { picked = false, hover = false, index = 0 }
    o:initialise()
    return o
end

UI.TileGrid = TileGrid
UI.CAPABILITIES.tileGrid = true

return TileGrid
