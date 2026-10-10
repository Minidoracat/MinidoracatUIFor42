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

return n
