-- 切片 rev 29：Toast 寬度跟 NewSmall 字高放大（toastFontWidth、Toast.currentWidth）、夾在螢幕內、自動欄右緣不變、
-- 玩家位置照目前寬度夾回、存讀保住右半部位置的右緣、移動模式範例框照目前寬度；紀錄視窗的時間欄保留寬照最寬的時間字串。
-- 契約見 smoke_harness.lua 的切片載入器註解。起因：字型大小 3 以上（畫面高 1212 起的自動）更新概要 3 行被截（2026-11-17）。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end
print("情境 rev29：通知寬度跟字型放大、夾在螢幕內、位置存讀、移動模式、紀錄視窗時間欄")

-- ---------- 本切片自備的全域（用完全部還原） ----------
local keep = {
    getCore = getCore, getTextManager = getTextManager, getText = getText, Events = Events,
    ISLayoutManager = ISLayoutManager, UIManager = UIManager, PZAPI = PZAPI, Dock = UI.Dock,
    dockCap = UI.CAPABILITIES.dock, historyCap = UI.CAPABILITIES.toastHistory, Toast = UI.Toast, History = UI.ToastHistory,
}
local screenW, screenH, fontH = 1920, 1080, 12
getCore = function()
    return { getScreenWidth = function() return screenW end, getScreenHeight = function() return screenH end }
end
getTextManager = function()
    return {
        MeasureStringX = function(_, _, text) return string.len(text) * 10 end,
        getFontHeight = function() return fontH end,
    }
end
-- 相對時間用接近真實長度的字（共用 stub 回 "[key]"，比真的時間字串長得多）
getText = function(key, a)
    if key == "IGUI_MinidoracatUI_History_MinutesAgo" then return tostring(a) .. " minutes ago" end
    if key == "IGUI_MinidoracatUI_History_HoursAgo" then return tostring(a) .. " hours ago" end
    if key == "IGUI_MinidoracatUI_History_JustNow" then return "just now" end
    return "[" .. tostring(key) .. "]"
end
local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = { Add = function(fn) handlers[name] = fn end }
    rawset(t, name, ev)
    return ev
end })
-- ISLayoutManager：同 test_rev21（讀回的值是字串）
local store = {}
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
    store[res()] = store[res()] or {}
    for name, w in pairs(ISLayoutManager.windows) do
        local layout = {}
        w.funcs.SaveLayout(w.target, name, layout)
        for k, v in pairs(layout) do layout[k] = tostring(v) end
        store[res()][name] = layout
    end
end
UIManager, PZAPI, UI.Dock, UI.CAPABILITIES.dock = nil, nil, nil, false

dofile(ctx.MOD_LUA .. "Widgets/Toast.lua")
local Toast = UI.Toast
UI.CAPABILITIES.toastHistory = false
dofile(ctx.MOD_LUA .. "Widgets/ToastHistory.lua")
local H = UI.ToastHistory
Toast._resetForTests()
check(UI.API_REVISION >= 29 and UI.CAPABILITIES.toastFontWidth == true and Toast.WIDTH == 300 and H ~= nil,
    "API_REVISION 至少 29；Toast 載入後 toastFontWidth 翻 true；Toast.WIDTH 仍是 300")

local function settle(...)
    ctx.advance(300)
    for _, t in ipairs({ ... }) do t:prerender() end
end

-- ---------- 寬度表：字高 <= 16 是 300；再大照比例 ×1.06（原版字級 2–5＝19／26／33／38，CatLang 20／25／30／34） ----------
local WANT = { [12] = 300, [16] = 300, [18] = 354, [19] = 373, [20] = 392, [25] = 486, [26] = 505,
    [30] = 580, [33] = 636, [34] = 655, [38] = 730 }
local allMatch, got = true, {}
for _, fh in ipairs({ 12, 16, 18, 19, 20, 25, 26, 30, 33, 34, 38 }) do
    fontH = fh
    local w = Toast.currentWidth()
    got[#got + 1] = fh .. "=" .. w
    if w ~= WANT[fh] then allMatch = false end
end
check(allMatch, "currentWidth 照字高：" .. table.concat(got, " "))

-- ---------- 每則通知用目前寬度斷行；自動欄右緣不變、往左長 ----------
local COL_RIGHT = 1920 - (10 + 32) - 60 - 16 -- 1802：moodle 欄與 Dock 預設格的左邊
local long = string.rep("A", 300)
local edges = {}
for _, fh in ipairs({ 16, 26, 38 }) do
    fontH = fh
    Toast._resetForTests()
    local t = Toast.show({ title = "T", message = long, maxLines = 3 })
    settle(t)
    local w = Toast.currentWidth()
    edges[#edges + 1] = { fh = fh, t = t, w = w }
end
local wrapOK, rightOK = true, true
for _, e in ipairs(edges) do
    if e.t.width ~= e.w or #e.t.lines ~= 3 or string.len(e.t.lines[1]) ~= math.floor((e.w - 16) / 10) then wrapOK = false end
    if e.t.x + e.t.width ~= COL_RIGHT then rightOK = false end
end
check(wrapOK, "字高 16／26／38：通知寬＝currentWidth，第一行字數＝(寬 - 16) / 10、照樣排滿 maxLines")
check(rightOK, "字高 16／26／38：自動欄右緣都在 " .. COL_RIGHT .. "（寬度往左長）")

-- ---------- 窄畫面＋大字級：寬夾在螢幕寬減兩側邊距內，左緣不出畫面；更窄時不比 300 窄 ----------
screenW, screenH, fontH = 640, 480, 38
Toast._resetForTests()
local narrow = Toast.show({ title = "T", message = long, maxLines = 3 })
settle(narrow)
check(narrow.width == 640 - 32 and narrow.x >= 16 and narrow.x + narrow.width <= 640,
    "螢幕寬 640、字高 38：寬 608、整則在畫面內（x=" .. narrow.x .. "）")
screenW = 320
check(Toast.currentWidth() == 300, "螢幕寬 320：寬仍是 300（不比字高 16 時窄）")
screenW, screenH = 1920, 1080

-- ---------- 玩家位置：照目前寬度夾回螢幕內 ----------
Toast._resetForTests()
fontH = 38
Toast.setAnchor(5000, 0)
check(Toast.anchor.x == 1920 - 730, "字高 38：setAnchor(5000, 0) 夾成 x=1190（整則看得到）")

-- ---------- 存讀：多存 w；右半部的位置換字型後保住右緣，左半部照舊；舊存檔沒有 w 當 300 ----------
Toast._resetForTests()
handlers.OnGameStart()
fontH = 16
Toast.setAnchor(1500, 100)
local saved = store["1920x1080"].MinidoracatUIToast
check(saved.x == "1500" and saved.w == "300", "存檔多一個 w（存的當下的通知寬）")
fontH = 38
Toast.anchor = nil
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor.x == 1070 and Toast.anchor.x + 730 == 1800, "字高 16 時存在右半部的位置，字高 38 讀回保住右緣（x 1500 → 1070）")
fontH = 16
Toast.setAnchor(100, 100)
fontH = 38
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor.x == 100, "左半部的位置讀回照舊（往右長）")
store["1920x1080"].MinidoracatUIToast = { x = "1500", y = "100" }
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor.x == 1070, "rev 28 以前的存檔沒有 w：當成 300，照樣保住右緣")
fontH = 16
Toast.setAnchor(750, 100)
check(store["1920x1080"].MinidoracatUIToast.r == "0", "存檔多一個 r：放的當下在左半部＝0")
fontH = 26
ISLayoutManager.TryRestore("MinidoracatUIToast")
ISLayoutManager.OnPostSave() -- 字高 26 時遊戲存檔：中心 750+252 已越過中線
fontH = 16
ISLayoutManager.TryRestore("MinidoracatUIToast")
check(Toast.anchor.x == 750, "換大字型再換回：左半部的位置照舊（不因放大時越過中線改判成右邊）")
Toast.setAnchor(nil)

-- ---------- 移動模式：範例框照目前寬度，起點在自動欄、拖到右緣夾住、完成存框的位置 ----------
fontH = 26
Toast._resetForTests()
H.move()
local p = H._placerForTests()
local f = p.frame
check(f.width == 505 and f:getX() == COL_RIGHT - 505 and f:getY() == 60,
    "字高 26：範例框寬 505，起點右緣對齊自動欄（x=" .. f:getX() .. "）")
ctx.setMouse(1500, 70)
f:onMouseDown(0, 0)
ctx.setMouse(5000, 70)
f:onMouseMove(0, 0)
f:onMouseUp(0, 0)
check(f:getX() == 1920 - 505, "拖到最右：範例框照目前寬度夾在螢幕內")
p.btnDone:forceClick()
check(Toast.anchor ~= nil and Toast.anchor.x == 1920 - 505, "完成：存下的位置就是範例框的位置")
ctx.setMouse(0, 0)

-- ---------- 紀錄視窗：時間欄保留寬照最寬的時間字串（"59 minutes ago" 140px＋內距 10＋間距 8） ----------
fontH = 12
Toast._resetForTests()
Toast.show({ title = string.rep("S", 40), message = "m" })
H.toggle()
local win = H._windowForTests()
win.status:prerender()
local row = win._rows[1]
local textX = 10 + 3 + 8
check(win._timeReserve == 158 and row.timeReserve == 158
    and string.len(row.titleText) * 10 <= row.width - textX - 158,
    "時間欄保留寬 158（比固定的 96 寬）：來源名稱截在它左邊，不和右側時間重疊")

-- ---------- 還原 ----------
H._resetForTests()
Toast._resetForTests()
getCore, getTextManager, getText, Events = keep.getCore, keep.getTextManager, keep.getText, keep.Events
ISLayoutManager, UIManager, PZAPI = keep.ISLayoutManager, keep.UIManager, keep.PZAPI
UI.Dock, UI.CAPABILITIES.dock, UI.CAPABILITIES.toastHistory = keep.Dock, keep.dockCap, keep.historyCap
UI.Toast, UI.ToastHistory = keep.Toast, keep.History
return n
