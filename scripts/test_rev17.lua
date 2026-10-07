-- rev 17：UI.NavList（分組列、開關、選取、狀態快取、滑鼠、焦點停點、ScrollPanel 捲到游標列）、UI.SliderRow（版面、
-- zeroLabel、format、伺服器上限）、UI.Preview（stencil 成對、draw 出錯停用）、Checkbox／Slider tooltip、watch／zone 圖示、
-- 載入自檢與零配置。斷行禁則在 test_wrap.lua。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
print("情境 rev17：NavList／SliderRow／Preview／控制項 tooltip／watch・zone 圖示")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local F, K, T = UI.Focus, Keyboard, ctx.TARGET

-- 忠於原版的位置與捲動 stub（同 test_rev16.lua；結束還原）
local STUBBED = { "getAbsoluteX", "getAbsoluteY", "getYScroll", "setYScroll", "setScrollHeight", "getScrollHeight",
    "setScrollChildren", "createChildren", "getMouseX", "getMouseY", "drawTextureScaled" }
local keep = {}
for _, k in ipairs(STUBBED) do
    keep[k] = rawget(ISPanel, k)
end
function ISPanel:getAbsoluteX()
    local p = self.parent
    if p then return p:getAbsoluteX() + self.x end
    return self.x
end
function ISPanel:getAbsoluteY()
    local p = self.parent
    if p then
        local s = p._scrollChildren and p:getYScroll() or 0
        return p:getAbsoluteY() + self.y + (s < 0 and math.ceil(s) or math.floor(s))
    end
    return self.y
end
function ISPanel:getYScroll() return self._ys or 0 end
function ISPanel:setYScroll(y)
    local h = self._sh or 0
    if -y > h - self.height then y = -(h - self.height) end
    if -y < 0 then y = 0 end
    self._ys = y
end
function ISPanel:setScrollHeight(h)
    self._sh = h
    self:setYScroll(self:getYScroll())
end
function ISPanel:getScrollHeight() return self._sh or 0 end
function ISPanel:setScrollChildren(b) self._scrollChildren = b end
function ISPanel:createChildren() end
local mx, my = 0, 0
local function setMouse(x, y)
    mx, my = x, y
    ctx.setMouse(x, y)
end
function ISPanel:getMouseX() return mx - self:getXScroll() - self:getAbsoluteX() end
function ISPanel:getMouseY() return my - self:getYScroll() - self:getAbsoluteY() end
function ISPanel:drawTextureScaled(tex, x, y, w, h, a, r, g, b)
    self.tex = self.tex or {}
    self.tex[#self.tex + 1] = { tex = tex, x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end
local keepGetText = getText
getText = function(key, a, b)
    if key == "IGUI_MinidoracatUI_Slider_ValueOfCap" then return a .. "/" .. b end
    return keepGetText(key)
end

local function reset(el)
    el.rects, el.borders, el.texts, el.tex = {}, {}, {}, {}
end
local function findText(el, text)
    for _, t in ipairs(el.texts) do if t.text == text then return t end end
    return nil
end
local function findRect(el, x, y, w, h)
    for _, r in ipairs(el.rects) do
        if r.x == x and r.y == y and r.w == w and r.h == h then return r end
    end
    return nil
end

-- ---------- 載入自檢 ----------
local saved = MinidoracatUI
MinidoracatUI = nil
local okN = pcall(dofile, ctx.MOD_LUA .. "Widgets/NavList.lua")
local okP = pcall(dofile, ctx.MOD_LUA .. "Widgets/Preview.lua")
check(okN and okP and MinidoracatUI == nil, "facade 未發布時 NavList／Preview 靜默 return、不建立殘缺全域")
local fh = io.open(ctx.MOD_LUA .. "V1.lua", "rb")
local src = fh:read("*a")
fh:close()
load(src, "@V1.lua")()
local fresh = MinidoracatUI.v1
local keepPanel = ISPanel
ISPanel = nil
local okN2 = pcall(dofile, ctx.MOD_LUA .. "Widgets/NavList.lua")
local okP2 = pcall(dofile, ctx.MOD_LUA .. "Widgets/Preview.lua")
ISPanel = keepPanel
check(okN2 and okP2 and fresh.CAPABILITIES.navList == false and fresh.NavList == nil
    and fresh.CAPABILITIES.preview == false and fresh.Preview == nil,
    "原生 ISPanel 缺席時 navList／preview 維持 false、不掛元件")
MinidoracatUI = saved
dofile(ctx.MOD_LUA .. "Widgets/NavList.lua")
dofile(ctx.MOD_LUA .. "Widgets/Preview.lua")
local C = UI.CAPABILITIES
check(UI.API_REVISION >= 17 and C.navList == true and C.preview == true and C.sliderRow == true and C.controlTooltips == true
    and C.buttonIconColor == true and UI.NavList ~= nil and UI.Preview ~= nil and UI.SliderRow ~= nil,
    "rev 17：API_REVISION >= 17，navList／sliderRow／preview／controlTooltips／buttonIconColor 五個旗標都 true 且元件掛上 facade")

-- ---------- Icons：watch／zone ----------
local keepGetTexture = getTexture
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()
local w1, z1 = UI.Icons.get("watch"), UI.Icons.get("zone")
check(w1 ~= nil and w1.path == "media/ui/MinidoracatUI/mui_icon_watch.png" and z1 ~= nil
    and z1.path == "media/ui/MinidoracatUI/mui_icon_zone.png" and UI.Icons.get("clock").path ~= w1.path,
    "rev 17：watch／zone 對到 mui_icon_watch.png／mui_icon_zone.png（watch 不是 clock）")
getTexture = nil
UI.Skin._resetForTests()
local probe = ISPanel.new(ISPanel, 0, 0, 10, 10)
check(UI.Icons.get("watch") == nil and UI.Icons.draw(probe, "zone", 0, 0, 16) == false, "缺貼圖：watch／zone 回 nil／false，不拋錯")

-- ---------- NavList ----------
local zOn, setCalls, getCalls, lastSet = true, 0, 0, nil
local itemTex = { name = "TextureIcon" }
local function groups()
    return {
        { title = "Layers", items = {
            { id = "base", label = "Base", icon = "layers" },
            { id = "zombie", label = "Zombies", icon = "skull", switch = {
                get = function() getCalls = getCalls + 1 return zOn end,
                set = function(v) setCalls = setCalls + 1; lastSet = v; zOn = v end } },
            { id = "animal", label = "Animals", icon = itemTex, switch = {
                get = function() return false end, set = function() setCalls = setCalls + 1 end,
                enabled = function() return false end } },
            { id = "locked", label = "Locked", icon = "lock", enabled = function() return false end },
        } },
        { items = { { id = "perf", label = "Performance very long label that is cut", icon = "chart" } } },
        { title = "Addons", items = {
            { id = "bad", label = "Bad", switch = { get = function() error("boom") end, set = function() error("boom") end } },
            { label = "no id is skipped" },
        } },
    }
end
local selects, lastSel = 0, nil
local function onSelect(target, id, nav)
    selects = selects + 1
    lastSel = { target = target, id = id, nav = nav }
end
local nav = UI.NavList.new{ x = 0, y = 0, width = 160, groups = groups(), selected = "zombie", target = T, onSelect = onSelect }
local rows = nav._rows
check(#rows == 8 and rows[1].header and rows[1].y == 0 and rows[1].h == 18 and rows[2].y == 18 and rows[2].h == 24
    and rows[6].id == "perf" and rows[6].y == 120 and rows[7].header and rows[7].y == 144 and rows[7].h == 24
    and rows[8].y == 168, "版面：群組標題（第一個上方留白較少）、24px 列、無標題群組之間留 6px、沒有 id 的項目略過")
check(nav:getContentHeight() == 192 and nav.height == 192 and nav:getSelected() == "zombie" and nav._cursor == 3,
    "內容高＝最後一列下緣；height 省略＝內容高；selected 生效、游標在選取列")
check(UI.NavList.new{ width = 100, groups = groups(), selected = "nope" }:getSelected() == nil,
    "selected 是不存在的 id：視為沒選")
check(rows[3].on == true and rows[4].on == false and rows[4].swEn == false and rows[5].en == false
    and rows[8].on == false and rows[8].swEn == true, "狀態：get／enabled 讀進快取；get 出錯當 false，不炸")

-- 繪製（缺貼圖：圖示不畫、名稱照畫）
local colors = nav.theme.colors
reset(nav)
nav:prerender()
local header = findText(nav, "Layers")
local zl = findText(nav, "Zombies")
local sel = findRect(nav, 0, 42, 160, 24)
local mark = findRect(nav, 0, 45, 2, 18)
check(header and header.x == 8 and header.y == 4 and header.r == colors.textMuted.r,
    "群組標題：小字 textMuted，貼齊標題列底")
check(sel and sel.r == colors.selected.r and mark and mark.r == colors.accent.r and zl and zl.x == 30
    and zl.r == colors.accent.r, "選中列：selected 底＋左側 2px accent 記號（不只靠顏色）＋accent 名稱")
local lockedT = findText(nav, "Locked")
check(lockedT and lockedT.r == colors.textDisabled.r and findText(nav, "Base").r == colors.text.r,
    "停用列名稱 textDisabled，其餘 text")
local onTrack = findRect(nav, 120, 44, 32, 20)
local offTrack = findRect(nav, 120, 68, 32, 20)
check(onTrack and onTrack.r == colors.accent.r and offTrack and offTrack.r == colors.well.r
    and nearly(offTrack.a, (colors.well.a or 1) * 0.45), "開關畫在右側（Skin.toggle）：開＝accent、關＝well；停用開關淡化 0.45")
local perfT = nil
for _, t in ipairs(nav.texts) do if string.find(t.text, "Perform", 1, true) then perfT = t end end
check(perfT and perfT.text ~= rows[6].label and string.sub(perfT.text, -3) == "..." and rows[6].cut == true,
    "放不下的名稱以 Text.fit 截字")
local texIcon = nav.tex[1]
check(#nav.tex == 1 and texIcon.tex == itemTex and texIcon.x == 8 and texIcon.y == 70 and texIcon.w == 16
    and nearly(texIcon.a, 1), "缺貼圖：Icons key 的圖示不畫（名稱照畫）；Texture 圖示原色 16px")
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()
reset(nav)
nav:prerender()
local skull = nil
for _, t in ipairs(nav.tex) do if type(t.tex.path) == "string" and string.find(t.tex.path, "skull", 1, true) then skull = t end end
check(skull and skull.x == 8 and skull.y == 46 and skull.w == 16 and skull.r == colors.accent.r,
    "貼圖在：Icons key 的圖示以名稱色染色（選中列 accent）")
function nav:drawTextureScaled() error("draw failure") end
reset(nav)
local okDraw = pcall(nav.prerender, nav)
check(okDraw and findText(nav, "Animals") ~= nil, "圖示繪製拋錯：被攔下，名稱照畫")
nav.drawTextureScaled = nil
getTexture = nil
UI.Skin._resetForTests()

-- hover
nav._mouseOver = true
setMouse(50, 30)
reset(nav)
nav:prerender()
local hov = findRect(nav, 0, 18, 160, 24)
check(hov and hov.r == colors.hover.r, "滑鼠停在列上：hover 底")
setMouse(50, 100) -- 停用列
reset(nav)
nav:prerender()
check(findRect(nav, 0, 90, 160, 24) == nil, "停用列不畫 hover")
nav._mouseOver = false

-- 狀態快取與 refresh
local before = getCalls
nav:prerender()
nav:prerender()
zOn = false
nav:prerender()
check(getCalls == before and rows[3].on == true, "沒呼叫 refresh：每幀不重讀 get（畫快取值）")
nav:refresh()
nav:prerender()
check(getCalls == before + 1 and rows[3].on == false, "refresh()：下一幀重讀一次")
zOn = true
nav:refresh()
nav:prerender()

-- 滑鼠
local function click(x, y, x2, y2)
    nav:onMouseDown(x, y)
    nav:onMouseUp(x2 or x, y2 or y)
end
click(50, 30)
check(selects == 1 and lastSel.target == T and lastSel.id == "base" and lastSel.nav == nav and nav:getSelected() == "base",
    "點列：選取並回呼 onSelect(target, id, nav) 一次")
click(50, 30)
check(selects == 1, "點已選中的列：不回呼")
click(130, 50)
check(setCalls == 1 and lastSet == false and zOn == false and rows[3].on == false and nav:getSelected() == "base"
    and selects == 1, "點開關：set(not get())、讀回新狀態，不改選取")
click(130, 74)
check(setCalls == 1, "停用的開關（switch.enabled 回 false）：點了不動")
click(50, 100)
check(selects == 1 and nav:getSelected() == "base", "停用列：點了不選")
click(50, 30, 50, 60)
check(selects == 1, "按下與放開在不同列：不算點擊")
nav:onMouseDown(50, 50)
nav:onMouseUpOutside(0, 0)
nav:onMouseUp(50, 50)
check(selects == 1, "放開在元件外：取消這次按下")
click(130, 180)
check(rows[8].on == false and setCalls == 1, "set／get 拋錯的開關：pcall 攔下、狀態讀回 false，不炸")
click(50, 10)
check(selects == 1, "點群組標題：沒有動作")

-- setSelected／setGroups
nav:setSelected("nope")
check(nav:getSelected() == "base", "setSelected 未知 id：忽略")
nav:setSelected("perf", true)
check(nav:getSelected() == "perf" and selects == 1 and nav._cursor == 6, "setSelected silent：不回呼、游標跟到選取列")
nav:setSelected("locked")
check(nav:getSelected() == "locked" and selects == 2, "setSelected 不受停用限制（非 silent 回呼一次）")
nav:setSelected(nil)
check(nav:getSelected() == nil and selects == 2, "setSelected(nil)：清空選取、不回呼")
nav:setSelected("bad", true)
nav:setGroups({ { title = "Only", items = { { id = "x", label = "X" } } } })
check(nav:getSelected() == nil and nav:getContentHeight() == 18 + 24 and nav.height == 42 and nav._cursor == 2,
    "setGroups：選取已不在就靜默清掉，height 跟著內容，游標回第一個可用列")
nav:setGroups(groups())
check(nav:getContentHeight() == 192 and #nav._rows == 8, "setGroups 重建")

-- 零配置：prerender（hover、開關、截字快取、缺圖）＋refresh
local noop = function() end
nav.drawRect, nav.drawRectBorder, nav.drawText, nav.drawTextureScaled = noop, noop, noop, noop
nav._mouseOver = true
local keepTM = getTextManager
local tm = keepTM()
getTextManager = function() return tm end
local function navRound()
    nav:refresh()
    nav:prerender()
end
collectgarbage("collect")
collectgarbage("stop")
navRound()
local kb = collectgarbage("count")
for _ = 1, 50 do navRound() end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
getTextManager = keepTM
nav.drawRect, nav.drawRectBorder, nav.drawText, nav.drawTextureScaled = nil, nil, nil, nil
nav._mouseOver = false
check(grew == 0, "NavList prerender（hover、開關、截字、缺圖）＋refresh 重讀 50 輪不配置記憶體")

-- ---------- NavList 焦點 ----------
local win = UI.Window.new{ x = 0, y = 0, width = 400, height = 400, title = "T" }
selects = 0
zOn = true
local fnav = UI.NavList.new{ x = 10, y = 30, width = 160, groups = groups(), selected = "zombie", target = T, onSelect = onSelect }
win:addChild(fnav)
local after = UI.Button.new{ x = 10, y = 300, title = "After" }
win:addChild(after)
win:addToUIManager()
local targets = F.collectTargets(win)
local navDesc, innerCount = nil, 0
for i = 1, #targets do
    if targets[i].control == fnav then navDesc = targets[i] end
end
check(navDesc ~= nil and navDesc.kind == "button" and navDesc.captionSide == "right",
    "NavList 是一個 kind=button 的自動目標，說明在右側")
F.focusControl(fnav, true)
local function rect() return fnav:focusRect() end
local x0, y0, w0, h0 = rect()
check(x0 == 0 and y0 == 42 and w0 == 160 and h0 == 24, "焦點框只框游標列（落點時在選取列）")
local pc = ctx.press(win, K.KEY_DOWN)
check(pc and fnav._cursor == 4 and select(2, rect()) == 66, "下：游標到下一列，焦點框跟著")
ctx.press(win, K.KEY_RIGHT)
check(not fnav._onSwitch and F.focused() == fnav, "右：這列的開關停用，不移到開關（鍵盤焦點留在導覽）")
ctx.press(win, K.KEY_DOWN)
check(fnav._cursor == 6 and fnav:focusLabel() == rows[6].label, "下：跳過停用列；名稱被截字時焦點說明給全名")
win.texts = {}
win:render()
check(findText(win, rows[6].label) ~= nil, "焦點說明經 Focus.render 畫出全名")
ctx.press(win, K.KEY_UP)
ctx.press(win, K.KEY_UP)
check(fnav._cursor == 3 and fnav:focusLabel() == nil, "上：回到 Zombies；沒截字時不給說明")
ctx.press(win, K.KEY_RIGHT)
local sx, sy, sw, sh = rect()
check(fnav._onSwitch and sx == 120 and sy == 44 and sw == 32 and sh == 20, "右：游標移到這列的開關，焦點框框住開關")
local sets = setCalls
ctx.press(win, K.KEY_RETURN)
check(setCalls == sets + 1 and zOn == false and fnav:getSelected() == "zombie" and selects == 0,
    "開關上按 Enter：切換開關、不改選取、不回呼 onSelect")
ctx.press(win, K.KEY_SPACE)
check(setCalls == sets + 2 and zOn == true, "Space 同 Enter")
ctx.press(win, K.KEY_DOWN)
check(fnav._cursor == 4 and not fnav._onSwitch, "下到開關停用的列：回到列停點")
ctx.press(win, K.KEY_UP)
ctx.press(win, K.KEY_UP)
ctx.press(win, K.KEY_RETURN)
check(fnav._cursor == 2 and selects == 1 and lastSel.id == "base" and fnav:getSelected() == "base",
    "列上按 Enter：選取並回呼 onSelect 一次")
ctx.press(win, K.KEY_END)
check(fnav._cursor == 8, "End：最後一個可用列")
local endConsumed = ctx.press(win, K.KEY_DOWN)
check(fnav._cursor == 8 and F.focused() == fnav and endConsumed, "最後一列再按下：游標不動，鍵盤焦點留在導覽（按鍵照樣消耗）")
ctx.press(win, K.KEY_HOME)
check(fnav._cursor == 2, "Home：第一個可用列")
F.focusControl(fnav, true)
ctx.press(win, K.KEY_END)
F.onJoypadDir(win, "down", nil)
check(F.focused() == after, "手把：最後一列再往下，移到下一個目標")
F.onJoypadDir(win, "up", nil)
check(F.focused() == fnav and fnav._cursor == 8, "手把：往上回到導覽，游標停在原處")
F.onJoypadDown(win, Joypad.AButton, nil)
check(fnav:getSelected() == "bad" and lastSel.id == "bad", "手把 A：選取游標列（同 Enter）")
F.onJoypadDir(win, "right", nil)
check(fnav._onSwitch == true and F.focused() == fnav, "手把右：移到開關（這列有可用開關）")
F.onJoypadDir(win, "left", nil)
F.onJoypadDir(win, "left", nil)
check(not fnav._onSwitch and F.focused() ~= fnav, "手把左：先回到列，再按一次離開導覽")
win:close()

-- ---------- NavList 在 ScrollPanel 裡 ----------
local win2 = UI.Window.new{ x = 0, y = 0, width = 400, height = 400, title = "S" }
local panel = UI.ScrollPanel.new{ x = 10, y = 30, width = 200, height = 60 }
panel:createChildren()
win2:addChild(panel)
local snav = UI.NavList.new{ width = panel:contentWidth(), groups = groups() }
panel:addChild(snav)
win2:addToUIManager()
local rings = 0
local keepRing = F.drawRing
F.drawRing = function(...) rings = rings + 1 return keepRing(...) end
local function frame()
    panel:prerender()
    panel:render()
    win2:render()
end
frame()
F.focusControl(snav, true)
frame()
check(panel:getYScroll() == 0 and rings == 1 and snav._cursor == 2, "游標列在可視區內：不捲，畫框")
ctx.press(win2, K.KEY_DOWN)
ctx.press(win2, K.KEY_DOWN)
ctx.press(win2, K.KEY_DOWN)
check(snav._cursor == 6 and panel:getYScroll() == -(144 + 4 - 60), "游標往下移出可視區：容器捲到游標列（底端對齊）")
ctx.press(win2, K.KEY_END)
check(panel:getYScroll() == -(192 - 60), "End：捲到最後一列（夾在內容底）")
ctx.press(win2, K.KEY_HOME)
check(panel:getYScroll() == -(18 - 4), "Home：捲回第一列（頂端對齊）")
panel:setYScroll(0)
panel:scrollTo(snav)
check(panel:getYScroll() == 0, "scrollTo(導覽)：看 focusRect（游標列已可見就不動），不是整個元件")
panel:onMouseWheel(100)
rings = 0
frame()
check(rings == 0 and panel:getYScroll() == -(192 - 60), "滾輪把游標列捲出可視區（導覽仍部分可見）：不畫框")
F.drawRing = keepRing
win2:close()

-- ---------- Checkbox／Slider tooltip ----------
local box = UI.Checkbox.new{ x = 10, y = 30, label = "Box", tooltip = "Box tip" }
local plain = UI.Checkbox.new{ x = 10, y = 60, label = "Plain" }
box:prerender()
plain:prerender()
check(box.tooltip == "Box tip" and box.tooltipPasses == 1 and plain.tooltipPasses == nil,
    "Checkbox opts.tooltip：prerender 走原版 updateTooltip（同 Button）；沒有 tooltip 不呼叫")
box:setTooltip(nil)
box:prerender()
box.tooltipUI = {}
box:prerender()
check(box.tooltip == nil and box.tooltipPasses == 2, "setTooltip(nil)：不再呼叫；還掛著 ISToolTip 時照樣呼叫（讓它收掉）")
box.tooltipUI = nil
box:setTooltip("Box tip")
local sl = UI.Slider.new{ x = 10, y = 90, width = 100, min = 0, max = 10, step = 1, tooltip = "Slide tip" }
sl:prerender()
sl:setTooltip("Other")
sl:prerender()
check(sl.tooltip == "Other" and sl.tooltipPasses == 2, "Slider opts.tooltip／setTooltip：prerender 走原版 updateTooltip")
local win3 = UI.Window.new{ x = 0, y = 0, width = 300, height = 300, title = "Tips" }
win3:addChild(box)
win3:addChild(sl)
win3:addToUIManager()
F.focusControl(box, true)
win3.texts = {}
win3:render()
local boxCap = findText(win3, "Box tip")
F.focusControl(sl, true)
win3.texts = {}
win3:render()
check(boxCap ~= nil and findText(win3, "Other") ~= nil, "鍵盤焦點：Checkbox／Slider 的 tooltip 當焦點說明")

-- ---------- Button iconColor ----------
local btex = { name = "PoiGlyph" }
local tint = { r = 0.9, g = 0.2, b = 0.1 }
local function lastTex(b) return b.tex[#b.tex] end
local ib = UI.Button.new{ x = 0, y = 0, title = "Poi", icon = btex, style = "chip" }
reset(ib)
ib:prerender()
local t0 = lastTex(ib)
check(t0 and t0.tex == btex and t0.r == 1 and t0.g == 1 and t0.b == 1 and nearly(t0.a, 1),
    "沒設 iconColor：Texture 圖示原色（頂點色全白）")
local tb = UI.Button.new{ x = 0, y = 0, title = "Poi", icon = btex, style = "chip", iconColor = tint }
reset(tb)
tb:prerender()
local t1 = lastTex(tb)
check(t1 and t1.r == 0.9 and t1.g == 0.2 and t1.b == 0.1 and nearly(t1.a, 1), "opts.iconColor：Texture 圖示以該色染色（沒給 a 當 1）")
tb:setIconColor({ r = 0.2, g = 0.4, b = 0.6, a = 0.5 })
tb:setEnabled(false)
reset(tb)
tb:prerender()
local t2 = lastTex(tb)
check(t2 and t2.r == 0.2 and t2.b == 0.6 and nearly(t2.a, 0.5 * 0.45), "停用：染色圖示 alpha＝color.a 乘停用淡化 0.45")
tb:setIconColor(nil)
reset(tb)
tb:prerender()
local t3 = lastTex(tb)
check(t3 and t3.r == 1 and t3.g == 1 and t3.b == 1 and nearly(t3.a, 0.45), "setIconColor(nil)：回到原色（停用照樣淡化）")
tb:setEnabled(true)
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()
local kb2 = UI.Button.new{ x = 0, y = 0, title = "Key", icon = "skull", iconColor = tint }
reset(kb2)
kb2:prerender()
local t4 = lastTex(kb2)
local tc = kb2.theme.colors.text
check(t4 and t4.r == tc.r and t4.g == tc.g and t4.b == tc.b, "Icons key 的圖示不吃 iconColor，照舊用字色")
getTexture = nil
UI.Skin._resetForTests()
tb:setIconColor(tint)
tb.drawTextureScaled, tb.drawRect, tb.drawRectBorder, tb.drawText = noop, noop, noop, noop
getTextManager = function() return tm end
collectgarbage("collect")
collectgarbage("stop")
tb:prerender()
kb = collectgarbage("count")
for _ = 1, 50 do tb:prerender() end
grew = collectgarbage("count") - kb
collectgarbage("restart")
getTextManager = keepTM
check(grew == 0, "Button 染色 Texture 圖示 prerender 50 輪不配置記憶體")

-- ---------- SliderRow ----------
local rowCalls, lastRow = 0, nil
local function onRow(target, value, r)
    rowCalls = rowCalls + 1
    lastRow = { target = target, value = value, row = r }
end
local function meters(v) return tostring(math.floor(v)) .. "m" end
local row = UI.SliderRow.new{ x = 0, y = 0, width = 300, label = "Dist", min = 0, max = 2000, step = 1, value = 0,
    zeroLabel = "Off", format = meters, tooltip = "Row tip", target = T, onChange = onRow }
local s = row._slider
check(row:getValue() == 0 and row._text == "Off" and s.x == 48 and s.width == 300 - 48 - 8 - 50 and s._trackW == s.width - 12
    and row.children[1] == s, "版面：標籤寬＝標籤字寬、滑桿夾在中間、數值欄寬取兩端與 zeroLabel 最寬；值 0 顯示 zeroLabel")
reset(row)
row:prerender()
local lt, vt = findText(row, "Dist"), findText(row, "Off")
check(lt and lt.x == 0 and vt and vt.x == 300 - 30 and lt.r == row.theme.colors.text.r and row.tooltipPasses == 1,
    "繪製：標籤在左、數值靠右；有 tooltip 時走原版 updateTooltip")
row:setValue(500)
check(rowCalls == 1 and lastRow.target == T and lastRow.value == 500 and lastRow.row == row and row._text == "500m",
    "setValue：回呼 onChange(target, value, row) 一次、數值文字用 format")
row:setValue(500)
row:setValue(700, true)
check(rowCalls == 1 and row:getValue() == 700 and row._text == "700m", "相同值 no-op；silent 不回呼")
row:setCap(800)
check(s.max == 800 and row:getValue() == 700 and row._text == "700m/800m" and s.width == 300 - 48 - 8 - 90,
    "setCap：滑桿範圍夾到上限，數值寫成「值／上限」，數值欄跟著加寬")
row:setValue(1500)
check(row:getValue() == 800 and rowCalls == 2 and lastRow.value == 800, "上限生效時 setValue 超過上限：夾在上限（回呼實際值）")
row:setCap(nil)
check(s.max == 2000 and row:getValue() == 1500 and rowCalls == 2 and row._text == "1500m" and s.width == 300 - 48 - 8 - 50,
    "取消上限：還原到最後設定的值（不回呼）、數值欄縮回")
local capV = 600
row:setCap(function() return capV end)
check(row:getValue() == 600 and row._text == "600m/600m" and rowCalls == 2, "上限函式：立即套用、顯示值靜默夾住")
capV = 1000
row:prerender()
check(s.max == 1000 and row:getValue() == 1000 and rowCalls == 2, "上限函式每幀問一次：放寬就重排並還原")
row:setCap(function() error("no cap") end)
check(s.max == 2000 and row:getValue() == 1500, "上限函式出錯：當作沒有上限")
row:setCap(0)
check(s.max == 2000 and row._capNow == nil, "上限 0／nil：沒有上限")
row:setCap(800)
row:setValue(100)
local calls = rowCalls
s:onMouseDown(s._trackW + 8, 5)
s:onMouseUp(0, 0)
check(rowCalls == calls + 1 and lastRow.value == 800 and row:getValue() == 800, "拖到軌道最右：值停在上限，不超過")
row:setValue(0)
check(row._text == "Off/800m", "值 0 有上限：zeroLabel／上限")
row:setCap(nil)
local fw = UI.Window.new{ x = 0, y = 0, width = 400, height = 200, title = "R" }
fw:addChild(row)
fw:addToUIManager()
local found, inner = false, false
for _, d in ipairs(F.collectTargets(fw)) do
    if d.control == row then found = true end
    if d.control == s then inner = true end
end
check(found and not inner, "焦點：整列是一個目標（內層滑桿不另列）")
F.focusControl(row, true)
calls = rowCalls
ctx.press(fw, K.KEY_RIGHT)
check(row:getValue() == 1 and rowCalls == calls + 1, "焦點右鍵交給滑桿：＋step、回呼一次")
fw.texts = {}
fw:render()
check(findText(fw, "Row tip") ~= nil, "焦點說明是 tooltip")
row:setEnabled(false)
reset(row)
row:prerender()
check(not row:isEnabled() and not s:isEnabled() and row:onFocusKey(K.KEY_RIGHT) == false
    and findText(row, "Dist").r == row.theme.colors.textDisabled.r, "setEnabled(false)：滑桿一起停用、方向鍵不吃、標籤 textDisabled")
row:setEnabled(true)
row:setTooltip(nil)
check(row.tooltip == nil, "setTooltip(nil)")
fw:close()
local dec = UI.SliderRow.new{ width = 200, min = 0, max = 1, step = 0.05, value = 0.3 }
local int = UI.SliderRow.new{ width = 200, label = "N", min = 0, max = 100, step = 5, value = 35 }
check(dec._text == "0.3" and dec._labelW == 0 and dec._slider.x == 0 and int._text == "35",
    "沒給 format：小數步進到小數兩位、整數步進顯示整數；沒有標籤時滑桿從 0 開始")

-- 零配置：上限函式每幀詢問＋tooltip＋文字
row:setCap(function() return capV end)
row:setTooltip("Row tip")
row.drawText = noop
getTextManager = function() return tm end
collectgarbage("collect")
collectgarbage("stop")
row:prerender()
kb = collectgarbage("count")
for _ = 1, 50 do row:prerender() end
grew = collectgarbage("count") - kb
collectgarbage("restart")
getTextManager = keepTM
row.drawText = nil
check(grew == 0, "SliderRow prerender（上限函式、tooltip）50 輪不配置記憶體")

-- ---------- Preview ----------
local drawCalls, drawArgs = 0, nil
local function painter(self, x, y, w, h)
    drawCalls = drawCalls + 1
    drawArgs = { self = self, x = x, y = y, w = w, h = h }
    self:drawRect(x, y, 10, 10, 1, 1, 0, 0)
end
local faded = UI.Theme.create()
faded.alpha = 0.5
local pv = UI.Preview.new{ x = 0, y = 0, width = 200, height = 60, theme = faded, draw = painter, caption = "Cap" }
pv:prerender()
local pc2 = pv.theme.colors
local st = pv.stencil
local cap = findText(pv, "Cap")
check(pv.rects[1].x == 0 and pv.rects[1].w == 200 and pv.rects[1].h == 60 and pv.rects[1].r == pc2.well.r
    and nearly(pv.rects[1].a, (pc2.well.a or 1) * 0.5) and pv.borders[1].r == pc2.border.r,
    "圓角 well（缺貼圖退直角）：well 底＋border，chrome 乘 theme.alpha")
check(drawCalls == 1 and drawArgs.self == pv and drawArgs.x == 2 and drawArgs.y == 2 and drawArgs.w == 196 and drawArgs.h == 56,
    "每幀呼叫 draw(self, x, y, w, h)，給內框（四邊內縮 2）")
check(st.set == 1 and st.clear == 1 and st.repaint == 1, "stencil：set → draw → clear → repaint 同一 rect")
check(cap and cap.x == 6 and cap.y == 3 and cap.r == pc2.textMuted.r, "caption：內框左上小字 textMuted，畫在 draw 之上")
local boom = function() error("preview failure") end
pv:setDraw(boom)
local okPv = pcall(pv.prerender, pv)
check(okPv and pv._failed == true and st.set == 2 and st.clear == 2 and st.repaint == 2,
    "draw 拋錯：被攔下、不外洩，stencil 照樣成對")
pv:prerender()
check(st.set == 2, "出錯後不再呼叫 draw（也不設 stencil）")
pv:setDraw(painter)
pv:prerender()
check(drawCalls == 2 and st.set == 3 and st.clear == 3, "setDraw 再給一次：恢復呼叫")
pv:setCaption("")
reset(pv)
pv:prerender()
check(findText(pv, "Cap") == nil and drawCalls == 3 and st.set == 4, "setCaption(\"\")：不畫說明")
pv:setDraw(nil)
pv:prerender()
check(st.set == 4 and drawCalls == 3, "setDraw(nil)：只畫空框")
pv.isCollapsed = true
reset(pv)
pv:prerender()
check(#pv.rects == 0 and st.set == 4 and st.clear == 4, "收合：什麼都不畫、不設 stencil")
pv.isCollapsed = false
local tiny = UI.Preview.new{ width = 4, height = 4, draw = painter }
tiny:prerender()
check(tiny.stencil.set == 0 and drawCalls == 3, "內框沒有面積：不設 stencil、不呼叫 draw")
pv:setDraw(painter)
pv:setCaption("Cap")
pv.drawRect, pv.drawRectBorder, pv.drawText = noop, noop, noop
local quiet = function(self, x, y) self:drawRect(x, y, 1, 1, 1, 1, 1, 1) end
pv:setDraw(quiet)
getTextManager = function() return tm end
collectgarbage("collect")
collectgarbage("stop")
pv:prerender()
kb = collectgarbage("count")
for _ = 1, 50 do pv:prerender() end
grew = collectgarbage("count") - kb
collectgarbage("restart")
getTextManager = keepTM
check(grew == 0, "Preview prerender（draw、stencil、caption）50 輪不配置記憶體")

getTexture = keepGetTexture
UI.Skin._resetForTests()
getText = keepGetText
for _, k in ipairs(STUBBED) do ISPanel[k] = keep[k] end
return n
