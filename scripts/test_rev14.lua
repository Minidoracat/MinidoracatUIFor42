-- rev 14：12 個幾何圖示 key、theme token onAccent／titleText／titleMuted、Button／Window 的 Texture 圖示、
-- Button:setIcon。Dropdown 在 test_rev14_dropdown.lua。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
print("情境 rev14：圖示 key／標題列與 accent token／Texture 圖示／setIcon")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

-- ISPanel stub 沒有 drawTextureScaled：本切片暫時補上（紀錄進 self.tex），結束還原
local keepDrawTexture = ISPanel.drawTextureScaled
function ISPanel:drawTextureScaled(tex, x, y, w, h, a, r, g, b)
    self.tex = self.tex or {}
    self.tex[#self.tex + 1] = { tex = tex, x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end
local keepGetTexture = getTexture
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()

local function reset(el)
    el.rects, el.borders, el.texts, el.tex = {}, {}, {}, {}
end

-- ---------- facade ----------
check(UI.API_MAJOR == 1 and UI.API_REVISION >= 14 and UI.CAPABILITIES.dropdown ~= nil,
    "rev 14：API_REVISION >= 14、CAPABILITIES 有 dropdown 旗標")

-- ---------- Icons：12 個新 key 對到約定檔名、各不相同 ----------
local files = {
    battery = "battery", lightbulb = "lightbulb", card = "card", screwdriver = "screwdriver",
    insert = "insert", eject = "eject", plus = "plus", check = "check", clock = "clock",
    pause = "pause", warning = "warning", infinity = "infinity",
}
local mapped, seen, distinct = true, {}, 0
for key, file in pairs(files) do
    local t = UI.Icons.get(key)
    mapped = mapped and t ~= nil and t.path == "media/ui/MinidoracatUI/mui_icon_" .. file .. ".png"
    if t and not seen[t.path] then
        seen[t.path] = true
        distinct = distinct + 1
    end
end
check(mapped and distinct == 12, "rev 14：十二個 key 各自對到 mui_icon_<key>.png")
check(UI.Icons.get("lock") ~= nil and UI.Icons.get("close").path == "media/ui/MinidoracatUI/mui_icon_close.png",
    "既有 key 不受影響")

-- ---------- Theme：新 token 的預設值等於 rev 13 的實際繪製色 ----------
local function same(a, b)
    return a ~= nil and b ~= nil and nearly(a.r, b.r) and nearly(a.g, b.g) and nearly(a.b, b.b) and nearly(a.a, b.a)
end
local dark, light = UI.Theme.defaultPalette("dark"), UI.Theme.defaultPalette("light")
check(same(dark.titleText, dark.text) and same(dark.titleMuted, dark.textMuted)
    and same(light.titleText, light.text) and same(light.titleMuted, light.textMuted),
    "titleText／titleMuted 預設＝text／textMuted（兩套 palette，視窗外觀不變）")
check(same(dark.onAccent, { r = 0.1, g = 0.08, b = 0.02, a = 1 }) and same(light.onAccent, dark.onAccent),
    "onAccent 預設＝rev 13 primary 按鈕的深色字常數")

-- ---------- Button：primary 字讀 onAccent ----------
local WHITE = { r = 1, g = 1, b = 1, a = 1 }
local paws = UI.Theme.create({ variant = "light", colors = { accent = { r = 0.69, g = 0.23, b = 0.42, a = 1 }, onAccent = WHITE } })
local primary = UI.Button.new{ title = "Go", style = "primary", theme = paws }
primary:prerender()
check(nearly(primary.rects[1].r, 0.69) and nearly(primary.texts[1].r, 1) and nearly(primary.texts[1].g, 1),
    "primary：accent 底上的字改讀 onAccent（深色 accent 配白字）")
local raw = { colors = {} }
for k, v in pairs(UI.Theme.defaultPalette("dark")) do raw.colors[k] = v end
raw.colors.onAccent, raw.colors.titleText, raw.colors.titleMuted = nil, nil, nil
local legacy = UI.Button.new{ title = "Go", style = "primary", theme = raw }
legacy:prerender()
check(nearly(legacy.texts[1].r, 0.1) and nearly(legacy.texts[1].b, 0.02),
    "theme 缺 onAccent（不是 create 建的）：退回原本的深色字常數，不炸")

-- ---------- Button：Texture 圖示（原色）與 Icons key（染色） ----------
local itemTex = { name = "Base.WatchModule" }
local tb = UI.Button.new{ title = "AB", icon = itemTex }
check(tb.width == 20 + 20 + 16 + 6, "Texture 圖示：自動寬度＝標題＋內距＋圖示 16＋間距 6（同 Icons key）")
tb:prerender()
local d = tb.tex[1]
check(#tb.tex == 1 and d.tex == itemTex and d.w == 16 and d.h == 16 and d.r == 1 and d.g == 1 and d.b == 1
    and nearly(d.a, 1), "Texture 圖示原色畫（頂點色全白、alpha 1、16px）")
check(tb.texts[1].x == d.x + 16 + 6, "Texture 圖示在標題左側、隔 6px")
tb:setEnabled(false)
reset(tb)
tb:prerender()
check(nearly(tb.tex[1].a, 0.45) and tb.tex[1].r == 1, "停用：原色貼圖無法改色，改以 0.45 淡化")

local kb = UI.Button.new{ title = "AB", icon = "battery", style = "danger" }
kb:prerender()
check(#kb.tex == 1 and kb.tex[1].tex.path == "media/ui/MinidoracatUI/mui_icon_battery.png"
    and nearly(kb.tex[1].r, 0.9) and nearly(kb.tex[1].g, 0.35), "Icons key 照舊以字色（danger＝errorText）染色")

local broken = UI.Button.new{ title = "AB", icon = itemTex }
broken.drawTextureScaled = function() error("simulated draw failure") end
local okDraw = pcall(broken.prerender, broken)
check(okDraw and broken.texts[1] ~= nil and broken.texts[1].text == "AB",
    "Texture 繪製拋錯被攔下：標題照畫、不外洩錯誤")

-- ---------- Button:setIcon ----------
local sb = UI.Button.new{ title = "AB" }
local plainW = sb.width
sb:setIcon(itemTex)
check(sb.width == plainW + 16 + 6 and sb.icon == itemTex, "setIcon：自動寬度加上圖示與間距")
sb:setIcon(itemTex)
check(sb.width == plainW + 22, "setIcon 相同值 no-op")
sb:setIcon("plus")
reset(sb)
sb:prerender()
check(sb.tex[1].tex.path == "media/ui/MinidoracatUI/mui_icon_plus.png", "setIcon 換成 Icons key 後下一幀改畫該 key")
sb:setIcon(nil)
reset(sb)
sb:prerender()
check(sb.width == plainW and #sb.tex == 0, "setIcon(nil)：拿掉圖示、寬度縮回")

local fixed = UI.Button.new{ title = "ABCDEF", width = 80 }
fixed:prerender()
check(fixed._fitTitle == "ABCDEF" and fixed.tooltip == nil, "明示寬度 80：沒有圖示時標題放得下")
fixed:setIcon(itemTex)
reset(fixed)
fixed:prerender()
check(fixed.width == 80 and fixed._fitTitle == "A..." and fixed.tooltip == "ABCDEF",
    "明示寬度：setIcon 後下一幀依扣掉圖示的寬度重新截字並自動 tooltip")
fixed:setIcon(nil)
reset(fixed)
fixed:prerender()
check(fixed._fitTitle == "ABCDEF" and fixed.tooltip == nil, "拿掉圖示後標題恢復、自動 tooltip 收掉")

local unknown = UI.Button.new{ title = "AB", icon = "noSuchIcon" }
unknown:prerender()
check(unknown.tex == nil and unknown.texts[1].text == "AB", "未知 key：只畫文字（rev 7 行為不變）")

-- ---------- Window：Texture 標題圖示、titleText／titleMuted ----------
local valutech = UI.Theme.create({ colors = {
    surfaceTitle = { r = 0.79, g = 0.80, b = 0.83, a = 1 },
    titleText = { r = 0.12, g = 0.12, b = 0.13, a = 1 },
    titleMuted = { r = 0.24, g = 0.25, b = 0.27, a = 1 },
} })
getTexture = nil -- 關閉鈕走文字退回，方便讀顏色；標題 Texture 圖示不經 getTexture
UI.Skin._resetForTests()
local win = UI.Window.new{ x = 0, y = 0, width = 300, height = 200, title = "Watch", icon = itemTex, theme = valutech }
win:prerender()
local wt = win.tex[1]
check(#win.tex == 1 and wt.tex == itemTex and wt.w == 16 and wt.r == 1 and nearly(wt.a, 1),
    "Window：Texture 標題圖示原色 16px")
local title = win.texts[#win.texts]
check(title.text == "Watch" and nearly(title.r, 0.12) and title.x == wt.x + 16 + 6,
    "Window：標題字讀 titleText、接在圖示後")
reset(win)
ctx.setMouse(0, 0)
win._mouseOver = false
win:render()
local closeIdle = win.texts[1]
check(closeIdle ~= nil and closeIdle.text == "x" and nearly(closeIdle.r, 0.24), "關閉鈕閒置讀 titleMuted")
reset(win)
ctx.setMouse(win.width - 4, 4)
win._mouseOver = true
win:render()
check(nearly(win.texts[1].r, 0.12), "關閉鈕 hover 讀 titleText")
win._mouseOver = false

local old = UI.Window.new{ x = 0, y = 0, width = 300, height = 200, title = "Old", theme = raw }
old:prerender()
old:render()
check(nearly(old.texts[1].r, 1) and nearly(old.texts[2].r, 0.62),
    "theme 缺 titleText／titleMuted：退回 text／textMuted（rev 13 外觀）")

local keyWin = UI.Window.new{ x = 0, y = 0, width = 300, height = 200, title = "K", icon = "noSuchIcon" }
keyWin:prerender()
check(keyWin.tex == nil and keyWin.texts[1].x == 8, "Window 未知 icon key：不畫圖示、標題不位移")

getTexture = keepGetTexture
ISPanel.drawTextureScaled = keepDrawTexture
UI.Skin._resetForTests()
return n
