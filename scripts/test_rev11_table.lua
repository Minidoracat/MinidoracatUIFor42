-- rev 11 Slice B：UI.Table／UI.TableHeader（Widgets/Table.lua）。載入契約見 smoke_harness.lua 的 rev 11 載入器註解。
local ctx = ...
local check, nearly, UI, TARGET = ctx.check, ctx.nearly, ctx.UI, ctx.TARGET

dofile(ctx.MOD_LUA .. "Widgets/Table.lua")
print("情境 rev11-table：Table／TableHeader")

check(UI.CAPABILITIES.table == true and type(UI.Table.new) == "function" and type(UI.TableHeader.new) == "function",
    "Table.lua 載入後翻 CAPABILITIES.table，掛 UI.Table／UI.TableHeader")

local dark = UI.Theme.create()
local C = dark.colors

-- ===== Table.new：createCell／bindCell／unbindCell =====
do
    local Hooked = ISPanel:derive("TestTableHookedCell")
    local binds, unbinds = {}, 0
    function Hooked:onBind() binds[#binds + 1] = self.entry.id .. "@" .. self.index end
    function Hooked:onUnbind()
        unbinds = unbinds + 1
        self.sawEntry = self.entry
    end
    local list = UI.Table.new{ rowHeight = 20, height = 60, cell = Hooked, theme = dark }
    local cell = list.pool[1]
    check(getmetatable(cell) == Hooked and cell.background == false and cell.list == list and cell.theme == dark
        and list.theme == dark and type(list.cols) == "table" and #list.cols == 0,
        "createCell：用 opts.cell 建、background=false、帶 list／theme；list.cols 空表、list.theme")
    check(list.colors.thumb == C.textFaint and list.colors.thumbHover == C.textMuted and list.colors.track == C.selected,
        "colors 省略：thumb=textFaint、thumbHover=textMuted、track=selected")
    local custom = { thumb = C.text }
    local plain = UI.Table.new{ rowHeight = 20, colors = custom }
    check(plain.colors == custom and getmetatable(plain.pool[1]) == UI.Table.TextCell,
        "colors 原樣傳給 VirtualList；cell 省略＝TextCell")

    list:setItems({ { id = "a" }, { id = "b" } })
    check(binds[1] == "a@1" and binds[2] == "b@2" and cell.entry.id == "a" and cell.index == 1,
        "bindCell：先寫 entry／index 再呼叫 onBind")
    list:setItems({ { id = "c" } })
    check(unbinds == 1 and list.pool[2].entry == nil and list.pool[2].sawEntry.id == "b" and binds[3] == "c@1",
        "unbindCell：先呼叫 onUnbind（entry 還在）再清 entry；留下的列重綁")
end

-- ===== rowBackground：斑馬紋／選取／hover 與 lit =====
do
    local list = UI.Table.new{ rowHeight = 20, height = 100, theme = dark }
    list:setItems({ {}, {}, {} })
    local function row(index, theme)
        local c = ISPanel.new(ISPanel, 0, 0, 100, 20)
        c.theme, c.list, c.index = theme or dark, list, index
        return c
    end
    local odd, even = row(1), row(2)
    local litOdd, litEven = UI.Table.rowBackground(odd), UI.Table.rowBackground(even)
    check(#odd.rects == 0 and litOdd == false, "奇數列、未選、未 hover：不畫底、lit=false")
    check(#even.rects == 1 and nearly(even.rects[1].a, 0.04) and even.rects[1].w == 100 and even.rects[1].h == 20
        and litEven == false, "偶數列斑馬紋：dark 下 alpha 0.04（＝Economy card），整列、lit=false")
    local light = UI.Theme.create{ variant = "light" }
    local lightRow = row(2, light)
    UI.Table.rowBackground(lightRow)
    check(nearly(lightRow.rects[1].a, 0.05 * 2 / 3), "斑馬紋＝hover×2/3（light 主題跟著 token 走）")

    list:setSelectedIndex(1)
    local sel = row(1)
    local litSel = UI.Table.rowBackground(sel)
    check(#sel.rects == 1 and nearly(sel.rects[1].a, 0.12) and litSel == true, "選取列：selected 底、lit=true")
    local hov = row(3)
    hov._mouseOver = true
    local litHov = UI.Table.rowBackground(hov)
    check(#hov.rects == 1 and nearly(hov.rects[1].a, 0.06) and litHov == true, "hover 列：hover 底、lit=true")

    local faded = UI.Theme.create()
    faded.alpha = 0.5
    local fz = row(2, faded)
    fz._mouseOver = true
    UI.Table.rowBackground(fz)
    check(#fz.rects == 2 and nearly(fz.rects[1].a, 0.02) and nearly(fz.rects[2].a, 0.03),
        "theme.alpha：斑馬紋與 hover 底都乘 0.5")
end

-- ===== TextCell：截字、token、muted、刪除線、提亮、快取 =====
do
    local list = UI.Table.new{ rowHeight = 20, width = 200, height = 40, theme = dark }
    list.cols = { { x = 10, width = 50 }, { x = 190, right = true } }
    local items = {
        { cells = { "abcdefghij", 42 }, tokens = { "textMuted", "accent" } },
        { cells = { "x", "y" }, muted = true },
    }
    list:setItems(items)
    local c1, c2 = list.pool[1], list.pool[2]
    c1:render()
    local t = c1.texts
    check(#t == 2 and t[1].text == "ab..." and t[1].x == 10 and t[1].y == 4 and t[2].text == "42" and t[2].x == 170,
        "TextCell：col.width 截字、靠右欄畫到 x、文字垂直置中（(20-12)/2）")
    check(nearly(t[1].r, C.textMuted.r) and nearly(t[2].g, C.accent.g), "TextCell：tokens 取 theme 色")

    c1._mouseOver = true
    c1.texts, c1.rects = {}, {}
    c1:render()
    check(nearly(c1.texts[1].r, C.text.r) and nearly(c1.texts[1].g, C.text.g) and nearly(c1.texts[2].g, C.accent.g),
        "lit：textMuted 提亮成 text，其他 token 不動")
    c1._mouseOver = false

    c2:render()
    local strike
    for _, r in ipairs(c2.rects) do
        if r.h == 1 then strike = r end
    end
    check(nearly(c2.texts[1].r, C.textFaint.r) and nearly(c2.texts[2].r, C.textFaint.r),
        "muted：每欄一律 textFaint")
    check(strike and strike.x == 10 and strike.y == 10 and strike.w == 178 and nearly(strike.r, C.textFaint.r),
        "muted：第一欄 x 到 w-12 畫 1px textFaint 刪除線（字高一半）")
    c2._mouseOver = true
    c2.texts, c2.rects = {}, {}
    c2:render()
    check(nearly(c2.texts[1].r, C.text.r), "muted＋lit：textFaint 也提亮成 text")
    c2._mouseOver = false

    items[1].tokens = { "noSuchToken", "text" }
    list:setItems(items)
    c1.texts = {}
    c1:render()
    check(nearly(c1.texts[1].r, C.text.r) and c1.texts[1].g == C.text.g, "未知 token 退成 text")

    -- 快取：同 cols／寬度不重量；換 cols 或重綁才重算
    local keepTM = getTextManager
    local measures = 0
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) measures = measures + 1; return string.len(s) * 10 end,
            getFontHeight = function() return 12 end }
    end
    c1:render()
    local steady = measures
    list.cols = { { x = 10, width = 200 }, { x = 190, right = true } }
    c1.texts = {}
    c1:render()
    local recut = c1.texts[1].text
    items[1].cells[1] = "zz"
    list:setItems(items)
    c1.texts = {}
    c1:render()
    getTextManager = keepTM
    check(steady == 0 and recut == "abcdefghij" and c1.texts[1].text == "zz",
        "截字快取：同 cols／寬度零量測；換 cols 重算；原地改 entry 再 setItems 也重算")

    -- 使用端原地重算同一組 cols（清單總寬不變）：以每欄 width 當快取鍵
    items[1].cells[1] = "abcdefghij"
    list.cols[1].width = 60
    list:setItems(items)
    c1.texts = {}
    c1:render()
    local wide = c1.texts[1].text
    list.cols[1].width = 40
    c1.texts = {}
    c1:render()
    check(wide == "abc..." and c1.texts[1].text == "a...",
        "截字快取：同一顆 cols 原地把欄寬 60 改 40，下一幀重新截字")
    list.cols[1].x, list.cols[1].right = 100, true
    c1.texts = {}
    c1:render()
    check(c1.texts[1].text == "a..." and c1.texts[1].x == 60,
        "截字快取：原地把欄改成靠右，下一幀重量字寬、畫到 x 為右緣")
    list.cols[1].x, list.cols[1].right = 10, nil

    local Receipt = ISPanel:derive("TestTableReceiptCell")
    function Receipt:render()
        UI.Table.TextCell.render(self)
        self.extra = true
    end
    local rl = UI.Table.new{ rowHeight = 20, width = 200, height = 40, cell = Receipt, theme = dark }
    rl.cols = { { x = 4 } }
    rl:setItems({ { cells = { "r" } } })
    rl.pool[1]:render()
    check(rl.pool[1].texts[1].text == "r" and rl.pool[1].extra == true,
        "衍生 cell 可直接呼叫 UI.Table.TextCell.render(self)")
end

-- ===== layoutColumns：五段縮欄順序 =====
-- 量測 10px/字、pad 12、SORT_GUTTER 11。名稱欄 floor＝max("..."=30, 40+11)=51。
-- 其他欄起始寬：seller 72（可讓到 42）、price 62（extra 20）、date 112（wrapW→62）、qty 73（soft→41）
local function specs()
    return {
        { key = "name", title = "Name" },
        { key = "seller", title = "S", sample = "mmmmmm", sortable = false },
        { key = "price", title = "P", sample = "999", extra = 20, right = true, sortable = false },
        { key = "date", title = "D", sampleW = 100, wrapW = 50, right = true, sortable = false },
        { key = "qty", title = "Qty", sample = "99999", right = true, soft = true },
    }
end
local function widths(s)
    return s[1].w .. "," .. s[2].w .. "," .. s[3].w .. "," .. s[4].w .. "," .. s[5].w
end
local function contiguous(s, leftX)
    local x = leftX
    for i = 1, #s do
        if s[i].x ~= x then return false end
        x = x + s[i].w
    end
    return true
end
do
    local layout = UI.Table.layoutColumns
    local s = layout(specs(), 0, 1000, 100)
    check(widths(s) == "681,72,62,112,73" and contiguous(s, 0) and s[4].wrapped == false,
        "預算充足：各欄量測寬，名稱欄拿剩下的，欄位首尾相接")
    check(s[5].textR == s[5].x + 73 - 11 and s[5].textW == 62 and s[2].textR == s[2].x + 72 and s[1].wrapped == false,
        "textR／textW：可排序欄扣 SORT_GUTTER，不可排序欄不扣")
    check(widths(layout(specs(), 0, 399, 100)) == "100,52,62,112,73",
        "第 1 段：sample 型非靠右文字欄先讓（只讓到名稱欄達 nameMin）")
    local b = layout(specs(), 0, 330, 100)
    check(widths(b) == "100,42,52,63,73" and b[4].wrapped == true and b[3].wrapped == false,
        "第 2、3 段：extra 只讓到 nameFloor，再由 wrapW 欄縮到 nameMin 並標 wrapped")
    local c = layout(specs(), 0, 248, 100)
    check(widths(c) == "51,42,42,62,51" and c[4].wrapped == true,
        "第 4 段：soft 欄讓到名稱欄 floor（前 3 段已讓到底）")
    local d = layout(specs(), 10, 160, 100)
    check(widths(d) == "53,22,22,32,21" and d[4].wrapped == false and contiguous(d, 10)
        and d[5].x + d[5].w <= 160, "第 5 段：全部按比例縮、不超出預算、wrapped 收回")
    local reuse = layout(b, 0, 1000, 100)
    check(reuse[4].wrapped == false and reuse[4].w == 112, "同一組 specs 重算：wrapped 與寬度都重設")
    local p = layout({ { key = "a", title = "A" },
        { key = "b", title = "B", sample = "xxxxxxxxxx", sampleW = 20, sortable = false } }, 0, 1000, 10, 4)
    check(p[2].w == 24, "sampleW 優先於 sample；pad 參數取代預設 12")
end

-- ===== TableHeader：點擊、live、箭頭 =====
do
    local sortKey, sortDesc, live = "qty", true, true
    local calls = {}
    local hdr = UI.TableHeader.new{ width = 1000, theme = dark, target = TARGET,
        sort = function(t) return sortKey, sortDesc end,
        live = function(t) return live end,
        onSort = function(t, key, h) calls[#calls + 1] = { t = t, key = key, h = h } end }
    local s = UI.Table.layoutColumns(specs(), 0, 1000, 100)
    hdr:setColumns(s)
    check(hdr.height == 22 and hdr.background == false, "TableHeader 預設高＝字高+10、不畫原生底")

    local r1 = hdr:onMouseDown(s[5].x + 1)
    hdr:onMouseDown(s[2].x + 1)
    hdr:onMouseDown(1200)
    check(r1 == true and #calls == 3 and calls[1].key == "qty" and calls[1].t == TARGET and calls[1].h == hdr
        and calls[2].key == nil and calls[3].key == nil,
        "點可排序欄回 key（target, key, header）；不可排序欄與欄外回 nil")
    live = false
    local r2 = hdr:onMouseDown(s[5].x + 1)
    check(r2 == true and #calls == 3, "live=false：不回呼但照樣吞掉點擊")

    live = true
    hdr:prerender()
    local q = s[5]
    local arrow = hdr.rects[2]
    check(#hdr.rects == 5 and nearly(hdr.rects[1].a, C.well.a) and hdr.rects[1].w == 1000,
        "表頭：well 直角底＋作用中那欄四列箭頭")
    check(arrow.x == q.x + q.w - 7 and arrow.w == 7 and arrow.y == 9 and nearly(arrow.g, C.accent.g),
        "desc＋靠右欄：▼ 畫在 x+w-ARROW_W，accent 色、與字垂直置中")
    local qtyText, nameText
    for _, tx in ipairs(hdr.texts) do
        if tx.text == "Qty" then qtyText = tx elseif tx.text == "Name" then nameText = tx end
    end
    check(qtyText.x == q.textR - 30 and nearly(qtyText.g, C.accent.g) and nearly(nameText.r, C.textMuted.r),
        "作用中標題 accent、靠右欄畫到 textR；其他 live 時 textMuted")

    sortKey, sortDesc, live = "name", false, false
    hdr.rects, hdr.texts = {}, {}
    hdr:prerender()
    local tip, base = hdr.rects[2], hdr.rects[5]
    local seller
    for _, tx in ipairs(hdr.texts) do
        if tx.text == "S" then seller = tx end
    end
    check(tip.w == 1 and tip.x == 44 + 3 and base.w == 7 and base.x == 44 and nearly(seller.r, C.textFaint.r),
        "asc＋靠左欄：▲ 畫在標題後 4px；live=false 時非作用中標題 textFaint")

    sortKey = "seller"
    hdr.rects = {}
    hdr:prerender()
    check(#hdr.rects == 1, "sort 指到不可排序欄：不亮、不畫箭頭")

    -- 每幀零配置：幾何沒變時 prerender 不量字、不截字；原地改 specs（沒呼叫 setColumns）下一幀重算
    local cached = UI.TableHeader.new{ width = 200, theme = dark, sort = function() return "name", true end }
    local cs = { { key = "name", title = "Abcdefgh", x = 0, w = 91 } }
    cached:setColumns(cs)
    cached:prerender()
    local keepTM = getTextManager
    local measures = 0
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) measures = measures + 1; return string.len(s) * 10 end,
            getFontHeight = function() return 12 end }
    end
    cached.rects, cached.texts = {}, {}
    cached:prerender()
    local steady = measures
    check(steady == 0 and cached.texts[1].text == "Abcdefgh" and cached.rects[2].x == 84,
        "表頭快取：幾何沒變時 prerender 零量測（不呼叫 Text.fit）")
    cs[1].w = 61
    cached.rects, cached.texts = {}, {}
    cached:prerender()
    getTextManager = keepTM
    check(cached.texts[1].text == "Ab..." and cached.rects[2].x == 54,
        "表頭快取：原地改欄寬（未呼叫 setColumns）下一幀重新截字並移動箭頭")

    local faded = UI.Theme.create()
    faded.alpha = 0.5
    local fh = UI.TableHeader.new{ width = 100, theme = faded, sort = function() return "name", true end }
    fh:setColumns(UI.Table.layoutColumns({ { key = "name", title = "Name" } }, 0, 100, 10))
    fh:prerender()
    check(nearly(fh.rects[1].a, C.well.a * 0.5) and nearly(fh.rects[2].a, 1) and nearly(fh.texts[1].a, 1),
        "theme.alpha：表頭底乘 0.5，箭頭與文字不乘")
end

return 42
