-- rev 19：Toast 的 title 放不下時換成最多兩行（toastTitleWrap）。量測模型同情境七：每位元組 10px、字高 12，
-- Toast 寬 300 → 一行 284px＝28 字。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev19：Toast 標題換行（最多兩行）")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local Toast = UI.Toast
check(UI.API_REVISION >= 19 and UI.CAPABILITIES.toastTitleWrap == true, "rev 19：toastTitleWrap 翻 true")

Toast._resetForTests()
local short = Toast.show({ title = "Short title", message = "msg" })
check(short.titleText == "Short title" and #short.titleLines == 1 and short.titleLines[1] == "Short title"
    and short.height == 56, "放得下的標題照舊一行、高度不變；titleText 仍是原始標題")

-- 34 字、有空白：在空白處斷成兩行，下一行不以空白開頭，每行都在 284px 內
local title = "aaaa bbbb cccc dddd eeee ffff gggg"
local two = Toast.show({ title = title, message = "msg" })
local fits = true
for _, line in ipairs(two.titleLines) do
    if string.len(line) * 10 > 284 then fits = false end
end
check(two.titleText == title and #two.titleLines == 2 and string.sub(two.titleLines[1], -1) ~= " "
    and string.sub(two.titleLines[2], 1, 1) ~= " " and fits, "超寬標題在空白處斷成兩行、每行都放得下")
check(two.height == 56 + two.fontHeight, "標題多一行，Toast 高一行")

-- 兩行也放不下：停在兩行、第二行帶省略號
local long = Toast.show({ title = string.rep("X", 70), message = "msg" })
check(#long.titleLines == 2 and string.sub(long.titleLines[2], -3) == "..." and string.len(long.titleLines[2]) * 10 <= 284,
    "比兩行還長：停在兩行、第二行帶省略號")

-- 繪製：標題畫在 y=7、7+字高；訊息從第二行標題下面開始（一行標題時是 10+字高，往下移一行）
Toast._resetForTests()
local both = Toast.show({ title = title, message = string.rep("A", 60), maxLines = 3 })
local fh = both.fontHeight
check(#both.lines == 3 and both.height == 56 + fh * (2 + 1), "標題兩行＋訊息三行：高度兩者都算進去")
ctx.advance(300)
both.texts = {}
both:prerender()
local ys = {}
for _, t in ipairs(both.texts) do ys[#ys + 1] = t.y end
check(#ys == 5 and ys[1] == 7 and ys[2] == 7 + fh and ys[3] == 10 + fh * 2 and ys[5] == 10 + fh * 4
    and ys[5] + fh <= both.height, "兩行標題在 7、7+字高，訊息從 10+字高×2 起往下，最後一行在框內")

-- 堆疊：下一則接在兩行標題那則的實際高度下面
Toast._resetForTests()
local a = Toast.show({ title = title, message = "msg" })
local b = Toast.show("next")
ctx.advance(300)
a:prerender()
b:prerender()
check(b.y == a.y + a.height + 8, "下一則接在兩行標題那則的實際高度下面")
Toast._resetForTests()

return n
