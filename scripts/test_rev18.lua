-- rev 18：theme token warning（警示字與圖示；框架元件不讀）＋法文標點空白的斷行禁則。
-- 契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
print("情境 rev18：warning token 的預設值、對比與色相")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

-- WCAG 相對亮度（同 test_rev12）；surface 只看 rgb（深色＝黑底）
local function lum(v)
    return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end
local function gray(c) return 0.2126 * lum(c.r) + 0.7152 * lum(c.g) + 0.0722 * lum(c.b) end
local function ratio(a, b)
    a, b = gray(a), gray(b)
    if a < b then a, b = b, a end
    return (a + 0.05) / (b + 0.05)
end
-- HSV 色相（度）與色環上的距離
local function hue(c)
    local mx, mn = math.max(c.r, c.g, c.b), math.min(c.r, c.g, c.b)
    local d = mx - mn
    if d == 0 then return 0 end
    local h
    if mx == c.r then h = ((c.g - c.b) / d) % 6
    elseif mx == c.g then h = (c.b - c.r) / d + 2
    else h = (c.r - c.g) / d + 4 end
    return h * 60
end
local function hueGap(a, b)
    local d = math.abs(hue(a) - hue(b)) % 360
    return math.min(d, 360 - d)
end
local function same(a, b)
    return a ~= nil and b ~= nil and nearly(a.r, b.r) and nearly(a.g, b.g) and nearly(a.b, b.b) and nearly(a.a, b.a)
end

local dark, light = UI.Theme.defaultPalette("dark"), UI.Theme.defaultPalette("light")
check(UI.API_MAJOR == 1 and UI.API_REVISION >= 18
    and same(dark.warning, { r = 1, g = 0.55, b = 0.2, a = 1 })
    and same(light.warning, { r = 0.70, g = 0.27, b = 0, a = 1 }),
    "rev 18：兩套 palette 都有 warning（深色 #FF8C33、淺色 #B34500）")

-- 名單守門：16 個舊 token＋warning，少一個或多一個都紅（ARCHITECTURE §3.2 的 token 數）
local TOKENS = { "surface", "surfaceTitle", "well", "border", "text", "textMuted", "textFaint", "textDisabled",
    "accent", "hover", "selected", "errorSurface", "errorText", "onAccent", "titleText", "titleMuted", "warning" }
local function exactly(palette)
    local count = 0
    for _ in pairs(palette) do count = count + 1 end
    for _, token in ipairs(TOKENS) do
        if palette[token] == nil then return false end
    end
    return count == #TOKENS
end
check(exactly(dark) and exactly(light), "兩套 palette 的 token 名單＝17 個（16 個舊 token＋warning）")

check(ratio(dark.warning, dark.surface) >= 4.5 and ratio(light.warning, light.surface) >= 4.5,
    "warning 在 surface 上 >= 4.5:1（深色 9.07:1、淺色 4.66:1）")
check(hueGap(dark.warning, dark.accent) >= 15 and hueGap(light.warning, light.accent) >= 15,
    "warning 色相離 accent >= 15 度（深色 18.8、淺色 18.4）")
check(hueGap(dark.warning, dark.errorText) >= 15 and hueGap(light.warning, light.errorText) >= 15,
    "warning 色相離 errorText >= 15 度（警示與錯誤分得開）")

-- Theme.create：預設帶 warning 的拷貝、可覆寫、不污染 default
local t = UI.Theme.create({ variant = "light" })
t.colors.warning.r = 0
local skinned = UI.Theme.create({ colors = { warning = { r = 0.9, g = 0.5, b = 0.1, a = 1 } } })
check(same(UI.Theme.defaultPalette("light").warning, light.warning) and nearly(skinned.colors.warning.r, 0.9)
    and same(UI.Theme.create().colors.warning, dark.warning),
    "Theme.create 拷貝 warning：改實例不污染 default，consumer 可整顆覆寫")

-- ---------- 斷行：法文標點前後的空白不是斷點（Safehouse 法文實機截圖） ----------
-- 量測模型同 test_wrap：ASCII 7px、其他字（é、書名號）14px；用完還原 getTextManager。
local keepTextManager = getTextManager
local function width(text)
    local w = 0
    for ch in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
        w = w + (#ch == 1 and 7 or 14)
    end
    return w
end
getTextManager = function()
    return { MeasureStringX = function(_, _, text) return width(text) end,
        getFontHeight = function() return 12 end }
end

local LAQUO, RAQUO, NBSP = "\194\171", "\194\187", "\194\160"
local function badStart(line)
    local c = string.sub(line, 1, 1)
    return c == ":" or c == ";" or c == "!" or c == "?" or string.sub(line, 1, 2) == RAQUO
end
local function badEnd(line)
    return string.sub(line, -2) == LAQUO
end
-- 行寬從最長的黏住片段（「Interférences :」112px）以上掃到整段放得下：每一行都不得違規、
-- 不得超出行寬，去掉空白後接回去等於原文（沒有吃字）
local function sweep(text, from, to)
    local squash = string.gsub(text, "[ ]", "")
    local starts, ends, over, lost, multi = 0, 0, 0, 0, 0
    for w = from, to, 3 do
        local got = UI.Text.wrap(text, w)
        if #got > 1 then multi = multi + 1 end
        for _, line in ipairs(got) do
            if badStart(line) then starts = starts + 1 end
            if badEnd(line) then ends = ends + 1 end
            if width(line) > w then over = over + 1 end
        end
        if string.gsub(table.concat(got), "[ ]", "") ~= squash then lost = lost + 1 end
    end
    return starts, ends, over, lost, multi
end

local repair = "Derni\195\168re r\195\169paration compl\195\168te : il y a 0 min \226\128\162 \195\128 r\195\169parer : 0"
    .. " \226\128\162 Plus long \195\169cart : 0 s \226\128\162 Interf\195\169rences : 0"
local s1, e1, o1, l1, m1 = sweep(repair, 120, 720)
check(s1 == 0 and o1 == 0 and l1 == 0 and m1 > 100,
    "法文冒號：行寬 120～720 掃一遍，沒有一行以「:」開頭、每行放得下、沒吃字")

local perm = "Vous n'avez pas la permission " .. LAQUO .. " Cultiver " .. RAQUO .. " ici. Quoi ? Oui ! Non ; peut-\195\170tre."
local s2, e2, o2, l2, m2 = sweep(perm, 98, 600) -- 「« Cultiver »」整組 98px
check(s2 == 0 and e2 == 0 and o2 == 0 and l2 == 0 and m2 > 100,
    "法文書名號與 ? ! ;：行寬 98～600 掃一遍，沒有一行以 ? ! ; 右書名號開頭、沒有一行以左書名號結尾")

-- 截點剛好落在黏住的空白上：舊規則會斷成「Total Interférences」／「: 0」與「la permission «」／「Cultiver »」
local both = UI.Text.wrap("Total Interf\195\169rences : 0", 150) -- 「Total Interférences 」147px
local quote = UI.Text.wrap("la permission " .. LAQUO .. " Cultiver " .. RAQUO, 115) -- 「la permission «」112px
check(#both == 2 and both[1] == "Total" and both[2] == "Interf\195\169rences : 0"
    and #quote == 2 and quote[1] == "la permission" and quote[2] == LAQUO .. " Cultiver " .. RAQUO,
    "截點落在黏住的空白：往回找上一個斷點，冒號跟著前面的字、書名號整組換行")
local after = UI.Text.wrap("Interf\195\169rences : 0", 112)
check(#after == 2 and after[1] == "Interf\195\169rences :" and after[2] == "0",
    "冒號後面的空白照常是斷點")

local nb = UI.Text.wrap("Interf\195\169rences" .. NBSP .. ": 0", 120) -- 前段 119px（NBSP 算 14px）
check(#nb == 2 and nb[1] == "Interf\195\169rences" .. NBSP .. ":" and nb[2] == "0",
    "不換行空白 U+00A0 本來就不是斷點：冒號照樣留在本行")

local en = UI.Text.wrap("Go home now", 60)
local hard = UI.Text.wrap(LAQUO .. " aaaaaaaaaa " .. RAQUO, 50)
local hardOk = #hard >= 2
for _, line in ipairs(hard) do
    if line == "" then hardOk = false end
end
check(#en == 2 and en[1] == "Go home" and en[2] == "now" and hardOk,
    "一般空白照常斷；整段只剩黏住的空白時退回硬切（每行都有字、不卡住）")

getTextManager = keepTextManager

-- ---------- 不透明視窗（opts.opaque，CAPABILITIES.opaqueWindow） ----------
local function frame(win)
    win.rects, win.borders, win.texts = {}, {}, {}
    win:prerender()
    return win.rects
end
local darkTheme = UI.Theme.create()
local plain = UI.Window.new{ width = 300, height = 200, title = "W", theme = darkTheme }
local solid = UI.Window.new{ width = 300, height = 200, title = "W", theme = darkTheme, opaque = true }
local pr, sr = frame(plain), frame(solid)
check(UI.CAPABILITIES.opaqueWindow == true and plain.opaque == false and nearly(pr[1].a, 0.8)
    and nearly(pr[2].a, darkTheme.colors.surfaceTitle.a),
    "opaqueWindow 旗標 true；沒帶 opaque 的視窗本體照舊 surface 的 0.8（外觀不變）")
check(nearly(sr[1].a, 1) and nearly(sr[1].r, 0) and nearly(sr[1].g, 0) and nearly(sr[1].b, 0)
    and sr[1].w == 300 and sr[1].h == 200 and nearly(sr[2].a, darkTheme.colors.surfaceTitle.a)
    and nearly(darkTheme.colors.surface.a, 0.8),
    "opaque：本體整塊 surface 色、alpha 1，標題列疊層照舊；theme 的 surface 本身不被改")

local faded = UI.Theme.create({ variant = "light" })
faded.alpha = 0.5
local fsolid = UI.Window.new{ width = 300, height = 200, title = "W", theme = faded, opaque = true }
local fr = frame(fsolid)
local ls = faded.colors.surface
check(nearly(fr[1].a, 1) and nearly(fr[1].r, ls.r) and nearly(fr[1].g, ls.g) and nearly(fr[1].b, ls.b)
    and nearly(fr[2].a, faded.colors.surfaceTitle.a * 0.5),
    "opaque 不乘 theme.alpha（淺色 surface 色、alpha 1）；標題列疊層照樣乘 theme.alpha")

faded.colors.surface = { r = 0.2, g = 0.3, b = 0.4, a = 0.6 }
local late = UI.Window.new{ width = 300, height = 200, title = "W", theme = faded }
late.opaque = true
local lr, fr2 = frame(late), frame(fsolid)
check(nearly(fr2[1].r, 0.2) and nearly(fr2[1].b, 0.4) and nearly(fr2[1].a, 1)
    and nearly(lr[1].g, 0.3) and nearly(lr[1].a, 1),
    "consumer 事後換 surface 色下一幀跟上；建構後才把 opaque 設成 true 也照樣不透明")

local d1 = UI.Dialog.show{ title = "T", text = "a", confirmText = "OK" }
local d1a = frame(d1)[1].a
UI.Dialog.close(d1, false)
local d2 = UI.Dialog.show{ title = "T", text = "a", confirmText = "OK", opaque = true }
local d2a = frame(d2)[1].a
UI.Dialog.close(d2, false)
check(nearly(d1a, 0.8) and nearly(d2a, 1), "Dialog.show：預設照舊 0.8，帶 opaque 本體 alpha 1")

local noop = function() end
solid.drawRect, solid.drawRectBorder, solid.drawText = noop, noop, noop
local keepCore = getCore -- stub 每次回新表：量測期間固定成同一張
local core = keepCore()
getCore = function() return core end
collectgarbage("collect")
collectgarbage("stop")
solid:prerender()
local kb = collectgarbage("count")
for _ = 1, 50 do solid:prerender() end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
getCore = keepCore
solid.drawRect, solid.drawRectBorder, solid.drawText = nil, nil, nil
check(grew == 0, "opaque 視窗 prerender 50 輪不配置記憶體")

-- ---------- 彈出清單跟著不透明視窗（opaquePopup） ----------
-- 量測 stub 每次回新表：整段固定成同一張（零配置量測才準），結束還原
local keepTM, keepCore2 = getTextManager, getCore
local tm0, core0 = keepTM(), keepCore2()
getTextManager = function() return tm0 end
getCore = function() return core0 end
dofile(ctx.MOD_LUA .. "Widgets/Dropdown.lua")
dofile(ctx.MOD_LUA .. "Widgets/DatePicker.lua")
dofile(ctx.MOD_LUA .. "Widgets/FilterBar.lua")
dofile(ctx.MOD_LUA .. "Widgets/Autocomplete.lua")
local DD, DP, FB, AC = UI.Dropdown, UI.DatePicker, UI.FilterBar, UI.Autocomplete

-- 彈出面板本體＝prerender 的第一筆填色（E0 環境走 drawRect）
local function body(panel)
    panel.rects, panel.borders, panel.texts = {}, {}, {}
    panel:prerender()
    return panel.rects[1] or { a = -1 }
end
local function newWin(isOpaque)
    local win = UI.Window.new{ x = 0, y = 0, width = 600, height = 400, title = "W", opaque = isOpaque }
    win:addToUIManager()
    return win
end
local opaqueWin, semiWin = newWin(true), newWin(false)
local host = ISPanel.new(ISPanel, 0, 0, 600, 400) -- 不在視窗裡的容器
local OPTS = { { id = 1, label = "One" }, { id = 2, label = "Two" } }

-- Dropdown
local function ddBody(parent, explicit)
    local dd = DD.new{ x = 10, y = 40, options = OPTS, opaque = explicit }
    if parent then parent:addChild(dd) end
    dd:open()
    local a = body(DD._popupForTests()).a
    DD.close()
    return a
end
local ddOpaque, ddSemi, ddExplicit, ddLoose = ddBody(opaqueWin), ddBody(semiWin), ddBody(nil, true), ddBody(host)
check(UI.CAPABILITIES.opaquePopup == true and nearly(ddOpaque, 1) and nearly(ddSemi, 0.8) and nearly(ddExplicit, 1)
    and nearly(ddLoose, 0.8),
    "Dropdown 清單：不透明視窗裡 alpha 1、半透明視窗裡照舊 0.8、opts.opaque 單獨用 1、一般容器照舊")

-- DateField 的月曆
local function dateBody(parent, explicit)
    local f = UI.DateField.new{ x = 10, y = 40, text = "2026-09-07", opaque = explicit }
    if parent then parent:addChild(f) end
    f._button:forceClick()
    local a = body(DP._popupForTests()).a
    DP.close()
    return a
end
local dOpaque, dSemi, dExplicit = dateBody(opaqueWin), dateBody(semiWin), dateBody(host, true)
check(nearly(dOpaque, 1) and nearly(dSemi, 0.8) and nearly(dExplicit, 1),
    "月曆：不透明視窗裡 alpha 1、半透明視窗裡照舊 0.8、opts.opaque 在一般容器裡也是 1")

-- FilterBar 的類型選單與日期欄的月曆（opts.opaque 連月曆一起）
local KIND_ROWS = { { kind = "a" }, { kind = "b" } }
local function newBar(parent, explicit)
    local bar = FB.new{ parent = parent, onChange = function() end, kindsDropdown = true, opaque = explicit,
        kinds = { field = "kind", label = string.upper, multi = true }, dates = { field = "ts" },
        sorts = { { id = "time", field = "ts" } } }
    bar:syncKinds(KIND_ROWS)
    bar:layout(0, 30, 1000, true)
    return bar
end
local function menuBody(bar)
    bar._ddButton:forceClick()
    local m = FB._menuForTests()
    local a = m and m:getIsVisible() and body(m).a or -1
    bar._ddButton:forceClick() -- 同一顆再按＝關閉
    return a
end
local function barDateBody(bar)
    bar._from._button:forceClick()
    local a = body(DP._popupForTests()).a
    DP.close()
    return a
end
local barOpaque, barSemi, barExplicit = newBar(opaqueWin), newBar(semiWin), newBar(host, true)
check(nearly(menuBody(barOpaque), 1) and nearly(menuBody(barSemi), 0.8) and nearly(menuBody(barExplicit), 1),
    "FilterBar 類型選單：不透明視窗裡 alpha 1、半透明視窗裡照舊 0.8、opts.opaque 在一般容器裡也是 1")
check(nearly(barDateBody(barOpaque), 1) and nearly(barDateBody(barSemi), 0.8) and nearly(barDateBody(barExplicit), 1),
    "FilterBar 的日期月曆同一規則（opts.opaque 也作用在兩個日期欄）")

-- Autocomplete 的下拉（掛在容器裡的子元件，顯示時判斷）
local function newAc(parent, explicit)
    local ac = AC.new{ width = 200, opaque = explicit, onQuery = function() return true end, onPick = function() end }
    ac:addTo(parent)
    ac:layout(10, 40, 200, 300)
    ac.field._entry:focus()
    ac.field:prerender() -- 第一次聚焦立刻查
    ac:setResults(ac:getText(), { { name = "alice" }, { name = "bob" } })
    ac.field:prerender()
    return ac
end
local acOpaque, acSemi, acExplicit = newAc(opaqueWin), newAc(semiWin), newAc(host, true)
check(acOpaque.list:getIsVisible() and nearly(body(acOpaque.list).a, 1) and nearly(body(acSemi.list).a, 0.8)
    and nearly(body(acExplicit.list).a, 1),
    "Autocomplete 下拉：不透明視窗裡 alpha 1、半透明視窗裡照舊 0.8、opts.opaque 在一般容器裡也是 1")

-- 開啟時決定一次；換 theme 色下一幀跟上
local late = DD.new{ x = 10, y = 40, options = OPTS, theme = UI.Theme.create() }
semiWin:addChild(late)
late:open()
local lp = DD._popupForTests()
semiWin.opaque = true
local stillSemi = body(lp).a
DD.close()
late:open()
local reopened = body(lp).a
late.theme.colors.surface = { r = 0.2, g = 0.3, b = 0.4, a = 0.5 }
local recolored = body(lp)
semiWin.opaque = false
check(nearly(stillSemi, 0.8) and nearly(reopened, 1),
    "開啟時才沿 parent 找視窗：開著時把視窗改成不透明不影響這次清單，重開才跟上")
check(nearly(recolored.r, 0.2) and nearly(recolored.g, 0.3) and nearly(recolored.b, 0.4) and nearly(recolored.a, 1),
    "不透明清單每幀讀 theme 的 surface：consumer 換色下一幀跟上，alpha 仍是 1")

-- 零配置：開著的不透明 Dropdown 清單與 Autocomplete 下拉各 50 幀
local function noAlloc(panel)
    local noop2 = function() end
    panel.drawRect, panel.drawRectBorder, panel.drawText = noop2, noop2, noop2
    collectgarbage("collect")
    collectgarbage("stop")
    panel:prerender()
    local before = collectgarbage("count")
    for _ = 1, 50 do panel:prerender() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    panel.drawRect, panel.drawRectBorder, panel.drawText = nil, nil, nil
    return grown
end
local grewDD = noAlloc(lp)
DD.close()
local grewAC = noAlloc(acOpaque.list)
check(grewDD == 0 and grewAC == 0, "不透明的 Dropdown 清單與 Autocomplete 下拉 prerender 50 幀不配置記憶體")
getTextManager, getCore = keepTM, keepCore2

return n
