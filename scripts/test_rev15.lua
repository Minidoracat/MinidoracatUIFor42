-- rev 15：可選圓角（Skin 半徑形狀與往下退、Skin.shapeOf、Theme 的 radius／controlRadius／buttonShape／font）、
-- 元件跟著 theme 的圓角與字型、沒設時與 rev 14 相同。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev15：可選圓角與 theme 字型")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local Skin = UI.Skin

-- NinePatchTexture stub：每次 render 記下貼圖名與尺寸（切片結束還原成 E0）
local draws = {}
local keepNPT = NinePatchTexture
NinePatchTexture = {
    getSharedTexture = function(path)
        local name = string.match(path, "([^/]+)$")
        return { name = name, render = function(self, x, y, w, h) draws[#draws + 1] = { name = self.name, w = w, h = h } end }
    end,
}
Skin._resetForTests()
local function take()
    local out = draws
    draws = {}
    return out
end
local function names()
    local list = take()
    local s = {}
    for i = 1, #list do s[i] = list[i].name end
    return table.concat(s, ",")
end
local WHITE = { r = 1, g = 1, b = 1, a = 1 }

check(UI.API_MAJOR == 1 and UI.API_REVISION >= 15 and type(Skin.shapeOf) == "function",
    "rev 15：API_REVISION >= 15、Skin.shapeOf 存在")

-- ---------- Skin.shapeOf ----------
local legacy = UI.Theme.create()
check(Skin.shapeOf(legacy, "panel") == nil and Skin.shapeOf(legacy, "control") == nil
    and Skin.shapeOf(legacy, "button") == nil and Skin.shapeOf(legacy, "title") == "roundTop"
    and Skin.shapeOf(nil, "panel") == nil and Skin.shapeOf(nil, "title") == "roundTop",
    "沒設圓角（或沒有 theme）：回 legacy 形狀（nil／roundTop），rev 14 外觀")
local snaps = { { 0, "rect" }, { 1, "rect" }, { 2, "round3" }, { 4, "round3" }, { 5, "round6" }, { 8, "round6" },
    { 9, "round10" }, { 15, "round10" }, { 16, "round20" }, { 999, "round20" } }
local snapOk = true
for _, s in ipairs(snaps) do
    snapOk = snapOk and Skin.shapeOf({ radius = s[1] }, "panel") == s[2]
end
check(snapOk, "radius 吸附到最近的支援值（0／3／6／10／20，中點歸小）")
check(Skin.shapeOf({ radius = 20 }, "title") == "roundTop20" and Skin.shapeOf({ radius = 3 }, "title") == "roundTop3"
    and Skin.shapeOf({ radius = 0 }, "title") == "rect", "title：上圓下直的同半徑形狀，0＝直角")
local split = { radius = 20, controlRadius = 3 }
check(Skin.shapeOf(split, "panel") == "round20" and Skin.shapeOf(split, "control") == "round3"
    and Skin.shapeOf(split, "button") == "round3", "controlRadius 只影響 control／button，panel 用 radius")
check(Skin.shapeOf({ buttonShape = "pill" }, "button") == "round20" and Skin.shapeOf({ buttonShape = "pill" }, "control") == nil,
    "buttonShape=\"pill\"：button 是整顆膠囊（round20 往下退），其他部位不受影響")
check(Skin.shapeOf({ radius = "6" }, "panel") == nil, "radius 不是數字：當沒設（legacy）")

-- ---------- 半徑形狀往下退 ----------
local el = ctx.newElement(0, 0)
Skin.fill(el, 0, 0, 100, 50, WHITE, "round20")
Skin.fill(el, 0, 0, 100, 30, WHITE, "round20")
Skin.fill(el, 0, 0, 100, 14, WHITE, "round20")
Skin.fill(el, 0, 0, 100, 8, WHITE, "round20")
check(names() == "mui_round20_fill.png,mui_pill_fill.png,mui_round_fill.png,mui_round3_fill.png",
    "round20 放不下依序退 10（pill 資產）→ 6 → 3")
local rectsBefore = #el.rects
Skin.fill(el, 0, 0, 100, 5, WHITE, "round20")
check(#take() == 0 and #el.rects == rectsBefore + 1, "連 3 都放不下（高 5）：直角 drawRect")
Skin.border(el, 0, 0, 100, 20, WHITE, "roundTop20")
Skin.border(el, 0, 0, 100, 19, WHITE, "roundTop20")
Skin.border(el, 0, 0, 30, 24, WHITE, "roundTop20")
check(names() == "mui_roundtop20_border.png,mui_roundtop10_border.png,mui_roundtop10_border.png",
    "roundTop：高 >= r、寬 >= 2r 才用該級；border 走 border 資產")
Skin.fill(el, 0, 0, 100, 8, WHITE, nil)
Skin.fill(el, 0, 0, 100, 8, WHITE, "pill")
check(#take() == 0, "legacy round／pill 放不下仍直接直角（行為不變，不往下退）")
check(Skin.fits(100, 8, "round20") == true and Skin.fits(100, 5, "round20") == false and Skin.fits(100, 8, nil) == false,
    "Skin.fits：半徑形狀任一級放得下就是 true；legacy 不變")

-- ---------- Theme.create ----------
local t = UI.Theme.create({ radius = 20, controlRadius = 10, buttonShape = "pill", font = UIFont.Medium })
check(t.radius == 20 and t.controlRadius == 10 and t.buttonShape == "pill" and t.font == UIFont.Medium
    and legacy.radius == nil and legacy.font == nil, "Theme.create 收 radius／controlRadius／buttonShape／font，預設都是 nil")

-- ---------- 元件跟著 theme ----------
take()
local b0 = UI.Button.new({ title = "Go", style = "primary" })
b0:prerender()
check(names() == "mui_round_fill.png,mui_round_border.png", "Button 沒設圓角：6px 圓角（rev 14）")
local b3 = UI.Button.new({ title = "Go", theme = UI.Theme.create({ radius = 3 }) })
b3:prerender()
check(names() == "mui_round3_fill.png,mui_round3_border.png", "Button radius 3：3px 圓角")
local pill = UI.Theme.create({ radius = 20, controlRadius = 10, buttonShape = "pill" })
local bp = UI.Button.new({ title = "Go", theme = pill })
bp:prerender()
local bpDraws = take()
check(bp.height == 22 and bpDraws[1].name == "mui_pill_fill.png", "buttonShape pill、高 22：退到半徑 10（近似整顆膠囊）")
local bp44 = UI.Button.new({ title = "Go", height = 44, theme = pill })
bp44:prerender()
check(take()[1].name == "mui_round20_fill.png", "buttonShape pill、高 44：半徑 20 的整顆膠囊")
local chip = UI.Button.new({ title = "C", style = "chip", active = true, theme = UI.Theme.create({ radius = 3 }) })
chip:prerender()
check(take()[1].name == "mui_pill_fill.png", "chip 固定 pill，不跟 theme 圓角")

local w0 = UI.Window.new({ x = 0, y = 0, width = 300, height = 200, title = "W" })
w0:prerender()
w0:render()
check(names() == "mui_round_fill.png,mui_roundtop_fill.png,mui_round_border.png", "Window 沒設圓角：rev 14 的 round／roundTop")
local w20 = UI.Window.new({ x = 0, y = 0, width = 300, height = 200, title = "W", theme = UI.Theme.create({ radius = 20 }) })
w20:prerender()
w20:render()
check(names() == "mui_round20_fill.png,mui_roundtop20_fill.png,mui_round20_border.png", "Window radius 20：本體、標題列、外框都是 20")
local wr = UI.Window.new({ x = 0, y = 0, width = 300, height = 200, title = "W", theme = UI.Theme.create({ radius = 0 }) })
wr:prerender()
wr:render()
check(#take() == 0, "Window radius 0：全部直角")

local tf = UI.TextField.new({ x = 0, y = 0, width = 120, theme = UI.Theme.create({ radius = 3 }) })
tf:prerender()
check(names() == "mui_round3_fill.png,mui_round3_border.png", "TextField 跟 control 圓角")
local tabs = UI.Tabs.new({ items = { { id = "a", label = "A" }, { id = "b", label = "B" } }, selected = "a",
    theme = UI.Theme.create({ radius = 20, controlRadius = 3 }) })
tabs:prerender()
check(names() == "mui_round3_fill.png,mui_round3_border.png,mui_round3_fill.png", "Tabs 外框與選中項跟 controlRadius")
local dd = UI.Dropdown.new({ options = { { id = 1, label = "x" } }, theme = UI.Theme.create({ radius = 3 }) })
dd:prerender()
check(names() == "mui_round3_fill.png,mui_round3_border.png", "Dropdown 跟 control 圓角")

local box = UI.Checkbox.new({ x = 0, y = 0, width = 100, height = 14, label = "L", checked = true,
    theme = UI.Theme.create({ radius = 3 }) })
box:prerender()
check(names() == "mui_round3_border.png,mui_round3_fill.png", "Checkbox 方框退回（高 < 20）跟 control 圓角")
local box0 = UI.Checkbox.new({ x = 0, y = 0, width = 100, height = 14, label = "L", checked = true })
box0:prerender()
check(#take() == 0 and #box0.borders == 1, "Checkbox 沒設圓角：方框維持直角 drawRectBorder（rev 14）")

local s3 = UI.Slider.new({ min = 0, max = 10, value = 5, theme = UI.Theme.create({ radius = 3 }) })
s3:prerender()
local sd = take()
check(#sd == 3 and sd[1].name == "mui_round3_fill.png" and sd[1].h == 6 and sd[3].name == "mui_round3_border.png",
    "Slider 有圓角：6px 高的圓角軌道（底、填色、外框）")
local s0 = UI.Slider.new({ min = 0, max = 10, value = 5 })
s0:prerender()
check(#take() == 0 and s0.rects[1].h == 4, "Slider 沒設圓角：原本 4px 直線軌道")

-- ---------- 字型 ----------
local ft = UI.Theme.create({ font = UIFont.Medium })
check(UI.Button.new({ title = "x", theme = ft }).font == UIFont.Medium
    and UI.Button.new({ title = "x", theme = ft, font = UIFont.NewSmall }).font == UIFont.NewSmall
    and UI.Button.new({ title = "x" }).font == UIFont.Small, "font：opts.font 優先，再 theme.font，再 UIFont.Small")
check(UI.Window.new({ x = 0, y = 0, width = 300, height = 200, title = "W", theme = ft }).font == UIFont.Medium
    and UI.Dropdown.new({ options = {}, theme = ft }).font == UIFont.Medium
    and UI.TextField.new({ width = 100, theme = ft }).font == UIFont.Medium, "Window／Dropdown／TextField 也讀 theme.font")

NinePatchTexture = keepNPT
Skin._resetForTests()
return n
