-- rev 22：UI.TileGrid（方格清單，收編自 Economy ECPanelGrid）。載入自檢、每列格數與 12px 捲軸預留、setItems 保留／清掉
-- 游標、方向鍵（跨列、最後一列較短）、Home／End／PgUp／PgDn、Enter／Space／手把 A＝onPick、滑鼠點卡片與空隙、
-- 滾輪、scrollToIndex、focusRect 捲出可視區回 nil／部分可見裁切、經 Focus.render 不畫到元件外、捲動容器祖先、
-- 繪製（卡片、選取框、hover、drawTile 參數與重用 state）、hover 提示（只在換格時問）、焦點說明與零配置。
-- 契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev22：TileGrid 方格清單")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local F, K, T = UI.Focus, Keyboard, ctx.TARGET

-- ---------- 載入自檢 ----------
local saved = MinidoracatUI
MinidoracatUI = nil
local okA = pcall(dofile, ctx.MOD_LUA .. "Widgets/TileGrid.lua")
check(okA and MinidoracatUI == nil, "facade 未發布時 TileGrid 靜默 return、不建立殘缺全域")
local fh = io.open(ctx.MOD_LUA .. "V1.lua", "rb")
local src = fh:read("*a")
fh:close()
load(src, "@V1.lua")()
local fresh = MinidoracatUI.v1
local okB = pcall(dofile, ctx.MOD_LUA .. "Widgets/TileGrid.lua")
check(okB and fresh.VirtualList == nil and fresh.CAPABILITIES.tileGrid == false and fresh.TileGrid == nil,
    "VirtualList 缺席（require 不到）時 tileGrid 維持 false、不掛元件")
local keepPanel = ISPanel
ISPanel = nil
local okC = pcall(dofile, ctx.MOD_LUA .. "Widgets/TileGrid.lua")
ISPanel = keepPanel
check(okC and fresh.CAPABILITIES.tileGrid == false and fresh.TileGrid == nil, "原生 ISPanel 缺席時 tileGrid 維持 false")
MinidoracatUI = saved
dofile(ctx.MOD_LUA .. "Widgets/TileGrid.lua")
check(UI.API_REVISION >= 22 and UI.CAPABILITIES.tileGrid == true and UI.TileGrid ~= nil, "rev 22：tileGrid 翻 true、UI.TileGrid 掛上 facade")

-- ---------- 幾何 ----------
local picks, last = 0, nil
local function onPick(target, item, index, grid)
    picks = picks + 1
    last = { target = target, item = item, index = index, grid = grid }
end
local function items(count)
    local t = {}
    for i = 1, count do t[i] = { name = "Item" .. i } end
    return t
end
-- 寬 340：(340 - 12) / 100 → 每列 3 格、格寬 109；格高 80、高 200（2.5 列）；10 格＝4 列（3,3,3,1）
local g = UI.TileGrid.new{ x = 0, y = 0, width = 340, height = 200, tileW = 100, tileH = 80, target = T, onPick = onPick,
    label = "Grid" }
g:setItems(items(10))
check(g:perRow() == 3 and g:tileWidth() == 109 and g:contentHeight() == 320 and g:maxScrollOffset() == 120,
    "每列格數扣掉 12px 捲軸預留、多出的寬平均分；內容高＝列數 × 格高")
g:resize(312, 200)
local exact = g:perRow()
g:resize(311, 200)
local short = g:perRow()
g:resize(50, 200)
check(exact == 3 and short == 2 and g:perRow() == 1 and g:tileWidth() == 38,
    "resize 重算：312 寬剛好 3 格、311 寬只剩 2 格（12px 一律預留）、比一格還窄時 1 格且縮到可用寬")
g:resize(340, 200)

-- ---------- setItems 保留／清掉游標 ----------
g:setSelectedIndex(8)
g:setItems(items(5))
local cleared = g:getSelectedIndex()
g:setSelectedIndex(4)
local list10 = items(10)
g:setItems(list10)
check(cleared == nil and g:getSelectedIndex() == 4 and g:getSelectedItem() == list10[4] and g:getItems() == list10,
    "setItems：游標超出新範圍就清掉，仍在範圍內就保留；getItems／getSelectedItem")
g:setSelectedIndex(99)
check(g:getSelectedIndex() == 4, "setSelectedIndex 超出範圍：忽略")

-- ---------- 方向鍵 ----------
local function key(k) return g:onFocusKey(k) end
g:setSelectedIndex(3)
local r1 = key(K.KEY_RIGHT)
local at4 = g:getSelectedIndex()
local l1 = key(K.KEY_LEFT)
check(r1 and at4 == 4 and l1 and g:getSelectedIndex() == 3, "左右：前／後一格，行尾的右鍵跨到下一列開頭、左鍵跨回來")
g:setSelectedIndex(1)
local l0 = key(K.KEY_LEFT)
local u0 = key(K.KEY_UP)
check(l0 == false and u0 == false and g:getSelectedIndex() == 1, "第一格再按左／上：不動、回 false（手把移到上一個目標）")
g:setSelectedIndex(2)
key(K.KEY_DOWN)
local d5 = g:getSelectedIndex()
g:setSelectedIndex(8)
key(K.KEY_DOWN)
local d8 = g:getSelectedIndex()
check(d5 == 5 and d8 == 10, "上下保持欄位；最後一列較短時往下落在它的最後一格")
local d10 = key(K.KEY_DOWN)
key(K.KEY_UP)
check(d10 == false and g:getSelectedIndex() == 7, "最後一列再按下回 false；從最後一格往上回到同一欄")
key(K.KEY_HOME)
local h1 = g:getSelectedIndex()
key(K.KEY_END)
check(h1 == 1 and g:getSelectedIndex() == 10, "Home／End：第一格／最後一格")
g:setSelectedIndex(1)
key(K.KEY_NEXT)
local p7 = g:getSelectedIndex()
key(K.KEY_NEXT)
local p10 = g:getSelectedIndex()
key(K.KEY_PRIOR)
check(p7 == 7 and p10 == 10 and g:getSelectedIndex() == 4,
    "PgDn／PgUp：一頁（可見 2 列）同一欄；碰到底落在最後一列的同欄或最後一格、碰到頂落在第一列同欄")
g:setSelectedIndex(nil)
local first = key(K.KEY_RIGHT)
local f1 = g:getSelectedIndex()
g:setSelectedIndex(nil)
key(K.KEY_END)
check(first and f1 == 1 and g:getSelectedIndex() == 10, "沒有游標：第一個導覽鍵落在第一格，End 落在最後一格")
check(key(K.KEY_A) == false, "其他鍵不處理")

-- ---------- Enter／Space ----------
picks = 0
g:setSelectedIndex(5)
local e1 = key(K.KEY_RETURN)
check(e1 and picks == 1 and last.target == T and last.item == list10[5] and last.index == 5 and last.grid == g,
    "Enter：onPick(target, item, index, grid) 一次")
key(K.KEY_SPACE)
key(K.KEY_NUMPADENTER)
check(picks == 3 and last.index == 5, "Space／小鍵盤 Enter 同 Enter")
g:setSelectedIndex(nil)
key(K.KEY_RETURN)
check(picks == 4 and last.index == 1 and g:getSelectedIndex() == 1, "沒有游標時 Enter：先把游標放在第一格再 onPick")
local empty = UI.TileGrid.new{ width = 340, height = 200, tileW = 100, tileH = 80, onPick = onPick }
check(empty:onFocusKey(K.KEY_RETURN) == true and empty:onFocusKey(K.KEY_DOWN) == false and picks == 4,
    "沒有格子：Enter 吃掉不回呼、方向鍵回 false")

-- ---------- 捲動 ----------
g:setScrollOffset(0)
g:setSelectedIndex(1)
key(K.KEY_DOWN)
local s4 = g.scrollOffset
key(K.KEY_DOWN)
check(s4 == 0 and g.scrollOffset == 40, "游標移動捲到那格：可見時不捲，往下移出可視區時底端對齊")
g:scrollToIndex(10)
local s10 = g.scrollOffset
g:scrollToIndex(8) -- 第 3 列 160..240，在 120..320 內
local s8 = g.scrollOffset
g:scrollToIndex(5) -- 第 2 列 80..160，上半被捲走：頂端對齊
local s5 = g.scrollOffset
g:scrollToIndex(1)
check(s10 == 120 and s8 == 120 and s5 == 80 and g.scrollOffset == 0,
    "scrollToIndex：捲到最後一列、已完整可見不動、部分可見時捲到完整可見、捲回頂端")
g:scrollToIndex(0)
g:scrollToIndex(11)
check(g.scrollOffset == 0, "scrollToIndex 超出範圍：不動")
g:onMouseWheel(1)
local w1 = g.scrollOffset
g:onMouseWheel(5)
check(w1 == 80 and g.scrollOffset == 120, "滾輪一次捲一列，夾在內容底")
local scrolls = 0
g.parent = { _scrollPanel = true, scrollTo = function(_, el) if el == g then scrolls = scrolls + 1 end end }
key(K.KEY_UP)
g.parent = nil
check(scrolls == 1, "游標移動時請捲動容器祖先 scrollTo(自己)")

-- ---------- 滑鼠 ----------
picks = 0
g:setScrollOffset(0)
g:setSelectedIndex(nil)
check(g:onMouseDown(109 + 50, 40) == true and picks == 1 and last.index == 2 and g:getSelectedIndex() == 2,
    "點卡片：游標移到那格＋onPick 一次")
g:onMouseDown(109, 40)
g:onMouseDown(150, 79)
g:onMouseDown(150, 81)
local gapPicks = picks
check(gapPicks == 1 and g:getSelectedIndex() == 2, "點卡片之間的空隙（左緣、下緣、上緣 2px 內）：不動")
g:setScrollOffset(120)
g:onMouseDown(109 + 50, 150) -- 第 4 列只有一格：這裡是空位
g:onMouseDown(330, 150)       -- 捲軸（落在拇指上：開始拖曳）
g:onMouseUp(330, 150)
check(picks == 1 and g:indexAt(330, 150) == nil and g:indexAt(50, 150) == 10, "最後一列的空位、捲軸區：不選")
g:onMouseDown(335, 10) -- 拇指在底端（75..200），點它上方的軌道
check(g.scrollOffset == 0 and picks == 1, "捲軸軌道照 VirtualList 跳頁")

-- ---------- focusRect ----------
g:setScrollOffset(0)
g:setSelectedIndex(1)
local fx, fy, fw, fhh = g:focusRect()
check(fx == 2 and fy == 2 and fw == 105 and fhh == 76, "focusRect：只框游標格的卡片（格子四邊內縮 2）")
g:setScrollOffset(120)
local gone = g:focusRect()
g:setSelectedIndex(4)
local _, py, _, ph = g:focusRect()
g:setSelectedIndex(10)
local _, ly, _, lh = g:focusRect()
check(gone == nil and py == 0 and ph == 38 and ly == 122 and lh == 76,
    "游標格捲出本元件可視區回 nil；部分可見時裁到可視區內；完整可見照原樣")
g:setSelectedIndex(nil)
check(g:focusRect() == nil, "沒有游標：nil（框住整個元件）")

-- ---------- 繪製 ----------
local function reset(el) el.rects, el.borders, el.texts = {}, {}, {} end
local function sameColor(r, c) return r ~= nil and r.r == c.r and r.g == c.g and r.b == c.b end
local calls, states = {}, {}
local dg = UI.TileGrid.new{ x = 0, y = 0, width = 340, height = 200, tileW = 100, tileH = 80, target = T,
    drawTile = function(target, grid, item, x, y, w, h, state)
        calls[#calls + 1] = { target = target, grid = grid, item = item, x = x, y = y, w = w, h = h,
            picked = state.picked, hover = state.hover, index = state.index }
        states[#states + 1] = state
    end }
local dlist = items(10)
dg:setItems(dlist)
dg:setSelectedIndex(2)
dg._mouseOver = true
ctx.setMouse(109 * 2 + 50, 40)
reset(dg)
dg:prerender()
local colors = dg.theme.colors
local well = colors.card or colors.well
check(colors.card == nil and sameColor(dg.rects[1], well) and dg.rects[1].x == 2 and dg.rects[1].y == 2
    and dg.rects[1].w == 105 and dg.rects[1].h == 76, "卡片底：palette 沒有 card 時用 well，畫在卡片範圍")
local sel, hov = nil, nil
for _, r in ipairs(dg.rects) do
    if r.x == 111 and sameColor(r, colors.selected) then sel = r end
    if r.x == 220 and sameColor(r, colors.hover) then hov = r end
end
local b = dg.borders[1]
check(sel ~= nil and #dg.borders == 1 and b.x == 111 and b.y == 2 and b.w == 105 and b.h == 76 and sameColor(b, colors.accent),
    "選取格：selected 底＋1px accent 框（只有它有框）")
check(hov ~= nil, "滑鼠下的格：hover 底、沒有框")
check(#calls == 9 and calls[1].index == 1 and calls[9].index == 9 and dg.stencil.set == 1,
    "只畫可見的列（0..2 列＝9 格），stencil 設一次")
local c2, c3 = calls[2], calls[3]
check(c2.target == T and c2.grid == dg and c2.item == dlist[2] and c2.x == 111 and c2.y == 2 and c2.w == 105 and c2.h == 76
    and c2.picked == true and c2.hover == false and c3.hover == true and c3.picked == false,
    "drawTile(target, grid, item, x, y, w, h, state)：卡片座標、state 的 picked／hover／index")
check(states[1] == states[9], "state 是重用的同一張表")
dg:render()
check(dg.stencil.clear == 1 and dg.stencil.repaint == 1, "render：stencil clear＋repaint 成對（VirtualList）")
calls = {}
dg:setScrollOffset(120)
dg:prerender()
check(#calls == 7 and calls[1].index == 4 and calls[1].y == 80 - 120 + 2 and calls[7].index == 10,
    "捲到底：畫第 1..3 列（部分可見的第 1 列也畫，stencil 裁切）")
local custom = UI.Theme.create{ colors = { card = { r = 0.1, g = 0.2, b = 0.3, a = 1 } } }
local cg = UI.TileGrid.new{ width = 340, height = 200, tileW = 100, tileH = 80, theme = custom }
cg:setItems(items(1))
cg:prerender()
check(sameColor(cg.rects[1], custom.colors.card), "theme 有 card token 時卡片底用它")

-- ---------- 提示 ----------
local asks = 0
local tg = UI.TileGrid.new{ x = 0, y = 0, width = 340, height = 200, tileW = 100, tileH = 80, target = T,
    tooltip = function(target, item, index)
        asks = asks + 1
        if index == 3 then return nil end
        return target == T and item.name or "bad"
    end }
tg:setItems(items(10))
tg._mouseOver = true
ctx.setMouse(50, 120) -- 第 4 格
tg:prerender()
tg:prerender()
tg:prerender()
check(asks == 1 and tg.tooltip == "Item4" and tg.tooltipPasses == 3, "滑鼠停在格上：只問一次，每幀走原版 updateTooltip")
local placed = nil
tg.tooltipUI = { setDesiredPosition = function(_, x, y) placed = { x = x, y = y } end }
tg:prerender()
check(placed ~= nil and placed.x == 50 and placed.y == 80 + 2 + 76 + 8, "提示框放在那格卡片下方 8px、游標的 x")
ctx.setMouse(109 * 2 + 50, 40) -- 第 3 格：沒有提示
tg:prerender()
check(asks == 2 and tg.tooltip == nil and tg.tooltipPasses == 5, "換到沒有提示的格：收掉（還掛著 ISToolTip 時照樣呼叫讓它關）")
ctx.setMouse(109, 40) -- 空隙
tg:prerender()
tg._mouseOver = false
tg:prerender()
check(asks == 2 and tg.tooltip == nil, "空隙與滑鼠離開：不問、沒有提示")
tg.tooltipUI = nil
tg._mouseOver = true
ctx.setMouse(50, 40)
tg:prerender()
tg:setItems({ { name = "Fresh" } })
tg:prerender()
check(asks == 4 and tg.tooltip == "Fresh", "setItems 後同一格重問（內容換了）")

-- ---------- 焦點說明 ----------
local lg = UI.TileGrid.new{ width = 340, height = 200, tileW = 100, tileH = 80, target = T, label = "Items",
    focusLabel = function(target, item) if item.name == "Item2" then return nil end return target == T and item.name end }
lg:setItems(items(3))
local none = lg:focusLabel()
lg:setSelectedIndex(1)
local named = lg:focusLabel()
lg:setSelectedIndex(2)
check(none == "Items" and named == "Item1" and lg:focusLabel() == "Items", "focusLabel：游標格的說明；回 nil 或沒有游標時退回 label")

-- ---------- Focus 接線 ----------
local win = UI.Window.new{ x = 0, y = 0, width = 600, height = 400, title = "T" }
picks = 0
local fg = UI.TileGrid.new{ x = 10, y = 30, width = 340, height = 200, tileW = 100, tileH = 80, target = T, onPick = onPick,
    label = "Grid" }
fg:setItems(items(10))
win:addChild(fg)
local after = UI.Button.new{ x = 10, y = 300, title = "After" }
win:addChild(after)
win:addToUIManager()
local desc = nil
for _, d in ipairs(F.collectTargets(win)) do
    if d.control == fg then desc = d end
end
check(desc ~= nil and desc.kind == "button" and desc.label == "Grid", "TileGrid 是一個 kind=button 的自動目標，label 是說明")
F.focusControl(fg, true)
ctx.press(win, K.KEY_RIGHT)
ctx.press(win, K.KEY_DOWN)
ctx.press(win, K.KEY_RETURN)
check(fg:getSelectedIndex() == 4 and picks == 1 and last.index == 4, "鍵盤經 Focus：右（落在第一格）、下、Enter＝onPick")
F.onJoypadDir(fg.parent, "right", nil)
F.onJoypadDown(win, Joypad.AButton, nil)
check(fg:getSelectedIndex() == 5 and picks == 2 and last.index == 5, "手把：方向移動、A＝onPick")
local rings = {}
local keepRing = F.drawRing
F.drawRing = function(el, x, y, w, h, theme)
    rings[#rings + 1] = { x = x, y = y, w = w, h = h }
    return keepRing(el, x, y, w, h, theme)
end
win:render()
local inside = rings[1]
fg:setScrollOffset(120) -- 第 5 格（第 2 列）卡片 y=82..158 → 可視區 -38..38：部分可見
rings = {}
win:render()
local part = rings[1]
fg:setSelectedIndex(1)
rings = {}
win:render()
local whole = rings[1]
F.drawRing = keepRing
check(inside and inside.x == 10 + 111 and inside.y == 30 + 82 and inside.w == 105 and inside.h == 76,
    "Focus.render：焦點框只框游標格")
check(part and part.y == 30 and part.h == 38 and whole and whole.x == 10 and whole.y == 30 and whole.w == 340 and whole.h == 200,
    "游標格部分捲出：框裁在元件內；整格捲出：focusRect 回 nil，框住整個元件，不畫到元件外")
F.focusControl(fg, true)
fg:setSelectedIndex(10)
F.onJoypadDir(win, "down", nil)
check(F.focused() == after, "手把：最後一列再往下，移到下一個目標")
win:close()

-- ---------- 零配置 ----------
local noop = function() end
local zg = UI.TileGrid.new{ x = 0, y = 0, width = 340, height = 200, tileW = 100, tileH = 80, target = T, drawTile = noop,
    tooltip = function(_, item) return item.name end, focusLabel = function(_, item) return item.name end }
zg:setItems(items(10))
zg:setSelectedIndex(2)
zg:setScrollOffset(40)
zg.drawRect, zg.drawRectBorder = noop, noop
zg._mouseOver = true
ctx.setMouse(160, 60)
local function round()
    zg:prerender()
    zg:render()
    zg:focusRect()
    zg:focusLabel()
end
collectgarbage("collect")
collectgarbage("stop")
round()
local kb = collectgarbage("count")
for _ = 1, 50 do round() end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(grew == 0, "prerender＋render（捲軸、hover、提示、drawTile）＋focusRect／focusLabel 50 輪不配置記憶體")

return n
