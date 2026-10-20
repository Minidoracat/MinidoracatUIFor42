-- rev 21：Dock 三種排版（直排／橫排／方格）、入口往畫面中間長且把手不動、layout.ini 存 home、把手右鍵選單、
-- 選項 → MODS 的下拉、方向鍵照畫面位置、提示框在側邊（Widgets/Dock.lua，2026-10-20 設計稿四項照建議）。
-- 契約見 smoke_harness.lua 的切片載入器註解與 ARCHITECTURE §3.16。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
local F, K = UI.Focus, Keyboard
local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end
print("情境 rev21-dock：三種排版／往中間長與把手不動／存讀／右鍵選單／選項頁／方向鍵照畫面／提示框位置／零配置")

-- ---------- 本切片自備的全域（用完全部還原） ----------
local keep = {
    getCore = getCore, getText = getText, getSpecificPlayer = getSpecificPlayer, Events = Events,
    ISLayoutManager = ISLayoutManager, ISToolTip = ISToolTip, PZAPI = PZAPI, ISContextMenu = ISContextMenu,
    absX = ISPanel.getAbsoluteX, absY = ISPanel.getAbsoluteY, Dock = UI.Dock, dockCap = UI.CAPABILITIES.dock,
    KEY_PERIOD = K.KEY_PERIOD,
}

local screenW, screenH = 1920, 1080
local core = { -- 同一張表：每幀路徑呼叫 getCore() 也不配置
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

-- 子元件的絕對座標沿父鏈累加（共用 stub 只回自己的 x）
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

-- ISLayoutManager：以解析度分組存 layout，讀回時值變字串（同 layout.ini）
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

-- ISToolTip：doLayout 依文字算大小（原版在自己的 prerender 才算，Dock 換字時先叫一次）
local tipW, tipH = 200, 30
ISToolTip = {}
ISToolTip.__index = ISToolTip
function ISToolTip:new()
    local t = setmetatable({ visible = false, description = "", width = 0, height = 0, layouts = 0 }, ISToolTip)
    ISToolTip.last = t
    return t
end
function ISToolTip:setOwner(o) self.owner = o end
function ISToolTip:setVisible(v) self.visible = v end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:addToUIManager() end
function ISToolTip:removeFromUIManager() end
function ISToolTip:doLayout()
    self.layouts = self.layouts + 1
    self.width, self.height = tipW, tipH
end
function ISToolTip:setDesiredPosition(x, y) self.px, self.py = x, y end

-- PZAPI.ModOptions：原版的 create／getOptions／addComboBox（addItem 走 getText）／load（讀 ini）／save
local iniLayout, loads, saves = nil, 0, 0
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
    if iniLayout and page then page.dict.dockLayout.selected = iniLayout end
end
function PZAPI.ModOptions:save()
    saves = saves + 1
    iniLayout = self.Dict.MinidoracatUIFor42.dict.dockLayout.selected
end

-- ISContextMenu.get：記下開出來的選單（選項、打勾、位置）。原版每個玩家只有一個選單：開新的就把舊的藏起來
local menus = {}
ISContextMenu = {}
function ISContextMenu.get(player, x, y)
    local last = menus[#menus]
    if last then last.visible = false end
    local m = { player = player, x = x, y = y, width = 150, options = {}, visible = true }
    function m:addOption(name, target, fn, p1)
        local o = { name = name, target = target, fn = fn, p1 = p1 }
        self.options[#self.options + 1] = o
        return o
    end
    function m:setOptionChecked(o, v) o.checkMark = v end
    function m:setX(v) self.x = v end
    function m:getIsVisible() return self.visible end
    menus[#menus + 1] = m
    return m
end
local function pick(m, i)
    m.visible = false -- 原版選了先 closeAll 再呼叫（ISContextMenu.lua:66-70）
    m.options[i].fn(m.options[i].target, m.options[i].p1)
end

-- ---------- 小工具 ----------
local DOCK_LUA = ctx.MOD_LUA .. "Widgets/Dock.lua"
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
local function register(from, to)
    for i = from, to do UI.Dock.register(spec("e" .. i, i)) end
    if handlers.OnTick then handlers.OnTick() end -- register only marks dirty; the next poll lays out
end
local function unregister(from, to)
    for i = from, to do UI.Dock.unregister("e" .. i) end
end
local function setLayout(page, v)
    page.dict.dockLayout.selected = v
    page:apply()
end

-- ---------- 選項頁 ----------
UI.Toast._resetForTests()
F.clear()
UI.CAPABILITIES.dock, UI.Dock = false, nil
dofile(DOCK_LUA)
local D = UI.Dock
local page = PZAPI.ModOptions.Dict.MinidoracatUIFor42
local combo = page and page.dict.dockLayout
check(page ~= nil and page.name == "UI_optionscreen_binding_MinidoracatUI" and combo ~= nil
    and combo.name == "IGUI_MinidoracatUI_Dock_Layout" and combo.tooltip == "IGUI_MinidoracatUI_Dock_Layout_tooltip"
    and #combo.values == 3 and combo.values[1] == "[IGUI_MinidoracatUI_Dock_LayoutColumn]"
    and combo.values[3] == "[IGUI_MinidoracatUI_Dock_LayoutGrid]" and combo.selected == 1 and loads == 0,
    "選項 → MODS：框架頁多一個「工具列排版」下拉（直排／橫排／方格，預設直排）；載入時不讀 ini")

-- ---------- 三種排版的尺寸與鏡射（右上預設位置：往左、往下長） ----------
iniLayout = 2
register(1, 9)
handlers.OnGameStart()
local p = panel()
local h = handleOf(p)
check(loads == 1 and p.layout == 2 and p.width == 444 and p.height == 48,
    "ini 存了橫排：建立 Dock 時讀一次 ini，開局就是橫排（9 個入口 444×48）")
check(at(h) == "1822,124" and h.x == 400 and button(p, "e1").x == 356 and button(p, "e9").x == 4,
    "右上的橫排：把手在右端、停在預設位置（moodle 欄內側），入口往左長，第一個緊鄰把手")
setLayout(page, 3)
check(p.layout == 3 and p.width == 136 and p.height == 180 and at(h) == "1822,124" and h.x == 92 and h.y == 4
    and button(p, "e1").x == 92 and button(p, "e1").y == 48 and button(p, "e3").x == 4 and button(p, "e4").y == 92
    and loads == 1 and saves == 0,
    "選項套用方格：3 欄 136×180，把手不動、自己佔右上一列，入口從把手那側一列一列排；套用不重讀 ini、不另存")
setLayout(page, 1)
check(p.width == 48 and p.height == 444 and at(h) == "1822,124" and button(p, "e1").y == 48 and button(p, "e9").y == 400,
    "套用直排：48×444，把手不動、入口往下排")
setLayout(page, 7)
check(p.layout == 1, "選項值不認得：當直排")

setLayout(page, 3)
unregister(5, 9)
check(p.width == 92 and p.height == 136 and at(h) == "1822,124", "方格 4 個：2 欄 92×136，入口減少時把手不動")
register(5, 5)
check(p.width == 136 and p.height == 136, "方格 5 個：3 欄、2 列（最後一列空一格）")
register(6, 10)
check(p.width == 180 and p.height == 180 and at(h) == "1822,124", "方格 10 個：4 欄 180×180，入口增加時把手不動")
unregister(10, 10)

-- ---------- 收合與展開：把手不動 ----------
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
local collapsedAt, collapsedW = at(h), p.width
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
check(collapsedAt == "1822,124" and collapsedW == 48 and at(h) == "1822,124" and p.width == 136 and not p.collapsed,
    "方格收合成 48×48 再展開：把手都在原地")

-- ---------- 拖到左下：放開時改往上、往右長，把手留在放開的地方 ----------
setLayout(page, 1)
ctx.setMouse(1842, 144)
h:onMouseDown(1, 1)
ctx.setMouse(1842 - 1700, 144 + 500)
h:onMouseMoveOutside(0, 0)
local midDrag = h.y
h:onMouseUpOutside(0, 0)
check(midDrag == 4 and at(h) == "122,624" and h.y == p.height - 44 and button(p, "e1").y == h.y - 44
    and button(p, "e9").y == 4 and p.y == 624 - h.y,
    "拖曳中不變形；放到下半部：把手留在放開的位置、移到下端，入口往上長")
local saved = store[res()].MinidoracatUIDock
check(saved.x == "118" and saved.y == "620" and saved.collapsed == "false",
    "layout.ini 存的是把手那格的左上角（home），不是面板左上角")
setLayout(page, 2)
check(at(h) == "122,624" and h.x == 4 and button(p, "e1").x == 48 and p.x == 118,
    "左半部換橫排：把手在左端、不動，入口往右長")
setLayout(page, 1)

-- 重開：照 home 讀回、重新判斷方向（玩家存的排版是直排）
iniLayout = 1
D._resetForTests()
register(1, 9)
handlers.OnGameStart()
p = panel()
h = handleOf(p)
check(loads == 2 and p.layout == 1 and at(h) == "122,624" and h.y == p.height - 44,
    "重開（TryRestore）：讀回 home，把手回到同一點、入口照樣往上長")

-- 換解析度：先套預設再讀該解析度的記錄（新解析度沒有）
screenW, screenH = 2560, 1440
handlers.OnResolutionChange()
check(at(h) == (2560 - 42 - 12 - 44) .. ",124" and h.y == 4, "新解析度沒有記錄：回預設位置（右上），入口改往下長")
screenW, screenH = 1920, 1080
handlers.OnResolutionChange()
check(at(h) == "122,624", "換回原解析度：讀回那裡存的位置")

-- ---------- 把手右鍵選單 ----------
local m0 = #menus
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
local m = menus[#menus]
check(#menus == m0 + 1 and #m.options == 4 and m.options[1].name == "[IGUI_MinidoracatUI_Dock_LayoutColumn]"
    and m.options[2].name == "[IGUI_MinidoracatUI_Dock_LayoutRow]" and m.options[3].name == "[IGUI_MinidoracatUI_Dock_LayoutGrid]"
    and m.options[4].name == "[IGUI_MinidoracatUI_Dock_ResetPosition]"
    and m.options[1].checkMark == true and not m.options[2].checkMark and not m.options[3].checkMark,
    "把手按右鍵：選單是直排／橫排／方格／恢復預設位置，目前的排版打勾")
check(m.player == 0 and m.x == 122 + 40 + 4 and m.y == 624, "選單開在把手靠畫面中間那側（左半部 → 右邊）")
pick(m, 3)
check(p.layout == 3 and combo.selected == 3 and saves == 1 and iniLayout == 3 and at(h) == "122,624" and h.x == 4
    and h.y == p.height - 44, "選方格：立刻寫 ModOptions.ini、把手不動（左下：把手在左下角）")
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
m = menus[#menus]
check(m.options[3].checkMark == true and not m.options[1].checkMark, "再開選單：打勾換到方格")
m0 = #menus
h:onRightMouseDown(1, 1)
ctx.advance(800)
h:onRightMouseUp(1, 1)
ctx.setMouse(200, 200)
h:onMouseDown(1, 1)
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
h:onMouseUp(1, 1)
check(#menus == m0 and p.collapsed, "右鍵：800ms 過期不開、左鍵按住中不接（那一下左鍵照舊收合）")
h:onMouseDown(1, 1)
h:onMouseUp(1, 1)
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
pick(menus[#menus], 4)
check(at(h) == "1822,124" and h.y == 4 and h.x == 92 and store[res()].MinidoracatUIDock.x == "1818",
    "恢復預設位置：把手回右上、改往左下長，並立刻存檔")
h:onRightMouseDown(1, 1)
h:onRightMouseUp(1, 1)
check(menus[#menus].x == 1822 - 150 - 4, "右半部：選單開在把手左邊")
h._mouseOver = true
p:prerender()
local hiddenWhileMenu = not ISToolTip.last or ISToolTip.last.visible == false
menus[#menus].visible = false
p:prerender()
check(hiddenWhileMenu and ISToolTip.last.visible == true, "選單開著時把手的提示框不出來（會疊在選單上），選單收掉才出來")
h._mouseOver = false
p:prerender()

-- ---------- 方向鍵照畫面位置（右上方格 3×3） ----------
local function key(k)
    ctx.press(p, k)
    local f = F.focused()
    return f and f._rec and f._rec.spec.id
end
local function from(id, k)
    F.focusControl(button(p, id), true)
    return key(k)
end
handlers.OnKeyPressed(52)
local left, right = from("e5", K.KEY_LEFT), from("e5", K.KEY_RIGHT)
local up, down = from("e5", K.KEY_UP), from("e5", K.KEY_DOWN)
check(left == "e6" and right == "e4" and up == "e2" and down == "e8",
    "方格（右上、往左長）：e5 在中間，左 e6、右 e4、上 e2、下 e8，照畫面上的位置走")
check(from("e4", K.KEY_RIGHT) == "e6" and from("e1", K.KEY_UP) == "e7", "走出邊界：同一列或同一欄繞回另一端")
ctx.press(p, K.KEY_ESCAPE)
unregister(6, 9)
handlers.OnKeyPressed(52)
check(from("e5", K.KEY_LEFT) == "e4", "最後一列不滿：往空格走會跳過它（e5 左邊是空格，繞到 e4）")
ctx.press(p, K.KEY_ESCAPE)
setLayout(page, 1)
handlers.OnKeyPressed(52)
local colRight = from("e1", K.KEY_RIGHT)
local colUp = key(K.KEY_UP)
check(colRight == "e2" and colUp == "e1", "直排只有一條：左右鍵也沿著它走（右＝下一個、上＝上一個，同 rev 13）")
ctx.press(p, K.KEY_ESCAPE)

-- ---------- 提示框：側邊、靠畫面中間那側、不出螢幕 ----------
register(6, 9)
local e3 = button(p, "e3")
e3._mouseOver = true
p:prerender()
local tip = ISToolTip.last
check(tip.visible and tip.layouts >= 1 and tip.px == 1818 - 200 - 8 and tip.py == e3:getAbsoluteY(),
    "直排在右半部：提示框在 Dock 左邊、和入口同高；換字時先算好大小")
e3._mouseOver = false
setLayout(page, 2)
local e5 = button(p, "e5")
e5._mouseOver = true
p:prerender()
check(tip.px == e5:getAbsoluteX() and tip.py == p.y + 48 + 8, "橫排在上半部：提示框在 Dock 下面、對齊入口")
e5._mouseOver = false
p:prerender()
ctx.setMouse(100, 100)
h:onMouseDown(1, 1)
ctx.setMouse(100, 1100)
h:onMouseMoveOutside(0, 0)
h:onMouseUpOutside(0, 0)
e5._mouseOver = true
ctx.advance(500)
p:prerender()
check(p.y + p.height == 1080 and tip.py == p.y - 30 - 8, "橫排拖到最下面（夾回螢幕）：提示框在 Dock 上面")
e5._mouseOver = false
setLayout(page, 3)
h._mouseOver = true
tipH = 2000
ctx.advance(500)
p:prerender()
local HINT = "[IGUI_MinidoracatUI_Dock_HandleHint]"
check(string.sub(tip.description, -#HINT) == HINT and h.y == p.height - 44 and tip.px == p.x - 200 - 8 and tip.py == 0,
    "把手提示最後一行是右鍵說明；方格在右下：提示框在左邊，比螢幕高時夾到 y=0")
tipH = 30

-- ---------- 零配置：方格＋提示框顯示中 ----------
local noop = function() end
p.drawRect, p.drawRectBorder, p.drawText, p.drawTextCentre = noop, noop, noop, noop
ctx.advance(1000)
p:prerender()
collectgarbage("collect")
collectgarbage("stop")
p:prerender()
local kb = collectgarbage("count")
for _ = 1, 50 do
    p:prerender()
    p:render()
end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
p.drawRect, p.drawRectBorder, p.drawText, p.drawTextCentre = nil, nil, nil, nil
h._mouseOver = false
check(grew == 0, "方格、提示框顯示中：面板 prerender＋render 50 幀不配置記憶體")

-- ---------- 建立時只有 1 個入口、之後才有別的：那顆按鈕就在把手的位置 ----------
D._resetForTests()
for k in pairs(store) do store[k] = nil end
iniLayout = 1
register(1, 1)
handlers.OnGameStart()
p = panel()
local loneAt = at(button(p, "e1"))
register(2, 9)
h = handleOf(p)
check(loneAt == "1822,124" and at(h) == "1822,124" and p.x + p.width == 1866,
    "建立時只有 1 個入口：那顆按鈕放在把手的位置；入口變多時把手接手同一點，直排右緣照舊離 moodle 欄 12px")

-- ---------- 還原 ----------
D._resetForTests()
UI.Toast._resetForTests()
UI.Skin._resetForTests()
F.clear()
UI.Dock, UI.CAPABILITIES.dock = keep.Dock, keep.dockCap
getCore, getText, getSpecificPlayer, Events = keep.getCore, keep.getText, keep.getSpecificPlayer, keep.Events
ISLayoutManager, ISToolTip, PZAPI, ISContextMenu = keep.ISLayoutManager, keep.ISToolTip, keep.PZAPI, keep.ISContextMenu
ISPanel.getAbsoluteX, ISPanel.getAbsoluteY = keep.absX, keep.absY
K.KEY_PERIOD = keep.KEY_PERIOD
ctx.setMouse(0, 0)
return n
