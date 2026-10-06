-- rev 16：UI.ScrollPanel（內容高、stencil 成對、捲軸繪製與滑鼠、scrollTo）、Focus 接線（閱讀順序成塊、自動捲到焦點、
-- 捲出可視區不畫框、翻頁鍵、空容器是 scroll 目標、右搖桿）、control:focusLabel() 每幀說明、UI.Text.wrap（斷行與快取）、
-- TextField:setInvalid。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
print("情境 rev16：ScrollPanel／focusLabel／Text.wrap／TextField 錯誤狀態")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local F, K = UI.Focus, Keyboard

local STUBBED = { "getAbsoluteX", "getAbsoluteY", "getYScroll", "setYScroll", "setScrollHeight", "getScrollHeight",
    "setScrollChildren", "createChildren", "getMouseX", "getMouseY" }
local keep = {}
for _, k in ipairs(STUBBED) do
    keep[k] = rawget(ISPanel, k)
end
local scrollHeightSets = 0
-- UIElement.java:930-948：有 parent 時加總，父層 scrollChildren 時再加父層 scroll（intValue）
function ISPanel:getAbsoluteX()
    local p = self.parent
    if p then return p:getAbsoluteX() + self.x end
    return self.x
end
function ISPanel:getAbsoluteY()
    local p = self.parent
    if p then
        local s = p._scrollChildren and p:getYScroll() or 0
        return p:getAbsoluteY() + self.y + (s < 0 and math.ceil(s) or math.floor(s)) -- Double.intValue：往 0 截
    end
    return self.y
end
function ISPanel:getYScroll() return self._ys or 0 end
-- ISUIElement.lua:1685-1699：夾在 [-(scrollHeight - height), 0]
function ISPanel:setYScroll(y)
    local h = self._sh or 0
    if -y > h - self.height then y = -(h - self.height) end
    if -y < 0 then y = 0 end
    self._ys = y
end
function ISPanel:setScrollHeight(h)
    scrollHeightSets = scrollHeightSets + 1
    self._sh = h
    self:setYScroll(self:getYScroll()) -- updateScrollbars 再夾一次（:1701-1719）
end
function ISPanel:getScrollHeight() return self._sh or 0 end
function ISPanel:setScrollChildren(b) self._scrollChildren = b end
function ISPanel:createChildren() end
-- ISUIElement.lua:339-351：滑鼠座標扣自身 scroll（內容座標），再減 getAbsoluteX/Y
local mx, my = 0, 0
local function setMouse(x, y)
    mx, my = x, y
    ctx.setMouse(x, y)
end
function ISPanel:getMouseX() return mx - self:getXScroll() - self:getAbsoluteX() end
function ISPanel:getMouseY() return my - self:getYScroll() - self:getAbsoluteY() end

dofile(ctx.MOD_LUA .. "Widgets/ScrollPanel.lua")
local SP = UI.ScrollPanel

check(UI.API_REVISION >= 16 and UI.CAPABILITIES.scrollPanel == true and SP ~= nil and UI.CAPABILITIES.textWrap == true
    and type(UI.Text.wrap) == "function" and UI.CAPABILITIES.textFieldInvalid == true and UI.CAPABILITIES.focusLabel == true,
    "rev 16：API_REVISION >= 16，scrollPanel／textWrap／textFieldInvalid／focusLabel 四個旗標都 true")

-- ---------- Text.wrap ----------
local wrap = UI.Text.wrap
local lines = wrap("aaa bbb ccc\n\nddd", 50)
check(#lines == 5 and lines[1] == "aaa" and lines[2] == "bbb" and lines[3] == "ccc" and lines[4] == "" and lines[5] == "ddd",
    "Text.wrap：依 \\n 分段、空段落是空行、拉丁文在空白斷（同 Dialog 的斷行）")
check(wrap("aaa bbb ccc\n\nddd", 50) == lines and wrap("aaa bbb ccc\n\nddd", 50, UIFont.Small) == lines,
    "Text.wrap 快取：同字串／寬／字型回同一張表（font 省略＝UIFont.Small）")
check(wrap("aaa bbb ccc\n\nddd", 70) ~= lines and wrap("aaa bbb ccc\n\nddd", 50, UIFont.Medium) ~= lines,
    "Text.wrap 快取鍵含寬與字型：任一不同就重算")
local nilLines, numLines = wrap(nil, 100), wrap(42, 100)
check(#nilLines == 1 and nilLines[1] == "" and numLines[1] == "42", "Text.wrap：nil 當空字串、非字串 tostring")
for i = 1, 300 do wrap("filler " .. i, 100) end
check(wrap("aaa bbb ccc\n\nddd", 50) ~= lines, "Text.wrap 快取超過上限整個清掉（舊表不再回傳）")
local dlg = UI.Dialog.show{ title = "T", text = "aaa bbb ccc\n\nddd", confirmText = "OK", width = 50 + 24 }
check(dlg ~= nil, "Dialog 改走 TextWrap.lines 仍可建立")
UI.Dialog.close(dlg, false)

-- ---------- TextField:setInvalid ----------
local changes = 0
local tf = UI.TextField.new{ x = 0, y = 0, width = 200, placeholder = "Search", onChange = function() changes = changes + 1 end }
tf:prerender()
tf:setTooltip("Manual")
local entryW = tf._entry.width
check(tf:isInvalid() == false and tf:focusLabel() == nil, "TextField 預設不在錯誤狀態、focusLabel 回 nil")
tf:setInvalid(true, "Bad value")
check(tf:isInvalid() == true and tf._entry.tooltip == "Bad value" and tf._entry.width == entryW - 16 - 4
    and tf:focusLabel() == "Bad value", "setInvalid(true, msg)：錯誤訊息蓋過手動 tooltip、內層讓出圖示位、focusLabel 回訊息")
local colors = tf.theme.colors
tf.borders, tf.texts = {}, {}
tf:prerender()
local b = tf.borders[1]
local mark = nil
for _, t in ipairs(tf.texts) do if t.text == "!" then mark = t end end
check(b.r == colors.errorText.r and b.g == colors.errorText.g and mark ~= nil and mark.r == colors.errorText.r,
    "錯誤狀態：框用 errorText、圖示缺時右側畫 errorText 的 \"!\"（不只靠顏色）")
tf._entry:focus()
tf.borders = {}
tf:prerender()
check(tf.borders[1].r == colors.errorText.r, "錯誤狀態聚焦時框仍是 errorText，不換成 accent")
tf._entry:unfocus()
-- 有圖示時畫 warning（Icons），不畫 "!"
local keepTex = getTexture
getTexture = function(path) return { path = path } end
UI.Skin._resetForTests()
local drawn = nil
function tf:drawTextureScaled(tex, x, y, w, h, a, r, g, b2) drawn = { tex = tex, x = x, w = w, r = r } end
tf.texts = {}
tf:prerender()
local bang = false
for _, t in ipairs(tf.texts) do if t.text == "!" then bang = true end end
check(drawn ~= nil and string.find(drawn.tex.path, "warning", 1, true) ~= nil and drawn.w == 16
    and drawn.x == 200 - 6 - 16 and drawn.r == colors.errorText.r and not bang,
    "圖示在：右側 16px warning、errorText 染色，不畫退回的 \"!\"")
getTexture = keepTex
UI.Skin._resetForTests()
tf.drawTextureScaled = nil
tf:setInvalid(true, "Bad value")
check(tf._entry.width == entryW - 20 and tf._entry.tooltip == "Bad value", "相同狀態與訊息 no-op")
tf:setInvalid(true, "Other")
check(tf._entry.tooltip == "Other" and tf._entry.width == entryW - 20, "換訊息只換 tooltip，不重排")
tf:setInvalid(true)
check(tf:isInvalid() and tf._entry.tooltip == "Manual" and tf:focusLabel() == nil,
    "錯誤但沒有訊息：tooltip 回到手動的，focusLabel 回 nil")
tf:setInvalid(false, "ignored")
tf.borders = {}
tf:prerender()
check(not tf:isInvalid() and tf._entry.width == entryW and tf._entry.tooltip == "Manual"
    and tf.borders[1].r == colors.border.r and changes == 0,
    "清掉錯誤：寬度與手動 tooltip 恢復、框回 border；setInvalid 從不觸發 onChange")
local ph = UI.TextField.new{ x = 0, y = 0, width = 116, placeholder = "1234567890" } -- 可用寬 100：剛好放得下，錯誤時 80 放不下
ph:prerender()
local fitBefore = ph._phFit
ph:setInvalid(true, "Need a number")
ph:prerender()
check(fitBefore == "1234567890" and ph._phFit ~= fitBefore and ph._entry.tooltip == "Need a number",
    "錯誤狀態讓出圖示位：placeholder 重新截字；tooltip 仍是錯誤訊息（優先於自動 tooltip）")
ph:setInvalid(false)
ph:prerender()
check(ph._phFit == fitBefore and ph._entry.tooltip == nil, "清掉錯誤：placeholder 下一幀放得下、自動 tooltip 收掉")
local off = UI.TextField.new{ x = 0, y = 0, width = 120 }
off:setEnabled(false)
off:setInvalid(true, "x")
off.texts, off.borders = {}, {}
off:prerender()
local offMark = nil
for _, t in ipairs(off.texts) do if t.text == "!" then offMark = t end end
check(nearly(off.borders[1].a, (colors.errorText.a or 1) * 0.45) and offMark ~= nil and offMark.r == colors.textDisabled.r,
    "停用＋錯誤：框 errorText 乘停用淡化 0.45、記號改 textDisabled")

-- ---------- ScrollPanel 本體 ----------
local function plain(x, y, w, h)
    local p = ISPanel.new(ISPanel, x, y, w, h)
    return p
end
local faded = UI.Theme.create()
faded.alpha = 0.5
local panel = SP.new{ x = 0, y = 0, width = 200, height = 100, theme = faded }
panel:createChildren()
check(panel._scrollPanel == true and panel.background == false and panel:contentWidth() == 188 and panel._scrollChildren == true,
    "ScrollPanel.new：已標 _scrollPanel、透明、contentWidth＝寬－12、createChildren 開 scrollChildren")
local rowsP = {}
for i = 1, 10 do
    rowsP[i] = plain(0, (i - 1) * 30, 188, 24)
    panel:addChild(rowsP[i])
end
local ghost = plain(0, 900, 188, 24)
ghost:setVisible(false)
panel:addChild(ghost)
scrollHeightSets = 0
panel:prerender()
panel:render()
check(panel:getScrollHeight() == 9 * 30 + 24 and scrollHeightSets == 1, "內容高＝可見子元件的最大下緣（隱藏的不算）")
panel:prerender()
panel:render()
check(scrollHeightSets == 1, "內容高沒變：不再呼叫 setScrollHeight")
local s = panel.stencil
check(s.set == 2 and s.clear == 2 and s.repaint == 2, "stencil 每幀 set／clear／repaint 成對（巢狀後 repaint 同一 rect）")
panel.isCollapsed = true
panel:prerender()
panel:render()
check(s.set == 2 and s.clear == 2, "收合：prerender 不 set，render 也不 clear")
panel.isCollapsed = false

panel.rects = {}
panel:prerender()
panel:render()
local track, th = panel.rects[1], panel.rects[2]
local tc = panel.theme.colors
check(track and track.x == 192 and track.y == 0 and track.w == 8 and track.h == 100 and track.r == tc.well.r
    and nearly(track.a, (tc.well.a or 1) * 0.5) and th and th.r == tc.textFaint.r and th.y == 0,
    "捲軸：右側 8px well 軌道＋textFaint 拇指，chrome 乘 theme.alpha")
check(th.h == math.max(20, math.floor(100 * 100 / 294)), "拇指高＝可視比例（最小 20）")

check(panel:onMouseWheel(1) == true and panel:getYScroll() == -panel._wheelStep, "滾輪往下一格捲 3 行")
panel:onMouseWheel(100)
check(panel:getYScroll() == -(294 - 100), "滾輪捲到底夾在內容底")
panel.rects = {}
panel:prerender()
panel:render()
check(panel.rects[1].y == 194 and panel.rects[2].y == 194 + (100 - panel.rects[2].h),
    "自身繪製吃 yScroll：捲軸畫在 y－yScroll（可視區頂端），拇指在軌道底")
panel:onMouseWheel(-100)
check(panel:getYScroll() == 0, "滾輪往上回到頂端")

-- 拖曳拇指與點軌道
local thumbH = th.h
setMouse(195, 5)
check(panel:onMouseDown(195, 5) == true and panel.captured == true and panel._drag, "按在拇指上：開始拖曳並 setCapture")
setMouse(195, 5 + (100 - thumbH))
panel:onMouseMoveOutside(0, 0)
check(panel:getYScroll() == -194, "拖到軌道底：捲到內容底（拖出元件外照樣跟）")
panel:onMouseUpOutside(0, 0)
check(panel.captured == false and not panel._drag, "放開：結束拖曳並解除 capture")
panel:setYScroll(0)
panel:onMouseDown(195, 90)
check(panel:getYScroll() == -100, "點拇指下方的軌道：往下跳一頁")
panel:setYScroll(0)
check(panel:onMouseDown(50, 50) == true and panel:getYScroll() == 0 and not panel._drag, "內容區空白處：不捲、不拖")
-- 引擎傳給自己 onMouseDown 的 y 與 ISUIElement:getMouseY 都已扣自身 scroll（內容座標），捲軸在可視區座標
panel:setYScroll(-194)
local engineY = (100 - math.floor(thumbH / 2)) + 194 -- 拇指（在軌道底）中心的可視區 y，換成內容座標
setMouse(195, 100 - math.floor(thumbH / 2))
panel:onMouseDown(195, engineY)
check(panel._drag == true and panel:getYScroll() == -194, "捲到底後按拇指（引擎給內容座標）：開始拖曳，不誤判成軌道跳頁")
setMouse(195, math.floor(thumbH / 2)) -- 拇指拖回軌道頂
panel:onMouseMove(0, 0)
check(panel:getYScroll() == 0, "捲動中拖曳：getMouseY 換回可視區座標，拇指拖到頂就捲回頂端")
panel:onMouseUp(0, 0)
panel:setYScroll(-194)
panel._mouseOver = true
setMouse(195, 100 - 5) -- 可視區底部、拇指上
panel.rects = {}
panel:prerender()
panel:render()
panel._mouseOver = false
check(panel.rects[2].r == tc.textMuted.r, "捲動中滑鼠停在拇指上：拇指改 textMuted（hover 判定用可視區座標）")
panel:onMouseDown(195, 10 + 194)
check(not panel._drag and panel:getYScroll() == -94, "捲到底後按拇指上方的軌道：往上跳一頁")
panel:setYScroll(0)

-- scrollTo
panel:scrollTo(rowsP[8]) -- 內容 y 210..234
check(panel:getYScroll() == -(234 + 4 - 100), "scrollTo 下方的子元件：底端對齊（留 4px 給焦點框）")
panel:scrollTo(rowsP[7]) -- 180..204：已完整可見
check(panel:getYScroll() == -(234 + 4 - 100), "scrollTo 已完整可見：不動")
panel:scrollTo(rowsP[2]) -- 30..54
check(panel:getYScroll() == -(30 - 4), "scrollTo 上方的子元件：頂端對齊")
panel:scrollTo(rowsP[1])
check(panel:getYScroll() == 0, "scrollTo 第一列：夾在頂端")

local short = SP.new{ x = 0, y = 0, width = 200, height = 100 }
short:addChild(plain(0, 0, 100, 40))
short.rects = {}
short:prerender()
short:render()
check(#short.rects == 0 and short:onMouseWheel(1) == false, "內容放得下：不畫捲軸，滾輪交給父層（回 false）")

-- 零配置：捲軸顯示中的 prerender＋render、錯誤狀態的 TextField、Text.wrap 快取命中
local noop = function() end
panel:setYScroll(-50)
panel.drawRect, panel.drawRectBorder = noop, noop
tf:setInvalid(true, "Bad value")
tf.drawRect, tf.drawRectBorder, tf.drawText = noop, noop, noop
tf:prerender()
local keepTM = getTextManager
local tm = keepTM()
getTextManager = function() return tm end
local cached = wrap("cached text", 40)
local function round()
    panel:prerender()
    panel:render()
    tf:prerender()
    wrap("cached text", 40)
end
collectgarbage("collect")
collectgarbage("stop")
round() -- collect 會收掉 Lua 的 CallInfo 快取：先走一輪，量的是每輪的配置而不是呼叫堆疊重長
local before = collectgarbage("count")
for _ = 1, 50 do
    round()
end
local grew = collectgarbage("count") - before
collectgarbage("restart")
getTextManager = keepTM
panel.drawRect, panel.drawRectBorder = nil, nil
tf.drawRect, tf.drawRectBorder, tf.drawText = nil, nil, nil
tf:setInvalid(false)
check(grew == 0 and cached == wrap("cached text", 40), "ScrollPanel（捲軸顯示中）、錯誤狀態 TextField、Text.wrap 快取命中都不配置記憶體")

-- ---------- Focus：閱讀順序、自動捲、翻頁鍵 ----------
local win = UI.Window.new{ x = 0, y = 0, width = 300, height = 300, title = "T" }
local head = UI.Button.new{ x = 10, y = 30, title = "Head" }
win:addChild(head)
local list = SP.new{ x = 10, y = 60, width = 200, height = 100 }
list:createChildren()
win:addChild(list)
local items = {}
for i = 1, 10 do
    items[i] = UI.Button.new{ x = 0, y = (i - 1) * 30, title = "Item" .. i }
    list:addChild(items[i])
end
local side = UI.Button.new{ x = 220, y = 70, title = "Side" } -- 和容器同一列、在右邊
win:addChild(side)
local foot = UI.Button.new{ x = 10, y = 200, title = "Foot" }
win:addChild(foot)
win:addToUIManager()
list:prerender()
list:render()
local function order()
    local t = F.collectTargets(win)
    local out = {}
    for i = 1, #t do out[i] = t[i].control.title end
    return table.concat(out, ",")
end
local expected = "Head,Item1,Item2,Item3,Item4,Item5,Item6,Item7,Item8,Item9,Item10,Side,Foot"
check(order() == expected, "閱讀順序：容器裡的目標排成一塊、以容器位置排（容器右邊同列的 Side 在整塊之後）")
list:setYScroll(-150)
check(order() == expected, "捲動後閱讀順序不變")
list:setYScroll(0)

local rings = 0
local keepRing = F.drawRing
F.drawRing = function(...) rings = rings + 1 return keepRing(...) end
local function frame()
    list:prerender()
    list:render()
    win:render()
end
F.focusControl(items[6], false) -- 滑鼠焦點：不亮框、不捲
frame()
check(list:getYScroll() == 0 and rings == 0, "滑鼠焦點（不畫框）：不自動捲")
ctx.press(win, K.KEY_TAB)
frame()
local ay = items[7]:getAbsoluteY()
check(F.focused() == items[7] and ay >= list:getAbsoluteY() and ay + items[7].height <= list:getAbsoluteY() + list.height
    and rings == 1, "Tab 到可視區外的 Item7：自動捲到看得見並畫框")
local afterTab = list:getYScroll()
list:onMouseWheel(-100) -- 玩家用滾輪捲回頂端
frame()
check(list:getYScroll() == 0 and rings == 1, "同一個焦點下用滾輪捲走：不搶回，捲出可視區時不畫框")
ctx.press(win, K.KEY_TAB)
frame()
check(F.focused() == items[8] and list:getYScroll() < afterTab, "換到下一個焦點才再自動捲")
local before = list:getYScroll()
local pc = ctx.press(win, K.KEY_NEXT)
check(pc and list:getYScroll() < before and F.focused() == items[8], "焦點在容器裡：PgDn 捲容器一頁、焦點不動、按鍵消耗")
ctx.press(win, K.KEY_HOME)
check(list:getYScroll() == 0, "Home 捲回容器頂端")
ctx.press(win, K.KEY_END)
check(list:getYScroll() == -(list:getScrollHeight() - list.height), "End 捲到容器底端")

-- 空容器（只有說明文字）＝ scroll 目標
local notes = SP.new{ x = 10, y = 170, width = 200, height = 20 }
notes:createChildren()
notes._focusLabel = "Notes"
notes:addChild(plain(0, 0, 180, 60))
win:addChild(notes)
notes:prerender()
notes:render()
local t = F.collectTargets(win)
local found = nil
for i = 1, #t do if t[i].control == notes then found = t[i] end end
check(found ~= nil and found.kind == "scroll" and found.label == "Notes", "容器裡沒有目標：容器本身是 kind=scroll 目標，_focusLabel 當說明")
F.focusControl(notes, true)
ctx.press(win, K.KEY_DOWN)
check(notes:getYScroll() == -math.max(16, 12 + 4), "scroll 目標：方向鍵下捲一行")
ctx.press(win, K.KEY_NEXT)
local firstPage = notes:getYScroll()
ctx.press(win, K.KEY_NEXT)
check(firstPage == -32 and notes:getYScroll() == -40, "scroll 目標：PgDn 捲一頁（頁＝可視高－一行，至少一行），到底夾住")

-- 右搖桿（手把）
local keepAxis, keepUIM = getJoypadAimingAxisY, UIManager
local axis = 0
getJoypadAimingAxisY = function(id) return axis end
UIManager = { getMillisSinceLastRender = function() return 33.3 end }
ctx.joy[1] = { focus = nil, id = 3 }
F.takeJoypad(win, 0)
F.focusControl(items[2], true)
frame()
list:setYScroll(0)
axis = 0.5
frame()
check(list:getYScroll() == 0, "右搖桿沒過 0.75 門檻：不捲")
axis = 1
frame()
check(nearly(list:getYScroll(), -20), "右搖桿往下：每 33.3ms 捲 20px（同原版 doRightJoystickScrolling）")
axis = -1
frame()
check(nearly(list:getYScroll(), 0), "右搖桿往上：捲回")
F.releaseJoypad(win)
axis = 1
frame()
check(nearly(list:getYScroll(), 0), "不持有手把焦點：右搖桿不捲")
ctx.joy[1] = nil
getJoypadAimingAxisY, UIManager = keepAxis, keepUIM
F.drawRing = keepRing

-- ---------- focusLabel：每幀讀的說明 ----------
local grid = UI.Button.new{ x = 10, y = 240, width = 60, height = 24, title = "" }
grid.cursor = 1
function grid:focusLabel() return "Cell " .. self.cursor end
win:addChild(grid)
F.focusControl(grid, true)
local function caption(text)
    win.texts = {}
    win:render()
    for _, tx in ipairs(win.texts) do if tx.text == text then return tx end end
    return nil
end
check(caption("Cell 1") ~= nil, "focusLabel()：焦點說明讀控制項每幀的回答")
grid.cursor = 2
check(caption("Cell 2") ~= nil and caption("Cell 1") == nil, "游標換格不必重新落點：下一幀說明就換")
grid._focusLabel = "Grid"
function grid:focusLabel() error("boom") end
F.focusControl(grid, true)
check(caption("Grid") ~= nil, "focusLabel 出錯：照原本的說明（_focusLabel），不炸")
function grid:focusLabel() return nil end
check(caption("Grid") ~= nil, "focusLabel 回 nil：照原本的說明")
local bad = UI.TextField.new{ x = 100, y = 240, width = 100 }
win:addChild(bad)
bad:setInvalid(true, "Bad number")
F.focusControl(bad._entry, true)
check(caption("Bad number") ~= nil, "TextField 錯誤：鍵盤焦點說明是錯誤訊息（外框的 focusLabel）")
win:close()

for _, k in ipairs(STUBBED) do ISPanel[k] = keep[k] end
return n
