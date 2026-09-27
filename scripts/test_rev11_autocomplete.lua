-- rev 11 切片 E：UI.Autocomplete（契約見 smoke_harness.lua 的 rev 11 載入器註解）
local ctx = ...
local check, UI, TARGET = ctx.check, ctx.UI, ctx.TARGET
local K = Keyboard

dofile(ctx.MOD_LUA .. "Widgets/Autocomplete.lua")
print("情境 rev11-autocomplete：debounce／首次聚焦查詢／重試／過期丟棄／More・Empty・Partial／pick／queryFailed／list 契約")

check(UI.CAPABILITIES.autocomplete == true and UI.Autocomplete ~= nil, "Autocomplete 載入成功且 capability 翻 true")

local queries, accept = {}, true
local picks = {}
local enters = {}
local function names(n, prefix)
    local rows = {}
    for i = 1, n do rows[i] = { name = (prefix or "p") .. i } end
    return rows
end

local host = ISPanel.new(ISPanel, 0, 0, 600, 400)
local ac = UI.Autocomplete.new{
    width = 200, target = TARGET, placeholder = "P",
    onQuery = function(target, text, picker)
        queries[#queries + 1] = text
        return accept and target == TARGET and picker ~= nil
    end,
    tagOf = function(row) return row.online and "ON" or nil end,
    onPick = function(target, row, picker)
        picks[#picks + 1] = { target = target, row = row, open = picker:isOpen(),
            focused = picker.field:isFocused(), text = picker:getText() }
    end,
    onEnter = function(target, text) enters[#enters + 1] = text end,
}
ac:addTo(host)
ac:layout(10, 20, 200, 300)
local field, list, entry = ac.field, ac.list, ac.field._entry
local RH = 12 + 12 -- stub 字高 12＋12

local function frame() field:prerender() end
local function typeText(s)
    entry._text = s
    frame()
end
local function settle(s) -- 打字、等滿 debounce、送出
    typeText(s)
    ctx.advance(250)
    frame()
end
local function respond(rows, total, truncated)
    return ac:setResults(ac:getText(), rows, total, truncated)
end

check(host.children[1] == field and host.children[2] == list and not ac:isOpen()
    and entry._clearButton == true and entry._maxLen == 64,
    "addTo：輸入框先加、下拉後加（蓋在兄弟上）；預設 clearButton、maxLength 64")

-- ---------- 首次聚焦與 debounce ----------
frame()
check(#queries == 0, "未聚焦時不查詢")
entry:focus()
frame()
check(#queries == 1 and queries[1] == "", "第一次聚焦立刻查一次空字串（不等 debounce）")
frame()
check(#queries == 1, "已送出的查詢不重送")
local realMatch, matches = string.match, 0
string.match = function(...) matches = matches + 1; return realMatch(...) end
frame()
frame()
frame()
string.match = realMatch
check(matches == 0, "聚焦中文字不變的幀不重算去空白查詢（每幀不產生新字串）")
check(respond({ { name = "alice", online = true }, { name = "bob" } }, 2) == true, "setResults：符合目前查詢時接受")
frame()
check(ac:isOpen() and list.shown == 2 and list.height == 2 * RH + 2 and list.x == 10 and list.y == 20 + field.height
    and list.width == 260, "下拉掛在輸入框正下方、寬至少 minListWidth、高＝列數×(字高＋12)＋2")

typeText("a")
check(not ac:isOpen() and list.shown == 0, "打字立刻丟掉舊候選（不顯示不符合的結果）")
ctx.advance(249)
frame()
check(#queries == 1, "debounce 未滿 250ms 不送")
ctx.advance(1)
frame()
check(#queries == 2 and queries[2] == "a", "滿 250ms 送出目前文字")
typeText("al")
ctx.advance(200)
typeText("ali")
ctx.advance(200)
frame()
check(#queries == 2, "連續打字：每次按鍵重新計時")
ctx.advance(50)
frame()
check(#queries == 3 and queries[3] == "ali", "停手滿 250ms 只送最後的文字一次")
respond(names(2))
typeText("  ali  ")
ctx.advance(250)
frame()
check(#queries == 3 and ac:getText() == "ali", "getText 去頭尾空白；去空白後相同且已有結果時不重送")

-- ---------- onQuery 回 false 下一幀重試 ----------
accept = false
settle("x")
check(#queries == 4 and queries[4] == "x", "debounce 滿後呼叫 onQuery")
frame()
check(#queries == 5 and queries[5] == "x", "onQuery 回 false：下一幀再試")
check(respond(names(1)) == false, "onQuery 回 false 的文字不算已送出：結果被丟棄")
accept = true
frame()
frame()
check(#queries == 6, "onQuery 回 true 後停止重試")

-- ---------- 過期結果丟棄 ----------
typeText("xy")
check(ac:setResults("x", names(3)) == false and not ac:isOpen(), "setResults：text 與目前輸入不同 → 丟棄")
ctx.advance(250)
frame()
check(queries[#queries] == "xy", "丟棄後照常送出目前文字")
check(ac:setResults("zzz", names(3)) == false, "setResults：不是最後送出的查詢 → 丟棄")

-- ---------- Empty／More／Partial ----------
check(respond({}) == true, "空結果被接受")
frame()
check(ac:isOpen() and list.shown == 0 and list._noteRaw == "[IGUI_MinidoracatUI_Autocomplete_Empty]"
    and list.height == RH + 2, "非空查詢沒結果：一列 Autocomplete_Empty")
settle("")
respond({})
frame()
check(not ac:isOpen(), "空字串查詢沒結果：不顯示 Empty")
settle("p")
respond(names(10), 10)
frame()
check(list.shown == 7 and list._noteRaw == "[IGUI_MinidoracatUI_Autocomplete_More]" and list.height == 8 * RH + 2,
    "超過 rows=8：顯示 7 列＋Autocomplete_More 一列")
check(list._noteCount == 3, "More 的數字＝total − 顯示列數")
settle("pp")
respond(names(3), 50)
frame()
check(list.shown == 3 and list._noteKind == "more" and list._noteCount == 47, "total 大於回傳列數：3 列＋還有 47 個")
settle("ppp")
respond(names(3), 3, true)
frame()
check(list.shown == 3 and list._noteRaw == "[IGUI_MinidoracatUI_Autocomplete_Partial]", "truncated：改用 Autocomplete_Partial")
ac:anchorList(3 * RH)
check(list.shown == 2 and list.height == 3 * RH + 2, "anchorList(maxH)：列數受可用高度限制（2 列＋提示）")
ac:anchorList(1000)
ac:anchorList(RH)
check(list.shown == 1 and list._noteKind == nil and list.height == RH + 2,
    "只剩一列高度：顯示第一筆候選，不畫提示列（仍有候選可選）")
ac:anchorList(1000)

-- ---------- 繪製：標籤、截字、theme.alpha ----------
settle("q")
respond({ { name = "alice", online = true }, { name = "averyveryverylongname" } }, 2)
frame()
list.rects, list.texts, list.borders = {}, {}, {}
list:prerender()
check(list.texts[1].text == "alice" and list.texts[2].text == "ON" and list.texts[2].x == 260 - 8 - 20
    and list.texts[3].text == "averyveryverylongname", "tagOf 的標籤靠右畫；放得下的名字不截")
list:setWidth(70)
frame()
list.texts = {}
list:prerender()
check(#list.texts == 2 and list.texts[1].text == "alice" and list.texts[2].text == "av...",
    "窄下拉：留不下 3 字高的名字空間時不畫標籤；過長名字截字")
list:setWidth(260)
local faded = UI.Theme.create()
faded.alpha = 0.5
local keepTheme = ac.theme
ac.theme = faded
list.rects, list.texts, list.borders = {}, {}, {}
list:prerender()
ac.theme = keepTheme
check(ctx.nearly(list.rects[1].a, faded.colors.surface.a * 0.5) and ctx.nearly(list.borders[1].a, 0.5)
    and ctx.nearly(list.texts[1].a, 1), "theme.alpha：下拉的 fill／border 乘上，文字不乘")

-- ---------- list 契約與 pick ----------
check(list._focusKind == "list" and list.items == ac.candidates and list.rowHeight == RH and list.padding == 0
    and type(list.getSelectedIndex) == "function" and type(list.onSelect) == "function",
    "下拉帶 Focus list 描述要讀的 items／rowHeight／padding／height／get・setSelectedIndex／onSelect")
list:setSelectedIndex(99)
local clamped = list:getSelectedIndex()
list:setSelectedIndex(0)
check(clamped == 2 and list:getSelectedIndex() == nil, "setSelectedIndex 夾在顯示列內；無效值清掉")

list:onMouseDown(5, 1 + RH + 3)
list:onMouseUp(5, 1 + RH + 3)
local p = picks[1]
check(#picks == 1 and p.target == TARGET and p.row.name == "averyveryverylongname", "點列：onPick 只回呼一次、帶 target 與 row")
check(p.text == "averyveryverylongname" and not p.open and not p.focused,
    "onPick 之前已寫入文字、blur、close")
check(list.items[1] == nil and list.shown == 0, "close 後下拉沒有列：Focus 的 Enter 不會再 pick 一次")
local before = #queries
frame()
ctx.advance(1000)
frame()
check(#queries == before, "pick 寫入的文字不觸發查詢")
entry:focus()
frame()
check(#queries == before + 1 and queries[#queries] == "averyveryverylongname", "再次聚焦：沒有結果時立刻查目前文字")

-- ---------- queryFailed ----------
local n0 = #queries
ac:queryFailed(true)
frame()
check(#queries == n0, "queryFailed(true)：重新計時，不立刻重送")
ctx.advance(250)
frame()
check(#queries == n0 + 1 and queries[#queries] == "averyveryverylongname", "queryFailed(true)：聚焦中滿 debounce 重送同一文字")
ac:queryFailed(false)
check(respond(names(2)) == false, "queryFailed(false)：清掉已送出的查詢，遲到的結果被丟棄")
ctx.advance(1000)
frame()
check(#queries == n0 + 1, "queryFailed(false)：不重送")
entry:unfocus()
frame()
settle("z")
entry:unfocus()
frame()
local n1 = #queries
ac:queryFailed(true)
ctx.advance(1000)
frame()
check(#queries == n1, "queryFailed(true)：沒聚焦、下拉也沒開時不重送")

-- ---------- setText／onEnter ----------
entry:focus()
frame()
settle("m")
respond(names(2))
frame()
check(ac:isOpen() and list.shown == 2, "（前置）聚焦中、候選已載入")
ac:setText("manual")
local closedNow = not ac:isOpen() -- host 接著問 isOpen（例如 Esc）時不必等下一幀
frame()
check(closedNow and field:getText() == "manual" and not ac:isOpen() and list.shown == 0 and list.selectedIndex == nil
    and #queries == n1 + 2 and queries[#queries] == "m",
    "setText 靜默（不立刻查詢）；文字變了當下就收掉舊候選與反白")
ctx.advance(250)
frame()
check(#queries == n1 + 3 and queries[#queries] == "manual", "setText：聚焦中為新文字排 debounce，滿後查詢新文字")
entry:onCommandEntered()
check(enters[1] == "manual", "輸入框 Enter 呼叫 onEnter(target, text, picker)")
settle("m2")
ac:setText("m2")
check(respond(names(1)) == false, "setText 清掉已送出的查詢：同文字的遲到結果也被丟棄")
entry:unfocus()
frame()
local nu = #queries
ac:setText("other")
ctx.advance(1000)
frame()
check(#queries == nu, "沒聚焦時 setText 不排程（下次聚焦沒有候選會立刻查）")
entry:focus()
frame()
check(#queries == nu + 1 and queries[#queries] == "other", "setText 後第一次聚焦查詢新文字")

-- ---------- 停用／隱藏時關閉 ----------
typeText("s")
ctx.advance(250)
frame()
respond(names(2))
frame()
check(ac:isOpen(), "（前置）下拉開著")
list._mouseOver = true -- 滑鼠停在下拉上也不能讓停用後的下拉留著
ac:setEnabled(false)
frame()
check(not ac:isOpen() and not entry:isFocused(), "setEnabled(false)：收起下拉、放掉文字焦點（滑鼠在下拉上也一樣）")
local nq = #queries
entry._focused = true -- UITextBox2 點擊直接聚焦、不經 Lua：停用中被點到也不開啟、不查詢
ctx.advance(1000)
frame()
check(not ac:isOpen() and #queries == nq, "停用中即使輸入框被聚焦也不查詢、下拉保持收起")
entry._focused = false
list._mouseOver = nil
ac:setEnabled(true)
entry:focus()
frame()
respond(names(2))
frame()
ac:setVisible(false)
check(not ac:isOpen() and not field:getIsVisible() and not entry:isFocused(), "setVisible(false)：隱藏輸入框、收起下拉並 blur")
ac:setVisible(true)
entry:focus()
local nb = #queries
frame()
check(#queries == nb + 1, "隱藏再顯示後，第一次聚焦立刻查詢（blur 歸零聚焦狀態）")

-- ---------- appendTargets ----------
entry:focus()
frame()
respond(names(2))
frame()
local out1 = ac:appendTargets({}, "F", "L")
local out2 = ac:appendTargets({}, "F2", "L2")
check(#out1 == 2 and out1[1].kind == "entry" and out1[1].control == entry and out1[1].frame == field
    and out1[2].kind == "list" and out1[2].control == list and out1[1] == out2[1] and out2[2].label == "L2",
    "appendTargets：entry＋開著的 list，重用同一批描述 table")
ac:close()
check(#ac:appendTargets({}, "F", "L") == 1, "appendTargets：下拉收起時只有 entry")

-- ---------- Focus 整合：自動目標、方向鍵、Enter、鍵盤聚焦維持可見 ----------
local F = UI.Focus
local win = UI.Window.new{ x = 0, y = 0, width = 400, height = 300, title = "AC" }
local picked = {}
local kac = UI.Autocomplete.new{ width = 200, onQuery = function() return true end,
    onPick = function(_, row) picked[#picked + 1] = row.name end }
kac:addTo(win)
kac:layout(10, 30, 200, 200)
win:addToUIManager()
win:onFocus()
kac.field._entry:focus()
kac.field:prerender()
kac:setResults("", names(3))
kac.field:prerender()
local found = false
for _, d in ipairs(F.collectTargets(win)) do
    if d.kind == "list" and d.control == kac.list then found = true end
end
check(found, "開著的下拉被 Focus 自動目標收成 kind=list")
F.focusControl(kac.list, true)
kac.field._entry:unfocus()
kac.field:prerender()
check(kac:isOpen(), "輸入框失焦但下拉持有鍵盤焦點：保持可見")
kac.list:setSelectedIndex(1)
ctx.press(win, K.KEY_DOWN)
check(kac.list:getSelectedIndex() == 2, "方向鍵在下拉內移動反白")
ctx.press(win, K.KEY_RETURN)
check(#picked == 1 and picked[1] == "p2" and kac:getText() == "p2" and not kac:isOpen(),
    "Enter 選取反白列（pick 一次並收起）")
ctx.press(win, K.KEY_RETURN)
check(#picked == 1, "收起後再按 Enter 不會重複 pick")
F.clear(win)
win:setVisible(false)

return 64
