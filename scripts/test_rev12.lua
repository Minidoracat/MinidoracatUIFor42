-- rev 12：textDisabled 停用對比／Tabs 停用／Focus captionSide／FilterBar 的 dateToggle、kindsDropdown、
-- sortInHeader。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
dofile(ctx.MOD_LUA .. "Widgets/DatePicker.lua")
dofile(ctx.MOD_LUA .. "Widgets/FilterBar.lua")
dofile(ctx.MOD_LUA .. "Widgets/Table.lua")
print("情境 rev12：停用對比／Tabs 停用／焦點說明位置／FilterBar 三種模式")

local K = Keyboard

-- ---------- textDisabled：token 與對比（WCAG 相對亮度） ----------
local function lum(v)
    return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end
local function gray(c) return 0.2126 * lum(c.r) + 0.7152 * lum(c.g) + 0.0722 * lum(c.b) end
local function ratio(a, b)
    if a < b then a, b = b, a end
    return (a + 0.05) / (b + 0.05)
end
local dark, light = UI.Theme.defaultPalette("dark"), UI.Theme.defaultPalette("light")
local dd, lt = dark.textDisabled, light.textDisabled
ok(dd ~= nil and lt ~= nil and nearly(dd.r, 0.40) and nearly(lt.r, 0.52) and UI.API_REVISION >= 12
    and UI.CAPABILITIES.tabsEnabled and UI.CAPABILITIES.focusCaption and UI.CAPABILITIES.filterBarModes,
    "rev 12：兩套 palette 都有 textDisabled，三個新旗標在載入後為 true")
local black = 0
ok(ratio(gray(dd), black) >= 3.6 and ratio(gray(dd), gray(dark.textMuted)) >= 2.1
    and ratio(gray(dark.textFaint), gray(dark.textMuted)) < 1.3,
    "深色：textDisabled 黑底 >= 3.6:1、與閒置 textMuted 差 >= 2.1:1（textFaint 只差 < 1.3:1）")
local surface = gray(light.surface)
ok(ratio(gray(lt), surface) >= 3.0 and ratio(gray(lt), gray(light.textMuted)) >= 1.8,
    "淺色：textDisabled 在 surface 上 >= 3:1、與 textMuted 差 >= 1.8:1")

-- ---------- 各控制元件的停用標籤 ----------
local function lastText(el) return el.texts[#el.texts] end
local primary = UI.Button.new{ title = "Go", style = "primary" }
primary:setEnabled(false)
primary:prerender()
ok(nearly(primary.rects[1].r, 0) and nearly(primary.rects[1].a, 0.5 * 0.45) and nearly(lastText(primary).r, 0.40)
    and nearly(lastText(primary).a, 1), "停用 primary：改畫 normal 的 well 底（淡化），字 textDisabled 不淡化")
local danger = UI.Button.new{ title = "Del", style = "danger" }
danger:setEnabled(false)
danger:prerender()
ok(nearly(danger.rects[1].r, 0.3) and nearly(danger.rects[1].a, 0.5 * 0.45) and nearly(lastText(danger).r, 0.40),
    "停用 danger：errorSurface 底淡化，字 textDisabled")
local ghost = UI.Button.new{ title = "G", style = "ghost" }
ghost:setEnabled(false)
ghost:prerender()
ok(nearly(lastText(ghost).r, 0.40) and nearly(lastText(ghost).a, 1), "停用 ghost：字 textDisabled")

local field = UI.TextField.new{ x = 0, y = 0, width = 200, placeholder = "Search" }
field:setEnabled(false)
field.texts = {}
field:prerender()
ok(nearly(field._entry._textColor.r, 0.40) and nearly(field.texts[1].r, 0.40) and nearly(field.texts[1].a, 1),
    "停用 TextField：原生文字與 placeholder 都是 textDisabled")
local box = UI.Checkbox.new{ x = 0, y = 0, label = "Auto" }
box:setEnabled(false)
box:prerender()
ok(nearly(lastText(box).r, 0.40), "停用 Checkbox：標籤 textDisabled")

local df = UI.DateField.new{}
df._button:setEnabled(false)
df._button.rects = {}
df._button:render()
local glyph = df._button.rects[#df._button.rects]
ok(glyph ~= nil and nearly(glyph.r, 0.40) and nearly(glyph.a, 1), "停用日曆鈕：圖樣 textDisabled、不淡化")

-- ---------- Tabs 停用 ----------
local picks = {}
local tabs = UI.Tabs.new{ x = 0, y = 0, selected = "a", onSelect = function(_, id) picks[#picks + 1] = id end,
    items = { { id = "a", label = "A" }, { id = "b", label = "B" }, { id = "c", label = "C" } } }
local function tabX(id)
    for _, item in ipairs(tabs._items) do if item.id == id then return item.x + 1 end end
end
tabs:setItemEnabled("b", false)
tabs:onMouseDown(tabX("b"), 5)
ok(#picks == 0 and tabs:getSelected() == "a" and not tabs:isItemEnabled("b") and tabs:isItemEnabled("c"),
    "setItemEnabled(false)：點那一項不切換")
ok(tabs:selectRelative(1) and tabs:getSelected() == "c", "左右鍵跳過停用項")
tabs.texts = {}
tabs:prerender()
ok(nearly(tabs.texts[2].r, 0.40) and nearly(tabs.texts[1].r, 0.62), "停用項標籤 textDisabled，可用的閒置項仍 textMuted")
tabs:setEnabled(false)
tabs:onMouseDown(tabX("a"), 5)
ok(not tabs:isEnabled() and tabs:getSelected() == "c" and not tabs:selectRelative(-1) and #picks == 1,
    "整列停用：點擊與左右鍵都不切換")
tabs.texts, tabs.rects = {}, {}
tabs:prerender()
ok(nearly(tabs.texts[1].r, 0.40) and nearly(tabs.texts[3].r, 0.40) and nearly(tabs.rects[1].a, 0.5 * 0.45),
    "整列停用：所有標籤 textDisabled（含選中項）、chrome 淡化")
tabs:setSelected("a")
ok(tabs:getSelected() == "a", "停用不擋程式呼叫 setSelected")

-- ---------- Focus.drawCaption 的 side ----------
local F = UI.Focus
local function captionBox(side, x, w)
    local el = ISPanel.new(ISPanel, 0, 0, 400, 300)
    el.rects, el.borders, el.texts = {}, {}, {}
    F.drawCaption(el, x or 100, 100, w or 20, 20, "Tip", nil, side)
    return el.rects[1], el
end
local below = captionBox(nil)
local belowExplicit = captionBox("below")
ok(below.y == 100 + 20 + 4 + 2 and belowExplicit.y == below.y and below.x == 100 + math.floor((20 - 40) / 2),
    "預設（below）位置不變：框下 RING_GAP+RING_W+2、水平置中")
-- right＝tooltip 式飛出標籤：不透明底（theme.alpha 與 surface.a 都不乘）＋2px 不透明外圈＋accent 淡底、
-- 對框垂直置中、6px 尖角指向控制項、與焦點框光暈外緣隔 3px（光暈最後一個像素＝x+w+RING_GAP+RING_W*2-1）。
-- 繪製順序：rects[1] 外圈底、rects[2] accent 淡底、rects[3..8] 尖角（尖端→最寬）；borders[1] 是標籤本身
local function rightBox(x, y, theme)
    local el = ISPanel.new(ISPanel, 0, 0, 400, 300)
    el.rects, el.borders, el.texts = {}, {}, {}
    F.drawCaption(el, x, y, 20, 20, "Tip", theme, "right")
    return el
end
local faded = UI.Theme.create()
faded.alpha = 0.3
local rEl = rightBox(100, 100, faded)
local right, halo, notchTip, notchBase = rEl.borders[1], rEl.rects[1], rEl.rects[3], rEl.rects[8]
ok(right.x == 100 + 20 + 9 + 6 and right.w == 30 + 16 and right.h == 12 + 8 and right.y + right.h / 2 == 100 + 10
    and right.a == 1 and halo.a == 1 and halo.x == right.x - 2 and halo.w == right.w + 4 and halo.h == right.h + 4
    and rEl.rects[2].x == right.x and nearly(rEl.rects[2].a, 0.18),
    "right：框右側、對框垂直置中；外圈底與框線不透明（不乘 theme.alpha），標籤疊 accent 淡底")
ok(#rEl.rects == 8 and notchTip.x == 100 + 20 + 4 + 2 + 3 and notchTip.h == 1 and notchTip.y == 110
    and notchBase.x + 1 == right.x and notchBase.h == 11 and notchBase.y == 110 - 5,
    "right：尖角從光暈外 3px 的尖端逐欄加高，最寬一欄緊貼標籤、指著框中線")
ok(rEl.texts[1].x == right.x + 8 and rEl.texts[1].y == right.y + 4, "right：文字有左右 8、上下 4 的內距")
local fEl = rightBox(360, 100)
local flipped = fEl.borders[1]
ok(#fEl.rects == 8 and flipped.x + flipped.w == fEl.rects[8].x and fEl.rects[3].x == 360 - 9 - 1
    and fEl.rects[3].x - fEl.rects[8].x == 5, "right 碰到右緣：翻到左側，尖角朝右指回控制項")
local cEl = rightBox(100, 285)
local clamped = cEl.borders[1]
ok(#cEl.rects == 8 and clamped.y + clamped.h == 300 - 2 and cEl.rects[1].y + cEl.rects[1].h == 300
    and cEl.rects[8].y >= clamped.y and cEl.rects[8].y + 11 <= clamped.y + clamped.h
    and cEl.rects[3].y == cEl.rects[8].y + 5, "right 碰到底邊：標籤連外圈夾在 el 內，尖角跟著夾在標籤高度內")
local above = captionBox("above")
ok(above.y == 100 - 4 - 2 - 18, "above：框上方")
local _, noneEl = captionBox("none")
ok(#noneEl.rects == 0 and #noneEl.texts == 0, "none：不畫")

-- 描述的 captionSide 經 Focus.render 生效；自動目標讀 _focusCaptionSide
local win = UI.Window.new{ x = 0, y = 0, width = 400, height = 300, title = "T" }
local icon = UI.Button.new{ x = 20, y = 60, width = 24, height = 24, title = "", tooltip = "Tip" }
icon._focusCaptionSide = "right"
win:addChild(icon)
win:addToUIManager()
local targets = F.collectTargets(win)
ok(targets[1].control == icon and targets[1].captionSide == "right", "collectTargets 把 _focusCaptionSide 寫進描述")
F.focusControl(icon, true)
local function captionText()
    win.texts = {}
    win:render()
    for _, t in ipairs(win.texts) do if t.text == "Tip" then return t end end
    return nil
end
local t = captionText()
ok(t ~= nil and t.x == icon.x + icon.width + 9 + 6 + 8, "Window 裡焦點框說明照 captionSide=right 畫成右側飛出標籤")
icon._focusCaptionSide = "none"
F.collectTargets(win)
F.focusControl(icon, true)
ok(captionText() == nil, "captionSide=none：焦點框照畫、說明不畫")
win:close()

-- ---------- FilterBar sortInHeader ----------
local FilterBar = UI.FilterBar
local function newParent() return ISPanel.new(ISPanel, 0, 0, 1000, 600) end
local changes, layouts = 0, 0
local function onChange() changes = changes + 1 end
local function onLayout() layouts = layouts + 1 end
local rows = {}
for i = 1, 6 do rows[i] = { kind = (i % 2 == 0) and "even" or "odd", ts = 1788739200000 + i * 3600000, price = (i * 7) % 10 } end

do
    local bar = FilterBar.new{ parent = newParent(), onChange = onChange, sortInHeader = true,
        sorts = { { id = "time", field = "ts" }, { id = "price", field = "price" } } }
    bar:layout(0, 0, 1000, true)
    ok(#bar._sortChips == 0 and #bar:appendTargets({}) == 0, "sortInHeader：沒有排序 chip、不給排序焦點")
    changes = 0
    bar:toggleSort("price")
    local id, desc = bar:getSort()
    local page = bar:apply(rows)
    ok(changes == 1 and id == "price" and desc == true and page[1].price >= page[2].price,
        "toggleSort 新欄：從 desc 開始、回呼一次，apply 依它排序")
    bar:toggleSort("price")
    id, desc = bar:getSort()
    page = bar:apply(rows)
    ok(id == "price" and desc == false and page[1].price <= page[2].price, "toggleSort 同一欄：翻轉方向")
    changes = 0
    bar:toggleSort(nil)
    bar:toggleSort("nope")
    ok(changes == 0, "toggleSort(nil／未知欄)：不動、不回呼")
    local hdr = UI.TableHeader.new{ target = bar, sort = FilterBar.getSort, onSort = FilterBar.toggleSort }
    hdr.onSort(hdr.target, "time", hdr)
    local hk, hdesc = hdr.sort(hdr.target)
    ok(hk == "time" and hdesc == true, "直接接 TableHeader：sort＝FilterBar.getSort、onSort＝FilterBar.toggleSort")
end

-- ---------- FilterBar inline 分頁：不截字，先換圖示鈕再拿掉筆數 ----------
-- 量測 10px/字：頁碼樣本 320、頁碼＋筆數樣本 670、文字鈕各 340、圖示鈕 26（bar.height 22）
do
    local PAGE, COUNT = "[IGUI_MinidoracatUI_Filter_Page]", "[IGUI_MinidoracatUI_Filter_Count]"
    local PREV = "[IGUI_MinidoracatUI_Filter_Prev]"
    local bar = FilterBar.new{ parent = newParent(), onChange = onChange, pager = "inline" }
    local prev, nextB = bar._prev, bar._next
    bar:layout(0, 0, 1400, true)
    ok(prev.title == PREV and prev.icon == nil and prev.width == 340 and bar._pageLine == PAGE .. "  " .. COUNT
        and nextB.x + nextB.width == 1400, "inline 放得下：文字鈕＋頁碼＋筆數，靠右")
    bar:layout(0, 0, 1000, true)
    ok(prev.title == "" and prev.icon == "chevronLeft" and nextB.icon == "chevronRight" and prev.width == 26
        and prev.tooltip == PREV and prev.fullTitle == PREV and bar._pageLine == PAGE .. "  " .. COUNT,
        "文字鈕放不下：換 chevron 圖示鈕（全名進 tooltip／fullTitle 焦點說明），頁碼與筆數完整")
    bar:layout(0, 0, 500, true)
    ok(prev.icon == "chevronLeft" and bar._pageLine == PAGE and bar._pageTextRight == prev.x - 8,
        "圖示鈕＋筆數也放不下：先拿掉筆數，頁碼完整不截字")
    bar:layout(0, 0, 300, true)
    ok(bar._pageLine == PAGE and not bar._pageLine:find("...", 1, true), "再窄也不截頁碼（寧可溢出）")
    bar:layout(0, 0, 1400, true)
    ok(prev.title == PREV and prev.icon == nil and prev.tooltip == nil and prev.width == 340,
        "空間恢復：換回文字鈕、收掉 tooltip")
    local wide = FilterBar.new{ parent = newParent(), onChange = onChange, pager = "inline", search = {} }
    wide:layout(0, 0, 1500, true)
    ok(wide._prev.y == wide._search.y and wide._prev.icon == "chevronLeft" and wide._pagerCount,
        "本列剩下的空間先試：放得下圖示鈕版就不換列")
    wide:layout(0, 0, 1000, true)
    ok(wide._prev.y > wide._search.y and wide._prev.icon == "chevronLeft" and wide._pagerCount,
        "本列連最小版都放不下：換到新的一列，用整列寬重選")
end

-- ---------- FilterBar dateToggle ----------
do
    local p = newParent()
    local bar = FilterBar.new{ parent = p, onChange = onChange, onLayout = onLayout, dateToggle = true,
        search = {}, dates = { field = "ts" } }
    bar:layout(0, 0, 1000, true)
    local chip = bar._dateChip
    ok(chip.visible and chip.title == "[IGUI_MinidoracatUI_Filter_CustomDate]" and not chip:isActive()
        and not bar._from.visible and not bar._to.visible, "dateToggle：預設只有「自訂日期...」chip，日期欄隱藏")
    local out = bar:appendTargets({})
    ok(#out == 2 and out[2].control == chip, "收起時焦點目標：關鍵字、日期 chip（沒有日期欄）")
    layouts = 0
    chip:forceClick()
    bar:layout(0, 0, 1000, true)
    ok(layouts == 1 and bar._from.visible and bar._to.visible and bar._from.y > chip.y,
        "按 chip：onLayout 一次，日期欄在下一列出現")
    ok(#bar:appendTargets({}) == 6, "打開時焦點目標：chip 後接起訖兩欄（各有輸入框與日曆鈕）")
    local year = UI.Date.fromMs(ctx.now(), UI.Date.localOffsetMinutes())
    local y = tostring(year)
    changes = 0
    bar._from._text._entry:setText(y .. "-09-01")
    bar._from._text:prerender()
    bar._to._text._entry:setText(y .. "-09-30")
    bar._to._text:prerender()
    ok(changes == 2 and chip.title == "09-01 ~ 09-30" and chip:isActive(),
        "選了區間：chip 亮起、今年省略年份顯示精簡區間")
    chip:forceClick()
    bar:layout(0, 0, 1000, true)
    local fromMs = bar:dateRange()
    ok(not bar._from.visible and chip.visible and chip:isActive() and fromMs ~= nil and chip.width == #chip.title * 10 + 20,
        "收起：日期欄隱藏，區間照樣生效，chip 寬跟著精簡區間")
    bar:setDateText("2020-01-05", "", true)
    ok(chip.title == "2020-01-05 ~", "只有起日、不同年份：寫全日期加 ~")
    chip:forceClick()
    layouts = 0
    bar:setDateText("", "", true)
    ok(not bar._datesOpen and not chip:isActive() and chip.title == "[IGUI_MinidoracatUI_Filter_CustomDate]"
        and layouts >= 1, "程式清空：收回「自訂日期...」chip、onLayout")
    chip:forceClick()
    bar:reset(true)
    ok(not bar._datesOpen, "reset：日期列收回 chip")
    bar:setEnabled(false)
    ok(not chip:isEnabled(), "setEnabled(false)：日期 chip 一併停用")
    local plain = FilterBar.new{ parent = newParent(), dates = { field = "ts" } }
    plain:layout(0, 0, 1000, true)
    ok(plain._dateChip == nil and plain._from.visible, "沒開 dateToggle：日期欄照舊直接顯示")
end

-- ---------- FilterBar kindsDropdown ----------
do
    local p = newParent()
    p:addToUIManager()
    local bar = FilterBar.new{ parent = p, onChange = onChange, kindsDropdown = true,
        kinds = { field = "kind", label = string.upper, multi = true }, sorts = { { id = "time", field = "ts" } } }
    bar:syncKinds(rows)
    bar:layout(0, 0, 1000, true)
    local dd = bar._ddButton
    ok(dd.visible and not bar._allChip.visible and not bar._kindChips[2].visible and not bar.multi
        and dd.title == "[IGUI_MinidoracatUI_Filter_All]", "kindsDropdown：只有一顆下拉鈕（標題「全部」），chip 隱藏、強制單選")
    ok(dd.width == #"[IGUI_MinidoracatUI_Filter_All]" * 10 + 20 + UI.Skin.ARROW_W + 4,
        "下拉鈕寬度預留最寬選項（stub 下是「全部」的鍵名）＋箭頭")
    local out = bar:appendTargets({})
    ok(out[1].control == dd and out[1].kind == "button" and out[1].label == "[IGUI_MinidoracatUI_Filter_Kind]",
        "焦點目標：類型位置是下拉鈕（標籤「類型」）")
    p.texts, p.rects = {}, {}
    bar:draw(p)
    local sawLabel = false
    for _, tx in ipairs(p.texts) do if tx.text == "[IGUI_MinidoracatUI_Filter_Kind]" then sawLabel = true end end
    ok(sawLabel and #p.rects == 8, "draw：畫「類型」標籤＋下拉箭頭（與排序箭頭各 4 列）")

    dd:forceClick()
    local m = FilterBar._menuForTests()
    ok(m ~= nil and m:getIsVisible() and m.rows == 3 and m.cursor == 1 and m.y == dd.y + dd.height + 2,
        "按下拉鈕：選單在鈕下方展開，三個選項，游標在目前選取")
    changes = 0
    m:onKeyPress(K.KEY_DOWN)
    m:onKeyRelease(K.KEY_DOWN)
    m:onKeyPress(K.KEY_RETURN)
    m:onKeyRelease(K.KEY_RETURN)
    ok(not m:getIsVisible() and changes == 1 and bar:getKind() == "odd" and dd.title == "ODD" and dd:isActive(),
        "鍵盤：下移＋Enter 選第二項，選單關閉、回呼一次、getKind 回該類型、鈕亮起")
    local page = bar:apply(rows)
    ok(#page == 3 and page[1].kind == "odd", "apply 依下拉選的類型過濾（同單選 chip）")
    dd:forceClick()
    m._mouseOver = true
    changes = 0
    m:onMouseUp(5, 4 + 1)
    ok(not m:getIsVisible() and changes == 1 and bar:getKind() == nil and not dd:isActive(),
        "滑鼠點第一列「全部」：getKind 回 nil、鈕不亮")
    m._mouseOver = nil
    dd:forceClick()
    m:onMouseDown(-5, -5)
    ok(not m:getIsVisible(), "在選單外按下：關閉")
    dd:forceClick()
    dd:forceClick()
    ok(not m:getIsVisible(), "同一顆下拉鈕再按：關閉")
    dd:forceClick()
    bar:layout(0, 0, 1000, false)
    ok(not m:getIsVisible(), "bar 隱藏（layout visible=false 會 blur）：關閉自己的選單")
    bar:layout(0, 0, 1000, true)
    dd:forceClick()
    bar:setEnabled(false)
    ok(not m:getIsVisible() and not dd:isEnabled(), "setEnabled(false)：下拉鈕停用、選單關閉")
    p.rects = {}
    bar:draw(p)
    ok(nearly(p.rects[#p.rects].r, 0.40), "停用時下拉箭頭用 textDisabled")
    bar:setEnabled(true)
    bar:syncKinds({ { kind = "zeta" } })
    ok(not bar._kindChips[2].visible and bar:getKind() == nil, "下拉模式新增的類型 chip 一建立就隱藏")
end

-- ---------- TableHeader 鍵盤焦點（sortInHeader 的鍵盤路徑） ----------
do
    local F = UI.Focus
    local bar = FilterBar.new{ parent = newParent(), sortInHeader = true,
        sorts = { { id = "time", field = "ts" }, { id = "price", field = "price" } } }
    local sorts = {}
    local hwin = UI.Window.new{ x = 0, y = 0, width = 400, height = 300, title = "T" }
    local header = UI.TableHeader.new{ x = 10, y = 40, width = 300, target = bar, sort = FilterBar.getSort,
        onSort = function(target, key, h) sorts[#sorts + 1] = key; FilterBar.toggleSort(target, key) end,
        focusable = true }
    header:setColumns({ { key = "name", title = "N", x = 0, w = 100, sortable = false },
        { key = "time", title = "T", x = 100, w = 100 }, { key = "price", title = "P", x = 200, w = 100 } })
    hwin:addChild(header)
    hwin:addToUIManager()
    header:prerender()
    ctx.press(hwin, K.KEY_TAB)
    ok(F.focused() == header and header._focusCol == 2 and UI.CAPABILITIES.tableHeaderFocus,
        "Tab 進表頭：焦點停在目前排序欄（time），不可排序欄不停")
    ctx.press(hwin, K.KEY_RIGHT)
    local onPrice = header._focusCol == 3
    ctx.press(hwin, K.KEY_RIGHT)
    local stayed = header._focusCol == 3
    ctx.press(hwin, K.KEY_LEFT)
    ctx.press(hwin, K.KEY_LEFT)
    ok(onPrice and stayed and header._focusCol == 2 and F.focused() == header,
        "左右鍵在可排序欄間移動、到邊停住、跳過不可排序欄，焦點留在表頭")
    ctx.press(hwin, K.KEY_RIGHT)
    ctx.press(hwin, K.KEY_RETURN)
    local id, desc = bar:getSort()
    ok(#sorts == 1 and sorts[1] == "price" and id == "price" and desc == true,
        "Enter 對目前欄呼叫 onSort 一次（接 toggleSort：換到 price、desc）")
    hwin.texts, hwin.borders = {}, {}
    hwin:render()
    local hx = header:getAbsoluteX() - hwin:getAbsoluteX()
    local hy = header:getAbsoluteY() - hwin:getAbsoluteY()
    local ringOnCol, captionAbove = false, false
    for _, b in ipairs(hwin.borders) do
        if b.x == hx + 200 - 4 and b.w == 100 + 8 then ringOnCol = true end
    end
    for _, tx in ipairs(hwin.texts) do
        if tx.text == "[IGUI_MinidoracatUI_Filter_Sort]" and tx.y < hy then captionAbove = true end
    end
    ok(ringOnCol and captionAbove, "焦點框畫在目前欄（focusRect），說明預設在框上方")
    local d = header:focusDescriptor("Sort")
    ok(d == header:focusDescriptor() and d.kind == "button" and d.control == header and d.captionSide == "above"
        and d.label == header._focusLabel, "focusDescriptor：原生 root 用的快取描述（label 省略＝「排序」）")
    header.live = function() return false end
    header:prerender()
    ok(header:onFocusKey(K.KEY_RETURN) == false and #sorts == 1 and header._enabled == false,
        "live=false：表頭不處理按鍵、不回呼")
    F.clear(hwin)
    ctx.press(hwin, K.KEY_TAB)
    ok(F.focused() ~= header, "live=false：Tab 不會停在表頭")
    hwin:close()
end

-- ---------- invalidate 的替代焦點沿用框可見性（TourI18n 實機：滑鼠開關疊層後切頁，導覽出現焦點框） ----------
do
    local F = UI.Focus
    local iwin = UI.Window.new{ x = 0, y = 0, width = 400, height = 300, title = "T" }
    local nav = UI.Button.new{ x = 10, y = 40, title = "Nav" }
    local gone = UI.Button.new{ x = 10, y = 80, title = "Gone" }
    iwin:addChild(nav)
    iwin:addChild(gone)
    local fixed = { { kind = "button", control = nav }, { kind = "button", control = gone } }
    iwin.keyboardTargets = function() return fixed end
    iwin:addToUIManager()
    F.focusControl(gone, false) -- 滑鼠放的焦點：不畫框
    gone:setVisible(false)      -- 疊層關掉／切頁：原控制項消失，原描述剩空組
    F.invalidate(iwin)
    ok(F.focused() == nav and not F.isKeyboardFocused(nav),
        "滑鼠焦點的控制項消失：invalidate 換到替代目標但不亮框")
    gone:setVisible(true)
    F.focusControl(gone, true)
    gone:setVisible(false)
    F.invalidate(iwin)
    ok(F.focused() == nav and F.isKeyboardFocused(nav), "鍵盤焦點的控制項消失：替代目標照樣亮框")
    iwin:close()
end

-- ---------- Toast.setAvoid（經濟中心頂端的餘額與「全部領取」被通知蓋住） ----------
do
    local Toast = UI.Toast
    Toast._resetForTests()
    local function settle(t)
        ctx.advance(300) -- 過了進場
        t:prerender()
        return t
    end
    local plain = settle(Toast.show("a"))
    local px, py = plain.x, plain.y
    ok(UI.CAPABILITIES.toastAvoid and px == 1920 - 300 - 16 and py == 60, "沒有登記：照舊右上（x=螢幕寬-寬-16、y=60）")
    Toast._resetForTests()
    local win = { x = 1500, y = 40, w = 400, h = 300 }
    local function winRect() return win.x, win.y, win.w, win.h end
    Toast.setAvoid("economy", winRect)
    local a = settle(Toast.show("a"))
    local b = settle(Toast.show("b"))
    a:prerender()
    ok(a.x == px and a.y == 40 + 300 + 8 and b.y == a.y + a.height + 8, "與視窗重疊：整疊移到視窗下方")
    win.h = 1000
    a:prerender()
    ok(a.x == 1500 - 300 - 16 and a.y == 60, "下方放不下：改放到視窗左側")
    win.x, win.y, win.h = 100, 40, 300
    a:prerender()
    ok(a.x == px and a.y == 60, "視窗不在右上欄：位置不變")
    local visible = false
    Toast.setAvoid("economy", function() if visible then return 1500, 40, 400, 300 end end)
    a:prerender()
    local hiddenOK = a.y == 60
    visible = true
    a:prerender()
    ok(hiddenOK and a.y == 348 and #Toast.avoid == 1, "fn 回 nil＝不避；同一 owner 再登記是覆寫")
    Toast.setAvoid("broken", function() error("boom") end)
    a:prerender()
    Toast.setAvoid("economy", nil)
    a:prerender()
    ok(a.y == 60 and #Toast.avoid == 1, "fn 出錯不影響通知；setAvoid(owner, nil) 取消登記")

    -- 兩個避開區連鎖：先比到的（小地圖，60 起不重疊）被後面的（Dock）推下去後才重疊。
    -- 單趟依登記順序會疊進小地圖；結果必須與登記順序無關。
    local function chained(first, second)
        Toast._resetForTests()
        local rects = { minimap = { 1500, 200, 400, 200 }, dock = { 1800, 40, 100, 150 } }
        for _, owner in ipairs({ first, second }) do
            local r = rects[owner]
            Toast.setAvoid(owner, function() return r[1], r[2], r[3], r[4] end)
        end
        return settle(Toast.show("a")).y
    end
    local y1, y2 = chained("minimap", "dock"), chained("dock", "minimap")
    ok(y1 == 200 + 200 + 8 and y2 == y1, "連鎖避開區：兩種登記順序都落在兩者下方（不疊進先登記的）")
    Toast._resetForTests()
end

return 79
