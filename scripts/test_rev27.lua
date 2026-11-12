-- rev 27：工具列的玩家設定（Widgets/Dock.lua＋Widgets/DockSettings.lua，2026-11-12 設計稿四項照建議）：
-- 閒置時不透明度（選項下拉、把手右鍵子選單、徽章與警示不變淡、用著的時候回 100%）、逐個入口顯示／隱藏
-- （Dock.ini、藏起的仍算已停靠、還有入口被藏時把手一定留著）、設定視窗（鍵盤從把手進去）、register 回原因、
-- 直排／橫排超出螢幕換行。DockSettings 缺席時的退路（選單照舊 4 項、把手不是焦點目標）由 rev13_dock／rev21_dock 守。
-- 契約見 smoke_harness.lua 的切片載入器註解與 ARCHITECTURE §3.16。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
local F, K = UI.Focus, Keyboard
local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end
print("情境 rev27：工具列不透明度／入口顯示與隱藏／把手保留／設定視窗與鍵盤路徑／register 原因／溢出換行／零配置")

-- ---------- 本切片自備的全域（用完全部還原） ----------
local SETTINGS_MOD = "MinidoracatUI/Widgets/DockSettings"
local keep = {
    getCore = getCore, getText = getText, getSpecificPlayer = getSpecificPlayer, Events = Events,
    ISLayoutManager = ISLayoutManager, ISToolTip = ISToolTip, PZAPI = PZAPI, ISContextMenu = ISContextMenu,
    absX = ISPanel.getAbsoluteX, absY = ISPanel.getAbsoluteY, Dock = UI.Dock, dockCap = UI.CAPABILITIES.dock,
    prefsCap = UI.CAPABILITIES.dockPrefs, KEY_PERIOD = K.KEY_PERIOD, getTexture = getTexture,
    drawTextureScaled = ISPanel.drawTextureScaled, getFileReader = getFileReader, getFileWriter = getFileWriter,
    preload = package.preload[SETTINGS_MOD], loaded = package.loaded[SETTINGS_MOD],
}

local screenW, screenH = 1920, 1080
local core = {
    getScreenWidth = function() return screenW end,
    getScreenHeight = function() return screenH end,
    getOptionMoodleSize = function() return 1 end,
    getOptionFontSizeReal = function() return 1 end,
    getKey = function(_, name) if name == "MinidoracatUI_Dock" then return 52 end return 0 end,
}
getCore = function() return core end
K.KEY_PERIOD = 52
local playerObj = {}
getSpecificPlayer = function() return playerObj end
getText = function(key) return "[" .. tostring(key) .. "]" end

ISPanel.getAbsoluteX = function(self)
    local x, p = self.x, self.parent
    while p do x, p = x + p.x, p.parent end
    return x
end
ISPanel.getAbsoluteY = function(self)
    local y, p = self.y, self.parent
    while p do y, p = y + p.y, p.parent end
    return y
end

local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = { Add = function(fn) handlers[name] = fn end }
    rawset(t, name, ev)
    return ev
end })

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

ISToolTip = {}
ISToolTip.__index = ISToolTip
function ISToolTip:new()
    local t = setmetatable({ visible = false, description = "", width = 0, height = 0 }, ISToolTip)
    ISToolTip.last = t
    return t
end
function ISToolTip:setOwner(o) self.owner = o end
function ISToolTip:setVisible(v) self.visible = v end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:addToUIManager() end
function ISToolTip:removeFromUIManager() end
function ISToolTip:doLayout() self.width, self.height = 200, 30 end
function ISToolTip:setDesiredPosition(x, y) self.px, self.py = x, y end

-- PZAPI.ModOptions：同 rev21_dock，另記 dockOpacity
local ini, loads, saves = {}, 0, 0
PZAPI = { ModOptions = { Dict = {} } }
function PZAPI.ModOptions:create(id, name)
    local page = { modOptionsID = id, name = name, dict = {}, apply = function() end }
    function page:addComboBox(oid, label, tooltip)
        local o = { type = "combobox", id = oid, name = label, tooltip = tooltip, values = {}, selected = 1 }
        function o:addItem(item, isSelected)
            self.values[#self.values + 1] = getText(item)
            if isSelected then self.selected = #self.values end
        end
        function o:getValue() return self.selected end
        function o:setValue(v) self.selected = v end
        self.dict[oid] = o
        return o
    end
    self.Dict[id] = page
    return page
end
function PZAPI.ModOptions:getOptions(id) return self.Dict[id] end
function PZAPI.ModOptions:load()
    loads = loads + 1
    local page = self.Dict.MinidoracatUIFor42
    for key, value in pairs(ini) do
        if page and page.dict[key] then page.dict[key].selected = value end
    end
end
function PZAPI.ModOptions:save()
    saves = saves + 1
    for key, o in pairs(self.Dict.MinidoracatUIFor42.dict) do ini[key] = o.selected end
end

-- ISContextMenu：原版的子選單寫法（getNew＋addSubMenu，ISChat.lua:274-287）
local menus = {}
local function newMenu(player, x, y)
    local m = { player = player, x = x, y = y, width = 150, options = {}, visible = true }
    function m:addOption(name, target, fn, p1)
        local o = { name = name, target = target, fn = fn, p1 = p1 }
        self.options[#self.options + 1] = o
        return o
    end
    function m:setOptionChecked(o, v) o.checkMark = v end
    function m:setX(v) self.x = v end
    function m:getIsVisible() return self.visible end
    function m:getNew(parent)
        local s = newMenu(parent.player, parent.x, parent.y)
        s.parentMenu = parent
        return s
    end
    function m:addSubMenu(option, sub) option.sub = sub end
    return m
end
ISContextMenu = {}
function ISContextMenu.get(player, x, y)
    local last = menus[#menus]
    if last then last.visible = false end
    local m = newMenu(player, x, y)
    menus[#menus + 1] = m
    return m
end
local function pick(m, i)
    local top = m.parentMenu or m
    top.visible = false -- 原版選了先 closeAll 再呼叫（ISContextMenu.lua:66-70）
    m.options[i].fn(m.options[i].target, m.options[i].p1)
end

-- 記憶體檔案系統（同 rev24）：寫入一開就截斷、close 時落盤；讀取照 readLine
local disk, writes, readerThrows = {}, 0, false
local PREFS = "MinidoracatUI/Dock.ini"
getFileWriter = function(name)
    local buf = {}
    return {
        write = function(_, s) buf[#buf + 1] = s end,
        close = function()
            disk[name] = table.concat(buf)
            writes = writes + 1
        end,
    }
end
getFileReader = function(name)
    if readerThrows then error("disk read failed") end
    local s = disk[name]
    if s == nil then return nil end
    local lines, i = {}, 0
    for line in string.gmatch(s, "([^\n]*)\n?") do lines[#lines + 1] = line end
    return {
        readLine = function()
            i = i + 1
            return lines[i] -- 行尾的 \r 留著：Dock 自己去掉
        end,
        close = function() end,
    }
end

-- 貼圖：每一張都載得到；繪製記在元件的 draws（含 alpha）
getTexture = function(path) return { path = path, getWidthOrig = function() return 32 end } end
ISPanel.drawTextureScaled = function(self, tex, x, y, w, h, a)
    self.draws = self.draws or {}
    self.draws[#self.draws + 1] = { path = tex.path, a = a, w = w }
end
local function clearDraws(el) el.rects, el.borders, el.texts, el.draws = {}, {}, {}, {} end

-- ---------- 小工具 ----------
local DOCK_LUA = ctx.MOD_LUA .. "Widgets/Dock.lua"
package.preload[SETTINGS_MOD] = function() return dofile(ctx.MOD_LUA .. "Widgets/DockSettings.lua") end
package.loaded[SETTINGS_MOD] = nil
local function spec(id, order)
    return { id = id, order = order, iconKey = "gauge", label = function() return "N" .. id end, onClick = function() end }
end
local function panel()
    local w = ISLayoutManager.windows.MinidoracatUIDock
    return w and w.target
end
local function handleOf(p)
    for _, c in ipairs(p.children) do
        if c._rec == nil then return c end
    end
end
local function button(p, id)
    for _, c in ipairs(p.children) do
        if c._rec and c._rec.spec.id == id then return c end
    end
end
local function at(el) return el:getAbsoluteX() .. "," .. el:getAbsoluteY() end
local function tick() if handlers.OnTick then handlers.OnTick() end end
local function register(from, to)
    for i = from, to do UI.Dock.register(spec("e" .. i, i)) end
    tick()
end
local function frame(p)
    clearDraws(p)
    p:prerender()
    return p.rects[1].a, p.borders[1].a
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- ---------- 載入：旗標、選項頁 ----------
UI.Toast._resetForTests()
F.clear()
UI.CAPABILITIES.dock, UI.CAPABILITIES.dockPrefs, UI.Dock = false, false, nil
dofile(DOCK_LUA)
local D = UI.Dock
local S = require(SETTINGS_MOD)
local page = PZAPI.ModOptions.Dict.MinidoracatUIFor42
local opacity = page and page.dict.dockOpacity
check(UI.API_REVISION >= 27 and UI.CAPABILITIES.dockPrefs == true and type(S) == "table" and S.open ~= nil,
    "API_REVISION 進到 27；Dock 載入後 dockPrefs 翻 true，設定視窗模組載得到")
check(opacity ~= nil and opacity.name == "IGUI_MinidoracatUI_Dock_OpacityOption"
    and opacity.tooltip == "IGUI_MinidoracatUI_Dock_Opacity_tooltip" and #opacity.values == 4
    and opacity.values[1] == "[IGUI_MinidoracatUI_Dock_Opacity100]" and opacity.values[4] == "[IGUI_MinidoracatUI_Dock_Opacity25]"
    and opacity.selected == 1 and loads == 0,
    "選項 → MODS：框架頁多一個「閒置時不透明度」下拉（100／75／50／25%，預設 100%）；載入時不讀 ini")

-- ---------- register：失敗時多回原因 ----------
local function reason(s)
    local r, why = D.register(s)
    return r == false and why
end
local noLabel, badBadge, noIcon = spec("x", 1), spec("x", 1), spec("x", 1)
noLabel.label = "Name"
badBadge.getBadge = 3
noIcon.iconKey = nil
check(reason(nil) == "spec must be a table" and reason({}) == "id must be a non-empty string"
    and reason({ id = "x" }) == "order must be a number" and reason(noLabel) == "label must be a function"
    and reason(noIcon) == "icon, iconKey or drawIcon is required" and reason(badBadge) == "getBadge must be a function",
    "register 不合法：回 false 與原因（哪一欄、該是什麼型別）")
check(select("#", D.register(spec("x", 1))) == 1 and D.register(spec("x", 1)) == true,
    "register 合法：照舊只回 true 一個值")
D.unregister("x")

-- ---------- 閒置時不透明度：ini 存了 50% ----------
ini.dockOpacity = 3
local drawArgs
local e1, e2, e3 = spec("e1", 1), spec("e2", 2), spec("e3", 3)
e1.isActive = function() return true end
e2.getBadge = function() return 3 end
e2.getState = function() return "warn" end
e3.iconKey = nil
e3.drawIcon = function(...) drawArgs = { ... } end
D.register(e1)
D.register(e2)
D.register(e3)
handlers.OnGameStart()
local p = panel()
local h = handleOf(p)
ctx.setMouse(0, 0)
local fillA, borderA = frame(p)
check(loads == 1 and near(fillA, 0.8 * 0.5) and near(borderA, 0.5),
    "ini 存了 50%：建立時讀一次；游標不在工具列上，底與框都乘 0.5")
local b1, b2, b3 = button(p, "e1"), button(p, "e2"), button(p, "e3")
clearDraws(b1)
b1:prerender()
check(near(b1.draws[1].a, 0.5) and near(b1.rects[1].a, 0.12 * 0.5) and near(b1.rects[2].a, 0.5),
    "入口的圖示、選中底與 accent 細條跟著變淡")
clearDraws(b2)
b2:prerender()
local warnFrame, badgeFill = b2.borders[1], b2.rects[#b2.rects]
check(near(b2.draws[1].a, 0.5) and warnFrame.a == 1 and badgeFill.a == 1 and b2.texts[#b2.texts].text == "3",
    "警示框、「!」與徽章不變淡（半透明時仍看得到有事）")
b3:prerender()
check(drawArgs[1] == b3 and drawArgs[4] == 28 and near(drawArgs[5], 0.5),
    "自己畫圖示的入口：drawIcon 多收第 5 個參數（這一幀的不透明度）")
clearDraws(h)
h:prerender()
check(near(h.draws[1].a, 0.5), "把手的圖也跟著變淡")
ctx.setMouse(p.x + 10, p.y + 60)
local overA = frame(p)
ctx.setMouse(0, 0)
handlers.OnKeyPressed(52)
local sessionA = frame(p)
ctx.press(p, K.KEY_ESCAPE)
check(near(overA, 0.8) and near(sessionA, 0.8) and near(frame(p), 0.4),
    "游標移到工具列上、快捷鍵工作階段中：回到 100%；結束後又變淡")

-- ---------- 把手右鍵選單：不透明度子選單與「工具列設定...」 ----------
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
local m = menus[#menus]
local sub = m.options[4].sub
check(#m.options == 6 and m.options[4].name == "[IGUI_MinidoracatUI_Dock_Opacity]" and sub ~= nil
    and m.options[5].name == "[IGUI_MinidoracatUI_Dock_SettingsMenu]"
    and m.options[6].name == "[IGUI_MinidoracatUI_Dock_ResetPosition]" and m.options[1].checkMark == true,
    "把手按右鍵：排版三項之後多「閒置時不透明度」（子選單）與「工具列設定...」，恢復預設位置照舊在最後")
check(#sub.options == 4 and sub.options[1].name == "[IGUI_MinidoracatUI_Dock_Opacity100]"
    and sub.options[3].checkMark == true and not sub.options[1].checkMark,
    "子選單四個值，目前的 50% 打勾")
local menuA = frame(p)
pick(sub, 2)
check(near(menuA, 0.8) and opacity.selected == 2 and saves == 1 and ini.dockOpacity == 2 and near(frame(p), 0.8 * 0.75),
    "選單開著時不變淡；選 75%：立刻寫 ModOptions.ini，下一幀就照 75% 畫")
opacity.selected = 4
page:apply()
check(near(frame(p), 0.8 * 0.25) and loads == 1, "選項頁套用 25%：直接讀選好的值，不重讀 ini")
opacity.selected = 9
page:apply()
check(near(frame(p), 0.8), "選項值不認得：當 100%")
opacity.selected = 3
page:apply()

-- ---------- 設定視窗：從選單打開 ----------
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 5)
local win = S._windowForTests()
check(win ~= nil and win:getIsVisible() and win.inUIManager == true and win.x + win.width == p.x - 8
    and #win._boxes == 3 and win._boxes[2].label == "Ne2" and win._boxes[2].checked == true
    and win.ddLayout:getSelected() == 1 and win.ddOpacity:getSelected() == 3,
    "「工具列設定...」：視窗開在工具列靠畫面中間那側，三個入口各一個勾選框，兩個下拉是目前的值")
check(win.btnAll._enabled == false or win.btnAll.enable == false,
    "沒有入口被藏起時「全部顯示」不能按")

-- 勾掉 e2：立刻從工具列消失、寫進 Dock.ini，仍算已停靠
local hAt = at(h)
win._boxes[2]:forceClick()
tick()
win.body:prerender()
check(not b2:getIsVisible() and p.height == 48 + 2 * 44 and at(h) == hAt and b3.y == 92
    and disk[PREFS] ~= nil and string.find(disk[PREFS], "hidden=e2\r\n", 1, true) ~= nil and D.isDocked("e2") == true,
    "勾掉一個入口：下一次輪詢就從工具列消失、其他入口補位、把手不動；Dock.ini 多一行；isDocked 照舊是 true")
check(win:getIsVisible() and win._boxes[2].checked == false and (win.btnAll._enabled == true or win.btnAll.enable == true),
    "視窗不關、那一列變成沒勾，「全部顯示」可以按")
h._mouseOver = true
ctx.advance(600)
p:prerender()
local tip = ISToolTip.last
check(string.find(tip.description, "[IGUI_MinidoracatUI_Dock_Hidden]", 1, true) ~= nil
    and string.sub(tip.description, -36) == "[IGUI_MinidoracatUI_Dock_HandleHint]",
    "把手提示多一行「已隱藏 N 個入口」，最後一行照舊是右鍵說明")
h._mouseOver = false
p:prerender()

-- 再勾掉 e1：只剩 1 個看得到的入口，把手照樣在
win._boxes[1]:forceClick()
tick()
check(h:getIsVisible() and at(h) == hAt and p.height == 48 + 44 and b3:getIsVisible(),
    "只剩 1 個入口但有入口被藏起：把手留著（平常 1 個入口不畫把手）")
-- 全部勾掉：整條不消失，剩把手
win._boxes[3]:forceClick()
tick()
check(p:getIsVisible() and h:getIsVisible() and at(h) == hAt and p.width == 48 and p.height == 48,
    "入口全部藏起：工具列不消失，剩把手一格、位置不變（設定找得回來）")

-- ---------- 鍵盤：沒有入口時快捷鍵落在把手，Enter 開設定 ----------
win:close()
handlers.OnKeyPressed(52)
local onHandle = F.focused() == h
h._mouseOver = false
ctx.advance(600)
p:prerender()
local focusTip = ISToolTip.last.description
ctx.press(p, K.KEY_RETURN)
check(onHandle and string.sub(focusTip, 1, 34) == "[IGUI_MinidoracatUI_Dock_Settings]" and win:getIsVisible()
    and p._kb == nil and F.focused() == win.ddLayout,
    "沒有看得到的入口：快捷鍵把焦點放在把手、提示寫「工具列設定」；Enter 開設定視窗，焦點框到第一個控制項")
win.btnAll:forceClick()
tick()
win.body:prerender()
check(b1:getIsVisible() and b2:getIsVisible() and b3:getIsVisible() and p.height == 48 + 3 * 44
    and string.find(disk[PREFS], "hidden=", 1, true) == nil and win._boxes[1].checked == true,
    "「全部顯示」：三個入口都回來，Dock.ini 沒有 hidden 行，視窗的勾選跟著更新")

-- ---------- 鍵盤：把手是入口旁邊的一格 ----------
win:close()
F.clear()
local function key(k)
    ctx.press(p, k)
    local f = F.focused()
    if f == h then return "handle" end
    return f and f._rec and f._rec.spec.id
end
handlers.OnKeyPressed(52)
local first = F.focused() == b1
local up1, up2 = key(K.KEY_UP), key(K.KEY_UP)
local down1, down2 = key(K.KEY_DOWN), key(K.KEY_DOWN)
check(first and up1 == "handle" and up2 == "e3" and down1 == "handle" and down2 == "e1",
    "直排：第一個入口往上是把手，再往上繞到最後一個；最後一個往下是把手，再往下是第一個")
-- 工作階段中用滑鼠點把手：照舊是收合，不是開設定
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
check(p.collapsed == true and not win:getIsVisible(), "工作階段中用滑鼠點把手：照舊收合，不開設定")
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
ctx.press(p, K.KEY_ESCAPE)
F.clear()

-- 方格（4 個入口，2 欄）：上到把手；把手上左右鍵不動
D.register(spec("e4", 4))
tick()
page.dict.dockLayout.selected = 3
page:apply()
handlers.OnKeyPressed(52)
F.focusControl(button(p, "e2"), true)
local gridUp = key(K.KEY_UP)
local gridSide = key(K.KEY_LEFT)
local gridDown = key(K.KEY_DOWN)
F.focusControl(button(p, "e1"), true)
local gridRight = key(K.KEY_RIGHT)
check(gridUp == "handle" and gridSide == "handle" and gridDown == "e1" and gridRight == "e2",
    "方格：最上面一列往上是把手；把手上按左右不動、往下回到第一個入口；同一列的左右照舊在列內繞")
ctx.press(p, K.KEY_ESCAPE)
F.clear()
page.dict.dockLayout.selected = 1
page:apply()
D.unregister("e4")

-- ---------- 設定視窗的下拉與「恢復預設位置」 ----------
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 5)
local savesBefore = saves
win.ddLayout:setSelected(2)
check(p.layout == 2 and page.dict.dockLayout.selected == 2 and saves == savesBefore + 1,
    "視窗的排版下拉：立刻換成橫排並寫 ModOptions.ini")
win.ddOpacity:setSelected(1)
check(opacity.selected == 1 and near(frame(p), 0.8), "視窗的不透明度下拉：選 100% 立刻生效")
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 1)
win.body:prerender()
check(win.ddLayout:getSelected() == 1, "視窗開著時從選單換排版：視窗的下拉跟著變")
ctx.setMouse(1842, 144)
h:onMouseDown(1, 1)
ctx.setMouse(400, 700)
h:onMouseMoveOutside(0, 0)
h:onMouseUpOutside(0, 0)
local movedAt = at(h)
win.btnReset:forceClick()
check(movedAt ~= "1822,124" and at(h) == "1822,124", "視窗的「恢復預設位置」：鍵盤也按得到，把手回到預設位置")
ctx.setMouse(0, 0)

-- ---------- 重開：照 Dock.ini 藏起；沒載入的 MOD 的 id 留在檔裡；讀檔出錯不擋工具列 ----------
disk[PREFS] = "# header\r\nhidden=ghost\r\nhidden=e3\r\nhidden=\r\njunk\r\n"
D._resetForTests()
register(1, 3)
handlers.OnGameStart()
p = panel()
h = handleOf(p)
check(button(p, "e3") == nil and p.height == 48 + 2 * 44 and D.isDocked("e3") == true,
    "重開：Dock.ini 列出的入口一開始就不顯示（行尾的 \\r、空值與不認得的行不影響）")
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 5)
win = S._windowForTests()
win._boxes[1]:forceClick()
check(string.find(disk[PREFS], "hidden=ghost\r\n", 1, true) ~= nil and string.find(disk[PREFS], "hidden=e1\r\n", 1, true) ~= nil
    and string.find(disk[PREFS], "hidden=e3\r\n", 1, true) ~= nil,
    "再藏一個：檔裡留著這次沒載入的 MOD 的 id（它回來時仍然是藏起的）")
readerThrows = true
D._resetForTests()
register(1, 3)
handlers.OnGameStart()
p = panel()
readerThrows = false
check(p:getIsVisible() and button(p, "e1") ~= nil and button(p, "e3") ~= nil and p.height == 48 + 3 * 44,
    "讀 Dock.ini 出錯：不拋錯，當成沒有入口被藏起")

-- ---------- 入口多到超出螢幕：直排、橫排自動換行 ----------
disk[PREFS] = nil
D._resetForTests()
screenH = 400
register(1, 12)
handlers.OnGameStart()
p = panel()
check(p.width == 92 and p.height == 48 + 6 * 44 and p.height <= screenH,
    "直排 12 個、螢幕高 400（放得下 8 個）：排成 2 欄 6 列，整條在螢幕內")
screenH, screenW = 1080, 500
handlers.OnResolutionChange()
page.dict.dockLayout.selected = 2
page:apply()
check(p.width == 48 + 6 * 44 and p.height == 92 and p.width <= screenW,
    "橫排 12 個、螢幕寬 500（放得下 10 個）：排成 2 列 6 欄，整條在螢幕內")
screenW = 1920
handlers.OnResolutionChange()
page.dict.dockLayout.selected = 1
page:apply()

-- ---------- 零配置：半透明、有入口被藏起、設定視窗開著 ----------
opacity.selected = 3
page:apply()
h = handleOf(p)
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 5)
win = S._windowForTests()
win._boxes[2]:forceClick()
tick()
local noop = function() end
local body, icons = win.body, win.icons
for _, el in ipairs({ p, body, icons }) do el.drawRect, el.drawRectBorder, el.drawText, el.drawTextCentre = noop, noop, noop, noop end
ISPanel.drawTextureScaled = noop
ctx.advance(1000)
p:prerender()
body:prerender()
icons:prerender()
collectgarbage("collect")
collectgarbage("stop")
p:prerender()
local kb = collectgarbage("count")
for _ = 1, 50 do
    p:prerender()
    p:render()
    body:prerender()
    icons:prerender()
end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
for _, el in ipairs({ p, body, icons }) do el.drawRect, el.drawRectBorder, el.drawText, el.drawTextCentre = nil, nil, nil, nil end
check(grew == 0, "半透明、有入口被藏起、設定視窗開著：面板與視窗內容 50 幀不配置記憶體")

-- ---------- 還原 ----------
D._resetForTests()
UI.Toast._resetForTests()
UI.Skin._resetForTests()
F.clear()
UI.Dock, UI.CAPABILITIES.dock, UI.CAPABILITIES.dockPrefs = keep.Dock, keep.dockCap, keep.prefsCap
getCore, getText, getSpecificPlayer, Events = keep.getCore, keep.getText, keep.getSpecificPlayer, keep.Events
ISLayoutManager, ISToolTip, PZAPI, ISContextMenu = keep.ISLayoutManager, keep.ISToolTip, keep.PZAPI, keep.ISContextMenu
ISPanel.getAbsoluteX, ISPanel.getAbsoluteY = keep.absX, keep.absY
ISPanel.drawTextureScaled, getTexture = keep.drawTextureScaled, keep.getTexture
getFileReader, getFileWriter = keep.getFileReader, keep.getFileWriter
package.preload[SETTINGS_MOD], package.loaded[SETTINGS_MOD] = keep.preload, keep.loaded
K.KEY_PERIOD = keep.KEY_PERIOD
ctx.setMouse(0, 0)
return n
