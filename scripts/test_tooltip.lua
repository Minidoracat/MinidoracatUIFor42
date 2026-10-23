-- 控制項說明框（原版 ISToolTip）的中日文斷行與不透明底：TextWrap.tooltip／fixTooltip 接在 Button、Checkbox、Slider、
-- SliderRow、Dropdown、TileGrid 的 ISButton:updateTooltip 之後，以及 TextField 的 render。契約見 smoke_harness.lua 的切片載入器註解。
-- 量測模型同 test_wrap.lua：ASCII 7px、其他字 14px、字高 12 → 原版行寬 300 × 12／15＝240px（17 個中文字）。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 tooltip：說明框的中日文斷行、快取與不透明底")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local function width(text)
    local w = 0
    for ch in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
        w = w + (#ch == 1 and 7 or 14)
    end
    return w
end
local keepTextManager = getTextManager
getTextManager = function()
    return { MeasureStringX = function(_, _, text) return width(text) end, getFontHeight = function() return 12 end }
end
local tipFont = UIFont.Small
local keepToolTip = ISToolTip
ISToolTip = { GetFont = function() return tipFont end }

-- 忠於 ISButton.lua:316-346：hover 或手把焦點時建提示框、每幀把 tooltip 原文寫進 description
local keepUpdate = ISButton.updateTooltip
function ISButton.updateTooltip(el)
    if (el:isMouseOver() or el.joypadFocused) and el.tooltip then
        el.tooltipUI = el.tooltipUI or { backgroundColor = { r = 0, g = 0, b = 0, a = 0 } }
        el.tooltipUI.maxLineWidth = string.find(el.tooltip, "\n", 1, true) and 1000 or 300
        el.tooltipUI.description = el.tooltip
    end
end

local TW = require("MinidoracatUI/TextWrap")
local keepLines, wraps = TW.lines, 0
TW.lines = function(...)
    wraps = wraps + 1
    return keepLines(...)
end

local LIMIT = 240
local SEP = " <LINE> "
local function split(desc)
    local parts, start = {}, 1
    while true do
        local i, j = string.find(desc, SEP, start, true)
        if not i then
            parts[#parts + 1] = string.sub(desc, start)
            return parts
        end
        parts[#parts + 1] = string.sub(desc, start, i - 1)
        start = j + 1
    end
end
local function wrappedOK(desc, original, minLines)
    local parts = split(desc)
    if #parts < minLines or table.concat(parts) ~= original then return false end
    for _, p in ipairs(parts) do
        if width(p) > LIMIT then return false end
    end
    return true
end

-- 地圖手錶「穿長袖時顯示地圖手錶」的 CH／JP 說明（2026-10-23 實機截圖一行約 700px）
local CH = "開啟：地圖手錶戴在袖子外，穿外套、毛衣也看得到。關閉：跟原版手錶一樣被長袖蓋住。只影響你的畫面，所有人的地圖手錶都照這個設定。"
local JP = "オン：マップウォッチを袖の上に着けるので、ジャケットやセーターを着ても見えます。オフ：バニラの腕時計と同じく長袖に隠れます。"
local EN = "On: map watches sit over the sleeve, so jackets and sweaters don't hide them. Off: long sleeves cover them, like vanilla watches."
local RU = "Вкл.: часы-карта надеваются поверх рукава, их видно под куртками и свитерами."

local box = UI.Checkbox.new{ x = 10, y = 10, label = "Box", tooltip = CH }
box._mouseOver = true
box:prerender()
local first = box.tooltipUI and box.tooltipUI.description
check(first ~= nil and wrappedOK(first, CH, 4) and box.tooltipUI.maxLineWidth == 300,
    "Checkbox：中文說明斷成多行、以 <LINE> 接起，每行不超過 240px，接回去就是原文；maxLineWidth 照原版 300")
check(box.tooltip == CH, "原始 tooltip 不變（Focus 的說明讀它）")
local before = wraps
box:prerender()
box:prerender()
check(wraps == before and box.tooltipUI.description == first, "同一段文字下一幀不重算，直接用快取")
tipFont = UIFont.Medium
box:prerender()
check(wraps == before + 1, "說明框字型換了（選項的 tooltip 字型）才重算")
tipFont = UIFont.Small
box:setTooltip(JP)
box:prerender()
check(wraps == before + 2 and wrappedOK(box.tooltipUI.description, JP, 4), "文字換了就重算：日文也斷成多行")
box._mouseOver = false
box.tooltipUI.description = "kept"
box:prerender()
check(box.tooltipUI.description == "kept", "沒有 hover 也沒有手把焦點：不碰提示框（同原版只在顯示時寫）")

local en = UI.Button.new{ x = 0, y = 0, title = "Go", tooltip = EN }
en._mouseOver = true
en:prerender()
local ru = UI.Slider.new{ x = 0, y = 0, width = 100, min = 0, max = 1, tooltip = RU }
ru._mouseOver = true
ru:prerender()
check(width(EN) > LIMIT and en.tooltipUI.description == EN and width(RU) > LIMIT and ru.tooltipUI.description == RU,
    "Button 的英文、Slider 的俄文：比行寬長也照原樣交給原版（原版在空白換行）")

local marked = "第一行說明文字比較短 <LINE> 第二行說明文字很長很長很長很長很長很長很長很長很長很長很長很長"
local nl = "第一行說明文字比較短\n第二行說明文字很長很長很長很長很長很長很長很長很長很長很長很長"
local row = UI.SliderRow.new{ x = 0, y = 0, width = 300, label = "Dist", min = 0, max = 10, tooltip = marked }
row._mouseOver = true
row:prerender()
local rowFirst = row.tooltipUI.description
row:setTooltip(nl)
row:prerender()
check(rowFirst == marked and row.tooltipUI.description == nl and row.tooltipUI.maxLineWidth == 1000,
    "SliderRow：已含 <LINE> 或 \\n 的說明不重複處理（\\n 照原版放到 1000、不換行）")

local short = UI.Checkbox.new{ x = 0, y = 0, label = "S", tooltip = "顯示地圖手錶" }
short.joypadFocused = true
short:prerender()
check(short.tooltipUI.description == "顯示地圖手錶", "放得下的中文說明不動；手把焦點時同樣走這條路")

-- TextField：原生 entry 的 prerender 寫原文，元件的 render 在子元件之後換成斷好行的
local field = UI.TextField.new{ x = 0, y = 0, width = 200 }
field:setTooltip(CH)
local entry = field._entry
entry._mouseOver = true
entry.tooltipUI = { description = entry.tooltip, backgroundColor = { r = 0, g = 0, b = 0, a = 0 } }
field:render()
check(wrappedOK(entry.tooltipUI.description, CH, 4) and entry.tooltip == CH,
    "TextField：說明框換成斷好行的版本，entry.tooltip 照舊是原文")

-- Dropdown、TileGrid（重新載入一次：前面的切片可能換過它們的依賴）
dofile(ctx.MOD_LUA .. "Widgets/Dropdown.lua")
dofile(ctx.MOD_LUA .. "Widgets/TileGrid.lua")
local dd = UI.Dropdown.new{ x = 0, y = 0, width = 160, options = { { id = "a", label = "A" } }, tooltip = JP }
dd._mouseOver = true
dd:prerender()
local tg = UI.TileGrid.new{ x = 0, y = 0, width = 340, height = 200, tileW = 100, tileH = 80,
    tooltip = function() return CH end }
tg:setItems({ { name = "a" }, { name = "b" } })
tg._mouseOver = true
ctx.setMouse(50, 40)
tg:prerender()
local chBtn = UI.Button.new{ x = 0, y = 0, title = "Go", tooltip = CH }
chBtn._mouseOver = true
chBtn:prerender()
check(wrappedOK(dd.tooltipUI.description, JP, 4) and wrappedOK(tg.tooltipUI.description, CH, 4)
    and wrappedOK(chBtn.tooltipUI.description, CH, 4), "Dropdown、TileGrid 與 Button 的說明同樣斷好行")

-- 不透明視窗（rev 18 opts.opaque）裡的說明框也不透明；一般視窗照原版透明底
local solid = UI.Window.new{ width = 300, height = 200, title = "W", opaque = true }
local plain = UI.Window.new{ width = 300, height = 200, title = "W" }
local inSolid = UI.Checkbox.new{ x = 10, y = 40, label = "A", tooltip = EN }
local inPlain = UI.Checkbox.new{ x = 10, y = 40, label = "B", tooltip = EN }
solid:addChild(inSolid)
plain:addChild(inPlain)
inSolid._mouseOver, inPlain._mouseOver = true, true
inSolid:prerender()
inPlain:prerender()
check(inSolid.tooltipUI.backgroundColor.a == 1 and inPlain.tooltipUI.backgroundColor.a == 0,
    "不透明視窗裡的說明框底改成不透明；半透明視窗的照原版")

ISButton.updateTooltip = keepUpdate
TW.lines = keepLines
ISToolTip = keepToolTip
getTextManager = keepTextManager

return 12
