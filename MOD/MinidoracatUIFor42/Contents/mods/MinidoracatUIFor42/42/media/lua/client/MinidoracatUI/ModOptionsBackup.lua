-- MinidoracatUI/ModOptionsBackup — consumer 自己的 PZAPI.ModOptions 設定的備份與逐筆補回（rev 23，modOptionsBackup）。
--
-- 為什麼：所有 MOD 的設定都在同一個 Zomboid/Lua/ModOptions.ini。主選單沒有任何 MOD 建選項時，原版
-- MainOptions:create 不 load（MainOptions.lua:409-411），按套用卻照樣 save（:3766），getFileWriter 一開就截斷
-- （LuaManager getFileWriter 的 FileOutputStream append=false），整個檔案變成 0 byte：多人玩家主選單常常沒啟用
-- MOD，進服後所有設定回到預設。save 寫回未載入 MOD 的行時不補換行（ModOptions.lua:286-288），那些行黏成一行，
-- 下次只有第一筆被認得、值也讀不對。框架不改原版函式（鐵則），改由 consumer 建好選項後呼叫 protect，各自補回自己的設定。
--
-- UI.ModOptionsBackup.protect(options) → 這次補回的選項數；options 不對或讀寫出錯時回 nil（不拋錯）
--   options＝PZAPI.ModOptions:create(modID, name) 的回傳值。建完選項就呼叫；之後又加選項（例如 OnGameBoot 才加的）
--   再呼叫一次，重複呼叫無害。要在原版 load 之前呼叫，補回的值才會被那次 load 套上：檔案載入時就自己 load 的
--   consumer 寫在自己的 load 前面，其餘在 OnGameBoot（早於 OnMainMenuEnter 裡 MainOptions:create 的 load）。
--   1. 讀 ModOptions.ini。某個選項（原版 save 會寫的：有 getValue）在檔案裡沒有自己的一行，而備份裡有同型別的一行，
--      就把備份那行接到檔尾。「自己的一行」＝以 | 切開（同 luautils.split，空欄不算）第 2、3 欄是本 MOD 與這個
--      選項、而且不超過 4 欄：黏行的第一筆超過 4 欄，原版讀不到正確的值。型別不看（舊 combobox 行留給 consumer
--      自己的遷移），檔案裡有的一律以檔案為準。寫完讀回比對，不符就寫回原內容、不算補回。
--   2. 備份 Zomboid/Lua/MinidoracatUI/ModOptions_<modID>.ini＝依 options.data 順序，檔案裡本 MOD 的行（同一選項以
--      最後一行為準，同原版 load），檔案裡沒有的選項留上一份備份的行；改了型別的舊行丟掉（不會補回），還沒註冊的
--      選項（之後才加，或已刪除）的行留在檔尾，等它註冊再補。內容沒變不寫，沒有任何一行時不建檔。
--   3. 遊戲中 EveryOneMinute（間隔至少 MIN_INTERVAL_MS 真實時間）讀一次 ModOptions.ini，照第 2 步更新每個 protect
--      過的備份：這一場改的設定，之後被清空時補回的也是新值。檔案讀不到時不動備份；內容和上次每個備份都跟上時一樣
--      就到此為止。有變時整份只切一次行，再把各 MOD 自己的行分給它。
--   零 log：回傳值給 consumer 自己決定記不記。
-- 本檔只能寫 ASCII 字面值（Kahlua 把字串字面值逐字截成一個位元組）。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local Backup = {}

local MAIN = "ModOptions.ini"
local BACKUP_PREFIX = "MinidoracatUI/ModOptions_"
-- 遊戲 1 分鐘只有真實幾秒（原版預設一天 1.5 小時＝3.75 秒，一天 1 小時＝2.5 秒）；間隔只決定備份多久跟上這一場的改動
local MIN_INTERVAL_MS = 60000

local entries = {} -- modID -> { options = ..., name = 備份檔名, lines = 備份內容（nil＝沒有備份檔） }
local order = {}   -- modID，依第一次 protect 的順序
local lastTick = nil
local seen = nil  -- 每個備份都已跟上的 ModOptions.ini 內容；nil＝下次每分鐘處理一定重做

local function fields(line)
    local t = {}
    for s in string.gmatch(line, "[^|]+") do
        t[#t + 1] = s
    end
    return t
end

local function readLines(name)
    local r = getFileReader(name, false)
    if not r then return nil end
    local out = {}
    while true do
        local line = r:readLine()
        if line == nil then break end
        out[#out + 1] = line
    end
    r:close()
    return out
end

local function writeLines(name, lines)
    local w = getFileWriter(name, true, false)
    if not w then return false end
    for i = 1, #lines do
        w:write(lines[i] .. "\r\n")
    end
    w:close()
    return true
end

local function same(a, b)
    if a == nil or b == nil or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- 寫完讀回比對；不符就寫回 previous（nil＝原本沒有這個檔，寫回空檔）並回 false
local function writeVerified(name, lines, previous)
    if writeLines(name, lines) and same(readLines(name), lines) then
        return true
    end
    writeLines(name, previous or {})
    return false
end

-- lines 裡本 MOD 還註冊、型別相同的行：id -> line（同一選項以最後一行為準）
local function ownLines(options, lines)
    local own = {}
    if lines == nil then return own end
    local modID = options.modOptionsID
    for i = 1, #lines do
        local t = fields(lines[i])
        if t[2] == modID and #t <= 4 then
            local opt = options.dict[t[3]]
            if opt ~= nil and opt.getValue ~= nil and opt.type == t[1] then
                own[t[3]] = lines[i]
            end
        end
    end
    return own
end

-- fileLines 裡 protect 過的 MOD 自己的行（第 3 欄有值、不超過 4 欄）：modID -> { 行, ... }（照檔案順序）
local function group(fileLines)
    local out = {}
    if fileLines == nil then return out end
    for i = 1, #fileLines do
        local t = fields(fileLines[i])
        if t[3] ~= nil and #t <= 4 and entries[t[2]] ~= nil then
            local own = out[t[2]]
            if own == nil then
                own = {}
                out[t[2]] = own
            end
            own[#own + 1] = fileLines[i]
        end
    end
    return out
end

-- modLines＝ModOptions.ini 裡本 MOD 的行（group 的一項，nil＝沒有）；備份已跟上（沒變或寫入成功）回 true
local function refresh(entry, modLines)
    local options = entry.options
    local fileOwn, oldOwn = ownLines(options, modLines), ownLines(options, entry.lines)
    local nextLines = {}
    local data = options.data
    for i = 1, #data do
        local opt = data[i]
        if opt.getValue ~= nil and opt.id ~= nil then
            local line = fileOwn[opt.id] or oldOwn[opt.id]
            if line then nextLines[#nextLines + 1] = line end
        end
    end
    local old = entry.lines
    if old ~= nil then
        local modID, dict = options.modOptionsID, options.dict
        for i = 1, #old do
            local t = fields(old[i])
            local opt = t[3] ~= nil and dict[t[3]] or nil
            if t[2] == modID and #t <= 4 and (opt == nil or opt.getValue == nil) then
                nextLines[#nextLines + 1] = old[i]
            end
        end
    end
    if #nextLines == 0 or same(old, nextLines) then return true end
    if writeVerified(entry.name, nextLines, old) then
        entry.lines = nextLines
        return true
    end
    return false
end

local function protectInner(options)
    local modID = options.modOptionsID
    local entry = entries[modID]
    if entry == nil then
        entry = { name = BACKUP_PREFIX .. string.gsub(modID, "[^%w_]", "_") .. ".ini" }
        entry.lines = readLines(entry.name)
        entries[modID] = entry
        order[#order + 1] = modID
    end
    entry.options = options
    seen = nil -- 只有這個 MOD 跟上了現在的檔案

    local fileLines = readLines(MAIN)
    local modLines = group(fileLines)[modID] or {}
    local present = {}
    for i = 1, #modLines do
        present[fields(modLines[i])[3]] = true
    end
    local saved = ownLines(options, entry.lines)
    local add = {}
    local data = options.data
    for i = 1, #data do
        local opt = data[i]
        if opt.getValue ~= nil and opt.id ~= nil and not present[opt.id] and saved[opt.id] then
            add[#add + 1] = saved[opt.id]
        end
    end

    local restored = 0
    if #add > 0 then
        local nextLines = {}
        if fileLines ~= nil then
            for i = 1, #fileLines do nextLines[i] = fileLines[i] end
        end
        for i = 1, #add do nextLines[#nextLines + 1] = add[i] end
        if writeVerified(MAIN, nextLines, fileLines) then
            for i = 1, #add do modLines[#modLines + 1] = add[i] end
            restored = #add
        end
    end
    refresh(entry, modLines)
    return restored
end

function Backup.protect(options)
    if type(options) ~= "table" or type(options.modOptionsID) ~= "string" or type(options.data) ~= "table"
        or type(options.dict) ~= "table" then
        return nil
    end
    local ok, restored = pcall(protectInner, options)
    if ok then return restored end
    return nil
end

local function refreshAll()
    local fileLines = readLines(MAIN)
    if fileLines == nil or same(fileLines, seen) then return end
    seen = nil
    local byMod = group(fileLines)
    local ok = true
    for i = 1, #order do
        local modID = order[i]
        if not refresh(entries[modID], byMod[modID]) then ok = false end
    end
    if ok then seen = fileLines end
end

local function tick()
    if #order == 0 then return end
    local now = getTimestampMs and getTimestampMs() or nil
    if now ~= nil and lastTick ~= nil and now - lastTick < MIN_INTERVAL_MS then return end
    lastTick = now
    pcall(refreshAll)
end

-- 只給測試用：清掉 protect 過的清單、節流時間與上次讀到的內容（不作為 production API）
function Backup._resetForTests()
    entries, order, lastTick, seen = {}, {}, nil, nil
end

if Events and Events.EveryOneMinute and Events.EveryOneMinute.Add then
    Events.EveryOneMinute.Add(tick)
end

local UI = MinidoracatUI and MinidoracatUI.v1
if UI and UI.API_MAJOR == 1 and UI.CAPABILITIES then
    UI.ModOptionsBackup = Backup
    UI.CAPABILITIES.modOptionsBackup = true
end

return Backup
