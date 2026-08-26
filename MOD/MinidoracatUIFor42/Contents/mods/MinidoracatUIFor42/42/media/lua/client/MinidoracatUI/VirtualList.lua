-- MinidoracatUI VirtualList — 垂直固定列高虛擬清單（v0.3）。
--
-- 為大清單場景（交易面板、拍賣場、數百筆以上的表列）設計：UIElement 數量
-- 只隨 viewport 高度成長（物件池），不隨資料筆數成長。
--
-- 【對 NeatUI 虛擬清單的修正】（docs/ARCHITECTURE.md §3.5，每列都是它的實證缺陷）
--   * setItems() 內建 revision——資料變更自動使所有可見綁定失效，
--     不要 caller 記得 forceRefresh（NeatUI 同範圍原地變更不重繪）
--   * cell 記 boundIndex＋boundRevision，兩者都沒變才跳過重綁
--   * 回收契約：cell 隱藏時框架清 boundIndex/boundRevision＋呼叫可選
--     unbindCell（consumer 清 hover/pressed 殘留）
--   * contentHeight 永遠 = count × stride + padding 純計算——不從已移動的
--     child 座標量測（NeatUI 的滾動範圍會自行收縮）
--   * selection/focus 存在 list、cell 只是投影（bindCell 裡問 list:isSelected）
--   * stencil：set → 畫 → clear → **repaint 同一 rect**（UIElement.stencilLevel
--     是 static、只在 UIManager.render 開頭歸零——家族踩坑錄；NeatUI 只
--     set→clear，當內層 clip 時會吃掉外層）
--   * 熱路徑零 log、零 per-frame table/closure 配置
--
-- 滾動是直接到位（無平滑插值）：與 vanilla ISScrollingListBox 行為一致，
-- 這是刻意取捨（記錄於 ARCHITECTURE §3.5），未來要平滑可 additive 加。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin) or not ISPanel then
    return -- 核心缺席：不掛能力
end

local Skin = UI.Skin

local VirtualList = ISPanel:derive("MinidoracatUIVirtualList")

local SCROLLBAR_WIDTH = 10
local SCROLLBAR_MARGIN = 2
local THUMB_MIN_HEIGHT = 20
local WHEEL_ROWS = 3 -- 一次滾輪滾動的列數（同 vanilla 清單的體感）

local FALLBACK = {
    thumb = { r = 0.55, g = 0.55, b = 0.55, a = 0.8 },
    thumbHover = { r = 0.75, g = 0.75, b = 0.75, a = 0.9 },
    track = { r = 1, g = 1, b = 1, a = 0.06 },
}

function VirtualList:initialise()
    ISPanel.initialise(self)
    self:rebuildPool()
end

-- ===== 幾何 =====

local function stride(list)
    return list.rowHeight + list.padding
end

function VirtualList:contentHeight()
    return #self.items * stride(self) + self.padding
end

function VirtualList:maxScrollOffset()
    return math.max(0, self:contentHeight() - self.height)
end

function VirtualList:cellWidth()
    local w = self.width
    if self:maxScrollOffset() > 0 then
        w = w - SCROLLBAR_WIDTH - SCROLLBAR_MARGIN
    end
    return w
end

-- ===== 資料 =====

-- 整批替換資料；revision++ 使所有可見綁定失效（原地變更的 items table 也
-- 可以重傳同一顆——revision 保證重綁）。scroll 夾回合法範圍。
function VirtualList:setItems(items)
    self.items = items or {}
    self.revision = self.revision + 1
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, self:maxScrollOffset()))
    if self.selectedIndex and (self.selectedIndex < 1 or self.selectedIndex > #self.items) then
        self.selectedIndex = nil -- 指向已刪項：清除，不留懸空選取
    end
    self:refreshCells()
end

function VirtualList:getItems()
    return self.items
end

-- ===== 選取（狀態在 list，cell 是投影）=====

function VirtualList:isSelected(index)
    return self.selectedIndex == index
end

function VirtualList:getSelectedIndex()
    return self.selectedIndex
end

function VirtualList:getSelectedItem()
    return self.selectedIndex and self.items[self.selectedIndex] or nil
end

function VirtualList:setSelectedIndex(index)
    if index ~= nil and (type(index) ~= "number" or index < 1 or index > #self.items) then
        return
    end
    if self.selectedIndex ~= index then
        self.selectedIndex = index
        self.revision = self.revision + 1 -- 高亮是 bindCell 的投影：強制重綁可見列
        self:refreshCells()
    end
end

-- 捲到讓 index 完整可見（已可見則不動）
function VirtualList:scrollToIndex(index)
    if type(index) ~= "number" or index < 1 or index > #self.items then
        return
    end
    local top = self.padding + (index - 1) * stride(self)
    local bottom = top + self.rowHeight
    if top < self.scrollOffset then
        self.scrollOffset = top
    elseif bottom > self.scrollOffset + self.height then
        self.scrollOffset = bottom - self.height
    end
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, self:maxScrollOffset()))
    self:refreshCells()
end

-- ===== 物件池 =====

function VirtualList:poolSize()
    return math.ceil(self.height / stride(self)) + 2
end

function VirtualList:rebuildPool()
    if not self.createCell then
        return
    end
    for i = 1, #self.pool do
        local cell = self.pool[i]
        cell:setVisible(false)
        self:removeChild(cell)
    end
    self.pool = {}
    for i = 1, self:poolSize() do
        local cell = self.createCell(self)
        -- ISUIElement:new 預設 wantMouseEvents=true（ISUIElement.lua:1998），ISPanel 衍生
        -- cell 的 onMouseDown 會因此回 true、把點擊吞在 cell 層（ISPanel.lua:49），本清單的
        -- onMouseDown（選取/滾動）永遠收不到——實機才會踩到（harness 不跑滑鼠分派），
        -- Cleaner Picker 首戰即中。清掉讓事件冒泡回 list；cell 尚未 instantiate，之後
        -- instantiate 會同步 java 端 setConsumeMouseEvents(false)（ISUIElement.lua:1004）
        cell.wantMouseEvents = nil
        cell:initialise()
        cell:setVisible(false)
        cell.boundIndex = nil
        cell.boundRevision = nil
        self:addChild(cell)
        self.pool[i] = cell
    end
    self:refreshCells()
end

-- viewport 尺寸變更（視窗 resize）：pool 重算＋重綁
function VirtualList:resize(width, height)
    self:setWidth(width)
    self:setHeight(height)
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, self:maxScrollOffset()))
    self:rebuildPool()
end

local function recycle(list, cell)
    if cell.boundIndex ~= nil and list.unbindCell then
        list.unbindCell(list, cell)
    end
    cell.boundIndex = nil
    cell.boundRevision = nil
    cell:setVisible(false)
end

-- 可見範圍計算＋pool 指派。只有 index 或 revision 變才呼叫 bindCell。
function VirtualList:refreshCells()
    if #self.pool == 0 or not self.bindCell then
        return
    end
    local count = #self.items
    local rowStride = stride(self)
    local first = math.max(1, math.floor((self.scrollOffset - self.padding) / rowStride) + 1)
    local last = math.min(count, math.ceil((self.scrollOffset + self.height - self.padding) / rowStride))

    local cellW = self:cellWidth()
    local poolIndex = 1
    for dataIndex = first, last do
        local cell = self.pool[poolIndex]
        if not cell then
            break
        end
        local needBind = cell.boundIndex ~= dataIndex or cell.boundRevision ~= self.revision
        if needBind then
            cell.boundIndex = dataIndex
            cell.boundRevision = self.revision
            cell:setWidth(cellW)
            cell:setHeight(self.rowHeight)
            self.bindCell(self, cell, self.items[dataIndex], dataIndex)
            cell:setVisible(true)
        end
        cell:setX(0)
        cell:setY(self.padding + (dataIndex - 1) * rowStride - self.scrollOffset)
        poolIndex = poolIndex + 1
    end
    -- 池中剩餘 cell：回收（清綁定＋隱藏；unbindCell 讓 consumer 清殘留狀態）
    for i = poolIndex, #self.pool do
        local cell = self.pool[i]
        if cell.boundIndex ~= nil then
            recycle(self, cell)
        end
    end
end

-- ===== 滾動 =====

function VirtualList:setScrollOffset(offset)
    local clamped = math.max(0, math.min(offset, self:maxScrollOffset()))
    if clamped ~= self.scrollOffset then
        self.scrollOffset = clamped
        self:refreshCells()
    end
end

function VirtualList:onMouseWheel(del)
    self:setScrollOffset(self.scrollOffset + del * stride(self) * WHEEL_ROWS)
    return true
end

-- ===== 滑鼠選取（點在 cell 的 rowHeight 內才算；padding 間隙不選）=====

function VirtualList:indexAt(x, y)
    if x < 0 or x >= self:cellWidth() or y < 0 or y >= self.height then
        return nil
    end
    local rowStride = stride(self)
    local offsetY = y + self.scrollOffset - self.padding
    if offsetY < 0 then
        return nil
    end
    local index = math.floor(offsetY / rowStride) + 1
    if index < 1 or index > #self.items then
        return nil
    end
    if (offsetY % rowStride) >= self.rowHeight then
        return nil -- 落在列間 padding
    end
    return index
end

function VirtualList:onMouseDown(x, y)
    -- scrollbar 區：thumb 拖曳／track 跳頁
    if self:maxScrollOffset() > 0 and x >= self.width - SCROLLBAR_WIDTH then
        local trackH = self.height
        local thumbH, thumbY = self:thumbMetrics()
        if y >= thumbY and y < thumbY + thumbH then
            self._thumbDrag = true
            self._thumbGrabDY = y - thumbY
            self:setCapture(true)
        else
            -- 點 track：往該方向跳一頁
            local page = self.height
            if y < thumbY then
                self:setScrollOffset(self.scrollOffset - page)
            else
                self:setScrollOffset(self.scrollOffset + page)
            end
        end
        return true
    end
    local index = self:indexAt(x, y)
    if index then
        self:setSelectedIndex(index)
        if self.onSelect then
            self.onSelect(self, self.items[index], index)
        end
    end
    return true
end

local function dragThumb(list)
    if not list._thumbDrag then
        return false
    end
    local y = list:getMouseY()
    local thumbH = select(1, list:thumbMetrics())
    local trackRange = list.height - thumbH
    if trackRange <= 0 then
        return true
    end
    local thumbY = math.max(0, math.min(y - list._thumbGrabDY, trackRange))
    list:setScrollOffset((thumbY / trackRange) * list:maxScrollOffset())
    return true
end

function VirtualList:onMouseMove(dx, dy) return dragThumb(self) end
function VirtualList:onMouseMoveOutside(dx, dy) return dragThumb(self) end

local function releaseThumb(list)
    if list._thumbDrag then
        list._thumbDrag = nil
        list:setCapture(false)
        return true
    end
    return false
end

function VirtualList:onMouseUp(x, y) return releaseThumb(self) end
function VirtualList:onMouseUpOutside(x, y) return releaseThumb(self) end

-- ===== 繪製 =====

-- thumb 高度與位置（比例映射；最小高度防「大清單細到抓不到」）
function VirtualList:thumbMetrics()
    local maxOffset = self:maxScrollOffset()
    if maxOffset <= 0 then
        return self.height, 0
    end
    local visible = self.height / self:contentHeight()
    local thumbH = math.max(THUMB_MIN_HEIGHT, math.floor(self.height * visible))
    local trackRange = self.height - thumbH
    local thumbY = math.floor((self.scrollOffset / maxOffset) * trackRange)
    return thumbH, thumbY
end

function VirtualList:prerender()
    -- 裁切：cell 是 child、走同一命令佇列，超出 viewport 的部分被 stencil 裁掉
    self:setStencilRect(0, 0, self.width, self.height)
end

function VirtualList:render()
    -- 家族踩坑錄：clear 後 repaint 同一 rect 還回父層 stencil；只 clear 會在
    -- 本清單作為內層 clip 時吃掉外層（stencilLevel 是 static、跨元件累積）
    self:clearStencilRect()
    self:repaintStencilRect(0, 0, self.width, self.height)

    -- scrollbar 畫在 stencil 之外（它本來就在 viewport 邊界內）
    if self:maxScrollOffset() > 0 then
        local colors = self.colors
        local x = self.width - SCROLLBAR_WIDTH
        Skin.fill(self, x, 0, SCROLLBAR_WIDTH, self.height,
            colors.track or FALLBACK.track, "rect")
        local thumbH, thumbY = self:thumbMetrics()
        local hovered = self._thumbDrag
            or (self:isMouseOver() and self:getMouseX() >= x
                and self:getMouseY() >= thumbY and self:getMouseY() < thumbY + thumbH)
        Skin.fill(self, x + 1, thumbY, SCROLLBAR_WIDTH - 2, thumbH,
            hovered and (colors.thumbHover or FALLBACK.thumbHover)
            or (colors.thumb or FALLBACK.thumb))
    end
end

-- opts:
--   x, y, width, height（必填）、rowHeight（必填）、padding（列間距，預設 0）、
--   createCell(list)->cell（必填；回傳 ISUIElement 衍生，尺寸由框架管）、
--   bindCell(list, cell, item, index)（必填）、unbindCell(list, cell)（可選）、
--   onSelect(list, item, index)（可選）、
--   colors = { thumb, thumbHover, track }（可選，color tables）
function VirtualList.new(opts)
    local o = ISPanel.new(VirtualList, opts.x, opts.y, opts.width, opts.height)
    o.background = false
    o.items = {}
    o.revision = 0
    o.scrollOffset = 0
    o.selectedIndex = nil
    o.rowHeight = opts.rowHeight
    o.padding = opts.padding or 0
    o.createCell = opts.createCell
    o.bindCell = opts.bindCell
    o.unbindCell = opts.unbindCell
    o.onSelect = opts.onSelect
    o.colors = opts.colors or {}
    o.pool = {}
    return o
end

UI.VirtualList = VirtualList
UI.CAPABILITIES.virtualList = true

return VirtualList
