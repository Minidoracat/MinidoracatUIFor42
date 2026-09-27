-- rev 11 Slice C：UI.FilterBar（Widgets/FilterBar.lua）。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local check, UI = ctx.check, ctx.UI
dofile(ctx.MOD_LUA .. "Widgets/DatePicker.lua")
dofile(ctx.MOD_LUA .. "Widgets/FilterBar.lua")
print("情境 rev11-filter：UI.FilterBar 狀態／apply／版面／焦點")

local FilterBar = UI.FilterBar
local DAY = 86400000
local BASE = 1788739200000 -- 2026-09-07 00:00 UTC
local KIND_LABEL = "[IGUI_MinidoracatUI_Filter_Kind]"
local SORT_LABEL = "[IGUI_MinidoracatUI_Filter_Sort]"
local PAGER_LABEL = "[IGUI_MinidoracatUI_Filter_PageNav]"

local function newParent()
    return ISPanel.new(ISPanel, 0, 0, 1000, 600)
end

local changes, layouts, lastTarget = 0, 0, nil
local function onChange(target, bar)
    changes = changes + 1
    lastTarget = target
end
local function onLayout(target, bar)
    layouts = layouts + 1
end
local function upper(id)
    return string.upper(tostring(id))
end

local function groupOf(bar, label)
    local out = bar:appendTargets({})
    for i = 1, #out do
        if out[i].kind == "group" and out[i].label == label then
            return out[i]
        end
    end
    return nil
end
local function chipOf(bar, id)
    local g = groupOf(bar, KIND_LABEL)
    for i = 1, #g.controls do
        if g.controls[i].internal == id and g.controls[i].title ~= "" then
            return g.controls[i]
        end
    end
    return nil
end
local function allChip(bar)
    return bar._allChip
end
local function type27(entry, text) -- 打字：寫進原生 entry，TextField 下一幀比對到
    entry._entry:setText(text)
    entry:prerender()
end

-- Economy 情境 27b 的資料：60 列、每小時一筆
local rows = {}
for i = 1, 60 do
    rows[i] = { kind = (i % 3 == 0) and "sold" or "listed", ts = BASE + i * 3600000, price = (i * 7) % 50,
        name = "n" .. (61 - i), searchText = "n" .. (61 - i) }
end
local indexOf = {}
for i = 1, 60 do indexOf[rows[i]] = i end

-- ---------- setKinds／syncKinds ----------
do
    local p = newParent()
    local bar = FilterBar.new{ parent = p, onChange = onChange, onLayout = onLayout,
        kinds = { field = "kind", label = upper, extra = { { id = "rolled", label = "R" } } }, pager = "inline" }
    bar:layout(0, 0, 1000, true)
    check(bar:setKinds({ "a", "b" }) == true and bar:setKinds({ "a", "b" }) == false
        and bar:setKinds({ "b", "a" }) == true, "setKinds：集合或順序變了回 true，相同回 false")
    bar:layout(0, 0, 1000, true)
    local g = groupOf(bar, KIND_LABEL)
    check(g.controls[1].internal == nil and g.controls[2].internal == "b" and g.controls[3].internal == "a"
        and g.controls[4].internal == "rolled" and g.controls[2].title == "B",
        "chip 順序：全部在前、類型依使用端順序、extra 最後；標題取 label(id)")
    local before = #p.children
    bar:setKinds({ "a", "b", "c" })
    local grown = #p.children
    bar:setKinds({ "a" })
    bar:layout(0, 0, 1000, true)
    local parked = 0
    for i = 1, #p.children do
        local c = p.children[i]
        if c.style == "chip" and c.internal == nil and c.title ~= "" and c ~= allChip(bar) and not c.visible then
            parked = parked + 1
        end
    end
    bar:setKinds({ "a", "b", "c" })
    check(grown == before + 1 and #p.children == grown and parked == 2,
        "chip 物件池只增不減：多出來的停放隱藏、不 removeChild，再變多時重用")

    changes = 0
    bar:setKind("b", true)
    bar:setPage(3, 5, 100)
    bar:setKinds({ "a", "c" })
    check(bar:getKind() == nil and bar.page == 1 and changes == 0 and allChip(bar):isActive(),
        "已選類型被移除：回到「全部」並靜默把頁碼設回 1")
    bar:setKind("a", true)
    bar:setPage(3, 5, 100)
    bar:setKinds({ "a", "d" })
    check(bar:getKind() == "a" and bar.page == 3, "已選類型還在：選取與頁碼都不動")
    bar:setKind("rolled", true)
    bar:setKinds({ "z" })
    check(bar:getKind() == "rolled", "extra 不會因類型集合改變而被丟掉")

    check(bar:syncKinds({ { kind = "x" }, { kind = "y" }, { kind = "x" }, { kind = "" }, {}, { kind = "w" } }) == true,
        "syncKinds：集合變了回 true")
    bar:layout(0, 0, 1000, true)
    g = groupOf(bar, KIND_LABEL)
    check(g.controls[2].internal == "x" and g.controls[3].internal == "y" and g.controls[4].internal == "w"
        and g.controls[5].internal == "rolled" and #g.controls == 5,
        "syncKinds 依首次出現的順序收集，略過 nil 與空字串")
    check(bar:syncKinds({ { kind = "y" }, { kind = "x" }, { kind = "w" } }) == true
        and bar:syncKinds({ { kind = "y" }, { kind = "y" }, { kind = "x" }, { kind = "w" } }) == false,
        "syncKinds：順序不同算改變，重複列不影響判定")
end

-- ---------- 多選「全部」與 extra ----------
do
    local p = newParent()
    local bar = FilterBar.new{ parent = p, target = ctx.TARGET, onChange = onChange,
        kinds = { field = "kind", label = upper, multi = true, extra = { { id = "rolled", label = "R" } } } }
    bar:setKinds({ "sold", "listed" })
    bar:layout(0, 0, 1000, true)
    local all, sold, listed, rolled = allChip(bar), chipOf(bar, "sold"), chipOf(bar, "listed"), chipOf(bar, "rolled")
    check(all:isActive() and bar:isKindSelected(nil) and not sold:isActive(), "多選：沒有任何選取時「全部」亮起")
    changes = 0
    sold:forceClick()
    listed:forceClick()
    check(bar:isKindSelected("sold") and bar:isKindSelected("listed") and not all:isActive()
        and sold:isActive() and listed:isActive() and changes == 2 and lastTarget == ctx.TARGET,
        "多選：點兩顆都選上、「全部」熄滅；每次點擊回呼一次，target 是 opts.target")
    check(bar:getKind() == nil, "多選模式 getKind 一律回 nil")
    sold:forceClick()
    check(not bar:isKindSelected("sold") and bar:isKindSelected("listed"), "多選：再點一次取消該類型")
    all:forceClick()
    check(all:isActive() and not listed:isActive() and bar:isKindSelected(nil) and changes == 4,
        "多選：點「全部」清空選取")
    all:forceClick()
    check(changes == 4, "多選：已是「全部」時再點不回呼")
    rolled:forceClick()
    check(#bar:apply(rows) == 25 and bar.total == 60 and rolled:isActive(), "多選：只選 extra 不過濾")
    listed:forceClick()
    bar:apply(rows)
    check(bar.total == 40, "多選：extra＋類型時只依類型過濾")
    bar:setKind("sold", true)
    check(bar:isKindSelected("sold") and not bar:isKindSelected("listed") and not bar:isKindSelected("rolled"),
        "多選 setKind：清空後只放這一顆")

    local single = FilterBar.new{ parent = newParent(), onChange = onChange,
        kinds = { field = "kind", label = upper, extra = { { id = "rolled", label = "R" } } } }
    single:setKinds({ "sold", "listed" })
    single:setKind("rolled", true)
    single:apply(rows)
    check(single:getKind() == "rolled" and single.total == 60, "單選：extra 可以選，但 apply 不拿它過濾")
end

-- ---------- apply（Economy 情境 27b 改用 bar:apply） ----------
do
    local plain = FilterBar.new{ parent = newParent(), onChange = onChange }
    plain:setPage(3)
    local page = plain:apply(rows)
    check(#page == 10 and plain.page == 3 and plain.pages == 3 and plain.total == 60 and page[1] == rows[51],
        "分頁：沒有排序時保留輸入順序，最後一頁 10 筆")
    plain:setPage(9)
    page = plain:apply(rows)
    check(plain.page == 3 and #page == 10, "分頁：超過最後一頁夾回最後一頁")
    plain:setPage(-2)
    page = plain:apply({})
    check(plain.page == 1 and plain.pages == 1 and plain.total == 0 and #page == 0, "分頁：空結果是 1／1 頁")

    local bar = FilterBar.new{ parent = newParent(), onChange = onChange, perPage = 100,
        kinds = { field = "kind", label = upper }, dates = { field = "ts" },
        search = { field = "searchText" },
        sorts = {
            { id = "none", label = "None" },
            { id = "price", label = "Price", field = "price" },
            { id = "name", label = "Name", field = "name" },
            { id = "fn", label = "Fn", field = function(e) return e.ts end },
        } }
    bar:setKinds({ "listed", "sold" })
    bar:setKind("sold", true)
    page = bar:apply(rows)
    check(bar.total == 20 and page[1].kind == "sold" and page[20] == rows[60], "類型過濾")
    bar:setKind(nil, true)

    local oldOffset = UI.Date.localOffsetMinutes
    UI.Date.localOffsetMinutes = function() return 0 end
    bar:setDateText("2026-09-08", "2026-09-08", true)
    page = bar:apply(rows)
    check(bar.total == 24 and page[1] == rows[24] and page[24] == rows[47],
        "日期：[起日 00:00, 迄日隔天 00:00)，迄日當天整天都算")
    bar:setDateText("2026-09-09", "", true)
    bar:apply(rows)
    check(bar.total == 13, "日期：只填起日＝沒有上界")
    bar:setDateText("2026-9", "2026-09-07", true)
    bar:apply(rows)
    check(bar.total == 23, "日期：格式不對的一端不算界線")
    UI.Date.localOffsetMinutes = function() return 480 end
    bar:setDateText("2026-09-08", "2026-09-08", true)
    local from, to = bar:dateRange()
    check(from == BASE + DAY - 480 * 60000 and to == BASE + 2 * DAY - 480 * 60000,
        "dateRange 依本機時差換算，迄日加一天成為不含的上界")
    UI.Date.localOffsetMinutes = oldOffset
    bar:setDateText("", "", true)

    bar:setSort("price", true, true)
    page = bar:apply(rows)
    local ordered, stable = true, true
    for i = 2, #page do
        if page[i - 1].price < page[i].price then ordered = false end
        if page[i - 1].price == page[i].price and indexOf[page[i - 1]] > indexOf[page[i]] then stable = false end
    end
    check(#page == 60 and ordered, "排序：數值欄位遞減")
    check(stable, "排序：穩定（相等值保留輸入順序）")
    bar:setSort("name", false, true)
    page = bar:apply(rows)
    check(page[1].name == "n1" and page[2].name == "n10", "排序：字串依字典序")
    page = bar:apply({ { name = "b" }, { name = "C" }, { name = "a" } })
    check(page[1].name == "a" and page[2].name == "b" and page[3].name == "C", "排序：字串比較不分大小寫")
    bar:setSort("fn", false, true)
    page = bar:apply(rows)
    check(page[1] == rows[1] and page[60] == rows[60], "排序：field 可以是函式")
    -- 20 與 "3" 型別不同：轉字串比，"3" > "20"，所以遞減時 "3" 在 20 前面（數值比會相反）
    local mixed = { { price = 20 }, { price = nil }, { price = "3" } }
    bar:setSort("price", true, true)
    page = bar:apply(mixed)
    check(page[1] == mixed[3] and page[2] == mixed[1] and page[3] == mixed[2],
        "排序遞減：型別不同轉字串比，nil 排最後")
    bar:setSort("price", false, true)
    page = bar:apply(mixed)
    check(page[1] == mixed[1] and page[2] == mixed[3] and page[3] == mixed[2], "排序遞增：nil 仍排最後")
    bar:setSort("none", true, true)
    page = bar:apply(rows)
    check(page[1] == rows[1] and page[60] == rows[60], "排序：沒有 field 的排序保留輸入順序")

    bar:layout(0, 0, 1000, true)
    local search = bar:appendTargets({})[1].frame
    changes = 0
    bar:setPage(2, 3, 60)
    type27(search, "  N1 ")
    check(changes == 1 and bar.page == 1 and bar:getQuery() == "n1",
        "關鍵字：每幀比對到新字就回呼一次、頁碼回 1，getQuery 已 trim 並轉小寫")
    page = bar:apply(rows)
    check(bar.total == 11 and page[1].name == "n19", "關鍵字：比對 row[search.field]（n1、n10..n19）")
    type27(search, "n1  ")
    type27(search, "  N1")
    check(changes == 1, "關鍵字：只差大小寫或前後空白不回呼")
    bar:setKind("sold", true)
    bar:apply(rows)
    check(bar.total == 5, "關鍵字與類型同時生效（n1、n10、n13、n16、n19 是 sold）")
end

-- ---------- 每個動作回呼一次並重設頁碼 ----------
do
    local p = newParent()
    local bar = FilterBar.new{ parent = p, onChange = onChange, pager = "inline",
        kinds = { field = "kind", label = upper }, dates = { field = "ts" },
        sorts = { { id = "time", label = "T", field = "ts" }, { id = "price", label = "P", field = "price" } } }
    bar:setKinds({ "listed", "sold" })
    bar:layout(0, 0, 1000, true)
    local sorts = groupOf(bar, SORT_LABEL).controls
    local function action(fn)
        bar:setPage(2, 3, 60)
        changes = 0
        fn()
        return changes, bar.page
    end
    local c, pg = action(function() chipOf(bar, "sold"):forceClick() end)
    check(c == 1 and pg == 1 and lastTarget == p, "點類型：回呼一次、頁碼回 1、target 預設 parent")
    c, pg = action(function() chipOf(bar, "sold"):forceClick() end)
    check(c == 0 and pg == 2, "單選：點已選的那顆不回呼")
    c, pg = action(function() sorts[1]:forceClick() end)
    local id, desc = bar:getSort()
    check(c == 1 and pg == 1 and id == "time" and desc == false, "點作用中的排序：翻轉方向、回呼一次、頁碼回 1")
    c, pg = action(function() sorts[2]:forceClick() end)
    id, desc = bar:getSort()
    check(c == 1 and pg == 1 and id == "price" and desc == true and sorts[2]:isActive() and not sorts[1]:isActive(),
        "點新的排序：從 desc 開始、chip 亮起")
    c, pg = action(function() type27(bar._from._text, "2026-09-08") end)
    check(c == 1 and pg == 1, "日期欄改動：回呼一次、頁碼回 1")
    c, pg = action(function() bar:setSort("time", true) end)
    check(c == 1 and pg == 1, "非 silent 的 setter 也回呼一次")
    c, pg = action(function() bar:setSort("time", true) end)
    check(c == 0 and pg == 2, "setter 對相同值是 no-op")
    c, pg = action(function() bar:setKind("listed", true); bar:setDateText("2026-01-01", "", true) end)
    check(c == 0 and pg == 1, "silent setter 不回呼，但改了條件頁碼一樣回 1")

    local pager = groupOf(bar, PAGER_LABEL).controls
    bar:setPage(2, 3, 60)
    changes = 0
    pager[2]:forceClick()
    check(changes == 1 and bar.page == 3 and not pager[2]:isEnabled() and pager[1]:isEnabled(),
        "下一頁：回呼一次、不重設頁碼；到最後一頁時下一頁停用")
    pager[2]:forceClick()
    check(changes == 1 and bar.page == 3, "最後一頁：下一頁點不動")
    bar:setPage(1, 1, 0)
    check(not pager[1]:isEnabled() and not pager[2]:isEnabled(), "只有一頁：兩顆分頁鈕都停用")

    bar:setPage(3, 3, 60)
    bar:setKind("sold", true)
    bar:setDateText("2026-01-01", "2026-02-01", true)
    changes = 0
    bar:reset()
    local from, to = bar:getDateText()
    id, desc = bar:getSort()
    check(changes == 1 and bar:getKind() == nil and from == "" and to == "" and id == "time" and desc == true
        and bar.page == 1 and allChip(bar):isActive() and sorts[1]:isActive(),
        "reset：類型全部、日期清空、排序回預設 desc、頁碼 1，回呼一次")

    bar:setEnabled(false)
    check(not allChip(bar):isEnabled() and not sorts[1]:isEnabled() and not bar._from:isEnabled()
        and not pager[1]:isEnabled() and not pager[2]:isEnabled(), "setEnabled(false)：所有控制項停用")
    bar:setPage(2, 3, 60)
    check(not pager[1]:isEnabled() and not pager[2]:isEnabled(), "停用中換頁碼：分頁鈕仍停用")
    bar:setEnabled(true)
    check(allChip(bar):isEnabled() and pager[1]:isEnabled() and pager[2]:isEnabled(),
        "setEnabled(true)：分頁鈕依頁碼重算")
end

-- ---------- 類型翻頁與精簡切換 ----------
do
    local p = newParent()
    local ids = {}
    for i = 1, 12 do ids[i] = "kind" .. i end
    local bar = FilterBar.new{ parent = p, onChange = onChange, onLayout = onLayout,
        kinds = { field = "kind", label = upper, multi = true }, dates = { field = "ts" },
        sorts = { { id = "time", label = "T", field = "ts" } } }
    bar:setKinds(ids)
    bar:layout(0, 0, 400, true)
    local g = groupOf(bar, KIND_LABEL)
    local prev, nextB = g.controls[1], g.controls[#g.controls]
    local shown = #g.controls - 2
    check(prev.icon == "chevronLeft" and nextB.icon == "chevronRight" and prev.visible and nextB.visible
        and shown >= 1 and shown < 13 and not prev:isEnabled() and nextB:isEnabled(),
        "類型溢出：出現 < >，只顯示放得下的 chip；第一頁 < 停用")
    local lastRight = 0
    for i = 2, #g.controls - 1 do lastRight = math.max(lastRight, g.controls[i].x + g.controls[i].width) end
    check(lastRight <= nextB.x and nextB.x + nextB.width == 400, "類型 chip 不超過 > 鈕，> 靠右")
    layouts = 0
    changes = 0
    nextB:forceClick()
    check(layouts == 1 and changes == 0, "翻頁：只要使用端重排（onLayout 一次），不回呼 onChange")
    bar:layout(0, 0, 400, true)
    g = groupOf(bar, KIND_LABEL)
    check(g.controls[2] == chipOf(bar, "kind1") and prev:isEnabled() and not allChip(bar).visible,
        "翻頁後從第二顆開始，< 可用")
    local dateY = bar._from.y
    check(dateY > prev.y, "類型翻頁時獨佔到列尾，日期從下一列開始")
    bar:layout(0, 0, 4000, true)
    check(not prev.visible and not nextB.visible and allChip(bar).visible, "放得下時收起 < >、從頭顯示")

    layouts = 0
    local listY, listH, records = bar:layoutViewport(0, 0, 400, 1000, true, 0, 100)
    check(listY > 0 and records and bar:isShown() and (bar._toggle == nil or not bar._toggle.visible),
        "空間夠：篩選列與清單同時顯示，清單在篩選列下方")
    listY, listH, records = bar:layoutViewport(0, 0, 400, 90, true, 0, 100)
    local toggle = bar._toggle
    check(listY == 0 and records and not bar:isShown() and toggle.visible
        and toggle.title == "[IGUI_MinidoracatUI_Filter_Open]" and toggle.x + toggle.width == 400,
        "空間不夠：精簡模式先顯示清單、篩選列收起，切換鈕靠右寫「篩選條件」")
    check(bar:appendTargets({})[1].control == toggle and #bar:appendTargets({}) == 1,
        "精簡且篩選收起：焦點目標只剩切換鈕")
    toggle:forceClick()
    check(layouts == 1 and bar.filtersOpen, "切換鈕：onLayout 一次")
    listY, listH, records = bar:layoutViewport(0, 0, 400, 90, true, 0, 100)
    check(not records and bar:isShown() and toggle.title == "[IGUI_MinidoracatUI_Filter_Results]"
        and listH >= 0, "打開篩選：清單隱藏、切換鈕改寫「返回結果」")
    local out = bar:appendPagerTargets({})
    check(#out == 0, "清單隱藏時 strip 分頁不給焦點")
    listY, listH, records = bar:layoutViewport(0, 0, 400, 1000, true, 0, 100)
    out = bar:appendPagerTargets({})
    check(not toggle.visible and records and out[1] and out[1].label == PAGER_LABEL and bar.pagerY == 1000 - bar.height,
        "空間恢復：切換鈕隱藏，strip 分頁在底部")
end

-- ---------- field=nil 只保存狀態 ----------
do
    local bar = FilterBar.new{ parent = newParent(), onChange = onChange,
        kinds = { label = upper }, dates = {}, sorts = { { id = "time", label = "T" } } }
    bar:setKinds({ "a", "b" })
    bar:setKind("a", true)
    bar:setDateText("2026-09-08", "2026-09-08", true)
    bar:setSort("time", false, true)
    local page = bar:apply(rows)
    local from, to = bar:getDateText()
    local fromMs = bar:dateRange()
    check(#page == 25 and bar.total == 60 and page[1] == rows[1] and bar:getKind() == "a"
        and from == "2026-09-08" and to == "2026-09-08" and fromMs ~= nil,
        "field=nil：apply 不依類型／日期／排序處理，狀態照樣保存（伺服器端篩選）")
end

-- ---------- 焦點描述重用／繪製 ----------
do
    local p = newParent()
    local combo = ISPanel.new(ISPanel, 0, 0, 120, 22)
    p:addChild(combo)
    local bar = FilterBar.new{ parent = p, onChange = onChange, pager = "inline",
        kinds = { field = "kind", label = upper }, dates = { field = "ts" }, search = {},
        sorts = { { id = "time", label = "T", field = "ts" } } }
    bar:addControl(combo, "Acct", "combo")
    bar:setKinds({ "a", "b" })
    bar:layout(0, 0, 1000, true)
    local a = bar:appendTargets({})
    bar:layout(0, 0, 1000, true)
    local b = bar:appendTargets({})
    local same = #a == #b and #a == 9
    for i = 1, #a do
        if a[i] ~= b[i] then same = false end
    end
    check(same and groupOf(bar, KIND_LABEL).controls == groupOf(bar, KIND_LABEL).controls,
        "appendTargets：重排後仍回傳同一批描述 table 與 controls 陣列")
    check(a[1].kind == "entry" and a[2].label == KIND_LABEL and a[3].kind == "entry"
        and a[3].label == "[IGUI_MinidoracatUI_Filter_From]" and a[4].kind == "button" and a[5].kind == "entry"
        and a[7].label == SORT_LABEL and a[8].control == combo and a[8].kind == "combo"
        and a[9].label == PAGER_LABEL, "appendTargets 順序：關鍵字、類型、起訖日期、排序、addControl、inline 分頁")
    local sortChip = groupOf(bar, SORT_LABEL).controls[1]
    check(combo.visible and (combo.y > sortChip.y or (combo.y == sortChip.y and combo.x > sortChip.x))
        and bar._search.y <= allChip(bar).y and bar._search.x == #"[IGUI_MinidoracatUI_Filter_Search]" * 10 + 4,
        "addControl 的控制項排在排序後面，關鍵字排最前")

    p.texts, p.rects = {}, {}
    bar:draw(p)
    local sawLabel, sawCombo = false, false
    for i = 1, #p.texts do
        if p.texts[i].text == KIND_LABEL then sawLabel = true end
        if p.texts[i].text == "Acct" then sawCombo = true end
    end
    local chip = groupOf(bar, SORT_LABEL).controls[1]
    local r1 = p.rects[1]
    check(sawLabel and sawCombo and #p.rects == 4 and r1.x >= chip.x and r1.x + 7 <= chip.x + chip.width
        and r1.w == 7, "draw：畫標籤（含 addControl 的）；desc 時作用中排序 chip 內畫 ▼（首列最寬）")
    bar:setSort("time", false, true)
    p.rects = {}
    bar:draw(p)
    check(#p.rects == 4 and p.rects[1].w == 1, "draw：asc 時畫 ▲（首列 1px）")

    bar._search._entry:focus()
    bar:layout(0, 0, 1000, false)
    p.texts, p.rects = {}, {}
    bar:draw(p)
    check(not bar._search:isFocused() and not bar:isShown() and #p.texts == 0 and not combo.visible
        and not allChip(bar).visible and #bar:appendTargets({}) == 0,
        "layout(visible=false)：全部隱藏並 blur，draw 與 appendTargets 都不輸出")
end

-- 同一個 parent 掛兩條 bar（Economy 經濟中心：錢包／市場紀錄／拍賣紀錄）：隱藏中的那條 blur、
-- layout(visible=false) 或按精簡切換，都不能收掉另一條正開著的日曆
do
    local p = newParent()
    local a = FilterBar.new{ parent = p, onChange = onChange, dates = { field = "ts" } }
    local b = FilterBar.new{ parent = p, onChange = onChange, dates = { field = "ts" } }
    a:layout(0, 0, 1000, true)
    b:layout(0, 100, 1000, true)
    a._from._button:forceClick()
    local pop = UI.DatePicker._popupForTests()
    local opened = pop ~= nil and pop:getIsVisible() and pop.field == a._from
    b:blur()
    b:layout(0, 100, 1000, false)
    check(opened and pop:getIsVisible() and pop.field == a._from,
        "另一條 bar 的 blur／layout(false) 不關這條 bar 開著的日曆")
    b:layoutViewport(0, 100, 1000, 130, true, 100, 400)
    local toggled = b._toggle ~= nil and b._toggle:getIsVisible()
    if toggled then b._toggle:forceClick() end
    check(toggled and pop:getIsVisible() and pop.field == a._from,
        "另一條 bar 的精簡切換不關這條 bar 的日曆")
    a:blur()
    check(not pop:getIsVisible(), "自己的 blur 關掉自己日期欄的日曆")
end

return 77
