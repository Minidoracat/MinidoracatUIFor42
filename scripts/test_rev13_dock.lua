-- rev 13：家族工具列 Dock（Widgets/Dock.lua）。契約見 smoke_harness.lua 的切片載入器註解與 ARCHITECTURE §3.16。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
local F, K = UI.Focus, Keyboard
print("情境 rev13-dock：登記排序／可見集合／版面／拖曳門檻／收合存讀／徽章與外殼／提示／把手退回／預設位置／快捷鍵焦點／手把入口／通知避開")

-- ---------- 本切片自備的全域（用完全部還原） ----------
local keep = {
    getCore = getCore, getText = getText, getSpecificPlayer = getSpecificPlayer, getTexture = getTexture,
    Events = Events, keyBinding = keyBinding, ISLayoutManager = ISLayoutManager, ISToolTip = ISToolTip,
    getKeyName = getKeyName, JoypadState = JoypadState, ISWorldObjectContextMenu = ISWorldObjectContextMenu,
    drawTextureScaled = ISPanel.drawTextureScaled, drawTextureAllPoint = ISPanel.drawTextureAllPoint,
    KEY_PERIOD = K.KEY_PERIOD,
}

local screenW, screenH, moodleOpt, fontOpt = 1920, 1080, 1, 1
local keys = { MinidoracatUI_Dock = 52, Bound_Toggle = 53, Unbound_Toggle = 0 }
getCore = function()
    return {
        getScreenWidth = function() return screenW end,
        getScreenHeight = function() return screenH end,
        getOptionMoodleSize = function() return moodleOpt end,
        getOptionFontSizeReal = function() return fontOpt end,
        getKey = function(_, name) return keys[name] or 0 end,
    }
end
getKeyName = function(code) if code == 53 then return "/" end return "K" .. tostring(code) end
K.KEY_PERIOD = 52

local player = true
getSpecificPlayer = function() if player then return {} end return nil end

-- 引擎 Translator：%1／%2 依參數代入（共用 stub 忽略參數，這裡要驗模板組字）
local TR = {
    IGUI_MinidoracatUI_Dock_EntryHotkey = "%1 (hotkey %2)",
    IGUI_MinidoracatUI_Dock_Expand = "Expand (%1 entries)",
    IGUI_MinidoracatUI_Dock_Collapse = "Collapse (%1 entries)",
    IGUI_MinidoracatUI_Dock_StatusLine = "%1: %2",
    IGUI_MinidoracatUI_Dock_Open = "Open family toolbar",
}
getText = function(key, a, b)
    local s = TR[key]
    if s == nil then return "[" .. tostring(key) .. "]" end
    s = (s:gsub("%%1", function() return tostring(a) end))
    return (s:gsub("%%2", function() return tostring(b) end))
end

local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = { Add = function(fn) handlers[name] = fn end }
    rawset(t, name, ev)
    return ev
end })
keyBinding = {}

-- ISLayoutManager：以解析度分組存 layout，讀回時值變字串（同 layout.ini）
local store, writes = {}, 0
local function res() return screenW .. "x" .. screenH end
ISLayoutManager = { windows = {} }
function ISLayoutManager.RegisterWindow(name, funcs, target)
    ISLayoutManager.windows[name] = { funcs = funcs, target = target }
    ISLayoutManager.TryRestore(name)
end
function ISLayoutManager.TryRestore(name)
    local w, saved = ISLayoutManager.windows[name], store[res()]
    if w and saved and saved[name] then w.funcs.RestoreLayout(w.target, name, saved[name]) end
end
function ISLayoutManager.OnPostSave()
    writes = writes + 1
    store[res()] = store[res()] or {}
    for name, w in pairs(ISLayoutManager.windows) do
        local layout = {}
        w.funcs.SaveLayout(w.target, name, layout)
        for k, v in pairs(layout) do layout[k] = tostring(v) end
        store[res()][name] = layout
    end
end

ISToolTip = {}
ISToolTip.__index = ISToolTip
function ISToolTip:new()
    local t = setmetatable({ visible = false, description = "" }, ISToolTip)
    ISToolTip.last = t
    return t
end
function ISToolTip:setOwner(o) self.owner = o end
function ISToolTip:setVisible(v) self.visible = v end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:addToUIManager() self.inUI = true end
function ISToolTip:removeFromUIManager() self.inUI = false end
function ISToolTip:setDesiredPosition(x, y) self.px, self.py = x, y end

-- 貼圖：只有 texOK 列出的路徑載得到；繪製記在元件的 draws
local texOK = {}
getTexture = function(path) if texOK[path] then return { path = path } end return nil end
local function record(el, entry)
    el.draws = el.draws or {}
    el.draws[#el.draws + 1] = entry
end
ISPanel.drawTextureScaled = function(self, tex, x, y, w, h, a, r, g, b)
    record(self, { path = tex.path, x = x, y = y, w = w, h = h, a = a, r = r, flip = false })
end
ISPanel.drawTextureAllPoint = function(self, tex, tlx, tly, trx, try, brx, bry, blx, bly, r, g, b, a)
    record(self, { path = tex.path, w = trx - tlx, flip = tly > bly })
end
local SLEEP = "media/ui/MinidoracatUI/mui_mascot_sleep.png"
local AWAKE = "media/ui/MinidoracatUI/mui_mascot_awake.png"
local CHEVRON = "media/ui/MinidoracatUI/mui_icon_chevron_down.png"

-- ---------- 小工具 ----------
local DOCK_LUA = ctx.MOD_LUA .. "Widgets/Dock.lua"
local clicks = {}
local function spec(id, order, extra)
    local s = { id = id, order = order, iconKey = "gauge",
        label = function() return "N" .. id end,
        onClick = function(e) clicks[#clicks + 1] = e.id end }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end
local function panel()
    local w = ISLayoutManager.windows.MinidoracatUIDock
    return w and w.target
end
local function tick()
    ctx.advance(300)
    handlers.OnTick()
end
-- 可見的入口按鈕 id，由上而下
local function ids(p)
    local list = {}
    for _, c in ipairs(p.children) do
        if c._rec and c.visible then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.y < b.y end)
    local out = {}
    for i, c in ipairs(list) do out[i] = c._rec.spec.id end
    return table.concat(out, ",")
end
local function button(p, id)
    for _, c in ipairs(p.children) do
        if c._rec and c._rec.spec.id == id then return c end
    end
end
local function handleOf(p)
    for _, c in ipairs(p.children) do
        if c._rec == nil then return c end
    end
end
local function clearDraws(el) el.rects, el.borders, el.texts, el.draws = {}, {}, {}, {} end
local function fresh()
    UI.Dock._resetForTests()
    UI.Skin._resetForTests()
    F.clear()
    clicks = {}
end

-- ---------- 載入自檢 ----------
UI.Toast._resetForTests()
F.clear()
UI.CAPABILITIES.dock, UI.Dock = false, nil
local keepButton = ISButton
ISButton = nil
dofile(DOCK_LUA)
ISButton = keepButton
ok(UI.CAPABILITIES.dock == false and UI.Dock == nil and handlers.OnKeyPressed == nil,
    "原生 ISButton 缺席：dock 維持 false、不掛 UI.Dock、不註冊事件")
dofile(DOCK_LUA)
local D = UI.Dock
ok(UI.API_REVISION == 13 and UI.CAPABILITIES.dock == true and D ~= nil, "載入成功：API_REVISION 13、dock 翻 true")
handlers.OnGameBoot()
ok(#keyBinding == 2 and keyBinding[1].value == "[MinidoracatUI]" and keyBinding[2].value == "MinidoracatUI_Dock"
    and keyBinding[2].key == 52, "OnGameBoot 註冊 [MinidoracatUI] 區段與 MinidoracatUI_Dock（預設 KEY_PERIOD）")

-- ---------- 登記與排序 ----------
fresh()
ok(D.register({ id = "x", order = 1, label = function() return "x" end, onClick = function() end }) == false
    and D.register({ id = "", order = 1, iconKey = "gauge", label = function() end, onClick = function() end }) == false
    and D.register(spec("y", "1")) == false and D.register(nil) == false
    and D.register(spec("z", 1, { getBadge = 3 })) == false,
    "不合法 spec 回 false 不拋錯（缺圖示來源／空 id／order 非數字／選填欄位型別錯）")
local avail = { c = true }
D.register(spec("b", 20))
D.register(spec("c", 10, { isAvailable = function() return avail.c end }))
D.register(spec("a", 10))
ok(D.isDocked("a") == false, "遊戲開始前（Dock 尚未建立）isDocked 為 false")
handlers.OnGameStart()
local p = panel()
ok(p ~= nil and p.visible and ids(p) == "a,c,b" and handleOf(p).visible,
    "依 order 再依 id 排序（a、c 同為 10）；2 個以上有把手")
ok(p.width == 48 and p.height == 4 + 40 + 3 * 44 + 4 and button(p, "a").x == 4 and button(p, "a").y == 48,
    "版面：40×40、間距 4、內距 4，把手在上")
ok(p.alwaysOnTop == false and p._nativeAlwaysOnTop == false and p.inUIManager,
    "alwaysOnTop=false 經原生 setter（addToUIManager 之後）")
ok(p.x == 1920 - (10 + 32) - 12 - 48 and p.y == 120, "預設位置：moodle 欄（選項 1＝32px）內側再左 12、y=120")
local bButton = button(p, "b")
D.register(spec("b", 5))
tick()
ok(ids(p) == "b,a,c" and button(p, "b") == bButton, "同 id 再登記＝覆寫（新 order 生效、沿用同一顆按鈕）")

-- ---------- 可見集合 ----------
avail.c = false
D.refresh()
tick()
ok(ids(p) == "b,a" and p.height == 4 + 40 + 2 * 44 + 4 and D.isDocked("c") == false and D.isDocked("a") == true,
    "isAvailable 變 false：其他入口補位、高度重算、isDocked 跟著變")
D.unregister("b")
ok(ids(p) == "a" and not handleOf(p).visible and p.width == 40 and p.height == 40
    and button(p, "a").x == 0 and button(p, "a").y == 0, "剩 1 個：不畫把手，面板就是那顆按鈕")
avail.c = true
tick()
ok(ids(p) == "a,c" and handleOf(p).visible, "isAvailable 變回 true（輪詢）：補回、把手回來")
D.unregister("a")
avail.c = false
tick()
ok(p.visible == false and D.isDocked("c") == false, "0 個可見入口：Dock 隱藏")
avail.c = true
D.register(spec("a", 10))
D.register(spec("b", 20))
tick()
ok(p.visible and ids(p) == "a,c,b", "隱藏中也輪詢：入口回來 Dock 重新顯示")

-- ---------- 預設位置與 clamp ----------
local function defaultX(opt, font)
    moodleOpt, fontOpt = opt, font or 1
    handlers.OnResolutionChange()
    return p.x
end
ok(defaultX(3) == 1920 - 74 - 12 - 48 and defaultX(6) == 1920 - 138 - 12 - 48
    and defaultX(7, 2) == 1920 - 58 - 12 - 48 and defaultX(7, 9) == 1920 - 42 - 12 - 48
    and defaultX(0) == 1920 - 42 - 12 - 48 and p.y == 120,
    "換解析度先套預設：moodle 64／128、選項 7 依字級（48）、字級超界與其他選項退 32")
moodleOpt = 1
p:setX(5000)
p:setY(-50)
p:prerender()
ok(p.x == 1920 - 48 and p.y == 0, "每幀夾回螢幕")
handlers.OnResolutionChange()

-- ---------- 點擊與拖曳門檻 ----------
local a = button(p, "a")
local x0, y0 = p.x, p.y
ctx.setMouse(100, 100)
a:onMouseDown(1, 1)
ctx.setMouse(104, 96)
a:onMouseMove(4, -4)
ok(p.x == x0 and p.y == y0 and a.captured == true, "移動 ≤4px（絕對位移）不拖、按下即 setCapture")
a:onMouseUp(1, 1)
ok(#clicks == 1 and clicks[1] == "a" and a.captured == false and writes == 0, "放開未超過門檻＝點擊 onClick(entry)、不存檔")
ctx.setMouse(100, 100)
a:onMouseDown(1, 1)
ctx.setMouse(90, 100)
a:onMouseMoveOutside(-10, 0)
ctx.setMouse(80, 130)
a:onMouseMoveOutside(-10, 30)
ok(p.x == x0 - 20 and p.y == y0 + 30, "超過門檻：整條 Dock 跟著滑鼠（出界仍收 move）")
a:onMouseUpOutside(0, 0)
ok(#clicks == 1 and writes == 1 and store[res()].MinidoracatUIDock.x == tostring(x0 - 20),
    "拖曳放開：不點擊、立即存位置")
local h = handleOf(p)
ctx.setMouse(200, 200)
h:onMouseDown(1, 1)
ctx.setMouse(200, 210)
h:onMouseMove(0, 10)
h:onMouseUp(1, 1)
ok(p.y == y0 + 40 and not p.collapsed and writes == 2, "從把手也能拖整條 Dock，拖曳不切換收合")

-- ---------- 右鍵 ----------
local rights = 0
D.register(spec("a", 10, { onRightClick = function(e) rights = rights + 1 end }))
tick()
a = button(p, "a")
a:onRightMouseDown(1, 1)
a:onRightMouseUp(1, 1)
a:onRightMouseDown(1, 1)
ctx.advance(800)
a:onRightMouseUp(1, 1)
a:onMouseDown(1, 1)
a:onRightMouseDown(1, 1)
a:onRightMouseUp(1, 1)
a:onMouseUp(1, 1)
ok(rights == 1, "右鍵：配對才觸發、800ms 過期作廢、左鍵按住中不接")

-- ---------- 收合：存讀 ----------
ctx.setMouse(200, 200)
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
ok(p.collapsed and ids(p) == "" and p.height == 48 and writes == 3
    and store[res()].MinidoracatUIDock.collapsed == "true", "點把手收合：入口藏起、外殼 48 高、collapsed 隨位置存檔")
local savedX = store[res()].MinidoracatUIDock.x
D._resetForTests()
D.register(spec("a", 10))
D.register(spec("b", 20))
D.register(spec("c", 10))
handlers.OnGameStart()
p = panel()
ok(p.collapsed and tostring(p.x) == savedX and ids(p) == "", "重開（RegisterWindow → TryRestore）：位置與收合狀態讀回")

-- ---------- 徽章與狀態 ----------
local st = { a = 0, b = 0, c = 0, stateA = nil, stateB = nil, active = false }
D.register(spec("a", 10, { getBadge = function() return st.a end, getState = function() return st.stateA end,
    isActive = function() return st.active end }))
D.register(spec("b", 20, { getBadge = function() return st.b end, getState = function() return st.stateB end }))
D.register(spec("c", 10, { getBadge = function() return st.c end, getStatus = function() return "c-status" end }))
tick()
st.a, st.c = 3, 5
clearDraws(p)
p:render()
local dot = p.rects[1]
ok(#p.rects == 1 and dot.w == 8 and dot.x == 48 - 10 and dot.y == 2 and #p.texts == 0 and #p.borders == 1,
    "收合外殼：有待處理只亮一個紅點（3＋5 不加總、不畫數字）")
st.stateB = "warn"
clearDraws(p)
p:render()
local frame = p.borders[1]
ok(frame.w == 48 and frame.h == 48 and math.abs(frame.r - 0.9) < 1e-9 and p.texts[1].text == "!",
    "收合外殼：任一入口 warn → 外殼紅框＋左下「!」")
st.a, st.c, st.stateB = 0, 0, nil
clearDraws(p)
p:render()
ok(#p.rects == 0 and #p.borders == 0 and #p.texts == 0, "沒有待處理也沒有警示：外殼不加任何標記")

h = handleOf(p)
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
a = button(p, "a")
st.a, st.active, st.stateA = 120, true, "on"
clearDraws(a)
a:prerender()
local bar = a.rects[2]
ok(math.abs(a.rects[1].a - 0.12) < 1e-9 and bar.w == 3 and bar.x == 0 and math.abs(bar.g - 0.85) < 1e-9,
    "開啟中：selected 淺底＋左側 3px accent 細條")
ok(math.abs(a.borders[#a.borders].g - 0.85) < 1e-9 and a.texts[#a.texts].text == "99+",
    "state on：accent 1px 框；徽章 >99 顯示 99+")
st.a, st.stateA, st.active = -1, "warn", false
clearDraws(a)
a:prerender()
local hasChip, hasRed = false, false
for _, t in ipairs(a.texts) do if t.text == "!" then hasChip = true end end
for _, b in ipairs(a.borders) do if math.abs(b.r - 0.9) < 1e-9 and b.w == 40 then hasRed = true end end
local dotRect = a.rects[#a.rects]
ok(hasChip and hasRed and dotRect.w == 8 and dotRect.x == 40 - 10, "state warn：紅框＋左下「!」；徽章 -1 畫紅點")
st.a, st.stateA = 7, nil
clearDraws(a)
a:prerender()
ok(a.texts[#a.texts].text == "7" and #a.texts == 1, "徽章 1-99 顯示數字膠囊")
st.a, st.stateA = 0, nil

-- ---------- 回呼出錯 ----------
local function boom() error("consumer bug") end
D.register({ id = "e", order = 15, label = boom, getBadge = boom, getState = boom, isActive = boom,
    getStatus = boom, drawIcon = boom, onClick = boom })
D.register(spec("f", 16, { isAvailable = boom }))
tick()
local e = button(p, "e")
local okDraw = pcall(function()
    e:prerender()
    p:prerender()
    p:render()
    e._mouseOver = true
    p:prerender()
    e._mouseOver = false
    e:forceClick()
end)
ok(okDraw and e.visible and button(p, "f") == nil and ids(p) == "a,c,e,b",
    "回呼全部拋錯：繪製／提示／點擊照常；isAvailable 拋錯＝不顯示")
ok(ISToolTip.last.description == "e", "label 拋錯時提示退回 id")
D.unregister("e")
D.unregister("f")
p:prerender()

-- ---------- 提示組字 ----------
D.register(spec("a", 10, { bind = "Bound_Toggle", getStatus = function() return st.status end,
    getBadge = function() return st.a end }))
D.register(spec("c", 10, { bind = "Unbound_Toggle", getBadge = function() return st.c end }))
tick()
a = button(p, "a")
a._mouseOver = true
p:prerender()
local tip = ISToolTip.last
ok(tip.visible and tip.description == "Na (hotkey /)" and tip.maxLineWidth == 300,
    "入口提示：名稱（快捷鍵 X）走模板、單行")
st.status = "2 waiting\nsecond"
p:prerender()
local throttled = tip.description == "Na (hotkey /)"
ctx.advance(500)
p:prerender()
ok(throttled and tip.description == "Na (hotkey /)\n2 waiting\nsecond" and tip.maxLineWidth == 1000,
    "第二行起 getStatus（可多行）；500ms 節流重建")
a._mouseOver = false
local c = button(p, "c")
c._mouseOver = true
p:prerender()
ok(tip.description == "Nc", "bind 未綁定：只有名稱，不附快捷鍵")
c._mouseOver = false
h = handleOf(p)
h._mouseOver = true
p:prerender()
ok(tip.description == "Collapse (3 entries)", "把手（展開中）：收合（N 個入口）")
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
st.c, st.stateB = 4, "warn"
ctx.advance(500)
p:prerender()
ok(tip.description == "Expand (3 entries)\nNc\nNb", "把手（收合中）：展開（N）＋每個待處理／警示入口一行（沒有狀態就只寫名稱）")
st.status = "mail"
st.a = 2
ctx.advance(500)
p:prerender()
ok(tip.description == "Expand (3 entries)\nNa: mail\nNc\nNb", "有狀態的入口用「名稱：狀態」模板")
h._mouseOver = false
p:prerender()
ok(tip.visible == false, "滑鼠離開：提示收掉")
st.a, st.c, st.stateB, st.status = 0, 0, nil, nil

-- ---------- 把手圖：吉祥物與退回 ----------
local function handleDraw()
    h = handleOf(p)
    clearDraws(h)
    local okH = pcall(h.prerender, h)
    return okH, h.draws[1], #h.rects
end
local okNone, drawNone, rectsNone = handleDraw()
ok(okNone and drawNone == nil and rectsNone == 4, "吉祥物與 chevron 都缺：退回 Skin.arrow（四列 drawRect），不拋錯")
fresh()
texOK[SLEEP], texOK[AWAKE] = true, true
D.register(spec("a", 10))
D.register(spec("b", 20))
handlers.OnGameStart()
p = panel()
local okSleep, sleepDraw = handleDraw()
p.collapsed = false
local okAwake, awakeDraw = handleDraw()
p.collapsed = true
ok(okSleep and okAwake and sleepDraw.path == SLEEP and sleepDraw.w == 32 and sleepDraw.x == 4
    and awakeDraw.path == AWAKE, "吉祥物：40 格內置中畫 32px，收合＝睡臉、展開＝醒臉")
fresh()
texOK[AWAKE], texOK[CHEVRON] = nil, true
D.register(spec("a", 10))
D.register(spec("b", 20))
handlers.OnGameStart()
p = panel()
p.collapsed = true
local okC1, down = handleDraw()
p.collapsed = false
local okC2, up = handleDraw()
ok(okC1 and okC2 and down.path == CHEVRON and down.flip == false and up.path == CHEVRON and up.flip == true,
    "任一張吉祥物缺：退回 chevronDown（展開時上下翻轉）")
texOK[SLEEP], texOK[CHEVRON] = nil, nil
fresh()

-- ---------- 快捷鍵：焦點交接 ----------
D.register(spec("a", 10))
D.register(spec("b", 20))
D.register(spec("c", 30))
handlers.OnGameStart()
p = panel()
h = handleOf(p)
if not p.collapsed then -- 前段存下的收合狀態已在 OnGameStart 讀回
    h:onMouseDown(1, 1)
    h:onMouseUp(1, 1)
end
local writesBefore = writes
local tabC, tabR = ctx.press(p, K.KEY_TAB)
ok(p.collapsed and p.wantKeyEvents == true and not tabC and not tabR and F.root ~= p,
    "沒有快捷鍵工作階段時 Dock 不搶 Tab（不消耗、不開焦點框）")
handlers.OnKeyPressed(51)
ok(p.collapsed and F.root ~= p, "其他鍵不觸發")
handlers.OnKeyPressed(52)
ok(not p.collapsed and F.root == p and F.focused() == button(p, "a"), "快捷鍵：收合中先展開，鍵盤焦點交給第一個入口")
local downC, downR = ctx.press(p, K.KEY_DOWN)
local second = F.focused()
ctx.press(p, K.KEY_UP)
ctx.press(p, K.KEY_UP)
ok(downC and downR and second == button(p, "b") and F.focused() == button(p, "c"),
    "方向鍵在入口間移動（消耗；往上越過第一個循環到最後一個）")
ctx.press(p, K.KEY_RETURN)
ok(clicks[#clicks] == "c" and F.root == p, "Enter 觸發焦點下的入口（工作階段持續）")
local escC, escR = ctx.press(p, K.KEY_ESCAPE)
ok(escC and escR and F.root == nil and p.collapsed and F.activeRoot ~= p and writes == writesBefore,
    "Esc：交還焦點、恢復收合，press 與 release 都消耗（不漏給暫停選單），暫時展開不存檔")
handlers.OnKeyPressed(52)
local opened = F.root == p and not p.collapsed
handlers.OnKeyPressed(52)
ok(opened and F.root == nil and p.collapsed, "再按一次快捷鍵＝交還焦點並恢復收合")
handlers.OnKeyPressed(52)
local win = UI.Window.new{ x = 0, y = 0, width = 200, height = 100, title = "w" }
F.onFocus(win)
p:prerender()
ok(F.root ~= p and p.collapsed, "別的視窗接手焦點：工作階段結束、恢復收合")
win:setVisible(false)
F.clear()

-- ---------- 手把入口（世界右鍵選單） ----------
local setTests = 0
ISWorldObjectContextMenu = { setTest = function() setTests = setTests + 1 return true end }
JoypadState = { players = {} }
local function menu(playerNum, test)
    local context = { options = {} }
    function context:addOption(name, target, fn) self.options[#self.options + 1] = { name = name, target = target, fn = fn } end
    local r = handlers.OnFillWorldObjectContextMenu(playerNum, context, {}, test)
    return context.options, r
end
local opts = menu(0, false)
ok(#opts == 0, "鍵盤滑鼠玩家：世界選單不加入口")
JoypadState.players[1] = {}
local probe, probeR = menu(0, true)
ok(#probe == 0 and probeR == true and setTests == 1, "手把玩家 test=true：走 setTest、不加選項")
local other = menu(1, false)
ok(#other == 0, "非玩家 0：不加")
ctx.joy[1] = { focus = nil }
opts = menu(0, false)
ok(#opts == 1 and opts[1].name == "Open family toolbar", "手把玩家：加一個「開啟家族工具列」")
opts[1].fn(opts[1].target)
ok(not p.collapsed and F.holdsJoypad(p) and F.focused() == button(p, "a"), "選項：展開並接手手把焦點，落在第一個入口")
p:onJoypadDirDown(ctx.joy[1])
ok(F.focused() == button(p, "b"), "手把方向下：移到下一個入口")
p:onJoypadDown(Joypad.BButton, ctx.joy[1])
ok(not F.holdsJoypad(p) and ctx.joy[1].focus == nil and p.collapsed and p.visible, "B：交還手把焦點、恢復收合，Dock 不被關掉")
opts = menu(0, false)
opts[1].fn(opts[1].target)
p:onJoypadDown(Joypad.AButton, ctx.joy[1])
ok(clicks[#clicks] == "a" and not F.holdsJoypad(p) and p.collapsed, "A 觸發入口：先交還手把（啟動器）再呼叫 onClick")
ctx.joy[1] = nil
JoypadState.players[1] = nil

-- ---------- 通知避開區 ----------
local avoid = nil
for _, item in ipairs(UI.Toast.avoid) do
    if item.owner == "MinidoracatUIDock" then avoid = item.fn end
end
local ax, ay, aw, ah
if avoid then ax, ay, aw, ah = avoid() end
ok(avoid ~= nil and ax == p.x and ay == p.y and aw == p.width and ah == p.height, "Toast 避開區：Dock 可見時回它的矩形")
player = false
p:prerender()
ok(p.visible == false and avoid() == nil and D.isDocked("a") == false, "沒有玩家（回主選單）：自我隱藏、避開區回 nil、isDocked false")
player = true
tick()
ok(p.visible, "玩家回來：輪詢重新顯示")
local collapsedTargets = p:keyboardTargets()
handleOf(p):onMouseDown(1, 1)
handleOf(p):onMouseUp(1, 1)
local t1, t2 = p:keyboardTargets(), p:keyboardTargets()
ok(p.collapsed == false and collapsedTargets == nil and t1 == t2 and #t1[1].controls == 3
    and t1[1].controls[1] == button(p, "a"), "keyboardTargets：收合時 nil；展開時重用同一張表、一組入口按鈕")

-- ---------- 沒有 Focus：快捷鍵只切換收合 ----------
fresh()
UI.Focus = nil
dofile(DOCK_LUA)
UI.Focus = F
D = UI.Dock
D.register(spec("a", 10))
D.register(spec("b", 20))
handlers.OnGameStart()
p = panel()
local w0 = writes
handlers.OnKeyPressed(52)
local first = p.collapsed
handlers.OnKeyPressed(52)
ok(first == true and p.collapsed == false and writes == w0 + 2 and not p.wantKeyEvents and F.root ~= p,
    "UI.Focus 缺席：快捷鍵只切換收合（並存檔），不要 key 事件")
opts = menu(0, false)
ok(#opts == 0, "UI.Focus 缺席：手把世界選單不加入口")

-- ---------- 還原 ----------
D._resetForTests()
dofile(DOCK_LUA)
UI.Dock._resetForTests()
UI.Toast._resetForTests()
UI.Skin._resetForTests()
F.clear()
getCore, getText, getSpecificPlayer, getTexture = keep.getCore, keep.getText, keep.getSpecificPlayer, keep.getTexture
Events, keyBinding, ISLayoutManager, ISToolTip = keep.Events, keep.keyBinding, keep.ISLayoutManager, keep.ISToolTip
getKeyName, JoypadState, ISWorldObjectContextMenu = keep.getKeyName, keep.JoypadState, keep.ISWorldObjectContextMenu
ISPanel.drawTextureScaled, ISPanel.drawTextureAllPoint = keep.drawTextureScaled, keep.drawTextureAllPoint
K.KEY_PERIOD = keep.KEY_PERIOD

return 66
