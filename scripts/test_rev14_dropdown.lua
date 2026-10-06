-- rev 14：通用單選下拉 UI.Dropdown（Widgets/Dropdown.lua）。契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI, nearly = ctx.check, ctx.UI, ctx.nearly
local F, K = UI.Focus, Keyboard
local DD_LUA = ctx.MOD_LUA .. "Widgets/Dropdown.lua"
print("情境 rev14-dropdown：載入自檢／預設尺寸／setSelected・setOptions／點選與外部點擊／停用與 alpha／鍵盤・連發／手把／捲動／錨點失效／close(scope)／零配置／Focus 缺席")

-- 量測 stub：每位元組 10px、字高 12 → 預設高 22、列高 20、清單上內距 4
local ROW_H, PAD = 20, 4
local function rowY(i) return PAD + (i - 1) * ROW_H + 1 end

-- ---------- 載入自檢 ----------
UI.CAPABILITIES.dropdown, UI.Dropdown = false, nil
local keepButton = ISButton
ISButton = nil
dofile(DD_LUA)
ISButton = keepButton
ok(UI.CAPABILITIES.dropdown == false and UI.Dropdown == nil, "原生 ISButton 缺席：dropdown 維持 false、不掛 UI.Dropdown")
dofile(DD_LUA)
local D = UI.Dropdown
ok(UI.API_REVISION >= 14 and UI.CAPABILITIES.dropdown == true and D ~= nil, "載入成功：dropdown 翻 true")

-- ---------- 建構預設 ----------
local calls = {}
local function onChange(target, id, dd)
    local p = D._popupForTests()
    calls[#calls + 1] = { target = target, id = id, dd = dd, open = dd:isOpen(), shown = p ~= nil and p:getIsVisible() }
end
local src = { { id = "a", label = "Apple" }, { id = "bb", label = "Banana split" }, { id = 3 } }
local dd = D.new{ x = 100, y = 100, options = src, placeholder = "Pick", target = ctx.TARGET, onChange = onChange }
src[1].label = "Changed"
src[4] = { id = "late", label = "Late" }
-- 最長標籤 "Banana split" 120px＋左右內距 20＋箭頭間距 6＋箭頭 7
ok(dd.width == 120 + 20 + 6 + UI.Skin.ARROW_W and dd.height == 22 and dd:getSelected() == nil and dd._focusKind == "button"
    and dd.font == UIFont.Small and dd.theme ~= nil and dd.maxRows == 8 and dd.enable == true,
    "預設：寬＝最長標籤＋內距＋箭頭、高＝字高＋10、未選、button 焦點、Small 字型、maxRows 8")
ok(#dd._options == 3 and dd._options[1].label == "Apple" and dd._options[3].label == "3",
    "選項是建構時的複本（consumer 事後改表不影響）；缺 label 用 tostring(id)")
local narrow = D.new{ width = 80, options = src, selected = "bb" }
narrow:prerender()
ok(narrow.width == 80 and narrow:getSelected() == "bb" and narrow.texts[1].text == "B..." and narrow.texts[1].x == 10,
    "明示寬度不被撐寬；標籤依可用寬（80-33）以 Text.fit 截字，畫在左內距")
local fits, realFit = 0, UI.Text.fit
UI.Text.fit = function(...) fits = fits + 1; return realFit(...) end
narrow:prerender()
narrow:prerender()
local afterSame = fits
narrow:setSelected("a", true)
narrow:prerender()
narrow:setWidth(200)
narrow:prerender()
UI.Text.fit = realFit
ok(afterSame == 0 and fits == 2, "截字只在標籤或寬度變了才重算（每幀只比兩個值）")

-- ---------- setSelected ----------
dd:setSelected("zzz")
ok(dd:getSelected() == nil and #calls == 0, "setSelected 未知 id：忽略、不回呼")
dd:setSelected("a")
ok(dd:getSelected() == "a" and #calls == 1 and calls[1].target == ctx.TARGET and calls[1].id == "a" and calls[1].dd == dd
    and dd._label == "Apple", "setSelected 改值：onChange(target, id, dropdown) 一次")
dd:setSelected("a")
ok(#calls == 1, "setSelected 相同值：no-op、不回呼")
dd:setSelected("bb", true)
ok(dd:getSelected() == "bb" and #calls == 1, "setSelected silent：改值不回呼")
dd:setSelected(nil)
ok(dd:getSelected() == nil and #calls == 2 and calls[2].id == nil and dd._label == "Pick", "setSelected(nil)：清空、回呼、顯示 placeholder")

-- ---------- setOptions ----------
dd:setSelected("bb", true)
local src2 = { { id = "bb", label = "B" }, { id = "c", label = "Cherry" } }
dd:setOptions(src2)
src2[1].label = "Mutated"
ok(dd:getSelected() == "bb" and dd._label == "B" and dd.width == 60 + 33 and #calls == 2,
    "setOptions：選取仍在就保留（標籤換新）、自動寬度重算、複製選項、不回呼")
dd:setOptions({ { id = "x", label = "X" } })
ok(dd:getSelected() == nil and dd._label == "Pick" and #calls == 2, "setOptions：選取不在新選項裡就靜默清成 nil")
narrow:setOptions({ { id = "x", label = "Extremely long label" } })
ok(narrow.width == 200, "setOptions：明示寬度不變")

-- ---------- 點擊開關、點選、外部點擊 ----------
dd:setOptions({ { id = "a", label = "Apple" }, { id = "b", label = "Berry" }, { id = "c", label = "Cherry" } })
calls = {}
dd:onMouseDown(5, 5)
dd:onMouseUp(5, 5)
local p = D._popupForTests()
ok(p ~= nil and dd:isOpen() and p:getIsVisible() and p.inUIManager and p._nativeAlwaysOnTop == true and p.captured == true
    and p.x == 100 and p.y == 100 + 22 + 2 and p.rows == 3 and p.height == 3 * ROW_H + PAD * 2 and p.width == dd.width,
    "點元件：共用清單在下方 2px 展開，addToUIManager 後才設 alwaysOnTop、setCapture，三列")
p._mouseOver = true
ok(p:onMouseDown(5, rowY(2)) == true, "清單內按下：吃掉、不漏到頁面")
p:onMouseUp(5, rowY(2))
ok(#calls == 1 and calls[1].id == "b" and calls[1].open == false and calls[1].shown == false and not p.inUIManager
    and dd:getSelected() == "b", "點第二列：先關清單再回呼一次")
dd:forceClick()
p:onMouseUp(5, rowY(2))
ok(#calls == 1 and not dd:isOpen(), "點已選中的那一列：關閉、不回呼")
dd:forceClick()
p._mouseOver = false
dd._mouseOver = true
local passOwn = p:onMouseDown(-5, -5)
local stillOpen = dd:isOpen()
dd:onMouseDown(5, 5)
dd:onMouseUp(5, 5)
ok(passOwn == false and stillOpen and not dd:isOpen(), "按在自己的元件上：清單放行給元件，元件切換成關閉")
dd._mouseOver = false
dd:forceClick()
local passOut = p:onMouseDown(-5, -5)
ok(passOut == false and not dd:isOpen() and #calls == 1, "清單外按下：關閉、不改值、不吃事件")

-- 外觀：選中列 selected 底＋左側 accent 記號＋accent 字，游標列疊 hover
dd:forceClick()
ok(p.cursor == 2, "開啟時游標在目前選取")
ctx.setMouse(p.x + 5, p.y + rowY(3))
p._mouseOver = true
p:onMouseMove(0, 0)
p._mouseOver = false
ok(p.cursor == 3, "滑鼠移動帶著游標走")
p.rects, p.texts = {}, {}
p:prerender()
local colors = dd.theme.colors
local mark, hover = nil, nil
for _, r in ipairs(p.rects) do
    if r.w == 2 and r.y == PAD + ROW_H and nearly(r.r, colors.accent.r) then mark = r end
    if r.y == PAD + 2 * ROW_H and nearly(r.a, colors.hover.a) then hover = r end
end
ok(#p.texts == 3 and nearly(p.texts[2].r, colors.accent.r) and nearly(p.texts[1].r, colors.text.r) and mark ~= nil
    and hover ~= nil, "選中列 accent 字＋2px accent 記號（不只靠顏色），游標列疊 hover 底")
dd.rects = {}
dd:prerender()
local arrowTop = dd.rects[#dd.rects - UI.Skin.ARROW_H + 1]
ok(nearly(dd.borders[1].r, colors.accent.r) and arrowTop.w == 1 and nearly(arrowTop.r, colors.accent.r),
    "開著：框 accent、箭頭朝上（第一列 1px）accent")
D.close()

-- ---------- 停用與 theme.alpha ----------
local faded = UI.Theme.create()
faded.alpha = 0.5
local fd = D.new{ options = { { id = "a", label = "Apple" } }, selected = "a", theme = faded }
fd:prerender()
local fc = faded.colors
ok(nearly(fd.rects[1].a, fc.well.a * 0.5) and nearly(fd.borders[1].a, fc.border.a * 0.5) and nearly(fd.texts[1].a, 1)
    and nearly(fd.texts[1].r, fc.text.r) and nearly(fd.rects[#fd.rects].a, 1) and nearly(fd.rects[#fd.rects].r, fc.textMuted.r),
    "theme.alpha：chrome 乘、文字與箭頭不乘；關著的箭頭 textMuted")
fd:forceClick()
fd:setEnabled(false)
local fp = D._popupForTests()
ok(not fd:isOpen() and not fp:getIsVisible() and not fd:isEnabled(), "setEnabled(false)：關掉自己的清單")
fd:forceClick()
fd:open()
ok(not fd:isOpen(), "停用時 forceClick 與 open() 都不開")
fd.rects, fd.borders, fd.texts = {}, {}, {}
fd:prerender()
ok(nearly(fd.rects[1].a, fc.well.a * 0.5 * 0.45) and nearly(fd.borders[1].a, fc.border.a * 0.5 * 0.45)
    and nearly(fd.texts[1].r, fc.textDisabled.r) and nearly(fd.texts[1].a, 1) and nearly(fd.rects[#fd.rects].r, fc.textDisabled.r)
    and nearly(fd.rects[#fd.rects].a, 1), "停用：chrome 乘 0.45 與 theme.alpha，字與箭頭 textDisabled 不淡化")
local bare = D.new{ options = { { id = "a" } }, theme = { colors = { well = fc.well, border = fc.border, text = fc.text,
    textFaint = fc.textFaint, textMuted = fc.textMuted, accent = fc.accent, hover = fc.hover, selected = fc.selected } } }
bare:setEnabled(false)
bare:prerender()
ok(nearly(bare.rects[#bare.rects].r, fc.textFaint.r), "theme 缺 textDisabled：退 textFaint，不炸")
local ph = D.new{ options = { { id = "a" } }, placeholder = "Pick" }
ph:prerender()
ok(ph.texts[1].text == "Pick" and nearly(ph.texts[1].r, ph.theme.colors.textFaint.r), "沒選：畫 placeholder，textFaint")
fd:setEnabled(true)

-- ---------- 鍵盤（Focus） ----------
local win = UI.Window.new{ x = 0, y = 0, width = 500, height = 300, title = "W" }
local kd = D.new{ x = 10, y = 40, options = { { id = 1, label = "One" }, { id = 2, label = "Two" }, { id = 3, label = "Three" } },
    selected = 1, onChange = onChange }
win:addChild(kd)
win:addToUIManager()
F.focusControl(kd, true)
calls = {}
ctx.press(win, K.KEY_RETURN)
p = D._popupForTests()
ok(kd:isOpen() and p.kbReturn == true and p.wantKeyEvents == true and p.cursor == 1, "焦點框上 Enter（Focus→forceClick）開啟清單")
local dc, dr = ctx.press(p, K.KEY_DOWN)
local afterDown = p.cursor
ctx.press(p, K.KEY_END)
local afterEnd = p.cursor
ctx.press(p, K.KEY_HOME)
local afterHome = p.cursor
ctx.press(p, K.KEY_NEXT)
ok(dc and dr and afterDown == 2 and afterEnd == 3 and afterHome == 1 and p.cursor == 3,
    "上下／End／Home／PgDn 移游標，press 與 release 都被消耗")
local ec, er = ctx.press(p, K.KEY_RETURN)
ok(ec and er and not kd:isOpen() and #calls == 1 and calls[1].id == 3 and calls[1].open == false and F.focused() == kd
    and F.isKeyboardFocused(kd), "Enter 選游標列：先關再回呼一次，焦點框回到元件")
ctx.press(win, K.KEY_SPACE)
ctx.press(p, K.KEY_UP)
local xc, xr = ctx.press(p, K.KEY_ESCAPE)
ok(xc and xr and not kd:isOpen() and #calls == 1 and kd:getSelected() == 3 and F.focused() == kd,
    "Space 開啟；Esc 關閉不改值（按住被消耗），焦點框回元件")
ctx.press(win, K.KEY_RETURN)
ctx.press(p, K.KEY_TAB)
ok(not kd:isOpen(), "Tab 關閉")
ctx.press(win, K.KEY_RETURN)
local cc, cr = ctx.press(p, K.KEY_C)
ok(cc == false and cr == false and kd:isOpen(), "未處理的鍵不消耗，留給遊戲")
ctx.press(p, K.KEY_NUMPADENTER)
ok(not kd:isOpen() and #calls == 1, "小鍵盤 Enter 選中已選的那列：關閉、不回呼")

-- 連發：按住 400ms 後才動，之後每 60ms 一步；Esc 的 repeat 不處理
kd:setOptions({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 }, { id = 6 } })
kd:setSelected(1, true)
ctx.press(win, K.KEY_RETURN)
p:onKeyPress(K.KEY_DOWN)
local s0 = p.cursor
p:onKeyRepeat(K.KEY_DOWN)
local s1 = p.cursor
ctx.advance(400)
p:onKeyRepeat(K.KEY_DOWN)
local s2 = p.cursor
ctx.advance(10)
p:onKeyRepeat(K.KEY_DOWN)
local s3 = p.cursor
ctx.advance(60)
p:onKeyRepeat(K.KEY_DOWN)
local s4 = p.cursor
p:onKeyRelease(K.KEY_DOWN)
p:isKeyConsumed(K.KEY_DOWN)
p:onKeyRepeat(K.KEY_ESCAPE)
ok(s0 == 2 and s1 == 2 and s2 == 3 and s3 == 3 and s4 == 4 and kd:isOpen(),
    "repeatDue 節奏：立即的 repeat 不動、400ms 後一步、60ms 內不動；Esc 的 repeat 不處理")
D.close()

-- ---------- 捲動（maxRows） ----------
local many = {}
for i = 1, 20 do many[i] = { id = i, label = "Item " .. i } end
local sd = D.new{ x = 100, y = 100, options = many, maxRows = 5, selected = 12 }
sd:forceClick()
p = D._popupForTests()
ok(p.rows == 5 and p.height == 5 * ROW_H + PAD * 2 and p.cursor == 12 and p.first == 8,
    "超過 maxRows：只開 5 列，開啟時捲到選中列可見")
ctx.press(p, K.KEY_END)
local endFirst = p.first
ctx.press(p, K.KEY_PRIOR)
local pgFirst, pgCursor = p.first, p.cursor
ctx.press(p, K.KEY_HOME)
ok(endFirst == 16 and pgCursor == 15 and pgFirst == 15 and p.first == 1 and p.cursor == 1,
    "End 捲到底、PgUp 上移一頁、Home 回頂：游標永遠可見")
p:onMouseWheel(1)
p:onMouseWheel(1)
local wheelFirst = p.first
p:onMouseWheel(-1)
for _ = 1, 30 do p:onMouseWheel(1) end
ok(wheelFirst == 3 and p.cursor == 1 and p.first == 16, "滾輪捲動不動游標，夾在最後一頁")
p.rects, p.texts = {}, {}
p:prerender()
local thumb = p.rects[#p.rects]
local track = p.rects[#p.rects - 1]
ok(#p.texts == 5 and p.texts[1].text == "Item 16" and thumb.w == 3 and track.w == 3 and thumb.x == p.width - PAD - 3
    and thumb.y + thumb.h == track.y + track.h, "只畫可見的 5 列；右側細捲軸，捲到底時拇指貼底")
D.close()

-- ---------- 位置 ----------
sd:forceClick()
sd:setY(1070)
p:prerender()
local aboveY = p.y
sd:setX(1900)
p:prerender()
ok(aboveY == 1070 - p.height - 2 and p.x == 1920 - p.width, "放不下翻到上方；右緣夾回螢幕（每幀跟著元件）")
D.close()

-- ---------- 錨點失效自動關 ----------
local ad = D.new{ x = 10, y = 10, options = { { id = "a" }, { id = "b" } } }
ad:forceClick()
ad:setVisible(false)
p:prerender()
local closedHidden = not ad:isOpen()
ad:setVisible(true)
local holder = ISPanel.new(ISPanel, 0, 0, 600, 600)
holder:addChild(ad)
ad:forceClick()
holder.isCollapsed = true
p:prerender()
local closedCollapsed = not ad:isOpen()
holder.isCollapsed = nil
ad:forceClick()
ad.enable = false -- 原生 setEnable 之類繞過 setEnabled 的停用
p:prerender()
local closedDisabled = not ad:isOpen()
ad.enable = true
ad:forceClick()
ad:setOptions({})
ok(closedHidden and closedCollapsed and closedDisabled and not ad:isOpen() and not p.inUIManager,
    "錨點失效自動關：元件隱藏、祖先收合、停用、選項清空")
ad:forceClick()
ok(not ad:isOpen(), "沒有選項：不開")
ad:setOptions({ { id = "a" }, { id = "b" } })
ad:forceClick()
ad:setOptions({ { id = "a" }, { id = "b" }, { id = "c" } })
ok(ad:isOpen() and p.rows == 3, "開著時 setOptions：清單原地重排")
holder:removeChild(ad)
ad.parent = nil
D.close()

-- ---------- close(scope) ----------
local outer = ISPanel.new(ISPanel, 0, 0, 600, 600)
local mid = ISPanel.new(ISPanel, 0, 0, 600, 600)
local other = ISPanel.new(ISPanel, 0, 0, 600, 600)
outer:addChild(mid)
mid:addChild(ad)
ad:forceClick()
D.close(other)
local keptOther = ad:isOpen()
D.close(outer)
local closedOuter = not ad:isOpen()
ad:forceClick()
sd:close()
local keptBySibling = ad:isOpen()
ad:close()
local closedSelf = not ad:isOpen()
ad:forceClick()
D.close()
ok(keptOther and closedOuter and keptBySibling and closedSelf and not ad:isOpen(),
    "close(scope)：無關的 scope 與別的元件 close() 不關；祖先、元件自己、省略 scope 才關")
sd:forceClick()
ad:forceClick()
ok(ad:isOpen() and not sd:isOpen(), "開另一個下拉：共用清單換擁有者")
D.close()
mid:removeChild(ad)
ad.parent = nil

-- ---------- 手把：借焦點與歸還 ----------
ctx.joy[1] = { focus = nil }
local jwin = UI.Window.new{ x = 0, y = 0, width = 500, height = 300, title = "J" }
local jd = D.new{ x = 10, y = 40, options = { { id = "a" }, { id = "b" } }, selected = "a", onChange = onChange }
jwin:addChild(jd)
jwin:addToUIManager()
local heldByWin = ctx.joy[1].focus == jwin
calls = {}
jd:forceClick()
p = D._popupForTests()
local borrowed = ctx.joy[1].focus == p
p:onJoypadDown(Joypad.BButton)
ok(heldByWin and borrowed and not jd:isOpen() and ctx.joy[1].focus == jwin and #calls == 0,
    "手把：視窗持有焦點時清單借走，B 關閉不改值、還給視窗")
jd:forceClick()
p:onJoypadDirDown()
p:onJoypadDown(Joypad.AButton)
ok(#calls == 1 and calls[1].id == "b" and calls[1].open == false and not jd:isOpen() and ctx.joy[1].focus == jwin,
    "手把：十字鍵下移、A 選取（先關再回呼）並歸還焦點")
jd:forceClick()
p:onJoypadBeforeDeactivate()
ok(not jd:isOpen(), "onJoypadBeforeDeactivate 關閉清單")
jwin:setVisible(false)
F.releaseJoypad(jwin)
ctx.joy[1] = nil
jd:forceClick()
ok(jd:isOpen() and p._focusJoyPlayer == nil, "沒有手把時不借焦點")
D.close()

-- ---------- 零配置：元件與清單的 prerender＋render ----------
sd:setX(100)
sd:setY(100)
sd:forceClick()
p = D._popupForTests()
local noop = function() end
p.drawRect, p.drawRectBorder, p.drawText = noop, noop, noop
sd.drawRect, sd.drawRectBorder, sd.drawText = noop, noop, noop
local realCore, realTM = getCore, getTextManager
local core, tm = realCore(), realTM()
getCore = function() return core end
getTextManager = function() return tm end
sd:prerender() -- 第一幀截字（只在標籤或寬度變時）
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do
    sd:prerender()
    sd:render()
    p:prerender()
    p:render()
end
local grew = collectgarbage("count") - before
collectgarbage("restart")
getCore, getTextManager = realCore, realTM
p.drawRect, p.drawRectBorder, p.drawText = nil, nil, nil
ok(grew == 0 and sd:isOpen(), "元件與清單（含捲軸）的 prerender＋render 不配置記憶體")
D.close()

-- ---------- Focus 缺席：只能用滑鼠 ----------
UI.Focus = nil
dofile(DD_LUA)
UI.Focus = F
local nd = UI.Dropdown.new{ x = 10, y = 10, options = { { id = "a" }, { id = "b" } }, onChange = onChange }
calls = {}
nd:forceClick()
local np = UI.Dropdown._popupForTests()
np._mouseOver = true
np:onMouseUp(5, rowY(2))
ok(np ~= p and not np.wantKeyEvents and #calls == 1 and calls[1].id == "b" and not nd:isOpen(),
    "UI.Focus 缺席：清單不要 key 事件，滑鼠照常選取")
UI.Dropdown.close()
dofile(DD_LUA)
win:setVisible(false)
F.clear()

return 54
