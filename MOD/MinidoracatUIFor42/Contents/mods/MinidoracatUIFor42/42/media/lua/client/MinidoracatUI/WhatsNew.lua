-- MinidoracatUI/WhatsNew — MOD 更新概要通知（API rev 24，CAPABILITIES.whatsNew）。
--
-- 玩家更新 MOD 後第一次進遊戲，右上角用 Toast 跳一則該 MOD 的更新重點；同一段概要在這台電腦只跳一次。
-- 設計稿 ui-whatsnew-1024（2026-10-24 使用者核准：同時只放一則；框架自己從 rev 24 的下一版起也登記）。
--
-- UI.WhatsNew.register(spec) → true｜false（spec 不對時回 false，不拋錯）
--   spec.modId  mod.info 的 id
--   spec.since  這段概要屬於哪一版（要含數字，例 "0.50.0"）；發版時寫了新概要才改它
--   spec.text   概要內文的翻譯鍵（Toast 最多畫 MAX_LINES 行；完整內文照樣記在通知紀錄）
--   spec.name   選用：標題用的 MOD 名稱翻譯鍵；沒有或查不到時用 mod.info 的 name
--   在 consumer 的檔案載入時呼叫；同一個 modId 再登記是覆寫。OnGameStart 之後才登記的，下一場才算。
--
-- 紀錄：Zomboid/Lua/MinidoracatUI/WhatsNew.ini，一行一個 MOD「modId=版本」，值是這台電腦最後看過的概要版本
--   （空值＝見過這個 MOD、它還沒有概要）。框架是唯一寫入者，每次整檔重寫（getFileWriter 一開就截斷）。
-- 判斷（每次 OnGameStart，每個 MOD 一次）：
--   沒有這一行 → 只記不跳（新安裝；剛升到 rev 24 時大家也都沒有紀錄）。所以本框架自己與 require= 有本框架的
--     MOD 就算沒登記也先記一行空值，它之後的第一段概要才跳得出來；
--   登記的 since 比紀錄新（逐段比數字）→ 跳；其餘（看過了、沒有概要、降版）不跳；
--   玩家在「選項 → MODS」關掉「顯示 MOD 更新概要」時，要跳的改成只記，之後再打開也不補跳。
-- 放出：OnGameStart 在載入畫面按下「點擊開始」之後才觸發（IngameState.java:766；多人進服後伺服器的 MOD 才載入）。
--   START_DELAY_MS 後開始，每 POLL_MS 看一次：上一則概要還在畫面上、Toast 有排隊的、或畫面已滿 MAX_VISIBLE 則
--   就等，所以概要不進 Toast 佇列、不會擠掉別的 MOD 的通知。每則停 HOLD_MS；真的放出去才寫紀錄。
-- 零 log；讀寫失敗一律當沒有紀錄（最壞是少跳一次，不會一直跳）。
-- 本檔只能寫 ASCII 字面值（Kahlua 把字串字面值逐字截成一個位元組）。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.CAPABILITIES) then
    return -- 核心缺席：不掛能力
end
-- 檔名排序在 Widgets/ 之前或之後都不一定：自己 require，不靠載入順序
if not UI.Toast then pcall(require, "MinidoracatUI/Widgets/Toast") end
if not (UI.Toast and UI.Toast.show and UI.Toast.active and UI.Toast.pending) then
    return -- 沒有 Toast 就放不出來：不掛能力，consumer 探旗標後不登記
end

local Toast = UI.Toast

local FRAMEWORK_ID = "MinidoracatUIFor42"
local FILE = "MinidoracatUI/WhatsNew.ini"
local HEADER = "# MinidoracatUI: the last update note each mod showed on this computer (modId=version)"
local OPTIONS_ID = "MinidoracatUIFor42" -- 框架的「選項 → MODS」頁（與 Dock.lua、ToastHistory.lua 共用）
local OPTION_SHOW = "WhatsNewShow"
local START_DELAY_MS = 5000
local POLL_MS = 500
local HOLD_MS = 10000 -- 預設 5 秒讀不完 3 行；游標停在上面時照 rev 21 暫停
local MAX_LINES = 3

local WhatsNew = {}

local notes, noteOrder = {}, {} -- modId -> { modId, since, text, name }；登記順序
local seen, seenOrder = {}, {}  -- modId -> 最後看過的概要版本（"" 沒有概要）；寫檔順序（不用 table.sort）
local queue = {}                -- 這一場要放的概要：{ modId, since, title, message }
local current = nil             -- 畫面上那一則概要的 Toast 實例
local startAt, lastPoll = 0, 0
local ticking = false
local modOptions, optionsLoaded = nil, false
local tick -- 下面定義；stop() 要用同一個函式參照 Remove

-- ---------- 玩家選項：顯示 MOD 更新概要（選項 → MODS，預設勾選；寫法同 ToastHistory.lua） ----------

local function createOptions()
    local M = PZAPI.ModOptions
    local o = M:getOptions(OPTIONS_ID)
    if o == nil then o = M:create(OPTIONS_ID, "UI_optionscreen_binding_MinidoracatUI") end
    o:addTickBox(OPTION_SHOW, "IGUI_MinidoracatUI_WhatsNew_Option", true,
        "IGUI_MinidoracatUI_WhatsNew_Option_tooltip")
    return o
end

if type(PZAPI) == "table" and type(PZAPI.ModOptions) == "table" and type(PZAPI.ModOptions.create) == "function" then
    local ok, created = pcall(createOptions)
    if ok then modOptions = created end
end

-- 沒有值或讀不到一律當打開。ini 原版只在選項畫面建立時讀回，第一次用到時自己補讀一次；之後只看記憶體裡的值
-- （遊戲中改選項時 MainOptions 先把畫面值寫回 option.value，MainOptions.lua:3760-3762）
local function optionOn()
    if not modOptions then return true end
    if not optionsLoaded then
        optionsLoaded = true
        pcall(PZAPI.ModOptions.load, PZAPI.ModOptions)
    end
    local opt = modOptions:getOption(OPTION_SHOW)
    return not (opt and opt:getValue() == false)
end

-- ---------- 紀錄檔 ----------

local function readSeen()
    local map, order = {}, {}
    local reader = nil
    local ok = pcall(function()
        reader = getFileReader(FILE, false)
        if not reader then return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local id, version = string.match(line, "^([^#=][^=]*)=(.*)$")
            if id and map[id] == nil then
                map[id] = version
                order[#order + 1] = id
            end
        end
    end)
    if reader then pcall(reader.close, reader) end
    if not ok then return {}, {} end
    return map, order
end

local function writeSeen()
    local writer = nil
    pcall(function()
        writer = getFileWriter(FILE, true, false)
        if not writer then return end
        writer:write(HEADER .. "\r\n")
        for i = 1, #seenOrder do
            local id = seenOrder[i]
            writer:write(id .. "=" .. seen[id] .. "\r\n")
        end
    end)
    if writer then pcall(writer.close, writer) end
end

local function markSeen(id, version)
    if seen[id] == nil then seenOrder[#seenOrder + 1] = id end
    seen[id] = version
end

-- ---------- 判斷 ----------

-- 逐段比數字："0.50.0" 比 "0.49.1" 新；少的段當 0；空字串最舊
local function newer(a, b)
    local x, y = {}, {}
    for n in string.gmatch(a, "%d+") do x[#x + 1] = tonumber(n) end
    for n in string.gmatch(b, "%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

local function trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- 這一場載入的 MOD 裡 require= 有本框架的（引擎已去掉反斜線、以逗號切開但不去空白，ChooseGameInfo.java:224）
local function addConsumers(ids, has)
    if not (getActivatedMods and getModInfoByID) then return end
    local mods = getActivatedMods()
    if not mods then return end
    for i = 0, mods:size() - 1 do
        local id = (string.gsub(tostring(mods:get(i)), "^\\", ""))
        local info = getModInfoByID(id)
        local req = info and info:getRequire()
        if req and not has[id] then
            for j = 0, req:size() - 1 do
                if trim(tostring(req:get(j))) == FRAMEWORK_ID then
                    has[id] = true
                    ids[#ids + 1] = id
                    break
                end
            end
        end
    end
end

-- 概要內文；翻譯鍵查不到（連英文都沒有，Translator 先載英文再蓋上玩家語言）就當沒有概要
local function noteText(note)
    if not (note and getTextOrNull) then return nil end
    local text = getTextOrNull(note.text)
    if type(text) ~= "string" or text == "" then return nil end
    return text
end

local function noteTitle(note)
    local name = note.name and getTextOrNull and getTextOrNull(note.name) or nil
    if type(name) ~= "string" or name == "" then
        local info = getModInfoByID and getModInfoByID(note.modId)
        name = info and info:getName() or note.modId
    end
    return getText("IGUI_MinidoracatUI_WhatsNew_Title", name, note.since)
end

local function start()
    queue, current = {}, nil
    seen, seenOrder = readSeen()
    local ids, has = { FRAMEWORK_ID }, { [FRAMEWORK_ID] = true }
    for i = 1, #noteOrder do
        local id = noteOrder[i]
        if not has[id] then
            has[id] = true
            ids[#ids + 1] = id
        end
    end
    addConsumers(ids, has)
    local dirty = false
    for i = 1, #ids do
        local id = ids[i]
        local note = notes[id]
        local text = noteText(note)
        if text == nil then note = nil end
        local last = seen[id]
        if last == nil then
            markSeen(id, note and note.since or "")
            dirty = true
        elseif note and newer(note.since, last) then -- 選項關掉的話，tick 第一次查看時改成只記
            queue[#queue + 1] = { modId = id, since = note.since, title = noteTitle(note), message = text }
        end
    end
    if dirty then writeSeen() end
end

-- ---------- 放出 ----------

local function stop()
    if ticking then
        ticking = false
        Events.OnTick.Remove(tick)
    end
end

local function onScreen(toast)
    if toast == nil then return false end
    local active = Toast.active
    for i = 1, #active do
        if active[i] == toast then return true end
    end
    return false
end

-- 每幀：到點前與兩次查看之間只比時間，不配置
tick = function()
    local now = getTimestampMs()
    if now < startAt or now - lastPoll < POLL_MS then return end
    lastPoll = now
    if #queue == 0 then
        stop()
        return
    end
    if not optionOn() then -- 遊戲中關掉：剩下的只記不跳
        for i = 1, #queue do markSeen(queue[i].modId, queue[i].since) end
        queue = {}
        writeSeen()
        stop()
        return
    end
    if onScreen(current) then return end
    if #Toast.pending > 0 or #Toast.active >= (Toast.MAX_VISIBLE or 3) then return end
    local item = table.remove(queue, 1)
    current = Toast.show({ title = item.title, message = item.message, maxLines = MAX_LINES, holdMs = HOLD_MS })
    markSeen(item.modId, item.since)
    writeSeen()
    if #queue == 0 then stop() end
end

local function onGameStart()
    start()
    startAt = getTimestampMs() + START_DELAY_MS
    lastPoll = 0
    if #queue == 0 then
        stop()
    elseif not ticking then
        ticking = true
        Events.OnTick.Add(tick)
    end
end

-- ---------- 公開面 ----------

function WhatsNew.register(spec)
    if type(spec) ~= "table" then return false end
    local id, since, text, name = spec.modId, spec.since, spec.text, spec.name
    if type(id) ~= "string" or id == "" or string.find(id, "[=\r\n]") then return false end
    if type(since) ~= "string" or not string.find(since, "%d") or string.find(since, "[\r\n]") then return false end
    if type(text) ~= "string" or text == "" then return false end
    if name ~= nil and type(name) ~= "string" then return false end
    if notes[id] == nil then noteOrder[#noteOrder + 1] = id end
    notes[id] = { modId = id, since = since, text = text, name = name }
    return true
end

if Events and Events.OnGameStart and Events.OnGameStart.Add and Events.OnTick then
    Events.OnGameStart.Add(onGameStart)
end

UI.WhatsNew = WhatsNew
UI.CAPABILITIES.whatsNew = true

return WhatsNew
