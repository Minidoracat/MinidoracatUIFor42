-- rev 11 切片 A：UI.Date／UI.DateField／UI.DatePicker（Widgets/DatePicker.lua）
-- 由 smoke_harness.lua 的 rev 11 loader 載入；ctx 契約見該檔 rev11Ctx 上方註解。
local ctx = ...
local check, UI = ctx.check, ctx.UI
local K = Keyboard
local held = ctx.held

-- 切片缺的全域：Delete 鍵碼（值只需與其他鍵不同）
K.KEY_DELETE = K.KEY_DELETE or 211

-- 星期標頭換成兩字，讓月曆寬度落在 1920 螢幕內（stub getText 回 "[key]"，33 字會撐到 2300px）；
-- popup 第一次開啟時讀標頭，之後快取，所以只在第一次開啟時替換
local realGetText = getText
local function shortWeekText(key)
    if string.find(key, "_Week", 1, true) then return "Wk" end
    return realGetText(key)
end

local savedNow = ctx.now()
ctx.setNow(5000000) -- 1970-01-01 01:23:20 UTC：「今天」＝1970-01-01

dofile(ctx.MOD_LUA .. "Widgets/DatePicker.lua")
print("情境 rev11-date：Date 曆法／DateField 回呼與正規化／DatePicker 選日・導覽夾限・鍵盤・手把・close(scope)・零配置")

local Date, DateField, DatePicker = UI.Date, UI.DateField, UI.DatePicker
check(UI.CAPABILITIES.datePicker == true and Date and DateField and DatePicker,
    "DatePicker 載入後 CAPABILITIES.datePicker 翻 true，UI.Date／DateField／DatePicker 都在")

-- ---------- UI.Date（Economy 情境 27b 的 5 個 parseDay 案例改用 dayStart） ----------
check(Date.dayStart("2026-09-07", 0) == 1788739200000 and Date.dayStart("2026/9/7", 480) == 1788739200000 - 480 * 60000,
    "dayStart 回該曆日 00:00 的毫秒，並依時鐘偏移平移")
check(Date.dayStart("2026-13-01", 0) == nil and Date.dayStart("nope", 0) == nil and Date.dayStart(nil, 0) == nil,
    "格式不合法的日期回 nil")
check(Date.dayStart("2026-02-29", 0) == nil and Date.dayStart("2024-02-30", 0) == nil,
    "不合法的二月日期不會滾進三月")
check(Date.dayStart("2026-04-31", 0) == nil and Date.dayStart("2026-04-30", 0) ~= nil,
    "小月拒絕 31 日、保留月底")
check(Date.dayStart("2100-02-29", 0) == nil and Date.dayStart("2000-02-29", 0) == Date.dayStart("2000-03-01", 0) - 86400000,
    "閏日遵守格里曆的世紀規則")

local py, pm, pd = Date.parse(" 2026/9/7 ")
check(py == 2026 and pm == 9 and pd == 7 and Date.parse("0000-01-01") == nil and Date.parse("2026-9-7x") == nil,
    "parse：斜線／單位數月日／前後空白可；年份 0 與多餘字元拒絕")
check(Date.format(7, 3, 5) == "0007-03-05" and Date.format(2026, 12, 31) == "2026-12-31",
    "format：年補到 4 位、月日補到 2 位")
local y1, m1, d1 = Date.fromMs(1788739200000 - 60000, 0)
local y2, m2, d2 = Date.fromMs(1788739200000 - 60000, 480)
local y3, m3, d3 = Date.fromMs(-1, 0)
check(y1 == 2026 and m1 == 9 and d1 == 6 and y2 == 2026 and m2 == 9 and d2 == 7
    and y3 == 1969 and m3 == 12 and d3 == 31, "fromMs：依偏移換日；1970 前一毫秒是 1969-12-31")
local ay, am, ad = Date.fromMs(Date.dayStart("0001-01-01", 0), 0)
local zy, zm, zd = Date.fromMs(Date.dayStart("9999-12-31", 0), 0)
check(ay == 1 and am == 1 and ad == 1 and zy == 9999 and zm == 12 and zd == 31,
    "dayStart／fromMs 在 0001-01-01 與 9999-12-31 兩端互為反函式")
check(Date.daysInMonth(1900, 2) == 28 and Date.daysInMonth(2000, 2) == 29 and Date.daysInMonth(2024, 2) == 29
    and Date.daysInMonth(2026, 4) == 30 and Date.daysInMonth(2026, 12) == 31, "daysInMonth：格里曆閏年與大小月")

-- localOffsetMinutes：UTC 01:23 時本地 9:23 → +480；20:53 → 超過 +14h 繞回 -270；缺 getHourMinute → 0
getHourMinute = function() return "9:23" end
local east = Date.localOffsetMinutes()
getHourMinute = function() return "20:53" end
local west = Date.localOffsetMinutes()
getHourMinute = function() return "bad" end
local bad = Date.localOffsetMinutes()
getHourMinute = nil
check(east == 480 and west == -270 and bad == 0 and Date.localOffsetMinutes() == 0,
    "localOffsetMinutes：當地減 UTC、繞回 -12h..+14h、取 15 分鐘倍數；讀不到回 0")

-- ---------- DateField ----------
local calls, lastTarget, lastText, lastField = 0, nil, nil, nil
local function onChange(target, text, field)
    calls = calls + 1
    lastTarget, lastText, lastField = target, text, field
end

local field = DateField.new{ x = 100, y = 100, text = "2026-09-07", target = ctx.TARGET, onChange = onChange }
local text, button = field._text, field._button
local entry = text._entry
-- 字高 12：高 22；寬＝max(量 "0000-00-00"=100, 量 placeholder "[IGUI_MinidoracatUI_Date_Hint]"=300)+24+4+22
check(field.height == 22 and field.width == 350 and text.width == 324 and button.x == 328 and button.width == 22
    and button.height == 22 and text.placeholder == "[IGUI_MinidoracatUI_Date_Hint]",
    "預設尺寸：高＝字高+10；寬容得下範例與 placeholder＋4px 間距＋正方形按鈕")
field:setWidth(200)
field:setHeight(30)
check(text.width == 166 and text.height == 30 and button.x == 170 and button.width == 30 and entry.width == 154,
    "setWidth／setHeight 重排：輸入框（含內層 entry）縮放、按鈕貼右且保持正方形")
field:setWidth(350)
field:setHeight(22)

entry:setText("2026-09-08") -- 模擬引擎打字：原生 entry 的文字直接變
text:prerender()
text:prerender()
check(calls == 1 and lastTarget == ctx.TARGET and lastText == "2026-09-08" and lastField == field,
    "打字：TextField 每幀比對，onChange(target, text, field) 只呼叫一次")
field:setText("2026-09-07")
text:prerender()
local gy, gm, gd = field:getDate()
check(calls == 1 and field:getText() == "2026-09-07" and gy == 2026 and gm == 9 and gd == 7,
    "setText 靜默：不觸發 onChange；getDate 解析目前文字")
check(field:dayStart(480) == Date.dayStart("2026-09-07", 480) and field:dayStart() == Date.dayStart("2026-09-07", 0),
    "dayStart(offsetMin)；省略時用 localOffsetMinutes()（此處 0）")

field:setText("2026/9/7")
entry:onLostFocus()
local normalized = field:getText()
entry:onLostFocus()
check(normalized == "2026-09-07" and calls == 2 and lastText == "2026-09-07",
    "失焦正規化：\"2026/9/7\" → \"2026-09-07\" 回呼一次；已正規化再失焦不回呼")
field:setText("2026/13/1")
entry:onLostFocus()
check(field:getText() == "2026/13/1" and calls == 2, "失焦正規化：不合法文字原樣保留、不回呼")
field:setText("2026-09-07")

local out1, out2 = {}, { "x" }
field:appendTargets(out1, "From")
field:appendTargets(out2, "To")
check(#out1 == 2 and out1[1] == out2[2] and out1[2] == out2[3] and out1[1].kind == "entry" and out1[1].control == entry
    and out1[1].frame == text and out1[1].label == "To" and out1[2].kind == "button" and out1[2].control == button
    and out1[2].label == "[IGUI_MinidoracatUI_Date_Open]",
    "appendTargets：兩個快取描述（entry＋frame、日曆按鈕），附加在 out 尾端、重用同一批 table")

local win = UI.Window.new{ x = 0, y = 0, width = 500, height = 300, title = "W" }
local fieldInWin = DateField.new{ x = 10, y = 40, text = "2026-09-07", onChange = onChange }
win:addChild(fieldInWin)
local auto = UI.Focus.collectTargets(win)
local autoEntry, autoButton = nil, nil
for _, d in ipairs(auto) do
    if d.kind == "entry" and d.control == fieldInWin._text._entry and d.frame == fieldInWin._text then autoEntry = d end
    if d.kind == "button" and d.control == fieldInWin._button then autoButton = d end
end
check(autoEntry ~= nil and autoButton ~= nil and autoButton.label == "[IGUI_MinidoracatUI_Date_Open]",
    "框架 Window 的自動目標直接找到輸入框與日曆按鈕（按鈕帶 _focusLabel）")

-- ---------- DatePicker：開啟、選日、切換、外部點擊 ----------
getText = shortWeekText
button:forceClick()
getText = realGetText
local p = DatePicker._popupForTests()
check(p ~= nil and p.field == field and p:getIsVisible() and p.inUIManager and p._nativeAlwaysOnTop == true
    and p.captured == true and p.wantKeyEvents == true and button:isActive(),
    "按鈕開啟共用 popup：可見、加入 UI、置頂（實例化後設）、capture、收 key；按鈕 active")
check(p.year == 2026 and p.month == 9 and p.cursor == 7 and p.selD == 7 and p.lead == 2 and p.days == 30,
    "開在欄位的月份：游標與選取在 7 日，2026-09-01 是週二（lead 2），30 天")

local function cellXY(d)
    local i = d + p.lead - 1
    return p.gridX + (i - math.floor(i / 7) * 7) * p.cellW + 2, p.gridY + math.floor(i / 7) * p.cellH + 2
end
p._mouseOver = true
local cx, cy = cellXY(10)
p:onMouseUp(cx, cy)
p._mouseOver = false
text:prerender()
check(calls == 3 and lastText == "2026-09-10" and field:getText() == "2026-09-10" and not p:getIsVisible()
    and not p.inUIManager and not button:isActive() and p.field == nil,
    "點日格：寫回 2026-09-10、onChange 只一次（下一幀不再重複），popup 關閉、按鈕取消 active")

button:forceClick()
local reopened = p:getIsVisible()
button:forceClick()
check(reopened and not p:getIsVisible(), "同一個欄位的按鈕再按一次＝關閉")

button:forceClick()
button._mouseOver = true
local passOwn = p:onMouseDown(-5, -5)
local stillOpen = p:getIsVisible()
button._mouseOver = false
local passOut = p:onMouseDown(-5, -5)
check(passOwn == false and stillOpen and passOut == false and not p:getIsVisible(),
    "popup 外按下會關閉；按在自己的日曆按鈕上不關、交給按鈕切換")

button:forceClick()
p.footButtons[2]:forceClick()
check(field:getText() == "" and calls == 4 and lastText == "" and not p:getIsVisible(), "Clear chip：清空、回呼一次、關閉")
field:setText("2026-09-07")

button:forceClick()
field:setEnabled(false)
check(not p:getIsVisible() and not field:isEnabled() and text._enabled == false and button.enable == false,
    "setEnabled(false)：輸入框與按鈕停用，開著的日曆一起關")
field:setEnabled(true)

button:forceClick()
field:setVisible(false)
p:prerender()
local closedHidden = not p:getIsVisible()
field:setVisible(true)
local holder = ISPanel.new(ISPanel, 0, 0, 600, 600)
holder:addChild(field)
button:forceClick()
holder.isCollapsed = true
p:prerender()
check(closedHidden and not p:getIsVisible(), "anchor 失效自動關閉：欄位隱藏、祖先 collapsed")
holder:removeChild(field)
field.parent = nil

-- 位置：錨在欄位下方；放不下翻到上方；右緣夾回螢幕
button:forceClick()
p:prerender()
local belowY = p.y
field:setY(1050)
p:prerender()
local aboveY = p.y
field:setX(1900)
p:prerender()
check(belowY == 100 + 22 + 2 and aboveY == 1050 - p.height - 2 and p.x == 1920 - p.width,
    "place：欄位下方 2px；放不下翻到上方；右緣夾回螢幕（每幀跟著欄位）")
DatePicker.close()
field:setX(100)
field:setY(100)

-- theme.alpha：chrome 乘、文字不乘；chip 換成開啟欄位的 theme
local faded = UI.Theme.create()
faded.alpha = 0.5
local fadedField = DateField.new{ x = 100, y = 100, theme = faded }
fadedField._button:forceClick()
p.rects, p.borders, p.texts = {}, {}, {}
p:prerender()
local todayCell = nil
for _, t in ipairs(p.texts) do
    if t.text == "1" then todayCell = t end
end
local accent = faded.colors.accent
check(ctx.nearly(p.rects[1].a, 0.4) and ctx.nearly(p.borders[1].a, 0.5) and ctx.nearly(p.texts[1].a, 1)
    and p.navButtons[1].theme == faded and p.footButtons[3].theme == faded,
    "theme.alpha：popup 底（surface 0.8）與框乘 0.5、標題文字不乘；chip 用開啟欄位的 theme")
check(p.year == 1970 and p.month == 1 and p.cursor == 1 and todayCell ~= nil and todayCell.r == accent.r
    and todayCell.g == accent.g and todayCell.b == accent.b,
    "空欄位開在今天的月份（1970-01），游標在今天；今天的日字用 accent")
DatePicker.close()

-- 1970 年前的星期（Kahlua 的 % 往零截斷，必須 floor 除法）
local function leadOf(s)
    field:setText(s)
    button:forceClick()
    local lead = p.lead
    DatePicker.close()
    return lead
end
check(leadOf("1969-12-15") == 1 and leadOf("1969-07-20") == 2 and leadOf("0001-01-01") == 1,
    "1970 年前的月初星期：1969-12-01 週一、1969-07-01 週二、0001-01-01 週一")

-- ---------- 導覽夾限與 chip 焦點停靠快取 ----------
field:setText("0001-01-15")
button:forceClick()
local nav = p.navButtons
local stops = p.stops
check(not nav[1].enable and not nav[2].enable and nav[3].enable and nav[4].enable and #stops == 5 and stops[1] == nav[3],
    "0001-01：<< 與 < 停用，停靠陣列只含可用的 chip（> >> Today Clear Close）")
p.cursor = 1
local c1, r1 = ctx.press(p, K.KEY_LEFT)
ctx.press(p, K.KEY_PRIOR)
check(c1 and r1 and p.year == 1 and p.month == 1 and p.cursor == 1, "0001-01-01 再往前：LEFT 與 PgUp 停在原處（按鍵仍消耗）")
ctx.press(p, K.KEY_NEXT)
check(p.month == 2 and p.stops == stops and #stops == 6 and nav[2].enable and not nav[1].enable,
    "換月後停靠陣列原地重建（同一個 table）：< 變可用")
ctx.press(p, K.KEY_TAB)
local focusedChip = p.kbButton
p.texts = {}
p:render()
local caption = false
for _, t in ipairs(p.texts) do
    if t.text == "[IGUI_MinidoracatUI_Date_PrevMonth]" then caption = true end
end
check(focusedChip == nav[2] and caption, "Tab 移到第一顆可用 chip（<），焦點說明顯示它的 tooltip")

-- 零配置：prerender＋render 期間不建立 table（繪製 stub 換成 no-op，getCore／getTextManager 換成快取）
local noop = function() end
p.drawRect, p.drawRectBorder, p.drawText, p.drawTextCentre = noop, noop, noop, noop
local realCore, realTM = getCore, getTextManager
local core, tm = realCore(), realTM()
getCore = function() return core end
getTextManager = function() return tm end
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do
    p:prerender()
    p:render()
end
local grew = collectgarbage("count") - before
collectgarbage("restart")
getCore, getTextManager = realCore, realTM
p.drawRect, p.drawRectBorder, p.drawText, p.drawTextCentre = nil, nil, nil, nil
check(grew == 0 and p.stops == stops, "popup 的 prerender＋render（含 chip 焦點框與說明）不配置記憶體")
DatePicker.close()

field:setText("9999-12-31")
button:forceClick()
ctx.press(p, K.KEY_RIGHT)
ctx.press(p, K.KEY_NEXT)
check(not nav[3].enable and not nav[4].enable and nav[1].enable and p.year == 9999 and p.month == 12 and p.cursor == 31,
    "9999-12：> 與 >> 停用；RIGHT 與 PgDn 停在 9999-12-31")
DatePicker.close()

-- ---------- 鍵盤 ----------
field:setText("2026-09-07")
calls = 0
button:forceClick()
local pc, rc = ctx.press(p, K.KEY_RIGHT)
local afterRight = p.cursor
ctx.press(p, K.KEY_DOWN)
local afterDown = p.cursor
ctx.press(p, K.KEY_UP)
check(pc and rc and afterRight == 8 and afterDown == 15 and p.cursor == 8,
    "方向鍵移動游標（±1、±7），press 與 release 都被消耗")
p.cursor = 1
ctx.press(p, K.KEY_LEFT)
local crossY, crossM, crossD = p.year, p.month, p.cursor
ctx.press(p, K.KEY_PRIOR)
local pgM = p.month
ctx.press(p, K.KEY_NEXT)
check(crossY == 2026 and crossM == 8 and crossD == 31 and pgM == 7 and p.month == 8,
    "LEFT 跨月到 8/31；PgUp／PgDn 換月")
ctx.press(p, K.KEY_RETURN)
check(field:getText() == "2026-08-31" and calls == 1 and not p:getIsVisible(), "Enter 在日格：寫入游標日、回呼一次、關閉")

button:forceClick()
ctx.press(p, K.KEY_HOME)
check(field:getText() == "1970-01-01" and calls == 2 and not p:getIsVisible(), "Home＝今天")
button:forceClick()
ctx.press(p, K.KEY_DELETE)
check(field:getText() == "" and calls == 3 and not p:getIsVisible(), "Delete＝清除")
field:setText("2026-09-07")

button:forceClick()
local ec, er = ctx.press(p, K.KEY_ESCAPE)
check(ec and er and not p:getIsVisible() and field:getText() == "2026-09-07" and calls == 3,
    "Esc 關閉不改值；關掉 popup 的這次按住 press／release 都被消耗")
button:forceClick()
local cc, cr = ctx.press(p, K.KEY_C)
check(cc == false and cr == false and p:getIsVisible(), "未處理的鍵不消耗，留給遊戲")

held[K.KEY_LSHIFT] = true
ctx.press(p, K.KEY_TAB)
held[K.KEY_LSHIFT] = nil
local backChip = p.kbButton
ctx.press(p, K.KEY_LEFT)
local leftChip = p.kbButton
ctx.press(p, K.KEY_UP)
check(backChip == p.footButtons[3] and leftChip == p.footButtons[2] and p.kbButton == nil,
    "Shift+Tab 從日格繞到最後一顆（Close）；chip 上 LEFT 換 chip、UP 回日格")
ctx.press(p, K.KEY_TAB)
ctx.press(p, K.KEY_RETURN)
local prevYear = p.year
local stillShown = p:getIsVisible()
held[K.KEY_LSHIFT] = true
ctx.press(p, K.KEY_TAB) -- << → 日格
ctx.press(p, K.KEY_TAB) -- 日格 → Close
held[K.KEY_LSHIFT] = nil
ctx.press(p, K.KEY_SPACE)
check(prevYear == 2025 and stillShown and not p:getIsVisible() and calls == 3,
    "chip 上 Enter／Space＝forceClick（<< 換到前一年且不關；繞回 Close 關閉、不改值）")

-- 連發：按住 400ms 後才動，之後每 60ms 一步；Esc／Enter 不連發
button:forceClick()
p:onKeyPress(K.KEY_RIGHT)
local s0 = p.cursor
p:onKeyRepeat(K.KEY_RIGHT)
local s1 = p.cursor
ctx.advance(400)
p:onKeyRepeat(K.KEY_RIGHT)
local s2 = p.cursor
ctx.advance(10)
p:onKeyRepeat(K.KEY_RIGHT)
local s3 = p.cursor
ctx.advance(60)
p:onKeyRepeat(K.KEY_RIGHT)
local s4 = p.cursor
p:onKeyRelease(K.KEY_RIGHT)
p:isKeyConsumed(K.KEY_RIGHT)
p:onKeyPress(K.KEY_RETURN)
ctx.advance(500)
field:setText("2026-09-07")
button:forceClick()
p:onKeyRepeat(K.KEY_ESCAPE)
check(s0 == 8 and s1 == 8 and s2 == 9 and s3 == 9 and s4 == 10 and p:getIsVisible(),
    "repeatDue 節奏：立即的 repeat 不動、400ms 後一步、60ms 內不動；Esc 的 repeat 不處理")
DatePicker.close()

-- ---------- close(scope) ----------
local outer = ISPanel.new(ISPanel, 0, 0, 600, 600)
local mid = ISPanel.new(ISPanel, 0, 0, 600, 600)
local other = ISPanel.new(ISPanel, 0, 0, 600, 600)
outer:addChild(mid)
mid:addChild(field)
button:forceClick()
DatePicker.close(other)
local keptOther = p:getIsVisible()
DatePicker.close(outer)
local closedOuter = not p:getIsVisible()
button:forceClick()
DatePicker.close(field)
local closedSelf = not p:getIsVisible()
button:forceClick()
field:focus()
field:blur()
check(keptOther and closedOuter and closedSelf and not p:getIsVisible() and not entry:isFocused(),
    "close(scope)：無關的 scope 不關、祖先或欄位本身才關；blur 取消輸入焦點並關掉自己的日曆")
mid:removeChild(field)
field.parent = nil

-- ---------- 手把：借焦點與歸還 ----------
ctx.joy[1] = { focus = nil }
local jwin = UI.Window.new{ x = 0, y = 0, width = 500, height = 300, title = "J" }
local jfield = DateField.new{ x = 10, y = 40, text = "2026-09-07", onChange = onChange }
jwin:addChild(jfield)
jwin:addToUIManager()
local heldByWin = ctx.joy[1].focus == jwin
jfield._button:forceClick()
local borrowed = ctx.joy[1].focus == p
p:onJoypadDown(Joypad.BButton)
check(heldByWin and borrowed and not p:getIsVisible() and ctx.joy[1].focus == jwin,
    "手把：視窗持有焦點時 popup 借走，B 關閉後還給視窗")
jfield._button:forceClick()
p:onJoypadDirRight()
p:onJoypadDown(Joypad.RBumper)
local rb = p.kbButton
p:onJoypadDown(Joypad.LBumper)
p:onJoypadDown(Joypad.AButton)
check(rb == p.navButtons[1] and jfield:getText() == "2026-09-08" and ctx.joy[1].focus == jwin,
    "手把：十字鍵移游標、RB／LB 走 chip、A 在日格寫入並歸還焦點")
jfield._button:forceClick()
p:onJoypadBeforeDeactivate()
check(not p:getIsVisible(), "onJoypadBeforeDeactivate 關閉 popup")
jwin:setVisible(false)
UI.Focus.releaseJoypad(jwin)
ctx.joy[1] = nil

ctx.setNow(savedNow)
return 53
