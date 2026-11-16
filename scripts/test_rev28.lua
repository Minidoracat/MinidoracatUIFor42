-- 切片 rev 28：TextField 同步的 onTextChange（textFieldSync）、NavList 被截字列的全名提示（navListTip）、
-- Tabs 逐項提示 items[i].tooltip／setItemTooltip（tabsItemTooltip）、undo 圖示 key。契約見 smoke_harness.lua 的切片載入器註解。
-- 起因：自由建造 1.0.0 的匯入框要在貼上「當下」清框（同一輪的全選＋複製才帶不出貼上的字），每幀比對的 onChange 太晚。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev28：TextField onTextChange、NavList 截字提示、Tabs 逐項提示、undo 圖示")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

dofile(ctx.MOD_LUA .. "Widgets/NavList.lua")
local C = UI.CAPABILITIES
check(UI.API_REVISION == 28 and C.textFieldSync == true and C.navListTip == true and C.tabsItemTooltip == true,
    "API_REVISION 28；三個旗標在 widget 檔載入後翻 true")

-- ---------- TextField onTextChange ----------
-- 忠於 ISTextEntryBox.lua:19-23：原生 UITextBox2.onTextChange 叫到 Lua 的 onTextChange，再轉給 onTextChangeFunction(target, self)
local keepOnTextChange = ISTextEntryBox.onTextChange
function ISTextEntryBox:onTextChange()
    if self.onTextChangeFunction then
        self.onTextChangeFunction(self.target, self)
    end
end
-- 模擬原生貼上（UITextBox2.java:1255）：先改內容、同一個呼叫堆疊裡呼叫 onTextChange
local function nativePaste(entry, s)
    entry._text = entry._text .. s
    entry:onTextChange()
end

local calls, seen, changes = 0, nil, 0
local field = UI.TextField.new{ width = 200, text = "PRE",
    onChange = function() changes = changes + 1 end,
    onTextChange = function(f, text)
        calls = calls + 1
        seen = text
        f:setText("")
    end }
local entry = field._entry
nativePaste(entry, "PASTED")
check(calls == 1 and seen == "PREPASTED" and entry:getInternalText() == "" and field:getText() == "",
    "貼上當下同步回呼一次、拿到貼上後的全文；回呼裡 setText(\"\") 後框內長度 0（同一輪的全選＋複製帶不出去）")
field:prerender()
check(changes == 0, "回呼裡的 setText 同步了 onChange 的比對基準：下一幀不再補報這次變更")

local keepCount, keepSeen = 0, nil
local keep = UI.TextField.new{ width = 200, text = "k",
    onChange = function(_, t) keepCount = keepCount + 1; keepSeen = t end,
    onTextChange = function() end }
nativePaste(keep._entry, "m")
keep:prerender()
check(keepCount == 1 and keepSeen == "km", "回呼裡不改字：下一幀 onChange 照常報一次")

local trimCount = 0
local trim = UI.TextField.new{ width = 200,
    onChange = function() trimCount = trimCount + 1 end,
    onTextChange = function(f, t) f:setText(string.sub(t, 1, 3)) end }
nativePaste(trim._entry, "abcdef")
trim:prerender()
check(trim:getText() == "abc" and trim._entry:getInternalText() == "abc" and trimCount == 0,
    "回呼裡 setText 非空字串：框內是新字、下一幀不補報")

local plain = UI.TextField.new{ width = 200, text = "a", onChange = function() changes = changes + 1 end }
check(plain._entry.onTextChangeFunction == nil and plain._entry.target == nil and plain.onTextChange == nil,
    "沒給 onTextChange：不接原生回呼（同 rev 27）")
nativePaste(plain._entry, "b")
plain:prerender()
check(plain:getText() == "ab" and changes == 1, "沒給 onTextChange：貼上照舊只由每幀的 onChange 報一次")

local depth, inner = 0, 0
local re
re = UI.TextField.new{ width = 200, onTextChange = function(f)
    depth = depth + 1
    inner = math.max(inner, depth)
    nativePaste(f._entry, "x") -- 回呼裡又觸發原生變更
    depth = depth - 1
end }
nativePaste(re._entry, "y")
check(inner == 1 and re._inTextChange == false and re:getText() == "yx", "回呼執行中再被觸發：不重入")

local boom = UI.TextField.new{ width = 200, onTextChange = function() error("consumer boom") end }
local okCall = pcall(nativePaste, boom._entry, "z")
check(okCall and boom._inTextChange == false and boom:getText() == "z",
    "consumer 回呼出錯：框架的 pcall 接住、不再往上丟（Kahlua 已在回呼那層記過），防重入旗標已重設")
local after = 0
boom.onTextChange = function() after = after + 1 end
nativePaste(boom._entry, "w")
check(after == 1, "出錯之後下一次變更照常回呼")
ISTextEntryBox.onTextChange = keepOnTextChange

-- ---------- 提示框 stub ----------
-- 忠於 ISButton.lua:316-346：滑鼠在上（或手把焦點）且有 tooltip 時建／顯示 ISToolTip、寫 description、
-- 放到游標 x 與元件下緣 +8；否則收掉。剛建的 ISToolTip 寬高是 0（ISToolTip.lua:354-355），doLayout 才排成 200×40
local tips = {}
local Tip = {}
Tip.__index = Tip
function Tip:setOwner(o) self.owner = o end
function Tip:setVisible(v) self.visible = v end
function Tip:getIsVisible() return self.visible end
function Tip:setAlwaysOnTop() end
function Tip:addToUIManager() self.inUI = true end
function Tip:removeFromUIManager() self.inUI = false end
function Tip:setDesiredPosition(x, y) self.desiredX, self.desiredY = x, y end
function Tip:doLayout() self.width, self.height = 200, 40 end
local keepUpdate = ISButton.updateTooltip
function ISButton.updateTooltip(el)
    if (el:isMouseOver() or el.joypadFocused) and el.tooltip then
        if not el.tooltipUI then
            el.tooltipUI = setmetatable({ width = 0, height = 0, visible = false,
                backgroundColor = { r = 0, g = 0, b = 0, a = 0.7 } }, Tip)
            tips[#tips + 1] = el.tooltipUI
        end
        local tip = el.tooltipUI
        if not tip:getIsVisible() then
            tip.maxLineWidth = string.find(el.tooltip, "\n", 1, true) and 1000 or 300
            tip:addToUIManager()
            tip:setVisible(true)
        end
        tip.description = el.tooltip
        tip:setDesiredPosition(getMouseX(), el:getAbsoluteY() + el:getHeight() + 8)
    elseif el.tooltipUI and el.tooltipUI:getIsVisible() then
        el.tooltipUI:setVisible(false)
        el.tooltipUI:removeFromUIManager()
    end
end
local function shown(el)
    local tip = el.tooltipUI
    return tip ~= nil and tip.visible and tip.inUI and tip.description or nil
end

-- ---------- Tabs 逐項提示 ----------
local noop = function() end
local function mute(el)
    el.drawRect, el.drawRectBorder, el.drawText, el.drawTextureScaled = noop, noop, noop, noop
end
-- 標籤每字 10px：A 寬 34（x 2..36）、Bb 寬 44（x 38..82）、Ccc 寬 54（x 84..138）
local tabs = UI.Tabs.new{ x = 100, y = 100, height = 24, selected = "a", items = {
    { id = "a", label = "A", tooltip = "First tab" },
    { id = "b", label = "Bb" },
    { id = "c", label = "Ccc", tooltip = "Locked until built" },
} }
mute(tabs)
tabs:setItemEnabled("c", false)
tabs._mouseOver = true
ctx.setMouse(110, 110) -- 在 A 上
tabs:prerender()
check(shown(tabs) == "First tab" and tabs.tooltipUI.desiredY == 100 + 24 + 8 and tabs.tooltipUI.desiredX == 110
    and tabs.tooltip == nil, "items[i].tooltip：滑鼠停在那一項顯示在下方 8px；el.tooltip 不留（Focus 說明不會誤讀）")
ctx.setMouse(150, 110) -- 在 Bb 上（沒提示）
tabs:prerender()
check(shown(tabs) == nil and tabs.tooltipUI.visible == false, "移到沒有提示的項：收掉")
ctx.setMouse(200, 110) -- 在停用的 Ccc 上
tabs:prerender()
check(shown(tabs) == "Locked until built", "停用的項也顯示提示（說明為什麼按不了）")
tabs:setEnabled(false)
tabs:prerender()
check(shown(tabs) == "Locked until built", "整列停用時照樣顯示")
tabs:setEnabled(true)
tabs:setItemTooltip("c", "")
tabs:prerender()
check(shown(tabs) == nil, "setItemTooltip(id, \"\")：拿掉")
tabs:setItemTooltip("b", "Second")
tabs:setItemTooltip("nope", "x")
ctx.setMouse(150, 110)
tabs:prerender()
check(shown(tabs) == "Second", "setItemTooltip 設新提示；未知 id 忽略")
tabs._mouseOver = false
tabs:prerender()
check(shown(tabs) == nil, "滑鼠離開元件：收掉")

-- 夾在螢幕內：靠下緣時放到上方、靠右緣時往左收
local low = UI.Tabs.new{ x = 1800, y = 1040, height = 24, items = { { id = "a", label = "Abcdefghijkl", tooltip = "Tip" } } }
mute(low)
low._mouseOver = true
ctx.setMouse(1910, 1050)
low:prerender()
check(shown(low) == "Tip" and low.tooltipUI.desiredY == 1040 - 8 - 40 and low.tooltipUI.desiredX == 1920 - 200,
    "下方放不下改放上方；右緣夾回螢幕內")

-- ---------- NavList 截字提示 ----------
local function navGroups()
    return { { title = "G", items = {
        { id = "short", label = "Base" },
        { id = "long", label = "  Performance very long label that is cut  " },
        { id = "sw", label = "Zombies with a very long switch label", switch = {
            get = function() return true end, set = function() end } },
        { id = "off", label = "Disabled row with a very long label", enabled = function() return false end },
    } } }
end
-- 版面（rev 17）：標題 0..18、short 18..42、long 42..66、sw 66..90、off 90..114；寬 160
local nav = UI.NavList.new{ x = 0, y = 0, width = 160, groups = navGroups() }
mute(nav)
nav.drawTextureScaledAspect = noop
nav._mouseOver = true
ctx.setMouse(50, 50)
nav:prerender()
local rows = nav._rows
check(rows[3].cut and shown(nav) == "Performance very long label that is cut" and nav.tooltip == nil
    and nav.tooltipUI.desiredY == 66 + 8,
    "被截字的列：顯示去掉頭尾空白的全名、放在那一列下方 8px；el.tooltip 不留")
ctx.setMouse(50, 30)
nav:prerender()
check(not rows[2].cut and shown(nav) == nil, "沒被截的列：沒有提示")
nav._cursor = 3
check(nav:focusLabel() == "Performance very long label that is cut",
    "focusLabel()：被截字列的全名也去掉頭尾空白（consumer 用前置空白當縮排；Builder 追加）")
ctx.setMouse(50, 10)
nav:prerender()
check(shown(nav) == nil, "群組標題：沒有提示")
ctx.setMouse(50, 74)
nav:prerender()
check(rows[4].cut and shown(nav) == "Zombies with a very long switch label", "有開關的列停在名稱上：顯示")
ctx.setMouse(150, 74)
nav:prerender()
check(shown(nav) == nil, "停在開關上：不顯示（開關自己的語意）")
ctx.setMouse(50, 98)
nav:prerender()
check(shown(nav) == "Disabled row with a very long label", "停用列被截字：照樣顯示全名")
nav:setGroups({ { items = { { id = "x", label = "X" } } } })
ctx.setMouse(50, 10)
nav:prerender()
check(shown(nav) == nil, "setGroups 換成短名：提示收掉")

-- 零配置：提示顯示中每幀走 prerender 不配置記憶體
nav:setGroups(navGroups())
ctx.setMouse(50, 50)
-- harness 的 getCore／getTextManager 每次呼叫都建新 table（遊戲裡是同一個 Java 物件）：量測期間換成同一份
local keepTM, keepCore = getTextManager, getCore
local tm, core = keepTM(), keepCore()
getTextManager = function() return tm end
getCore = function() return core end
nav:prerender()
tabs._mouseOver = true
ctx.setMouse(110, 110)
tabs:prerender()
collectgarbage("collect")
collectgarbage("stop")
-- 同一個迴圈裡先跑一輪再量：collect 會縮掉 Lua 的堆疊，第一輪會長回來（一次性；同 test_rev14_dropdown.lua）
local kb
for i = 1, 51 do
    if i == 2 then
        kb = collectgarbage("count")
    end
    ctx.setMouse(50, 50)
    nav:prerender()
    ctx.setMouse(110, 110)
    tabs:prerender()
end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
getTextManager, getCore = keepTM, keepCore
check(grew == 0, "NavList／Tabs 提示顯示中 prerender 50 輪不配置記憶體")

ISButton.updateTooltip = keepUpdate

-- ---------- undo 圖示 ----------
local keepGetTexture = getTexture
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()
local undo = UI.Icons.get("undo")
check(undo ~= nil and undo.path == "media/ui/MinidoracatUI/mui_icon_undo.png", "undo 對到 mui_icon_undo.png")
getTexture = keepGetTexture
UI.Skin._resetForTests()

return n
