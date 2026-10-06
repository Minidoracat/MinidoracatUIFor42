-- MinidoracatUI Focus — 鍵盤＋手把焦點引擎（API rev 10，CAPABILITIES.focus）。
--
-- 由 MinidoracatEconomyFor42 的 ECKeyboard 收編：一個 session 只有這一套引擎。視窗（root）把原生
-- key hooks 轉給這裡，引擎走訪 root 提供的「目標描述」清單、畫焦點框，並把自己處理過的按鍵全部
-- 消耗，不漏進遊戲按鍵。rev 10 另把手把接到同一份焦點狀態：方向鍵移動、A 啟動、B 取消／關窗、
-- LB／RB 交給 root 切頁。框架 Window／Dialog 已內建接好；其他 root 照下面「接線」自行轉發。
--
-- 目標描述（root:keyboardTargets() 回傳陣列；nil＝這個 root 現在不給鍵盤，例如模態框蓋住）：
--   { kind = "group",  controls = { button, ... }, label = string }  方向鍵在組內循環、Enter 按下
--   { kind = "button", control = button,           label = string }
--   { kind = "entry",  control = ISTextEntryBox,   label = string }
--   { kind = "combo",  control = ISComboBox,       label = string }
--   { kind = "list",   control = VirtualList,      label = string }
--   { kind = "scroll", control = element,          label = string }
-- 選用欄位：focusable = false（不把原生文字焦點交給它：唯讀框會吞掉所有按鍵，見唯讀陷阱）、
--   copyAll = button（Ctrl+C 改按這顆）、frame = element（焦點框畫在這個外框上）、
--   scrollOwner = element（落點前先請它 scrollTo(control)）、captionSide = "below"|"above"|"right"|"none"
--   （rev 12：框旁說明放哪；自動目標讀控制項的 _focusCaptionSide）。
-- 控制項選用方法 control:onFocusKey(key) → true＝已處理（Tabs 左右換頁、Slider 調值、樹狀清單展開、表頭換欄與排序）；
--   手把 A 以 KEY_RETURN、方向以對應方向鍵問同一個方法，順序同鍵盤（先於各種目標的預設處理）。
--   control:focusRect() → x, y, w, h（rev 12，選用；元素座標）：焦點框與說明只標這一塊（TableHeader 的目前欄）。
--   control:focusLabel() → string|nil（rev 16，選用；有外框時先問外框）：每幀讀的說明，優先於描述的 label
--   （一個元件內多個停點、游標換格就換說明；TextField 錯誤時回錯誤訊息）。
-- 捲動容器（rev 16，UI.ScrollPanel，`_scrollPanel`）：焦點框落到容器裡的控制項（或剛亮起）時請容器
--   scrollTo(外框或控制項)，外層容器也一樣；整個捲出可視區時不畫框與說明。焦點在容器裡時 PgUp／PgDn／
--   Home／End（控制項沒用掉的話）捲容器，手把右搖桿捲容器（kind="scroll" 的目標則捲它自己）。
-- 清單選用回呼 list.onHighlight(list, item, index)：方向鍵移動反白時呼叫；onSelect 只給點擊／Enter／A。
-- root 選用方法：root:onEscape() → true（root 自己的疊層關掉了）、root:isModal()、
--   root:onFocusShoulder(delta)（手把 LB＝-1、RB＝+1）。
--
-- 接線（框架 Window 已內建）：setWantKeyEvents(true)；onKeyPress／onKeyRepeat／onKeyRelease／
-- isKeyConsumed 轉同名函式；onFocus → Focus.onFocus；render 最後 Focus.render(root, theme)；
-- onJoypadDown → Focus.onJoypadDown；onJoypadDirUp/Down/Left/Right → Focus.onJoypadDir(root, "up"|…)；
-- 開窗 Focus.takeJoypad(root, playerNum)、關窗或手把斷線 Focus.releaseJoypad(root)。
--
-- 引擎出處（快照 42.20.4-20260826）：
--   派送順序    UIElement.java:2185-2214——onConsumeKeyPress 先呼叫 onKeyPress、之後才問
--               isKeyConsumed，所以剛關掉焦點的處理者仍要回答「這個鍵是我的」→ 下面的帳本
--   只派 top-level  UIManager.java:1435-1466（visible＋isWantKeyEvents，後加入的先問）
--   漏鍵代價    GameKeyboard.java:35-60——沒被消耗的 release 會到 OnKeyPressed（各 MOD 熱鍵），
--               沒被消耗的 press 會到 OnKeyStartPressed／遊戲按鍵（:72-84）
--   文字焦點優先 GameKeyboard.java:32 讀 Core.currentTextEntryBox:isDoingTextEntry()：有輸入框聚焦時
--               整條 UIManager key 路徑（press／repeat／release）都跳過，Tab／Esc 改走輸入框的
--               onOtherKey、Enter 走 onCommandEntered（Core.java:2044-2053、UITextBox2.java:841-856）
--   唯讀陷阱    Core.java:2036-2040——Core.updateKeyboard 要 isEditable()，GameKeyboard 只看
--               isDoingTextEntry()：聚焦唯讀框會吞掉所有按鍵卻什麼都不處理，所以唯讀框永不聚焦
--   滑鼠聚焦    UITextBox2.java:710-724——點擊直接聚焦輸入框，不經任何 Lua；所以可編輯目標只要
--               在畫面上就先掛勾（observe），勾子再認領玩家實際聚焦的那一個
--   修飾鍵失真  GameKeyboard.java:122-127——輸入框打字時 isKeyDown 一律回 false（wasKeyDown 同，
--               :157-162），全域 isShiftKeyDown／isCtrlKeyDown 正是它（LuaManager.java:7187-7200）：
--               在輸入框裡按 Shift+Tab 會往前走。org.lwjglx.input.Keyboard 也暴露給 Lua
--               （LuaManager.java:2491），isKeyDown 直接問 GLFW（Keyboard.java:232-240），
--               原版讀修飾鍵就用它（ISSetKeybindDialog.lua:108-110），同 Core 的 isKeyDownRaw（:2045）
--   按住歸屬    Core.java:2049-2050——Escape 由引擎回應並吃掉（eatKeyPress(1)，GameKeyboard.java:37-41
--               連 release 一起吞），所以這裡不認領它；Tab（:2051-2053）與 Enter（:2046-2047）不會被吃掉：
--               文字事件在幀尾處理（GameWindow.java:702-709），GameKeyboard 下一幀才以取樣狀態派同一次
--               按住（:310），輸入框若已放開鍵盤，它就變成新的 press 到 root → 勾子自己吞（見 settle）
--   按鈕        ISButton.lua:70-79（forceClick 檢查 visible＋enable，只呼叫一次 onclick）
--   下拉        ISComboBox.lua:200-215（showPopup／hidePopup）、:236-257（forceClick 確認並只觸發一次
--               onChange）、:159-179（popup.selected／ensureVisible）
--   清單        VirtualList.lua（setSelectedIndex 不觸發 onSelect：移動反白沒有副作用；onSelect
--               是滑鼠按下呼叫的那一個）
--   元件捲動    ISUIElement.lua:332-336、:1639-1700（getYScroll 頂端為 0、往下為負）
--   剪貼簿      core/Clipboard.java:52-59
--   手把焦點    JoyPadSetup.lua:430-457,482-535（有 focus 就呼叫 focus:onJoypadDown(button, data)，
--               方向呼叫 onJoypadDir*）、:537-583（setJoypadFocus 推 prevfocus 鏈、
--               setPrevFocusForPlayer 取回；兩者都不呼叫 updateJoypadFocus）
--   手把輸入框  ISTextEntryBox.lua:293-310（A 開螢幕鍵盤，osk.prevFocus＝目前焦點，關閉後還回）
--
-- 字串字面值只含 ASCII（Kahlua 載入會截斷非 ASCII）；顯示文字走 Translate。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Theme) or not Keyboard then
    return -- 核心或原生鍵盤缺席：不掛能力（consumer 以 CAPABILITIES.focus 探測）
end

local Focus = {}

-- ---------- 消耗帳本 ----------
-- 處理過的每個按鍵依 key 記住。記錄活得比處理者久（焦點可能已關、popup 可能已不在），release 之後
-- 再被問一次才刪：同一次實體按住的 press、每個 repeat 與 release 全部算消耗。

local eaten = {}
local releasing = {}

function Focus.eat(key)
    if key == nil then return end
    eaten[key] = true
end

-- isKeyConsumed 的答案；讀到 release 就結束這次按住
function Focus.consumed(key)
    local mine = eaten[key] == true
    if releasing[key] then
        eaten[key] = nil
        releasing[key] = nil
    end
    return mine
end

function Focus.release(key)
    if eaten[key] then releasing[key] = true end
end

-- 自動重複：GameKeyboard 在按住的每一幀都派 repeat、沒有延遲（GameKeyboard.java:61-64），240 FPS 下點一下
-- 方向鍵就連走四五列。照作業系統的節奏：按住 REPEAT_DELAY 之後才每 REPEAT_EVERY 動一次。自己接
-- onKeyRepeat 的元件（例如 root 開的 popup）在 press 時呼叫 pressed(key)、repeat 時先問 repeatDue(key)。
local REPEAT_DELAY, REPEAT_EVERY = 400, 60
local pressedAt, repeatedAt = {}, {}

function Focus.pressed(key)
    pressedAt[key], repeatedAt[key] = getTimestampMs(), nil
end

function Focus.repeatDue(key)
    local at = pressedAt[key]
    if at == nil then return false end
    local now = getTimestampMs()
    if now - at < REPEAT_DELAY then return false end
    local last = repeatedAt[key]
    if last ~= nil and now - last < REPEAT_EVERY then return false end
    repeatedAt[key] = now
    return true
end

-- 真正到達 root 的每次 press 都開新的按住，舊按住留下的記錄不能替它回答。按住結束卻沒送 release
-- 的幾種情形：別的元件回應了它（例如 popup 在 press 時關掉並離開 UI 清單），或引擎根本沒送——
-- 輸入框聚焦時按鍵走輸入框自己的回呼（GameKeyboard.java:32-43），settle 請引擎吞掉的按住也一樣（:37-41）。
local function startHold(key)
    eaten[key] = nil
    releasing[key] = nil
    Focus.pressed(key)
end

-- ---------- 焦點狀態 ----------
-- 畫面上可以同時有多個 root，但焦點框只屬於其中一個：Focus.root、它清單中的第幾個描述、描述內的
-- 哪個控制項。st.native＝可編輯輸入框持有引擎文字焦點；st.ring＝false 表示焦點是滑鼠移動的（不畫框）。

Focus.root = nil
Focus.activeRoot = nil
local st = { index = 0, sub = 0, control = nil, kind = nil, label = nil, native = nil, ring = true }
local joyActing = false -- 手把處理中：落點不把原生文字焦點交給輸入框（改由 A 開螢幕鍵盤）

-- 修飾鍵：用輸入框打字時仍然正確的讀法（見檔頭「修飾鍵失真」）；原始讀法不存在時退回全域函式
-- pcall 包一個具名 Lua 函式（不直接拿暴露的 Java 函式），也不在每次呼叫時新建 closure：render 在觸發鍵按住期間每幀都問
local function keyDown(left, right)
    return Keyboard.isKeyDown(left) or (right ~= nil and Keyboard.isKeyDown(right))
end

local function rawDown(left, right)
    if Keyboard.isKeyDown == nil or left == nil then return nil end
    local ok, down = pcall(keyDown, left, right)
    if not ok then return nil end
    return down == true
end

local function gatedDown(fn)
    if fn == nil then return false end
    local ok, down = pcall(fn)
    return ok and down == true
end

local function shiftDown()
    local raw = rawDown(Keyboard.KEY_LSHIFT, Keyboard.KEY_RSHIFT)
    if raw ~= nil then return raw end
    return gatedDown(isShiftKeyDown)
end

local function ctrlDown()
    local raw = rawDown(Keyboard.KEY_LCONTROL, Keyboard.KEY_RCONTROL)
    if raw ~= nil then return raw end
    return gatedDown(isCtrlKeyDown)
end

-- 滑鼠多選與鍵盤導覽共用同一條不受輸入框影響的修飾鍵讀法
function Focus.modifiers()
    return ctrlDown(), shiftDown()
end

-- 仍掛在 parent 底下：removeChild 會把它從 childrenInOrder 拿掉，但不清 parent 欄位（ISUIElement.lua:1480-1491）
local function attached(parent, el)
    local kids = parent.childrenInOrder
    if type(kids) ~= "table" then return true end
    for i = 1, #kids do
        if kids[i] == el then return true end
    end
    return false
end

-- 同 UIElement.java:1798-1805（自己可見、仍掛在父元件上、父元件也一樣），但頂層不問是否已在 UIManager 清單：
-- addToUIManager 只排進 toAdd，下一次 UIManager.update 才加入（UIManager.java:111-116,501-505），同一幀剛開的
-- 視窗（Dialog、外觀視窗）整個會被原生 isReallyVisible 當成看不見，手把接手時焦點框落不下去。原生答 true
-- 就直接用（每幀 render 走這條），答 false 才自己沿父鏈再判一次。
local function shown(c)
    if c.isReallyVisible == nil or c:isReallyVisible() then return true end
    local el = c
    for _ = 1, 32 do
        if el.getIsVisible and not el:getIsVisible() then return false end
        local parent = el.parent
        if parent == nil then return true end
        if not attached(parent, el) then return false end
        el = parent
    end
    return true
end

-- 可見、可用、仍掛在畫面上：失去頁面、權限或視窗的控制項不是目標，也不能留著焦點框
local function usable(c)
    if type(c) ~= "table" then return false end
    if c.javaObject == nil then return false end
    if c.getIsVisible and not c:getIsVisible() then return false end
    if not shown(c) then return false end
    if c.enable == false then return false end
    if c.disabled == true then return false end
    if c._enabled == false then return false end
    return true
end

local function ready(root)
    if type(root) ~= "table" then return false end
    if root.getIsVisible and not root:getIsVisible() then return false end
    if root.isCollapsed == true then return false end
    return true
end

-- nil（不是空陣列）＝這裡沒有鍵盤：模態框蓋住或頁面沒有東西可給；焦點改為放掉，不指向框後面的東西
local function targets(root)
    if type(root) ~= "table" or root.keyboardTargets == nil then return nil end
    local ok, list = pcall(root.keyboardTargets, root)
    if not ok or type(list) ~= "table" then return nil end
    return list
end

-- 一個描述下可到達的控制項（依 owner 的順序）
local function items(desc, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    if type(desc) ~= "table" then return out end
    if desc.kind == "group" then
        if type(desc.controls) == "table" then
            for _, c in ipairs(desc.controls) do
                if usable(c) then out[#out + 1] = c end
            end
        end
    elseif usable(desc.control) then
        out[1] = desc.control
    end
    return out
end

-- 控制項此刻是否仍是清單裡的目標（同 items 的判讀：group 看 controls，其餘看 control；描述 table
-- 會被 collectTargets 重用，非 group 描述的 controls 可能是舊資料）。每幀 render 也走這裡，不配置。
local function listed(list, c)
    for i = 1, #list do
        local desc = list[i]
        if type(desc) == "table" then
            if desc.kind == "group" then
                local controls = desc.controls
                if type(controls) == "table" then
                    for j = 1, #controls do
                        if controls[j] == c then return true end
                    end
                end
            elseif desc.control == c then
                return true
            end
        end
    end
    return false
end

-- root＝最外層有 keyboardTargets 的祖先：頁面自己也可能回答 keyboardTargets（它的清單只是視窗的
-- 一部分），停在第一個會讓焦點落在 key hooks 從未提到的 root 上
local function rootOf(control)
    local el = control
    local root = nil
    for _ = 1, 32 do
        if type(el) ~= "table" then return root end
        if el.keyboardTargets ~= nil then root = el end
        el = el.parent
    end
    return root
end

-- ---------- 原生文字焦點 ----------

local function nativeFocused(e)
    if e == nil or e.isFocused == nil then return false end
    local ok, focused = pcall(e.isFocused, e)
    return ok and focused == true
end

-- 原生文字事件與按住狀態 UI 事件是兩條獨立佇列；只比對它們的 Java 身分（KeyEventQueue 本身沒暴露）。
-- GameKeyboard.java:189-192、Keyboard.java:257-270、KeyboardStateCache.java:18-27。
-- nativeRoot＝持有那個輸入框的 root：Core.currentTextEntryBox 全遊戲只有一個，所以這份記帳是全域的；
-- 兩個 root 每幀都 render 時只有擁有者能重設它（否則另一個會在玩家打字時又把佇列清一次）。
local wasOurs, handoff, firstQueue, rootPressKey, nativeRoot = false, false, nil, nil, nil
local function beginHandoff()
    if handoff then return end
    handoff, firstQueue = true, nil
end
local function drainHandoff()
    if not handoff then return true end
    local queue = GameKeyboard and GameKeyboard.getEventQueue and GameKeyboard.getEventQueue() or nil
    if queue == nil then
        handoff, firstQueue = false, nil
        return false
    end
    if queue == firstQueue then return true end
    while Keyboard.next() do end
    if firstQueue == nil then firstQueue = queue else handoff = false end
    return true
end
local function triggerHeld(key)
    if st.triggerHold == nil then return false end
    if not rawDown(st.triggerHold) then st.triggerHold = nil; return false end
    return key == st.triggerHold
end

local function unfocusNative()
    local e = st.native
    st.native, st.triggerHold = nil, nil
    if e ~= nil and e.unfocus ~= nil then pcall(e.unfocus, e) end
end

-- 離開展開中的下拉會一起收掉它的 popup（popup 由各下拉共用 ISComboBox.SharedPopup，只收仍屬於它的）
local function closeCombo()
    if st.kind ~= "combo" then return false end
    local combo = st.control
    if type(combo) ~= "table" or combo.expanded ~= true then return false end
    combo.expanded = false
    local popup = combo.popup
    if popup ~= nil and popup.parentCombo == combo and combo.hidePopup ~= nil then
        pcall(combo.hidePopup, combo)
    end
    return true
end

-- 舊焦點還持有的東西在焦點移走前先還回去
local function releaseFocus()
    closeCombo()
    unfocusNative()
end

-- 輸入框在幀尾放開鍵盤後，同一次按住會在下一幀以新的 press 到 root（檔頭「按住歸屬」）：Tab 多走一格、
-- Enter 把剛放手的輸入框又聚焦回去；若視窗已關（Dialog 的輸入框按 Enter 確認），就漏給後面的視窗與遊戲。
-- 做法同引擎對 Escape（Core.java:2049-2050）與原版輸入框送出後（MapSpawnSelect.lua:950）：eatKeyPress
-- 吞掉這次的 press 與 release（GameKeyboard.java:37-41,71-77）。只在實體仍按著時吞——引擎沒取樣到的
-- 極短點按不會有 release 清掉記號，會改吞玩家的下一次按鍵。
local function settle(box, key)
    if nativeFocused(box) or not rawDown(key) then return end
    if GameKeyboard and GameKeyboard.eatKeyPress then GameKeyboard.eatKeyPress(key) end
end

local entryKey, entryCommit

-- 引擎跟聚焦輸入框溝通的兩個回呼，每個輸入框只包一次、接在 owner 原有的回呼之後
-- （搜尋框自己的 onCommandEntered 仍先跑查詢；這裡只處理之後鍵盤的去向）。
-- 不綁 root：勾子觸發時才以祖先鏈找 root，同一個輸入框換視窗也正確。
local function hookEntry(e)
    if e._focusHooked then return end
    e._focusHooked = true
    local previousKey = e.onOtherKey
    e.onOtherKey = function(box, key)
        if triggerHeld(key) then return end
        if previousKey then previousKey(box, key) end
        entryKey(rootOf(box), box, key)
        if key == Keyboard.KEY_TAB then settle(box, key) end
    end
    -- 輸入框內的 Enter 也不會到 key hook：引擎呼叫 onKeyEnter → onCommandEntered
    -- （UITextBox2.java:1051-1080、:841-848、Core.java:2046-2047）
    local previousEnter = e.onCommandEntered
    e.onCommandEntered = function(box)
        if triggerHeld(Keyboard.KEY_RETURN) or triggerHeld(Keyboard.KEY_NUMPADENTER) then return end
        if previousEnter then previousEnter(box) end
        entryCommit(rootOf(box), box)
        settle(box, Keyboard.KEY_RETURN)
        settle(box, Keyboard.KEY_NUMPADENTER)
    end
end

-- 可編輯目標只要在畫面上就掛勾（見檔頭「滑鼠聚焦」）：沒掛勾的輸入框會吞掉 Tab／Esc／Enter，
-- 玩家就出不了這個欄位。每框只掛一次，也尊重 owner 的 focusable = false。
local function observe(list)
    local ours = nil
    if type(list) ~= "table" then return nil end
    for _, desc in ipairs(list) do
        if type(desc) == "table" and desc.kind == "entry" and desc.focusable ~= false
            and type(desc.control) == "table" then
            hookEntry(desc.control)
            if usable(desc.control) and nativeFocused(desc.control) then ours = desc.control end
        end
    end
    return ours
end

-- 只聚焦 owner 沒標 focusable = false 的可編輯輸入框（見唯讀陷阱）；remember 已先跑過
local function focusEntry(root, e)
    if type(e) ~= "table" or e.focus == nil or e.isEditable == nil then return false end
    if st.focusable == false then return false end
    local ok, editable = pcall(e.isEditable, e)
    if not ok or editable ~= true then return false end
    hookEntry(e)
    st.native = e
    pcall(e.focus, e)
    if rootPressKey ~= nil or not wasOurs then
        st.triggerHold = rootPressKey
        beginHandoff()
        if not drainHandoff() then unfocusNative(); return false end
    end
    return true
end

-- 整個描述對焦點下控制項的說法（focusable、copyAll、frame、captionSide 是控制項自己答不出來的）
local function remember(desc)
    st.kind = desc.kind or "button"
    st.label = desc.label
    st.focusable = desc.focusable
    st.copyAll = desc.copyAll
    st.frame = desc.frame
    st.captionSide = desc.captionSide
end

local function forget()
    st.index, st.sub = 0, 0
    st.control, st.kind, st.label, st.focusable, st.copyAll, st.frame = nil, nil, nil, nil, nil, nil
    st.captionSide, st.revealed = nil, nil
end

-- 引擎實際在跟哪個輸入框說話：勾子為持有文字焦點的輸入框觸發，常常不是焦點框留下的那個（玩家直接
-- 點進去，或焦點把鍵盤還回後滑鼠又點了同一欄）。只接管「這個 root 此刻當作 entry 提供、且真的
-- 持有焦點」的輸入框；隱藏欄位、切走的頁面、別的視窗的框一律不接，按鍵留給它自己。
local function adopt(root, box)
    if st.native == box and Focus.root == root then return true end
    if type(box) ~= "table" or not ready(root) then return false end
    if not usable(box) or not nativeFocused(box) then return false end
    local list = targets(root)
    if list == nil then return false end
    for i, desc in ipairs(list) do
        if desc.kind == "entry" and desc.control == box and desc.focusable ~= false then
            releaseFocus() -- 舊焦點可能還開著下拉 popup 或另一個輸入框
            Focus.root = root
            Focus.activeRoot = root
            st.index, st.sub, st.control = i, 1, box
            remember(desc)
            st.ring = true
            st.native = box
            return true
        end
    end
    return false
end

-- 引擎擁有鍵盤時只有這兩條出路：Core 把 Escape 與 Tab 交給聚焦框的 onOtherKey（Core.java:2049-2053）。
-- Tab 另外會觸發原版 SwitchChatStream（Core.java:2053）——在任何輸入框打字時的引擎副作用，Lua 無法擋。
entryKey = function(root, box, key)
    if not adopt(root, box) then return end
    if key == Keyboard.KEY_TAB then
        Focus.step(root, shiftDown() and -1 or 1)
        -- 同一次按住的 press／release 由勾子的 settle 請引擎吞掉；repeat 不受 eatKeyPress 管
        -- （GameKeyboard.java:61-64），這裡認領讓它也不漏。Escape 相反——Core.java:2050 吃掉 press、
        -- GameKeyboard.java:37-41 連 release 一起吞，認領它只會留下永遠等不到 release 的記錄。
        Focus.eat(key)
    elseif key == Keyboard.KEY_ESCAPE then
        if not (root.onEscape and root:onEscape()) then Focus.clear(root) end
    end
end

-- Enter 結束輸入：欄位保留焦點框（Tab 從這裡接著走）但把鍵盤還回，不讓玩家以為已離開卻還在打字。
-- Enter 同 Tab（Core.java:2046-2047 不吃）：press／release 由 settle 交給引擎吞，這裡認領 repeat。
-- onCommandEntered 不告訴是哪個 Enter，兩個都認領（之後再按任何一個都會 startHold）。
entryCommit = function(root, box)
    if not adopt(root, box) then return end
    unfocusNative()
    Focus.eat(Keyboard.KEY_RETURN)
    Focus.eat(Keyboard.KEY_NUMPADENTER)
end

-- ---------- 導覽 ----------

local landBuf = {}

local function land(root, list, index, fromEnd)
    local desc = list[index]
    -- 只把下一個欄位捲進視野，其餘照一般的可見與焦點守衛
    if type(desc) == "table" then
        local owner, control = desc.scrollOwner, desc.control
        if usable(owner) and type(owner.scrollTo) == "function"
            and type(control) == "table" and control.parent == owner
            and control.javaObject ~= nil and control.enable ~= false and control.disabled ~= true then
            owner:scrollTo(control)
        end
    end
    local subs = items(desc, landBuf)
    if #subs == 0 then return false end
    local sub = 1
    if fromEnd then sub = #subs end
    Focus.root = root
    Focus.activeRoot = root
    st.index, st.sub, st.control = index, sub, subs[sub]
    remember(desc)
    if st.kind == "entry" and not joyActing then focusEntry(root, st.control) end
    return true
end

-- 另一個 root 接手前記住這個 root 的焦點框；回來後的第一次 Tab／手把輸入回到開啟它的控制項（詳情、
-- 確認框、外觀視窗關掉後不用從第一個目標重走，同瀏覽器對話框關閉後焦點回到觸發者）。
local function park()
    local root = Focus.root
    if root ~= nil and st.control ~= nil then root._focusResume = st.control end
end

local function resume(root)
    local c = root._focusResume
    if c == nil then return false end
    root._focusResume = nil
    return Focus.focusControl(c, true) -- 控制項已不在畫面上就照常從頭走
end

-- Tab／Shift+Tab：下一個有可到達控制項的描述，繞一圈為止。視窗完全不給鍵盤時回 false，按鍵留給別人。
function Focus.step(root, delta)
    local list = targets(root)
    if list == nil then
        Focus.clear(root)
        return false
    end
    if Focus.root ~= root and resume(root) then return true end
    releaseFocus()
    local count = #list
    if count == 0 then return false end
    local start = 0
    if Focus.root == root and st.index >= 1 and st.index <= count then start = st.index end
    if start == 0 and delta < 0 then start = count + 1 end
    for offset = 1, count do
        local i = start + delta * offset
        while i < 1 do i = i + count end
        while i > count do i = i - count end
        if land(root, list, i, delta < 0) then
            st.ring = true
            return true
        end
    end
    forget()
    return false
end

-- 組內方向鍵（分頁列、chip 列）：循環，永不離開這一組
local function moveInGroup(root, delta)
    local list = targets(root)
    if list == nil then return false end
    local subs = items(list[st.index])
    local count = #subs
    if count < 2 then return false end
    local i = st.sub + delta
    while i < 1 do i = i + count end
    while i > count do i = i - count end
    st.sub, st.control = i, subs[i]
    st.ring = true
    return true
end

-- ---------- 各種目標的處理 ----------

local function listKey(root, key)
    local list = st.control
    local rows = list.items
    local count = 0
    if type(rows) == "table" then count = #rows end
    if count == 0 then return false end
    local current = nil
    if list.getSelectedIndex then current = list:getSelectedIndex() end
    if type(current) ~= "number" then current = nil end
    local stride = (list.rowHeight or 0) + (list.padding or 0)
    local page = 1
    if stride > 0 then page = math.max(1, math.floor((list.height or 0) / stride)) end
    local target
    if key == Keyboard.KEY_UP then target = (current or 1) - 1
    elseif key == Keyboard.KEY_DOWN then target = (current or 0) + 1
    elseif key == Keyboard.KEY_PRIOR then target = (current or 1) - page
    elseif key == Keyboard.KEY_NEXT then target = (current or 1) + page
    elseif key == Keyboard.KEY_HOME then target = 1
    elseif key == Keyboard.KEY_END then target = count
    else return false end
    if target < 1 then target = 1 end
    if target > count then target = count end
    list:setSelectedIndex(target)
    if list.scrollToIndex then list:scrollToIndex(target) end
    if target ~= current and list.onHighlight then list.onHighlight(list, rows[target], target) end
    return true
end

-- 清單列上的 Enter／A：滑鼠按下呼叫的同一個 handler，只呼叫一次
local function listActivate(list)
    if list.getSelectedIndex == nil or list.onSelect == nil then return false end
    local index = list:getSelectedIndex()
    if type(index) ~= "number" then return false end
    local item = type(list.items) == "table" and list.items[index] or nil
    if item == nil then return false end
    list.onSelect(list, item, index)
    return true
end

local function scrollBy(c, delta)
    if c.setScrollOffset and c.maxScrollOffset then
        local maxOffset = c:maxScrollOffset()
        if maxOffset <= 0 then return false end
        local offset = c.scrollOffset or 0
        if delta == "top" then offset = 0
        elseif delta == "bottom" then offset = maxOffset
        else offset = offset + delta end
        c:setScrollOffset(offset)
        return true
    end
    if c.setYScroll and c.getYScroll and c.getScrollHeight then
        local room = math.max(0, c:getScrollHeight() - (c.height or 0))
        if room <= 0 then return false end
        local y = c:getYScroll() or 0
        if delta == "top" then y = 0
        elseif delta == "bottom" then y = -room
        else y = y - delta end
        if y > 0 then y = 0 end
        if y < -room then y = -room end
        c:setYScroll(y)
        return true
    end
    return false
end

local function notify(key)
    local Toast = UI.Toast
    if Toast and Toast.show then pcall(Toast.show, { message = getText(key) }) end
end

-- 文字目標上的 Ctrl+C。描述指定了 copyAll 時改按那顆：頁面已定義「整筆資料」與失敗訊息，鍵盤不另長
-- 第二條複製路徑。
local function copyTarget(c)
    local chip = st.copyAll
    if usable(chip) and chip.forceClick ~= nil then
        pcall(chip.forceClick, chip)
        return true
    end
    if c.getInternalText == nil then return false end
    local ok, value = pcall(c.getInternalText, c)
    if not ok or type(value) ~= "string" or value == "" then return false end
    local copied = false
    if Clipboard and Clipboard.setClipboard then
        copied = pcall(Clipboard.setClipboard, value)
    end
    notify(copied and "IGUI_MinidoracatUI_Copied" or "IGUI_MinidoracatUI_CopyFailed")
    return true
end

-- 捲動鍵（上下一行、PgUp／PgDn 一頁、Home／End 到兩端）捲 c；c 不能捲回 false
local function scrollKey(c, key)
    local line = math.max(16, getTextManager():getFontHeight(UIFont.Small) + 4)
    local page = math.max(line, (c.height or 0) - line)
    local delta
    if key == Keyboard.KEY_UP then delta = -line
    elseif key == Keyboard.KEY_DOWN then delta = line
    elseif key == Keyboard.KEY_PRIOR then delta = -page
    elseif key == Keyboard.KEY_NEXT then delta = page
    elseif key == Keyboard.KEY_HOME then delta = "top"
    elseif key == Keyboard.KEY_END then delta = "bottom"
    else return false end
    return scrollBy(c, delta)
end

-- 唯讀文字與捲動內容：在這裡捲動與複製，永不交給引擎文字焦點（唯讀框會拿走鍵盤卻什麼都不處理）
local function textKey(root, key)
    local c = st.control
    if key == Keyboard.KEY_C and ctrlDown() then return copyTarget(c) end
    return scrollKey(c, key)
end

-- rev 16：最近的捲動容器祖先（UI.ScrollPanel 標 `_scrollPanel`）
local function scrollParent(el)
    local p = type(el) == "table" and el.parent or nil
    for _ = 1, 32 do
        if type(p) ~= "table" then return nil end
        if p._scrollPanel then return p end
        p = p.parent
    end
    return nil
end

local function comboHighlight(combo)
    local popup = combo.popup
    local i = nil
    if popup then i = popup.selected end
    if type(i) ~= "number" then i = combo.selected end
    if type(i) ~= "number" then i = 1 end
    return i
end

-- 原生下拉只走它自己的 API：Enter 展開，方向鍵移動 popup 反白，再按 Enter 確認（forceClick 才觸發
-- 一次 onChange），Escape 收起 popup、不改值
local function comboKey(root, key)
    local combo = st.control
    local count = 0
    if combo.getOptionCount then count = combo:getOptionCount() end
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER or key == Keyboard.KEY_SPACE then
        if count == 0 or combo.forceClick == nil then return false end
        pcall(combo.forceClick, combo)
        Focus.invalidate(root)
        return true
    end
    if combo.expanded ~= true then return false end
    local popup = combo.popup
    if popup == nil or popup.parentCombo ~= combo then return false end
    if key == Keyboard.KEY_ESCAPE then
        combo.expanded = false
        if combo.hidePopup then pcall(combo.hidePopup, combo) end
        return true
    end
    local i = comboHighlight(combo)
    if key == Keyboard.KEY_UP then i = i - 1
    elseif key == Keyboard.KEY_DOWN then i = i + 1
    elseif key == Keyboard.KEY_HOME then i = 1
    elseif key == Keyboard.KEY_END then i = count
    else return false end
    if i < 1 then i = 1 end
    if i > count then i = count end
    popup.selected = i
    if popup.ensureVisible then pcall(popup.ensureVisible, popup, i) end
    return true
end

local function activate(root)
    local c = st.control
    if not usable(c) then return false end
    if st.kind == "list" then return listActivate(c) end
    if st.kind == "entry" then return focusEntry(root, c) end
    if st.kind == "scroll" then return false end
    if c.forceClick == nil then return false end
    pcall(c.forceClick, c)
    Focus.invalidate(root)
    return true
end

-- ---------- 公開焦點 API ----------

-- 頁面切換內容時用：焦點框跟著新內容，而不是留在不再畫出的控制項上。showRing == false 移動焦點但
-- 不畫框（滑鼠在操作，下一次 Tab 從這裡開始）。
function Focus.focusControl(control, showRing)
    if not usable(control) then return false end
    local root = rootOf(control)
    local list = targets(root)
    if list == nil then return false end
    for i, desc in ipairs(list) do
        local subs = items(desc)
        for j, c in ipairs(subs) do
            if c == control then
                releaseFocus()
                Focus.root = root
                Focus.activeRoot = root
                st.index, st.sub, st.control = i, j, control
                remember(desc)
                st.ring = showRing ~= false
                if st.kind == "entry" and not joyActing then focusEntry(root, control) end
                return true
            end
        end
    end
    return false
end

-- 把焦點框還給開啟 popup 的控制項，但只在鍵盤正在操作時：滑鼠玩家不該突然冒出焦點框
function Focus.refocus(control)
    if Focus.root == nil or st.control == nil then return false end
    return Focus.focusControl(control, true)
end

function Focus.focused()
    return st.control
end

function Focus.isKeyboardFocused(control)
    return control ~= nil and st.control == control and (st.ring == true or rootPressKey ~= nil)
end

-- 動態描述組移動時保留原本的控制項；只有它在整份清單都找不到了才選替代
function Focus.invalidate(window)
    local root = Focus.root
    if root == nil then return end
    if window ~= nil and window ~= root then return end
    local list = targets(root)
    if list == nil then
        Focus.clear(root)
        return
    end
    if st.native ~= nil and not usable(st.native) then unfocusNative() end
    local desc = list[st.index]
    local subs = items(desc)
    local found = 0
    for i, c in ipairs(subs) do
        if c == st.control then found = i end
    end
    if found == 0 and st.control ~= nil then
        for index, candidate in ipairs(list) do
            if index ~= st.index then
                for sub, control in ipairs(items(candidate)) do
                    if control == st.control then
                        st.index, st.sub = index, sub
                        remember(candidate)
                        return
                    end
                end
            end
        end
    end
    if #subs == 0 then
        -- 替代目標沿用原本的框可見性：滑鼠放的焦點（ring=false）換位後也不畫框（step 落點一律亮框）
        local ring = st.ring
        forget()
        Focus.step(root, 1)
        st.ring = ring
        return
    end
    if found == 0 then
        found = st.sub
        if found < 1 then found = 1 end
        if found > #subs then found = #subs end
    end
    local changed = st.control ~= subs[found]
    if changed then releaseFocus() end
    st.sub, st.control = found, subs[found]
    remember(desc)
    if changed and st.kind == "entry" and not joyActing then focusEntry(root, st.control) end
end

-- 冷路徑：滑鼠聚焦可能還沒觸發輸入框回呼、甚至還沒 render。只動失去焦點的視窗的子孫，不碰別的 MOD 的輸入框
function Focus.blurInputs(root)
    if root.getInternalText and root.isFocused and root:isFocused() then root:unfocus() end
    if root.childrenInOrder then
        for _, child in ipairs(root.childrenInOrder) do Focus.blurInputs(child) end
    end
end

-- 視窗隱藏、收合、切頁、失去權限：不留焦點框，也不讓任何輸入框繼續持有引擎鍵盤
function Focus.clear(root)
    if root ~= nil then root._focusResume = nil end -- 關掉或失去鍵盤的視窗不留舊位置
    if root ~= nil and Focus.root ~= nil and root ~= Focus.root then return end
    local owner = root or Focus.root or Focus.activeRoot or nativeRoot
    if owner then Focus.blurInputs(owner) end
    releaseFocus()
    if root == nil or nativeRoot == root then
        nativeRoot, handoff, firstQueue, wasOurs = nil, false, nil, false
    end
    if root == nil then Focus.activeRoot = nil end
    Focus.root = nil
    forget()
    st.ring = true
end

-- UIElement.onMouseDown 先呼叫 onFocus 再派給子元件（UIElement.java:1056-1065）；開窗走同一條路，
-- 被帶到前景的視窗擁有下一次 Tab
function Focus.onFocus(root)
    root:bringToTop()
    if Focus.activeRoot ~= root then park(); Focus.clear() end
    Focus.activeRoot = root
    st.ring = false
end

-- 由按鍵觸發的關窗：保留最後一個可見 root，直到觸發鍵的 release 被消耗為止。被原生文字輸入跳過的
-- release 改由 GameKeyboard 取樣的按住狀態觀察（見 render）。
function Focus.close(root)
    if root._focusCloseKey ~= nil then return end
    if rootPressKey ~= nil and Focus.root == root then root._focusCloseKey = rootPressKey
    else root:setVisible(false) end
end

-- ---------- key hooks（root 轉發四個） ----------

-- 目標清單是動態的（疊層、權限、頁面切換）：焦點下的控制項不在清單裡或已不能用，就不再是目標，
-- 即使它還看得見。回 true＝焦點框剛被搬到有效的目標（呼叫端不拿這次按鍵啟動任何東西）。
local function validate(root)
    if Focus.root ~= nil and Focus.root ~= root then return false end
    if st.native ~= nil and (not usable(st.native) or not nativeFocused(st.native)) then
        st.native = nil -- 玩家點走了：按鍵回到我們手上，焦點框保留
    end
    if st.control == nil then return false end
    local list = targets(root)
    if list == nil then
        Focus.clear(root)
        return false
    end
    if usable(st.control) and listed(list, st.control) then return false end
    Focus.invalidate(root)
    return true
end

-- root 自己擁有的疊層（物品挑選器、未存變更提示）先於焦點框回答 Escape，而且只問被派到這個鍵的
-- root：一個視窗永遠關不到另一個視窗的 popup。root 自己說有沒有真的關掉東西。
local function escapeOverlay(root)
    if type(root) ~= "table" or root.onEscape == nil then return false end
    local ok, closed = pcall(root.onEscape, root)
    return ok and closed == true
end

-- 焦點框屬於一個 root。引擎先把按鍵給最前面的視窗、第一個消耗者就停（UIManager.java:1435-1466），
-- 後面的 root 只看得到前面放掉的鍵——包括 Tab（否則會把焦點從忙著開模態框的視窗拉走）。
-- 只有沒有其他「就緒」root 持有焦點時，它才可以自己開始一個焦點框。
local function ownsInput(root)
    if not ready(Focus.activeRoot) then Focus.activeRoot = root end
    return Focus.activeRoot == root
end

local function handle(root, key)
    if key == Keyboard.KEY_ESCAPE and escapeOverlay(root) then return true end
    if key == Keyboard.KEY_TAB then
        return Focus.step(root, shiftDown() and -1 or 1) or (root.isModal and root:isModal()) or false
    end
    if st.control == nil or Focus.root ~= root then return false end
    local c = st.control
    if c.onFocusKey and c:onFocusKey(key) then return true end
    local taken = false
    if st.kind == "combo" then taken = comboKey(root, key)
    elseif st.kind == "list" then taken = listKey(root, key)
    elseif st.kind == "scroll" or st.kind == "entry" then taken = textKey(root, key) end
    if not taken and (key == Keyboard.KEY_PRIOR or key == Keyboard.KEY_NEXT or key == Keyboard.KEY_HOME
        or key == Keyboard.KEY_END) then
        -- rev 16：焦點在捲動容器裡的控制項上：翻頁鍵捲容器（焦點框不動，捲出可視區時不畫）
        local panel = scrollParent(c)
        taken = panel ~= nil and scrollKey(panel, key)
    end
    if taken then return true end
    if key == Keyboard.KEY_ESCAPE then
        Focus.clear(root)
        return true
    end
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER or key == Keyboard.KEY_SPACE then
        if st.kind == "entry" and key == Keyboard.KEY_SPACE then return true end
        activate(root)
        return true -- 焦點框亮著時 Enter／Space 屬於它，不給後面的聊天框
    end
    if key == Keyboard.KEY_LEFT or key == Keyboard.KEY_UP then
        moveInGroup(root, -1)
    elseif key == Keyboard.KEY_RIGHT or key == Keyboard.KEY_DOWN then
        moveInGroup(root, 1)
    elseif key ~= Keyboard.KEY_HOME and key ~= Keyboard.KEY_END and key ~= Keyboard.KEY_PRIOR
        and key ~= Keyboard.KEY_NEXT then
        return false
    end
    -- 焦點框亮著時導覽鍵都屬於面板，不論有沒有移動：漏下去的方向鍵會讓角色在玩家看表格時走動
    return true
end

function Focus.onKeyPress(root, key)
    if not ready(root) or not ownsInput(root) then return end
    startHold(key)
    if st.native ~= nil and nativeFocused(st.native) then return end
    if validate(root) and (key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER or key == Keyboard.KEY_SPACE) then
        -- 玩家看到的焦點框已不是有效目標：這次 Enter／Space 只把框放回有效目標，不按替補的控制項
        st.ring = true
        Focus.eat(key)
        return
    end
    rootPressKey = key
    local handled = handle(root, key)
    rootPressKey = nil
    if handled then st.ring = true; Focus.eat(key) end
end

-- 按住方向鍵會連續移動（過了自動重複延遲才動）；press 時沒拿下的按住之後也不拿，拿下的即使動作已不可能也維持消耗
local repeatKeys
local function repeatable(key)
    if repeatKeys == nil then
        repeatKeys = {}
        for _, code in ipairs({ Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT,
            Keyboard.KEY_PRIOR, Keyboard.KEY_NEXT }) do
            if code ~= nil then repeatKeys[code] = true end
        end
    end
    return repeatKeys[key] == true
end

function Focus.onKeyRepeat(root, key)
    if eaten[key] == nil then return end
    if not ownsInput(root) then return end
    if not repeatable(key) then return end
    if not ready(root) then return end
    if st.native ~= nil and nativeFocused(st.native) then return end
    if not Focus.repeatDue(key) then return end
    validate(root)
    handle(root, key)
end

function Focus.onKeyRelease(root, key)
    Focus.release(key)
    if root._focusCloseKey == key then
        root._focusCloseKey = nil
        root:setVisible(false)
    end
end

function Focus.isKeyConsumed(root, key)
    return Focus.consumed(key)
end

-- ---------- 手把 ----------
-- 手把沒有 Tab：方向鍵先交給焦點下的控制項（清單上下、組內左右、Slider／Tabs 的 onFocusKey），
-- 沒處理（或清單已到邊）就移到上／下一個目標。A＝Enter，B＝Escape 疊層→收下拉→關窗。

local DIR_KEYS = nil
local function dirKey(dir)
    if DIR_KEYS == nil then
        DIR_KEYS = { up = Keyboard.KEY_UP, down = Keyboard.KEY_DOWN, left = Keyboard.KEY_LEFT, right = Keyboard.KEY_RIGHT }
    end
    return DIR_KEYS[dir]
end

local function joypadButton(name)
    return Joypad ~= nil and Joypad[name] or nil
end

-- root 目前是否持有這位玩家的手把焦點
function Focus.holdsJoypad(root)
    local p = root and root._focusJoyPlayer
    if p == nil or getJoypadFocus == nil then return false end
    return getJoypadFocus(p) == root
end

-- 開窗：玩家正在用手把時把焦點交給 root，並記住原本的焦點以便關窗時還原（原版右鍵選單同一模式，
-- ISContextMenu.lua:263-290）。回 true＝已接手。鍵盤滑鼠玩家（getJoypadData 為 nil）不受影響。
-- 沒有 keyboardTargets 的元件（例如 root 開的 popup，自己處理 onJoypad*）只借走手把焦點，
-- 不動焦點框與作用中的 root；同樣以 releaseJoypad 歸還。
function Focus.takeJoypad(root, playerNum)
    playerNum = playerNum or 0
    if getJoypadData == nil or setJoypadFocus == nil then return false end
    local data = getJoypadData(playerNum)
    if data == nil then return false end
    if data.focus ~= root then
        root._focusJoyRestore = data.focus
        setJoypadFocus(playerNum, root) -- 推 prevfocus 鏈（JoyPadSetup.lua:546-569）
    end
    root._focusJoyPlayer = playerNum
    if root.keyboardTargets == nil then return true end
    if Focus.activeRoot ~= root then park(); Focus.clear() end
    Focus.activeRoot = root
    joyActing = true
    if Focus.root ~= root or st.control == nil then Focus.step(root, 1) end
    joyActing = false
    st.ring = true
    return true
end

-- 還原對象要此刻真的在畫面上（原生 isReallyVisible：自己與祖先可見、仍掛著、頂層在 UIManager，
-- UIElement.java:1798-1805）；只看自己的 visible 旗標，會把手把還給隱藏視窗裡的子元件
local function stillThere(el)
    if type(el) ~= "table" or el.javaObject == nil then return false end
    if el.isReallyVisible ~= nil then return el:isReallyVisible() == true end
    return el.getIsVisible ~= nil and el:getIsVisible() == true
end

-- 正借用 root 焦點的原版螢幕鍵盤：手把 A 在輸入框開它時記 prevFocus＝當時的焦點（ISTextEntryBox.lua:304-309），
-- 它自己關時把焦點還給 prevFocus 並重新聚焦它的輸入框（ISOnScreenKeyboard.lua:452-468）。關掉的鍵盤不算：
-- hide 不清 prevFocus，舊值會一直留著
local function borrowedBy(root)
    local OSK = OnScreenKeyboard
    if type(OSK) ~= "table" or OSK.IsVisible == nil then return nil end
    local osk = OSK.instance
    if type(osk) ~= "table" or osk.prevFocus ~= root or osk.hide == nil then return nil end
    local ok, visible = pcall(OSK.IsVisible)
    if not ok or visible ~= true then return nil end
    return osk
end

-- 關窗或手把斷線：只在 root 仍持有焦點時還原。原本的焦點若已不在畫面上就還給角色（nil），不把玩家卡在
-- 看不見的 UI 上（家族踩坑錄「手把焦點不是單一指標」）；prevfocus 鏈同 setPrevFocusForPlayer 還原。
-- 螢幕鍵盤開著時 root 被關：鍵盤改還給同一個對象、放掉它的輸入框（否則會聚焦看不見的框、吞掉所有按鍵）並一起關掉。
function Focus.releaseJoypad(root)
    local p = root and root._focusJoyPlayer
    if p == nil then return end
    local saved = root._focusJoyRestore
    root._focusJoyPlayer, root._focusJoyRestore = nil, nil
    local data = getJoypadData and getJoypadData(p) or nil
    if data == nil then return end
    local back = stillThere(saved) and saved or nil
    local osk = borrowedBy(root)
    if osk ~= nil then
        osk.prevFocus, osk.textEntryBox = back, nil
        pcall(osk.hide, osk)
    elseif data.focus ~= root then
        return
    end
    data.focus = back
    data.prevfocus = data.prevprevfocus
    data.prevprevfocus = nil
end

local function closeRoot(root)
    if root.close then root:close() else root:setVisible(false) end
    if not (root.getIsVisible and root:getIsVisible()) then Focus.releaseJoypad(root) end
end

function Focus.onJoypadDown(root, button, joypadData)
    if not ready(root) then return end
    Focus.activeRoot = root
    if button == joypadButton("BButton") then
        if escapeOverlay(root) then return end
        if closeCombo() then return end
        closeRoot(root)
        return
    end
    if button == joypadButton("LBumper") or button == joypadButton("RBumper") then
        if root.onFocusShoulder then root:onFocusShoulder(button == joypadButton("LBumper") and -1 or 1) end
        return
    end
    if button ~= joypadButton("AButton") then return end
    joyActing = true
    local moved = validate(root)
    st.ring = true
    local c = st.control
    if moved then
        -- 焦點框剛被搬到有效目標：這次 A 只讓玩家看到框在哪，不按替補的控制項
    elseif c == nil or Focus.root ~= root then
        Focus.step(root, 1)
    elseif c.onFocusKey and c:onFocusKey(Keyboard.KEY_RETURN) then
        -- A＝Enter：控制項自己的 Enter 先回答（同鍵盤 handle 的順序），例如用 Enter 選物的自訂清單
    elseif st.kind == "entry" then
        -- 原版輸入框的手把 A：開螢幕鍵盤，關閉後焦點回到這個 root（ISTextEntryBox.lua:293-310）
        if c.onJoypadDown then c:onJoypadDown(button, joypadData) end
    elseif st.kind == "combo" then
        comboKey(root, Keyboard.KEY_RETURN)
    else
        activate(root)
    end
    joyActing = false
end

function Focus.onJoypadDir(root, dir, joypadData)
    if not ready(root) then return end
    Focus.activeRoot = root
    local key = dirKey(dir)
    if key == nil then return end
    joyActing = true
    validate(root)
    st.ring = true
    if st.control == nil or Focus.root ~= root then
        Focus.step(root, 1)
        joyActing = false
        return
    end
    local c = st.control
    local vertical = dir == "up" or dir == "down"
    local handled = false
    if c.onFocusKey and c:onFocusKey(key) then
        handled = true
    elseif st.kind == "combo" and c.expanded == true then
        handled = comboKey(root, key)
    elseif st.kind == "list" and vertical then
        local before = c.getSelectedIndex and c:getSelectedIndex() or nil
        listKey(root, key)
        handled = c.getSelectedIndex ~= nil and c:getSelectedIndex() ~= before
    elseif st.kind == "group" and not vertical then
        handled = moveInGroup(root, dir == "left" and -1 or 1)
    elseif st.kind == "scroll" and vertical then
        handled = textKey(root, key)
    end
    if not handled then Focus.step(root, (dir == "up" or dir == "left") and -1 or 1) end
    joyActing = false
end

-- ---------- 焦點框 ----------

local RING_GAP = 2 -- 控制項邊緣與框之間留白
local RING_W = 2   -- 框寬（≥2px 實線，better-accessibility 焦點框最低面積）
local defaultTheme = nil

local function themeOf(root, theme)
    if theme then return theme end
    if type(root) == "table" and type(root.theme) == "table" and root.theme.colors then return root.theme end
    if defaultTheme == nil then defaultTheme = UI.Theme.create() end
    return defaultTheme
end

-- 框在控制項外側：RING_GAP 留白，再 RING_W 的 accent 框；外圈再一層不透明 surface 光暈，
-- 亮場景或淡化的外框上也分得出來。座標是 el 的元素座標。
function Focus.drawRing(el, x, y, w, h, theme)
    local colors = themeOf(el, theme).colors
    local c, bg = colors.accent, colors.surface
    local o = RING_GAP + RING_W
    local rx, ry = x - o, y - o
    local rw, rh = w + o * 2, h + o * 2
    if rw <= 0 or rh <= 0 then return end
    for i = 1, RING_W do
        el:drawRectBorder(rx - i, ry - i, rw + i * 2, rh + i * 2, 1, bg.r, bg.g, bg.b)
    end
    for i = 0, RING_W - 1 do
        el:drawRectBorder(rx + i, ry + i, rw - i * 2, rh - i * 2, c.a or 1, c.r, c.g, c.b)
    end
end

-- 框旁的說明：自己畫不出完整標籤的控制項（純圖示、被截短的標題）在這裡給鍵盤玩家讀全文。
-- side（rev 12）："below"（預設：框下方，碰到 el 底邊翻到上方）｜"above"（框上方，碰到頂邊翻到下方）｜
-- "right"（tooltip 式飛出標籤：框右側 FLY_GAP 外、對框垂直置中，尖角指向控制項，碰到右緣翻到左側）｜
-- "none"（不畫）。永遠夾在 el 之內。預設不自動避開別的控制項（會改變既有 consumer 的畫面）：
-- 直排導覽列、說明行緊貼控制項的版面由 owner 在描述指定 side。
-- 底色一律不透明（不乘 theme alpha、不吃 surface 自己的 a）。right 會蓋到旁邊的內容，所以要讀得出是
-- 浮動標籤、不是被切掉的字：外圈 FLY_HALO 的不透明 surface 讓內容和框線之間空出一條，底色再疊一層
-- accent（FLY_TINT），和頁面的黑底分得開。
local FLY_GAP = 3    -- right：焦點框外緣（含 surface 光暈）到尖角的距離
local NOTCH = 6      -- right：尖角深度（半高同值）
local FLY_HALO = 2   -- right：標籤外圈的不透明 surface
local FLY_TINT = 0.18 -- right：疊在底色上的 accent
function Focus.drawCaption(el, x, y, w, h, caption, theme, side)
    if type(caption) ~= "string" or caption == "" or side == "none" then return end
    local colors = themeOf(el, theme).colors
    local tm = getTextManager()
    local o = RING_GAP + RING_W
    local bg, bd, tc = colors.surface, colors.accent, colors.text
    if side == "right" then
        local bw = tm:MeasureStringX(UIFont.Small, caption) + 16
        local bh = tm:getFontHeight(UIFont.Small) + 8
        -- 光暈外緣最後一個像素在 x+w+o+RING_W-1（左側 x-o-RING_W）：兩側都留 FLY_GAP 像素再接尖端
        local edge = o + RING_W + FLY_GAP
        local tip = x + w + edge
        local bx, dir = tip + NOTCH, 1
        -- 夾邊連外圈一起算：外圈也要留在 el 裡
        if bx + bw + FLY_HALO > el.width then
            tip = x - edge - 1
            bx, dir = tip - NOTCH + 1 - bw, -1
        end
        if bx < FLY_HALO then bx = FLY_HALO end
        local cy = y + math.floor(h / 2)
        local by = cy - math.floor(bh / 2)
        if by + bh + FLY_HALO > el.height then by = el.height - bh - FLY_HALO end
        if by < FLY_HALO then by = FLY_HALO end
        local ny = math.max(by + NOTCH, math.min(by + bh - 1 - NOTCH, cy))
        -- 標籤連同外圈一次填不透明底，accent 只疊在標籤本身
        el:drawRect(bx - FLY_HALO, by - FLY_HALO, bw + FLY_HALO * 2, bh + FLY_HALO * 2, 1, bg.r, bg.g, bg.b)
        el:drawRect(bx, by, bw, bh, FLY_TINT, bd.r, bd.g, bd.b)
        el:drawRectBorder(bx, by, bw, bh, 1, bd.r, bd.g, bd.b)
        -- 尖角：從尖端往標籤逐欄加高的 1px 直條（實心 accent，緊接外框）
        for i = 0, NOTCH - 1 do
            el:drawRect(tip + dir * i, ny - i, 1, i * 2 + 1, 1, bd.r, bd.g, bd.b)
        end
        el:drawText(caption, bx + 8, by + 4, tc.r, tc.g, tc.b, tc.a or 1, UIFont.Small)
        return
    end
    local bw = tm:MeasureStringX(UIFont.Small, caption) + 10
    local bh = tm:getFontHeight(UIFont.Small) + 6
    local bx = x + math.floor((w - bw) / 2)
    local by
    if side == "above" then
        by = y - o - 2 - bh
        if by < 0 then by = y + h + o + 2 end
    else
        by = y + h + o + 2
        if by + bh > el.height then by = y - o - 2 - bh end
    end
    if by + bh > el.height then by = el.height - bh end
    if by < 0 then by = 0 end
    if bx + bw > el.width then bx = el.width - bw end
    if bx < 0 then bx = 0 end
    el:drawRect(bx, by, bw, bh, 1, bg.r, bg.g, bg.b)
    el:drawRectBorder(bx, by, bw, bh, bd.a or 1, bd.r, bd.g, bd.b)
    el:drawText(caption, bx + 5, by + 3, tc.r, tc.g, tc.b, tc.a or 1, UIFont.Small)
end

-- 自己把完整標籤畫出來的控制項不需要說明；什麼都不畫（圖示 chip）或標題被 owner 截短的，全文只能在這裡讀
local function captionOf(c, label)
    local full = c.fullTitle
    local title = c.title
    if type(full) == "string" and full ~= "" and title ~= full then return full end
    if type(title) == "string" and title ~= "" then return nil end
    if type(c.tooltip) == "string" and c.tooltip ~= "" then return c.tooltip end
    return label
end

-- rev 16：控制項（有外框時先問外框）每幀回答的焦點說明，例如一個元件內多個停點、游標換格就換說明；
-- 回 nil／空字串＝照原本的說明。pcall 傳參，不建 closure
local function liveLabel(c, f)
    local src = (f ~= c and type(f.focusLabel) == "function") and f or c
    if type(src.focusLabel) ~= "function" then return nil end
    local ok, label = pcall(src.focusLabel, src)
    if ok and type(label) == "string" and label ~= "" then return label end
    return nil
end

-- rev 16：手把右搖桿捲動焦點所在的捲動容器（或 scroll 目標本身）；門檻與速度同原版
-- ISPanelJoypad:doRightJoystickScrolling（ISPanelJoypad.lua:705-729）
local STICK_DEAD = 0.75
local STICK_SPEED = 20 -- 每 33.3ms 的像素
local function stick(root, target)
    if target == nil or getJoypadAimingAxisY == nil or not Focus.holdsJoypad(root) then return end
    local data = getJoypadData(root._focusJoyPlayer)
    if data == nil or UIManager == nil or UIManager.getMillisSinceLastRender == nil then return end
    local axis = getJoypadAimingAxisY(data.id)
    if axis > STICK_DEAD or axis < -STICK_DEAD then
        local step = STICK_SPEED * UIManager.getMillisSinceLastRender() / 33.3
        scrollBy(target, axis > 0 and step or -step)
    end
end

-- 由 owner 的 render 呼叫：子元件已畫完（UIElement.java:1626-1630），框畫在它標示的控制項上面。
-- 也是不論有沒有焦點框都會跑的那一個呼叫，所以畫面上可編輯目標的掛勾在這裡做（見 observe）：
-- 滑鼠在任何一幀都可能聚焦輸入框，之後引擎只跟那個框說話。
function Focus.render(el, theme)
    if el._focusCloseKey ~= nil and not GameKeyboard.isKeyDownRaw(el._focusCloseKey) then
        el._focusCloseKey = nil
        el:setVisible(false)
        return
    end
    local list = ready(el) and targets(el) or nil
    local ours = observe(list)
    if ours then
        nativeRoot = el
        if not wasOurs then beginHandoff() end
        if not drainHandoff() then
            if st.native == ours then unfocusNative() else ours:unfocus() end
            ours = nil
            nativeRoot = nil
        end
        wasOurs = ours ~= nil
    elseif nativeRoot == el or not ready(nativeRoot) then
        -- 持有鍵盤的輸入框屬於這個 root（或它的視窗已不在）：沒有人在打字
        nativeRoot = nil
        handoff, firstQueue = false, nil
        wasOurs = false
    end
    if st.triggerHold and not rawDown(st.triggerHold) then st.triggerHold = nil end
    if Focus.root ~= el then return end
    local c = st.control
    if c == nil or not st.ring then return end
    if not usable(c) or (list ~= nil and not listed(list, c)) then
        Focus.invalidate(el)
        c = st.control
        if c == nil or not st.ring then return end
    end
    local f = st.frame
    if not usable(f) then f = c end
    local panel = scrollParent(f)
    if st.revealed ~= f then
        -- rev 16：焦點換到捲動容器裡的控制項（或焦點框剛亮起）：捲進可視區，外層容器也一樣；滑鼠滾輪之後不搶回
        st.revealed = f
        local p = panel
        while p ~= nil do
            p:scrollTo(f)
            p = scrollParent(p)
        end
    end
    stick(el, st.kind == "scroll" and c or panel)
    if panel ~= nil then
        local py, fy = panel:getAbsoluteY(), f:getAbsoluteY()
        if fy + (f.height or 0) <= py or fy >= py + panel.height then return end -- 整個捲出可視區：框與說明都不畫
    end
    local x = f:getAbsoluteX() - el:getAbsoluteX()
    local y = f:getAbsoluteY() - el:getAbsoluteY()
    local w = f.width or 0
    local h = f.height or 0
    if f == c and c.focusRect then
        -- rev 12：控制項只標一部分（表頭的目前欄）：矩形是控制項的元素座標
        local rx, ry, rw, rh = c:focusRect()
        if rx ~= nil then x, y, w, h = x + rx, y + ry, rw, rh end
    end
    Focus.drawRing(el, x, y, w, h, theme)
    Focus.drawCaption(el, x, y, w, h, liveLabel(c, f) or captionOf(c, st.label), theme, st.captionSide)
end

-- ---------- 自動目標（框架 Window 預設的 keyboardTargets） ----------
-- 框架控制項自帶 `_focusKind`（button／entry／list）；consumer 自繪元件也可以自己標並提供 forceClick、
-- 選用 `_focusLabel`（說明文字）。同一個 `_focusGroup` 值、閱讀順序上連續的控制項併成一個 group
-- （方向鍵在組內走）。閱讀順序＝由上而下、同一列由左而右（上緣差距不超過較矮者一半視為同列）。
-- rev 16：捲動容器（`_scrollPanel`）裡的目標在閱讀順序上排成一塊、整塊以容器的位置排（捲動不改 Tab 順序）；
-- 容器裡沒有任何目標時，容器本身是一個 kind="scroll" 目標（方向鍵捲一行、PgUp／PgDn 一頁）。
-- Focus.render 每幀都要走一次（原生文字焦點接線），所以每個 root 重用同一組陣列與描述 table，
-- 不配置新 table（框架熱路徑鐵則）；描述的內容在引擎讀進 st 之後才會被下一次呼叫覆寫。
local ROW_SLOP = 6

-- owner＝最外層的捲動容器（nil＝不在容器裡）
local function collect(el, raw, owners, n, owner)
    local kids = el.childrenInOrder
    if type(kids) ~= "table" then return n end
    for i = 1, #kids do
        local c = kids[i]
        if type(c) == "table" and c.javaObject ~= nil and c:getIsVisible() then
            if c._focusKind ~= nil then
                n = n + 1
                raw[n], owners[n] = c, owner
            elseif c._scrollPanel then
                local start = n
                n = collect(c, raw, owners, n, owner or c)
                if n == start then
                    n = n + 1
                    raw[n], owners[n] = c, owner
                end
            else
                n = collect(c, raw, owners, n, owner)
            end
        end
    end
    return n
end

local function after(ay, ax, ah, by, bx, bh)
    local slop = math.max(ROW_SLOP, math.floor(math.min(ah, bh) / 2))
    if ay - by > slop then return true end
    if by - ay > slop then return false end
    return ax > bx
end

-- 穩定插入排序 [lo, hi]（家族禁用 table.sort；一個視窗的控制項只有數十個）
local function sortRange(buf, lo, hi)
    local raw, owners, ys, xs, hs = buf.raw, buf.owners, buf.ys, buf.xs, buf.hs
    for i = lo + 1, hi do
        local c, o, y, x, h = raw[i], owners[i], ys[i], xs[i], hs[i]
        local j = i - 1
        while j >= lo and after(ys[j], xs[j], hs[j], y, x, h) do
            raw[j + 1], owners[j + 1], ys[j + 1], xs[j + 1], hs[j + 1] = raw[j], owners[j], ys[j], xs[j], hs[j]
            j = j - 1
        end
        raw[j + 1], owners[j + 1], ys[j + 1], xs[j + 1], hs[j + 1] = c, o, y, x, h
    end
end

function Focus.collectTargets(root)
    local buf = root._focusBuf
    if buf == nil then
        buf = { raw = {}, owners = {}, ys = {}, xs = {}, hs = {}, list = {}, pool = {} }
        root._focusBuf = buf
    end
    local raw, owners, ys, xs, hs = buf.raw, buf.owners, buf.ys, buf.xs, buf.hs
    local n = collect(root, raw, owners, 0, nil)
    for i = #raw, n + 1, -1 do raw[i], owners[i] = nil, nil end
    for i = 1, n do
        local c = raw[i]
        ys[i], xs[i], hs[i] = c:getAbsoluteY(), c:getAbsoluteX(), c.height or 0
    end
    -- 先在每個容器的連續段內依自己的位置排，再把段內的鍵換成容器的位置整體排：段內鍵相同、排序穩定，段不會被拆開
    local i = 1
    while i <= n do
        local o, j = owners[i], i
        while j < n and o ~= nil and owners[j + 1] == o do j = j + 1 end
        if o ~= nil then
            sortRange(buf, i, j)
            local oy, ox, oh = o:getAbsoluteY(), o:getAbsoluteX(), o.height or 0
            for k = i, j do ys[k], xs[k], hs[k] = oy, ox, oh end
        end
        i = j + 1
    end
    sortRange(buf, 1, n)
    local list, pool = buf.list, buf.pool
    local count
    count, i = 0, 1
    while i <= n do
        local c = raw[i]
        count = count + 1
        local d = pool[count]
        if d == nil then
            d = { controls = {} }
            pool[count] = d
        end
        local group = c._focusGroup
        if group ~= nil then
            local controls, m = d.controls, 0
            while i <= n and raw[i]._focusGroup == group do
                m = m + 1
                controls[m] = raw[i]
                i = i + 1
            end
            for k = #controls, m + 1, -1 do controls[k] = nil end
            d.kind, d.control, d.frame = "group", nil, nil
        else
            if c._focusKind == "entry" and c._entry ~= nil then
                d.kind, d.control, d.frame = "entry", c._entry, c
            else
                d.kind, d.control, d.frame = c._focusKind or "scroll", c, nil -- 沒有 _focusKind 的只有空的捲動容器
            end
            i = i + 1
        end
        d.label = c._focusLabel
        d.captionSide = c._focusCaptionSide
        list[count] = d
    end
    for k = #list, count + 1, -1 do list[k] = nil end
    return list
end

UI.Focus = Focus
UI.CAPABILITIES.focus = true
UI.CAPABILITIES.focusCaption = true
UI.CAPABILITIES.focusLabel = true

return Focus
