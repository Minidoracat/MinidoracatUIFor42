-- 切片 rev 26：Dialog 不擋操作模式（opts.modal = false、opts.anchor = "mouse"，dialogModeless）。契約見 smoke_harness.lua 的切片載入器註解。
-- 玩家回報確認框「畫面會變暗、擋到人物、在室內很容易被偷襲」（Cleaner 0.10.0）：非模態框不鋪遮罩、不吃滑鼠，
-- Enter 只在焦點框亮著時收（Enter 是原版開聊天的鍵）；滑鼠玩家的框開在游標旁，夾到下緣時放到游標上方。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev26：Dialog 不擋操作（無遮罩、游標旁開框、夾到下緣放到游標上方、非模態的 Enter／Esc／方向鍵、旗標）")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local K, F, press = Keyboard, UI.Focus, ctx.press
local SW, SH = 1920, 1080 -- harness 的 getCore 螢幕
local keepJoy = ctx.joy[1]
ctx.joy[1] = nil -- 鍵盤滑鼠玩家

-- 記下加進 UIManager 的順序（stub 只記旗標；原版 alwaysOnTop 依加入順序排，UIManager.java:544-556）
local added = {}
local keepAdd = ISPanel.addToUIManager
ISPanel.addToUIManager = function(self)
    added[#added + 1] = self
    keepAdd(self)
end
local function indexOf(el)
    for i = 1, #added do
        if added[i] == el then return i end
    end
    return nil
end
local function guardsAdded()
    local count = 0
    for i = 1, #added do
        if added[i].Type == "MinidoracatUIDialogGuard" then count = count + 1 end
    end
    return count
end

local results = {}
local function record(okv) results[#results + 1] = okv end
local function show(modal, anchor)
    for i = #added, 1, -1 do added[i] = nil end
    return UI.Dialog.show{ title = "T", text = "Hello", confirmText = "OK", cancelText = "Cancel",
        onResult = record, modal = modal, anchor = anchor }
end
local function inside(d)
    return d:getX() >= 0 and d:getY() >= 0 and d:getX() + d.width <= SW and d:getY() + d.height <= SH
end
-- 游標（螢幕座標 y）不在按鈕列上，而且框整個在游標上方
local function aboveCursor(d, my)
    local top = d:getY() + d._confirm:getY()
    local onRow = my >= top and my < top + d._confirm.height
    return not onRow and d:getY() + d.height <= my
end

-- ---------- 旗標 ----------
check(UI.API_REVISION >= 26 and UI.CAPABILITIES.dialog == true and UI.CAPABILITIES.dialogModeless == true,
    "API_REVISION 至少 26，Window 載入成功後 dialogModeless 與 dialog 一起翻 true")

local saved = MinidoracatUI
MinidoracatUI = nil
dofile(ctx.MOD_LUA .. "V1.lua")
local fresh = MinidoracatUI.v1
check(fresh.CAPABILITIES.dialogModeless == false, "V1 預設 dialogModeless = false（Window.lua 載入前）")
dofile(ctx.MOD_LUA .. "Widgets/Window.lua") -- Controls 沒載入（require 在 harness 找不到）
local noControls = fresh.CAPABILITIES.dialog == false and fresh.CAPABILITIES.dialogModeless == false
fresh.Button, fresh.TextField = UI.Button, UI.TextField
local keepPreload, keepLoaded = package.preload["MinidoracatUI/TextWrap"], package.loaded["MinidoracatUI/TextWrap"]
package.preload["MinidoracatUI/TextWrap"], package.loaded["MinidoracatUI/TextWrap"] = nil, nil
dofile(ctx.MOD_LUA .. "Widgets/Window.lua")
package.preload["MinidoracatUI/TextWrap"], package.loaded["MinidoracatUI/TextWrap"] = keepPreload, keepLoaded
check(noControls and fresh.CAPABILITIES.dialog == false and fresh.CAPABILITIES.dialogModeless == false,
    "Controls 或 TextWrap 缺席時 dialog 與 dialogModeless 都維持 false")
MinidoracatUI = saved

-- ---------- 模態（預設）：迴歸 ----------
ctx.setMouse(5, 5)
local d = show()
local guard = d._guard
check(guard ~= nil and guard.inUIManager and guard._nativeAlwaysOnTop == true
    and indexOf(guard) ~= nil and indexOf(d) ~= nil and indexOf(guard) < indexOf(d),
    "不帶 modal：建 guard、加進 UIManager 並置頂，在框的下面（先加）")
check(d:getX() == math.floor((SW - d.width) / 2) and d:getY() == math.floor((SH - d.height) / 2),
    "不帶 anchor：畫面置中（不看游標）")
local pc, rc = press(d, K.KEY_RETURN)
check(pc and rc and results[#results] == true and not d.inUIManager and not guard.inUIManager,
    "模態框沒有焦點框時 Enter 照舊確認並消耗，guard 一起移除")

-- ---------- 非模態：沒有 guard，收尾照常 ----------
local count = #results
d = show(false)
check(d._guard == nil and guardsAdded() == 0 and d.inUIManager and d._nativeAlwaysOnTop == true,
    "modal = false：不建 guard（_guard 是 nil、UIManager 裡沒有 MinidoracatUIDialogGuard），框照樣置頂")
local clean = pcall(function()
    d._confirm:onMouseDown(1, 1)
    d._confirm:onMouseUp(1, 1)
    UI.Dialog.close(d, false)
    d:close()
end)
check(clean and #results == count + 1 and results[#results] == true and not d.inUIManager,
    "非模態：按確認收尾不出錯、onResult 只回呼一次（之後 close／關閉鈕不重複）")
d = show(false)
clean = pcall(function() d:close() end)
local closeOk = clean and #results == count + 2 and results[#results] == false
d = show(false)
clean = pcall(function()
    d._cancel:onMouseDown(1, 1)
    d._cancel:onMouseUp(1, 1)
end)
local cancelOk = clean and #results == count + 3 and results[#results] == false
d = show(false)
clean = pcall(UI.Dialog.close, d, true)
check(closeOk and cancelOk and clean and #results == count + 4 and results[#results] == true,
    "非模態：關閉鈕、取消鈕、Dialog.close 收尾都不出錯，各回呼一次")

-- ---------- anchor = "mouse" ----------
ctx.setMouse(800, 500)
d = show(false, "mouse")
check(d:getX() + d.width / 2 == 800 and d:getY() + d.height / 2 == 500, "游標在畫面中段：框的中心等於游標")
UI.Dialog.close(d)
ctx.setMouse(5, 5)
d = show(false, "mouse")
d:prerender()
local topLeft = inside(d)
UI.Dialog.close(d)
ctx.setMouse(SW - 3, 4)
d = show(false, "mouse")
d:prerender()
check(topLeft and inside(d), "游標在上方角落：第一次 prerender 之後框在畫面內")
UI.Dialog.close(d)
ctx.setMouse(5, SH - 5)
d = show(false, "mouse")
d:prerender()
check(inside(d) and d:getX() == 0 and aboveCursor(d, SH - 5),
    "游標在左下角：框夾回畫面內、整個在游標上方（游標不在按鈕列）")
UI.Dialog.close(d)
ctx.setMouse(SW - 5, SH - 5)
d = show(false, "mouse")
d:prerender()
check(inside(d) and d:getX() == SW - d.width and aboveCursor(d, SH - 5),
    "游標在右下角：框夾回畫面內、整個在游標上方（確認鈕靠右，最容易對上）")
UI.Dialog.close(d)

-- ---------- consumer 在 onResult 裡開下一個框（Cleaner：主框按刪除後接著開膠囊框） ----------
-- 舊框先清掉「目前的框」、收掉再回呼：新框要留著、拿到手把焦點，也要記成目前的框（再開一個時先關它）
ctx.joy[1] = { focus = nil }
local chained
local first = UI.Dialog.show{ title = "T", text = "a", confirmText = "OK", cancelText = "C", modal = false,
    onResult = function(okv)
        record(okv)
        chained = UI.Dialog.show{ title = "T2", text = "b", confirmText = "OK", cancelText = "C", modal = false,
            onResult = record }
    end }
first:onJoypadDown(Joypad.AButton, ctx.joy[1])
check(results[#results] == true and not first.inUIManager and chained ~= nil and chained.inUIManager
    and getJoypadFocus(0) == chained and F.focused() == chained._confirm,
    "onResult 裡開下一個框：舊框收掉、回呼一次，新框留著並拿到手把焦點")
ctx.joy[1] = nil
d = show(false)
check(chained ~= nil and not chained.inUIManager and results[#results] == false and d.inUIManager,
    "onResult 裡開的框記成目前的框：再開一個時先以取消關掉它（不會兩個框同時開著）")
UI.Dialog.close(d)

-- ---------- 非模態的鍵盤 ----------
count = #results
d = show(false)
pc, rc = press(d, K.KEY_RETURN)
local pn, rn = press(d, K.KEY_NUMPADENTER)
check(not pc and not rc and not pn and not rn and #results == count and d.inUIManager,
    "非模態、焦點框沒亮：Enter／NumpadEnter 按下與放開都不消耗、不確認（交給遊戲開聊天）")
local du, ru = press(d, K.KEY_DOWN)
local dl, rl = press(d, K.KEY_LEFT)
check(not du and not ru and not dl and not rl, "非模態、焦點框沒亮：方向鍵不消耗（角色照常走）")
pc, rc = press(d, K.KEY_ESCAPE)
check(pc and rc and #results == count + 1 and results[#results] == false and not d.inUIManager,
    "非模態：Esc 取消並消耗")
d = show(false)
pc = press(d, K.KEY_TAB)
check(pc and F.focused() == d._cancel and F.isKeyboardFocused(d._cancel),
    "非模態：Tab 把焦點框帶進框（先到「取消」，同一般視窗消耗 Tab）")
pc, rc = press(d, K.KEY_RETURN)
check(pc and rc and #results == count + 2 and results[#results] == false,
    "非模態、焦點框在「取消」：Enter 按取消並消耗")
d = show(false)
press(d, K.KEY_TAB)
press(d, K.KEY_TAB)
local onConfirm = F.focused() == d._confirm and F.isKeyboardFocused(d._confirm)
pc, rc = press(d, K.KEY_RETURN)
check(onConfirm and pc and rc and #results == count + 3 and results[#results] == true,
    "非模態、焦點框在「確認」：Enter 確認並消耗")
d = show(false)
press(d, K.KEY_TAB)
d:onKeyPress(K.KEY_RETURN)
local pressTaken = d:isKeyConsumed(K.KEY_RETURN)
F.clear(d) -- 按住 Enter 時焦點框不見了（例如滑鼠點了別的視窗）
d:onKeyRelease(K.KEY_RETURN)
check(pressTaken and d:isKeyConsumed(K.KEY_RETURN) and #results == count + 3 and d.inUIManager,
    "非模態：按下時焦點框亮著、放開前不見了：不確認，放開照樣消耗（與按下一致）")
UI.Dialog.close(d)

ISPanel.addToUIManager = keepAdd
ctx.joy[1] = keepJoy
return n
