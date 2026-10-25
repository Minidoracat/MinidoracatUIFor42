-- 切片 rev 23：UI.ModOptionsBackup（ModOptionsBackup.lua，modOptionsBackup）
-- 照載本機遊戲的原版 client/PZAPI/ModOptions.lua 與 shared/luautils.lua（PZ_HOME 可改安裝目錄）；檔案系統用記憶體
-- stub：getFileWriter 只收 ini 等副檔名、一開就截斷（FileOutputStream append=false）、close 時落盤；getFileReader 照
-- BufferedReader.readLine（\r\n、\n、\r 都算行尾），createIfNull=false 時檔案不存在回 nil。
local ctx = ...
local check, UI = ctx.check, ctx.UI

local PZ_HOME = os.getenv("PZ_HOME") or "D:/SteamLibrary/steamapps/common/ProjectZomboid"
local MAIN = "ModOptions.ini"
local BK = "MinidoracatUI/ModOptions_MineMod.ini"

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

print("情境 rev23：ModOptionsBackup 設定備份與逐筆補回")
local VANILLA_MODOPTIONS = readFile(PZ_HOME .. "/media/lua/client/PZAPI/ModOptions.lua")
local VANILLA_LUAUTILS = readFile(PZ_HOME .. "/media/lua/shared/luautils.lua")
if not (VANILLA_MODOPTIONS and VANILLA_LUAUTILS) then
    check(false, "找不到原版 ModOptions.lua／luautils.lua（設 PZ_HOME 指到遊戲目錄）")
    return 1
end

-- ── 暫換的全域（檔尾還原） ───────────────────────────────────────────
local saved = { getFileReader = getFileReader, getFileWriter = getFileWriter, PZAPI = PZAPI, luautils = luautils,
    Events = Events, print = print }
local prints = 0

local disk, writes, reads = {}, {}, {} -- reads：檔名 → getFileReader 開了幾次
local dropWrite = {} -- 檔名 → 下一次寫入這個檔時靜默丟掉內容
local ALLOWED = { ini = true, cfg = true, txt = true, log = true, json = true }
getFileWriter = function(name, create, append)
    if not ALLOWED[name:match("%.(%w+)$") or ""] then return nil end
    writes[name] = (writes[name] or 0) + 1
    local drop = dropWrite[name] == true
    dropWrite[name] = nil
    local buf = append and (disk[name] or "") or ""
    disk[name] = buf
    return {
        write = function(_, s) if not drop then buf = buf .. s end end,
        close = function() disk[name] = buf end,
    }
end
local readerThrows = false
getFileReader = function(name, create)
    if readerThrows then error("disk read failed") end
    reads[name] = (reads[name] or 0) + 1
    local data = disk[name]
    if data == nil then
        if not create then return nil end
        data = ""
        disk[name] = data
    end
    local pos = 1
    return {
        readLine = function()
            if pos > #data then return nil end
            local s = data:find("[\r\n]", pos)
            local line
            if not s then
                line = data:sub(pos); pos = #data + 1
            else
                line = data:sub(pos, s - 1)
                pos = (data:sub(s, s + 1) == "\r\n") and s + 2 or s + 1
            end
            return line
        end,
        close = function() end,
    }
end
luautils = {}
assert(load(VANILLA_LUAUTILS, "=luautils.lua"))()

local minuteHandlers = {}
Events = { EveryOneMinute = { Add = function(fn) minuteHandlers[#minuteHandlers + 1] = fn end } }

local function freshVanilla()
    PZAPI = nil
    assert(load(VANILLA_MODOPTIONS, "=ModOptions.lua"))()
end

local function lines(s)
    local out = {}
    for l in (s or ""):gmatch("([^\r\n]*)\r\n") do out[#out + 1] = l end
    return out
end

local function has(s, line)
    for _, l in ipairs(lines(s)) do
        if l == line then return true end
    end
    return false
end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function regMine(skipLate)
    local o = PZAPI.ModOptions:create("MineMod", "Mine")
    o:addTitle("t")
    o:addTickBox("a", "x", false)
    o:addSlider("s", "x", 0, 100, 1, 50)
    local c = o:addComboBox("c", "x")
    c:addItem("1", true); c:addItem("2"); c:addItem("3")
    o:addTextEntry("txt", "x", "def")
    local m = o:addMultipleTickBox("m", "x")
    m:addTickBox("p", false); m:addTickBox("q", false)
    o:addColorPicker("col", "x", 1, 1, 1, 1)
    o:addKeyBind("k", "x", 10)
    o:addButton("btn", "x", nil, function() end)
    return o
end

local function regOther()
    local o = PZAPI.ModOptions:create("OtherMod", "Other")
    o:addTickBox("o1", "x", false)
    return o
end

local function setMine(o)
    o.dict.a.value = true
    o.dict.s.value = 80
    o.dict.c.selected = 3
    o.dict.txt.value = "hello"
    o.dict.m.values[2].value = true
    o.dict.col.color = { r = 0.5, g = 0.25, b = 1, a = 1 }
    o.dict.k.key = 42
end

local function isSet(o)
    return o.dict.a.value == true and o.dict.s.value == 80 and o.dict.c.selected == 3 and o.dict.txt.value == "hello"
        and o.dict.m.values[2].value == true and o.dict.col.color.r == 0.5 and o.dict.k.key == 42
end

local EXPECTED_BACKUP = {
    "tickbox|MineMod|a|true", "slider|MineMod|s|80", "combobox|MineMod|c|3", "textentry|MineMod|txt|hello",
    "multipletickbox|MineMod|m|false true ", "colorpicker|MineMod|col|0.5 0.25 1 1", "keybind|MineMod|k|42",
}

assert(minuteHandlers ~= nil)
dofile(ctx.MOD_LUA .. "ModOptionsBackup.lua")
local B = UI.ModOptionsBackup
check(UI.API_REVISION >= 23 and UI.CAPABILITIES.modOptionsBackup == true and B ~= nil
    and type(B.protect) == "function", "rev 23：modOptionsBackup 翻 true、UI.ModOptionsBackup 掛上 facade")
check(#minuteHandlers == 1, "載入時掛一個 EveryOneMinute 處理器")
local tick = minuteHandlers[1] or function() end

-- 呼叫模組時暫換 print 計數（框架預設零 log）；harness 自己的 PASS／FAIL 照常印
local realPrint = print
local function quiet(fn, ...)
    print = function() prints = prints + 1 end
    local ok, a = pcall(fn, ...)
    print = realPrint
    if not ok then error(a, 0) end
    return a
end
local function protect(o) return quiet(B.protect, o) end
local function runTick() return quiet(tick) end

-- 新的 Lua 環境：原版表重建、模組狀態清空（同 ResetLua 後重新載入）
local function session()
    freshVanilla()
    B._resetForTests()
end

-- 1. 第一次用：沒有設定檔也沒有備份 → 不建任何檔
do
    disk, writes = {}, {}
    session()
    local o = regMine()
    check(protect(o) == 0 and disk[MAIN] == nil and disk[BK] == nil,
        "沒有設定檔與備份：回 0，不建 ModOptions.ini 也不建備份")
end

-- 2. 平常：檔案裡有本 MOD 的設定 → 不改檔案，備份照 options.data 順序只收本 MOD 會存的選項
local goodFile
do
    disk, writes = {}, {}
    session()
    local o = regMine()
    regOther().dict.o1.value = true
    setMine(o)
    PZAPI.ModOptions:save()
    goodFile = disk[MAIN]
    session()
    o = regMine()
    regOther()
    local before = writes[MAIN] or 0
    check(protect(o) == 0 and disk[MAIN] == goodFile and (writes[MAIN] or 0) == before,
        "檔案裡都有：回 0，ModOptions.ini 一個位元組都沒動")
    check(sameList(lines(disk[BK]), EXPECTED_BACKUP),
        "備份＝本 MOD 七個會存的選項、照註冊順序（不含標題、按鈕與其他 MOD）")
    local bkWrites = writes[BK]
    check(protect(o) == 0 and writes[BK] == bkWrites, "再呼叫一次：內容沒變就不寫備份")
end

-- 3. 主選單沒有 MOD 選項時按套用（原版清空）→ 下一場 protect 全部補回
do
    session()
    PZAPI.ModOptions:save() -- 主選單：沒有任何 MOD 建選項
    check(disk[MAIN] == "", "對照：原版在沒有選項時 save 把 ModOptions.ini 清成 0 byte")
    local bkBefore = disk[BK]
    session()
    local o = regMine()
    regOther()
    check(protect(o) == 7, "清空後 protect 補回 7 個選項")
    PZAPI.ModOptions:load()
    check(isSet(o), "補回後原版 load 套上原本的值（tickbox／slider／combobox／textentry／multipletickbox／colorpicker／keybind）")
    check(disk[BK] == bkBefore, "補回後備份不變")
    check(PZAPI.ModOptions.Dict.OtherMod.dict.o1.value == false, "別的 MOD 不在範圍：OtherMod 照原版回預設")
end

-- 4. 部分遺失：檔案裡還有的以檔案為準，只補缺的；別的 MOD 的行原樣在前
do
    disk[MAIN] = "tickbox|MineMod|a|false\r\ntickbox|OtherMod|o1|true\r\nslider|MineMod|s|10\r\n"
    session()
    local o = regMine()
    regOther()
    check(protect(o) == 5, "缺 5 個：只補缺的")
    local got = lines(disk[MAIN])
    check(got[1] == "tickbox|MineMod|a|false" and got[2] == "tickbox|OtherMod|o1|true" and got[3] == "slider|MineMod|s|10"
        and #got == 8, "原本的三行原樣在前，補回的接在後面")
    PZAPI.ModOptions:load()
    check(o.dict.a.value == false and o.dict.s.value == 10 and o.dict.c.selected == 3 and o.dict.k.key == 42,
        "檔案裡有的（a、s）照檔案，缺的照備份")
    check(has(disk[BK], "tickbox|MineMod|a|false") and has(disk[BK], "slider|MineMod|s|10"),
        "備份跟上檔案裡的值")
end

-- 5. 黏行：本 MOD 的設定被黏在別的行裡 → 原版讀不到正確的值，protect 補回單獨一行
do
    local glued = "tickbox|MineMod|a|trueslider|MineMod|s|80\r\n"
    disk[MAIN] = glued
    session()
    local ctl = regMine()
    PZAPI.ModOptions:load()
    check(ctl.dict.a.value == false and ctl.dict.s.value == 50, "對照：原版讀黏行，a、s 都停在預設")
    disk[MAIN] = glued
    disk[BK] = table.concat(EXPECTED_BACKUP, "\r\n") .. "\r\n"
    session()
    local o = regMine()
    check(protect(o) == 7, "黏行的第一筆不算有：7 個都補")
    PZAPI.ModOptions:load()
    check(isSet(o), "補回的單獨行在後面，原版 load 以它為準")
end

-- 6. 備份裡改了型別的選項不補、備份丟掉；已刪除（沒註冊）的不補、備份留著（之後才加的選項靠它補回）
do
    disk[MAIN] = ""
    disk[BK] = "combobox|MineMod|s|2\r\ntickbox|MineMod|gone|true\r\ntickbox|MineMod|a|true\r\n"
    session()
    local o = regMine()
    check(protect(o) == 1 and disk[MAIN] == "tickbox|MineMod|a|true\r\n", "只補型別相同、還註冊的 a")
    check(not has(disk[BK], "combobox|MineMod|s|2") and has(disk[BK], "tickbox|MineMod|gone|true")
        and has(disk[BK], "tickbox|MineMod|a|true"), "備份丟掉改了型別的舊行，沒註冊的 gone 留著")
end

-- 7. 檔案裡同 id 的舊型別行算「有」：不補，原版的 .selected 遷移訊號照舊
do
    disk[MAIN] = "combobox|MineMod|s|2\r\n"
    disk[BK] = "slider|MineMod|s|80\r\n"
    session()
    local o = regMine()
    check(protect(o) == 0 and disk[MAIN] == "combobox|MineMod|s|2\r\n", "舊 combobox 行在：s 不補、檔案不動")
    PZAPI.ModOptions:load()
    check(o.dict.s.selected == 2 and o.dict.s.value == 50, "原版 load 照舊把舊值寫進 .selected（consumer 自己遷移）")
    check(disk[BK] == "slider|MineMod|s|80\r\n", "備份不收舊型別行、保留原本的 slider 行")
end

-- 8. 寫入被靜默丟掉 → 讀回不符，寫回原內容、不算補回
do
    disk[MAIN] = ""
    local bk = table.concat(EXPECTED_BACKUP, "\r\n") .. "\r\n"
    disk[BK] = bk
    session()
    local o = regMine()
    dropWrite[MAIN] = true
    check(protect(o) == 0 and disk[MAIN] == "", "寫入被丟：回 0、ModOptions.ini 寫回原本的空檔")
    check(disk[BK] == bk, "寫入被丟：備份不動")
end

-- 9. 遊戲中每分鐘跟上這一場改的值：兩次讀檔至少隔 60 秒真實時間（一天 1 小時的伺服器，遊戲 1 分鐘是真實 2.5 秒）；
--    備份寫入失敗時，設定檔沒再變也照樣重試
do
    disk[MAIN] = goodFile
    disk[BK] = nil
    session()
    local o = regMine()
    regOther()
    protect(o)
    PZAPI.ModOptions:load()
    o.dict.s.value = 33
    PZAPI.ModOptions:save()
    ctx.advance(5000)
    runTick()
    check(has(disk[BK], "slider|MineMod|s|33"), "改了值並存檔後，下一次每分鐘處理把備份跟上")
    o.dict.s.value = 44
    PZAPI.ModOptions:save()
    local mainReads = reads[MAIN]
    for _ = 1, 23 do
        ctx.advance(2500)
        runTick()
    end
    check(reads[MAIN] == mainReads and not has(disk[BK], "slider|MineMod|s|44"),
        "之後 57.5 秒（遊戲 23 分鐘）都不讀檔")
    ctx.advance(2500)
    runTick()
    check(has(disk[BK], "slider|MineMod|s|44"), "滿 60 秒：跟上新值")
    o.dict.s.value = 55
    PZAPI.ModOptions:save()
    dropWrite[BK] = true
    ctx.advance(60000)
    runTick()
    check(has(disk[BK], "slider|MineMod|s|44"), "備份寫入被丟：備份留著 44")
    ctx.advance(60000)
    runTick()
    check(has(disk[BK], "slider|MineMod|s|55"), "設定檔沒再變，下一次照樣重試：跟上 55")
    local bk = disk[BK]
    local bkWrites = writes[BK]
    disk[MAIN] = ""
    ctx.advance(60000)
    runTick()
    disk[MAIN] = nil
    ctx.advance(60000)
    runTick()
    check(disk[BK] == bk and writes[BK] == bkWrites, "設定檔變空或不見：備份不動")
end

-- 10. 之後才加的選項：再呼叫一次就補它
do
    disk[MAIN] = "tickbox|MineMod|a|true\r\n"
    disk[BK] = "tickbox|MineMod|a|true\r\ntickbox|MineMod|late|true\r\n"
    session()
    local o = PZAPI.ModOptions:create("MineMod", "Mine")
    o:addTickBox("a", "x", false)
    check(protect(o) == 0 and has(disk[BK], "tickbox|MineMod|late|true"), "late 還沒註冊：不補，備份裡的 late 留著")
    o:addTickBox("late", "x", false)
    check(protect(o) == 1 and has(disk[MAIN], "tickbox|MineMod|late|true"), "加了 late 再呼叫：補回 late")
end

-- 11. 參數不對、讀檔出錯：回 nil、不拋錯
do
    check(protect(nil) == nil and protect({}) == nil and protect({ modOptionsID = "x" }) == nil,
        "options 不是 create 的回傳值：回 nil")
    session()
    local o = regMine()
    protect(o)
    readerThrows = true
    local ok, r = pcall(B.protect, o)
    local okTick = pcall(function() ctx.advance(5000); runTick() end)
    readerThrows = false
    check(ok and r == nil, "讀檔拋錯：protect 自己接住、回 nil")
    check(okTick, "讀檔拋錯：每分鐘處理也不拋錯")
end

-- 12. 備份檔名只留英數與底線
do
    disk = {}
    session()
    local o = PZAPI.ModOptions:create("Weird Mod/../x", "W")
    o:addTickBox("a", "x", true)
    PZAPI.ModOptions:save()
    protect(o)
    check(disk["MinidoracatUI/ModOptions_Weird_Mod____x.ini"] ~= nil, "MOD ID 的非英數字元換成底線")
end

-- 13. 每分鐘處理的工作量（2026-10-25 實測 138 個 MOD 的組合每 2.5 秒卡 22-29 ms：每個 protect 過的 MOD 各切一次整份
--     檔案）：檔案沒變只讀檔比對；有變整份只切一次，protect 的 MOD 多幾個也不多切。量本模組執行的行數（line hook），
--     不量時間：harness 跑在標準 Lua，速度和 Kahlua 不同
do
    local SRC = "@" .. ctx.MOD_LUA .. "ModOptionsBackup.lua"
    local function moduleLines(fn)
        local n = 0
        debug.sethook(function()
            if debug.getinfo(2, "S").source == SRC then n = n + 1 end
        end, "l")
        fn()
        debug.sethook()
        return n
    end
    local buf = {}
    for i = 1, 480 do buf[#buf + 1] = "tickbox|Other" .. (i % 40) .. "|opt" .. i .. "|true\r\n" end
    for m = 1, 5 do
        for k = 1, 4 do buf[#buf + 1] = "tickbox|Mod" .. m .. "|o" .. k .. "|true\r\n" end
    end
    local FILE, LINES = table.concat(buf), #buf
    -- protect n 個 MOD、跑掉 protect 之後那一次（一定重做），回傳檔案多一行之後那一次執行的行數
    local function changedTick(n)
        disk, writes = { [MAIN] = FILE }, {}
        session()
        for m = 1, n do
            local o = PZAPI.ModOptions:create("Mod" .. m, "M")
            for k = 1, 4 do o:addTickBox("o" .. k, "x", false) end
            protect(o)
        end
        ctx.advance(60000)
        runTick()
        disk[MAIN] = disk[MAIN] .. "tickbox|Other0|late|true\r\n"
        ctx.advance(60000)
        return moduleLines(runTick)
    end
    local one, five = changedTick(1), changedTick(5)
    ctx.advance(60000)
    local unchanged = moduleLines(runTick)
    check(unchanged <= 10 * LINES,
        string.format("檔案沒變：只讀檔比對（%d 行設定，執行 %d 行程式，上限每行 10）", LINES, unchanged))
    check(five < 1.5 * one,
        string.format("檔案有變：整份只切一次（5 個 MOD 執行 %d 行、1 個 %d 行，上限 1.5 倍）", five, one))
end

check(prints == 0, "全程零 log")

for k, v in pairs(saved) do _G[k] = v end
return 40
