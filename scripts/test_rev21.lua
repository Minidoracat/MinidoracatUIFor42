-- rev 21：Toast 位置（自動欄、只往下避、預留高度、玩家位置與方向、存讀）、紀錄、預設停留與游標暫停，
-- 以及紀錄視窗、移動模式與 Dock 入口（Widgets/Toast.lua、Widgets/ToastHistory.lua）。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
local K, F = Keyboard, UI.Focus
local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end
print("情境 rev21：通知位置／玩家位置與存讀／紀錄／停留與游標暫停／紀錄視窗／移動模式／Dock 入口")

-- ---------- 本切片自備的全域（用完全部還原） ----------
local keep = {
    getCore = getCore, Events = Events, ISLayoutManager = ISLayoutManager, PZAPI = PZAPI,
    isShiftKeyDown = isShiftKeyDown, UIManager = UIManager, Dock = UI.Dock, dockCap = UI.CAPABILITIES.dock,
    Toast = UI.Toast,
}

local screenW, screenH = 1920, 1080
getCore = function()
    return { getScreenWidth = function() return screenW end, getScreenHeight = function() return screenH end }
end
local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = { Add = function(fn) handlers[name] = fn end }
    rawset(t, name, ev)
    return ev
end })
-- ISLayoutManager：以解析度分組存 layout，讀回時值變字串（同 layout.ini，ISLayoutManager.lua:125-184）
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
UIManager = nil

-- 重新載入 Toast：在本切片的 Events 上登記位置存讀
dofile(ctx.MOD_LUA .. "Widgets/Toast.lua")
local Toast = UI.Toast
check(Toast ~= keep.Toast and handlers.OnGameStart ~= nil and handlers.OnResolutionChange ~= nil,
    "Toast 載入時登記 OnGameStart（位置存讀）與 OnResolutionChange")
Toast._resetForTests()

local function settle(...)
    ctx.advance(300) -- 過了進場
    for _, t in ipairs({ ... }) do t:prerender() end
end

-- ---------- 自動位置 ----------
local COL_X = 1920 - (10 + 32) - 60 - 16 - 300 -- 1502：moodle 欄（32px）與 Dock 預設格的左邊
local a = Toast.show("a")
settle(a)
check(a.x == COL_X and a.y == 60, "自動欄：右緣在 moodle 欄與 Dock 預設格左邊，從 60 起疊")
Toast._resetForTests()
UIManager = { getMoodleUI = function() return { getWidth = function() return 48 end } end }
a = Toast.show("a")
settle(a)
check(a.x == 1920 - (10 + 48) - 60 - 16 - 300, "moodle 圖示放大到 48px：欄位跟著往左讓")
UIManager = nil

-- 障礙物在 150..200：一則（60..116）碰不到，三則的預留區（60..244）碰得到——位置不看目前有幾則
Toast._resetForTests()
Toast.setAvoid("box", function() return 1500, 150, 400, 50 end)
local one = Toast.show("one")
settle(one)
local y1 = one.y
local two = Toast.show("two")
settle(one, two)
check(y1 == 208 and one.y == 208 and two.y == 208 + one.height + 8,
    "閃避看預留的三則高度：第一則就在障礙物下方，第二則來了也不跳")

Toast._resetForTests()
Toast.setAvoid("tall", function() return 1300, 40, 600, 1000 end)
local s = Toast.show("s")
settle(s)
check(s.x == COL_X and s.y == 60, "下方放不下：留在原欄原位，不往左移（rev 20 會移到 x=984）")

-- ---------- 玩家放的位置 ----------
Toast.dismiss(s) -- 留著兩個避開區，只清掉上一段的通知
Toast.setAvoid("cover", function() return 0, 0, 800, 600 end)
Toast.setAnchor(100, 200)
local p1, p2 = Toast.show("p1"), Toast.show("p2")
settle(p1, p2)
check(p1.x == 100 and p1.y == 200 and p2.y == 200 + p1.height + 8, "玩家放的位置優先、不避開；上半部往下疊")

Toast._resetForTests()
Toast.setAnchor(100, 900)
local tall = Toast.show({ message = string.rep("A", 60), maxLines = 3 })
local low = Toast.show("low")
settle(tall, low)
check(Toast.anchor.up == true and tall.height == 80 and tall.y == 900 + 56 - 80 and low.y == tall.y - 8 - low.height,
    "下半部往上疊：第一則下緣貼著位置（多行往上長），第二則在它上面")

Toast.setAnchor(5000, -50)
check(Toast.anchor.x == 1920 - 300 and Toast.anchor.y == 0 and Toast.anchor.up == false, "位置夾回螢幕內（第一則整個看得到）")
Toast.setAnchor(nil)
check(Toast.anchor == nil, "setAnchor(nil)：回到自動位置")

-- ---------- 存讀（layout.ini，每種解析度一份） ----------
Toast._resetForTests()
handlers.OnGameStart()
check(ISLayoutManager.windows.MinidoracatUIToast ~= nil and Toast.anchor == nil, "進遊戲登記 layout；沒存過＝自動位置")
local w0 = writes
Toast.setAnchor(321.7, 654.2)
local saved = store["1920x1080"] and store["1920x1080"].MinidoracatUIToast
check(writes == w0 + 1 and saved and saved.x == "321" and saved.y == "654", "設定位置立刻寫 layout.ini（取整數）")
Toast.anchor = nil
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor ~= nil and Toast.anchor.x == 321 and Toast.anchor.y == 654 and Toast.anchor.up == true,
    "讀回字串座標並重算方向（654＋28 在下半部）")
screenW, screenH = 1280, 720
handlers.OnResolutionChange()
check(Toast.anchor == nil, "換到沒存過的解析度：回自動位置")
screenW, screenH = 1920, 1080
handlers.OnResolutionChange()
check(Toast.anchor ~= nil and Toast.anchor.x == 321, "換回來：讀回這個解析度存的位置")
Toast.setAnchor(nil)
Toast.anchor = { x = 1, y = 1, up = false } -- 記憶體裡還留著舊值
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor == nil, "恢復預設位置後存的那一行沒有座標：讀回是自動位置")

-- ---------- 紀錄 ----------
Toast._resetForTests()
local long = string.rep("B", 60)
local h1 = Toast.show({ title = "Src", message = long, colors = { border = { r = 0.1, g = 0.2, b = 0.3, a = 1 } } })
local e1 = Toast.history[1]
check(#Toast.history == 1 and e1.message == long and string.sub(h1.message, -3) == "..." and e1.title == "Src"
    and e1.border.b == 0.3 and e1.atMs == ctx.now() and Toast.historyCount == 1,
    "紀錄存完整訊息（通知框截成 ...）、來源、色條與時間")
for i = 2, 9 do Toast.show("m" .. i) end
check(#Toast.active == 3 and #Toast.pending == 5 and #Toast.history == 9 and Toast.history[9].message == "m9",
    "排不進佇列被丟掉的第 9 則也在紀錄裡")
for i = 10, 105 do Toast.show("m" .. i) end
check(#Toast.history == 100 and Toast.history[1].message == "m6" and Toast.history[100].message == "m105"
    and Toast.historyCount == 105, "只留最近 100 則（最舊的先丟），historyCount 是累計筆數")

-- ---------- 停留與游標暫停 ----------
Toast._resetForTests()
check(Toast.show("d").holdMs == 5000 and Toast.show({ message = "e", holdMs = 1200 }).holdMs == 1200,
    "預設停留 5 秒；consumer 指定的 holdMs 照舊")
Toast._resetForTests()
local hv = Toast.show({ message = "hover", holdMs = 1000 })
ctx.setMouse(COL_X + 30, 70)
ctx.advance(100)
hv:prerender()
check(hv.pausedMs == 0, "進場階段游標在框內也不暫停")
ctx.advance(200)
hv:prerender()
for _ = 1, 30 do
    ctx.advance(100)
    hv:prerender()
end
check(#Toast.active == 1 and hv.pausedMs >= 2900, "停留階段游標在框內：暫停計時，超過 250＋1000＋400 仍在")
ctx.setMouse(0, 0)
for _ = 1, 20 do
    ctx.advance(100)
    if #Toast.active > 0 then hv:prerender() end
end
check(#Toast.active == 0, "游標移開：接著計時，跑完停留與淡出就消失")
check(hv.wantMouseEvents == false, "游標暫停不靠滑鼠事件：通知照樣不吃點擊")

-- ---------- 紀錄視窗與 Dock 入口 ----------
local captured, refreshes = nil, 0
UI.Dock = {
    register = function(spec) captured = spec return true end,
    refresh = function() refreshes = refreshes + 1 end,
}
UI.CAPABILITIES.dock = true
local loads = 0
PZAPI = { ModOptions = { Dict = {} } }
function PZAPI.ModOptions:getOptions(id) return self.Dict[id] end
function PZAPI.ModOptions:create(id, name)
    local page = { id = id, name = name, opts = {} }
    function page:addTickBox(oid, label, value, tooltip)
        local opt = { id = oid, label = label, value = value, tooltip = tooltip }
        function opt:getValue() return self.value end
        self.opts[oid] = opt
        return opt
    end
    function page:getOption(oid) return self.opts[oid] end
    self.Dict[id] = page
    return page
end
function PZAPI.ModOptions:load() loads = loads + 1 end
local shift = false
isShiftKeyDown = function() return shift end
UI.CAPABILITIES.toastHistory = false
dofile(ctx.MOD_LUA .. "Widgets/ToastHistory.lua")
local H = UI.ToastHistory
local page = PZAPI.ModOptions.Dict.MinidoracatUIFor42
local opt = page and page:getOption("ToastHistoryEntry")
check(UI.CAPABILITIES.toastHistory == true and H ~= nil and page.name == "UI_optionscreen_binding_MinidoracatUI"
    and opt ~= nil and opt.value == true and opt.label == "IGUI_MinidoracatUI_History_DockOption"
    and opt.tooltip == "IGUI_MinidoracatUI_History_DockOption_tooltip",
    "載入後 toastHistory 翻 true；選項 → MODS 有 MinidoracatUI 頁與預設勾選的入口選項")
check(captured ~= nil and captured.id == "toasthistory" and captured.order == 100 and captured.iconKey == "bell"
    and captured.getBadge == nil and captured.getState == nil and captured.label() == "[IGUI_MinidoracatUI_History_Title]",
    "Dock 入口：order 100、鈴鐺圖示、沒有徽章與狀態（不顯示未讀數字或紅點）")
local avail1 = captured.isAvailable()
local avail2 = captured.isAvailable()
check(avail1 == true and avail2 == true and loads == 1, "入口顯示：第一次用到才讀一次選項檔，之後回快取")
opt.value = false
page:apply()
check(captured.isAvailable() == false and refreshes == 1, "選項關掉並套用：入口隱藏、Dock 重新整理")
opt.value = true
page:apply()

Toast._resetForTests()
Toast.show({ title = "A", message = "first" })
local wide = string.rep("W ", 40)
Toast.show({ title = "B", message = wide })
ctx.advance(3 * 60000)
Toast.show("third")
captured.onClick(captured)
local win = H._windowForTests()
check(H.isOpen() and win ~= nil and win:getIsVisible() and captured.isActive() == true and win.inUIManager,
    "點 Dock 入口打開紀錄視窗（入口顯示作用中）")
win.status:prerender()
local r1, r2, r3 = win._rows[1], win._rows[2], win._rows[3]
check(r1.entry.message == "third" and r2.entry.message == wide and r3.entry.message == "first"
    and not win.empty:getIsVisible(), "最新的在最上面")
check(#r2.lines >= 2 and not string.find(table.concat(r2.lines, ""), "...", 1, true)
    and r2.height == 6 * 2 + 12 * (1 + #r2.lines) and r2.y == r1.height and r3.y == r1.height + r2.height,
    "長訊息換成多行、不截字，列高跟著行數，列依序往下排")
r1:prerender()
r3:prerender()
check(r1.timeText == "[IGUI_MinidoracatUI_History_JustNow]" and r3.timeText == "[IGUI_MinidoracatUI_History_MinutesAgo]",
    "相對時間：剛剛／N 分鐘前")
Toast.show("fourth")
win.status:prerender()
check(win._rows[1].entry.message == "fourth" and win._rows[4].entry.message == "first", "視窗開著時有新通知：下一幀重排")
Toast._resetForTests()
win.status:prerender()
check(win.empty:getIsVisible() and not win._rows[1]:getIsVisible(), "沒有紀錄：顯示說明、隱藏所有列")
check(win.btnReset:isEnabled() == false, "沒有玩家位置：「恢復預設位置」不能按")
Toast.setAnchor(200, 200)
win.status:prerender()
check(win.btnReset:isEnabled() == true, "有玩家位置：可以按")
win.btnReset:forceClick()
check(Toast.anchor == nil, "按「恢復預設位置」：回自動位置")
win.status.text = string.rep("kept ", 16)
win:setWidth(300)
win.onResize(win, 300, win.height)
local tm, fits = getTextManager(), true
for _, line in ipairs(win.status.lines) do
    if tm:MeasureStringX(win.font, line) > 300 - 20 then fits = false end
end
check(#win.status.lines >= 2 and fits and win.status:getY() + win.status:getHeight() <= win.height,
    "底部說明放不下一行時換行（長譯文、窄視窗）：每行放得下、整塊在視窗內")
check(pcall(win.prerender, win) and pcall(win.render, win) and pcall(win.empty.prerender, win.empty),
    "紀錄視窗的繪製不拋錯")
captured.onClick(captured)
check(not H.isOpen() and captured.isActive() == false, "再點一次入口：關掉視窗")

-- ---------- 移動模式 ----------
Toast._resetForTests()
H.move()
local p = H._placerForTests()
local f = p and p.frame
check(p ~= nil and p.inUIManager and p._nativeAlwaysOnTop == true and f:getX() == COL_X and f:getY() == 60
    and p.up == false, "移動模式：範例框從目前的自動位置開始，全螢幕層置頂")
check(F.root == p and F.focused() == f and p:keyboardTargets() == p:keyboardTargets(),
    "範例框拿到焦點框；keyboardTargets 每次回同一張表（不配置）")
f:onFocusKey(K.KEY_RIGHT)
shift = true
f:onFocusKey(K.KEY_DOWN)
shift = false
check(f:getX() == COL_X + 10 and f:getY() == 61, "方向鍵每次 10px，按住 Shift 每次 1px")
ctx.setMouse(1600, 70)
f:onMouseDown(0, 0)
ctx.setMouse(1603, 72)
f:onMouseMove(3, 2)
check(f:getX() == COL_X + 10 and f:getY() == 61 and f.captured == true, "拖曳 4px 內不動（同 Dock 門檻）")
ctx.setMouse(1600 - 900, 70 + 700)
f:onMouseMoveOutside(0, 0)
f:onMouseUp(0, 0)
check(f:getX() == COL_X + 10 - 900 and f:getY() == 61 + 700 and p.up == true and f.captured == false,
    "拖到下半部：範例框跟著移動、改成往上疊；放開解除 capture")
ctx.setMouse(0, 0)
f:onMouseDown(0, 0)
ctx.setMouse(5000, 5000)
f:onMouseMove(0, 0)
f:onMouseUp(0, 0)
check(f:getX() == 1920 - 300 and f:getY() == 1080 - 56, "範例框夾在螢幕內")
local stackTop = f:getY() + 56 - 184
check(p.btnDone:getY() + p.btnDone.height <= stackTop and p.btnCancel:getX() + p.btnCancel.width <= 1920
    and p.btnDone:getY() >= 0, "下半部：按鈕列放在三格堆疊的上方、不出螢幕")
check(pcall(p.prerender, p) and pcall(f.prerender, f) and pcall(p.render, p), "移動模式的繪製不拋錯")
local w1 = writes
local pressed, released = ctx.press(p, K.KEY_RETURN)
check(pressed and released and Toast.anchor ~= nil and Toast.anchor.x == 1620 and Toast.anchor.y == 1024
    and Toast.anchor.up == true and writes == w1 + 1 and H._placerForTests() == nil and not p.inUIManager
    and F.root ~= p, "Enter：存下位置並寫 layout.ini、關掉移動模式；按下與放開都被吃掉")

H.move()
p = H._placerForTests()
f = p.frame
check(f:getX() == 1620 and f:getY() == 1024, "再開移動模式：從玩家放的位置開始")
f:onFocusKey(K.KEY_LEFT)
pressed, released = ctx.press(p, K.KEY_ESCAPE)
check(pressed and released and H._placerForTests() == nil and Toast.anchor.x == 1620,
    "Esc：不存檔就關，按下與放開都被吃掉（不漏給遊戲開暫停選單）")
H.move()
p = H._placerForTests()
p.btnReset:forceClick()
check(Toast.anchor == nil and H._placerForTests() == nil, "移動模式的「恢復預設位置」：回自動位置並關閉")
H.move()
p = H._placerForTests()
p.frame:onFocusKey(K.KEY_UP)
p.btnCancel:forceClick()
check(Toast.anchor == nil and H._placerForTests() == nil, "「取消」：不存檔")
H.move()
p = H._placerForTests()
p.btnDone:forceClick()
check(Toast.anchor ~= nil and Toast.anchor.x == COL_X and Toast.anchor.y == 60, "「完成」：存下目前的位置")
H.move()
p = H._placerForTests()
check(p:onMouseDown(5, 5) == true and p:onMouseWheel(1) == true, "移動模式吃掉範例框外的點擊與滾輪")
p:onEscape()
ctx.joy[1] = { focus = nil }
H.move()
p = H._placerForTests()
check(string.find(table.concat(p.hintLines, ""), "HintJoypad", 1, true) ~= nil, "手把玩家：說明改成十字鍵／A／B")
p:onEscape()
ctx.joy[1] = nil

captured.onClick(captured)
H.move()
handlers.OnMainMenuEnter()
check(not H.isOpen() and H._placerForTests() == nil, "回主選單：收掉紀錄視窗與移動模式")

-- ---------- 還原 ----------
H._resetForTests()
Toast._resetForTests()
F.clear()
UI.Dock, UI.CAPABILITIES.dock = keep.Dock, keep.dockCap
getCore, Events, ISLayoutManager, PZAPI = keep.getCore, keep.Events, keep.ISLayoutManager, keep.PZAPI
isShiftKeyDown, UIManager = keep.isShiftKeyDown, keep.UIManager
ctx.setMouse(0, 0)
return n
