-- 切片 rev 24：UI.WhatsNew 更新概要通知（WhatsNew.lua，whatsNew）。契約見 smoke_harness.lua 的切片載入器註解。
-- 每一「場」重新 dofile 模組（同 ResetLua 後重新載入）。檔案系統是記憶體 stub：getFileWriter 只收 ini 等副檔名、
-- 一開就截斷（FileOutputStream append=false）、close 時落盤；getFileReader 照 BufferedReader.readLine（\r\n、\n、\r
-- 都算行尾），檔案不存在回 nil。Events、PZAPI.ModOptions、getActivatedMods、getModInfoByID、getTextOrNull、getText
-- 是本檔的 stub；Toast 用 harness 已載入的真實 UI.Toast（時鐘走 ctx 的 getTimestampMs）。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev24：WhatsNew 更新概要通知")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

local Toast = UI.Toast
local MOD_FILE = ctx.MOD_LUA .. "WhatsNew.lua"
local FILE = "MinidoracatUI/WhatsNew.ini"
local HEADER = "# MinidoracatUI: the last update note each mod showed on this computer (modId=version)"
local TITLE = "IGUI_MinidoracatUI_WhatsNew_Title"

-- ── 暫換的全域（檔尾還原） ───────────────────────────────────────────
local saved = { getFileReader = getFileReader, getFileWriter = getFileWriter, PZAPI = PZAPI, Events = Events,
    getActivatedMods = getActivatedMods, getModInfoByID = getModInfoByID, getTextOrNull = getTextOrNull,
    getText = getText, require = require, print = print }
local keepCap, keepApi = UI.CAPABILITIES.whatsNew, UI.WhatsNew

local disk, writes = {}, 0
local readerThrows = false
local ALLOWED = { ini = true, cfg = true, txt = true, log = true, json = true }
getFileWriter = function(name, create, append)
    if not ALLOWED[string.match(name, "%.(%w+)$") or ""] then return nil end
    if not append then disk[name] = "" end
    local buf = {}
    return {
        write = function(_, s) buf[#buf + 1] = s end,
        close = function()
            disk[name] = (disk[name] or "") .. table.concat(buf)
            writes = writes + 1
        end,
    }
end

local function splitLines(s)
    local out, i = {}, 1
    while i <= #s do
        local j = string.find(s, "[\r\n]", i)
        if not j then
            out[#out + 1] = string.sub(s, i)
            break
        end
        out[#out + 1] = string.sub(s, i, j - 1)
        if string.sub(s, j, j + 1) == "\r\n" then j = j + 1 end
        i = j + 1
    end
    return out
end

getFileReader = function(name, create)
    if readerThrows then error("disk read failed") end
    local s = disk[name]
    if s == nil then return nil end
    local lines, i = splitLines(s), 0
    return {
        readLine = function()
            i = i + 1
            return lines[i]
        end,
        close = function() end,
    }
end

local handlers
local function freshEvents()
    handlers = { OnGameStart = {}, OnTick = {} }
    Events = {}
    for _, name in ipairs({ "OnGameStart", "OnTick" }) do
        local list = handlers[name]
        Events[name] = {
            Add = function(fn) list[#list + 1] = fn end,
            Remove = function(fn)
                for i = #list, 1, -1 do
                    if list[i] == fn then table.remove(list, i) end
                end
            end,
        }
    end
end

-- PZAPI.ModOptions：同原版的 getOptions／create／addTickBox／getOption／getValue；load 把「ini 裡存的值」套上
local stored = nil -- ModOptions.ini 裡「顯示 MOD 更新概要」的值（nil＝沒存過）
local loads = 0
local function freshModOptions()
    local pages, M = {}, {}
    function M:getOptions(id) return pages[id] end
    function M:create(id, name)
        local p = { name = name, dict = {} }
        function p:addTickBox(oid, label, default, tooltip)
            local o = { label = label, default = default, tooltip = tooltip, value = default }
            function o:getValue() return self.value end
            self.dict[oid] = o
            return o
        end
        function p:getOption(oid) return self.dict[oid] end
        pages[id] = p
        return p
    end
    function M:load()
        loads = loads + 1
        local o = pages.MinidoracatUIFor42 and pages.MinidoracatUIFor42.dict.WhatsNewShow
        if o and stored ~= nil then o.value = stored end
    end
    PZAPI = { ModOptions = M }
    return pages
end

-- Java ArrayList 的 size()／get(i)（從 0 起算）
local function jlist(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

local activated = { "MinidoracatUIFor42", "ModA", "ModB", "Other", "\\ModC" }
local info = {
    MinidoracatUIFor42 = { name = "UI Library" },
    ModA = { name = "Alpha Mod", require = { "MinidoracatUIFor42" } },
    ModB = { name = "Bravo Mod", require = { "SomethingElse", " MinidoracatUIFor42" } },
    Other = { name = "Other Mod" },
    ModC = { name = "Charlie Mod", require = { "MinidoracatUIFor42" } },
}
local texts = { NoteA = "Alpha note", NameA = "Alpha", NoteB = "Bravo note" }
getActivatedMods = function() return jlist(activated) end
getModInfoByID = function(id)
    local m = info[id]
    if not m then return nil end
    return {
        getRequire = function() return m.require and jlist(m.require) or nil end,
        getName = function() return m.name end,
    }
end
getTextOrNull = function(key) return texts[key] end
getText = function(key, a, b) return key .. "|" .. tostring(a) .. "|" .. tostring(b) end

local function noteA(v) return { modId = "ModA", since = v, text = "NoteA", name = "NameA" } end
local function noteB(v) return { modId = "ModB", since = v, text = "NoteB" } end

-- 呼叫模組時暫換 print 計數（框架預設零 log）；harness 自己的 PASS／FAIL 照常印
local prints = 0
local realPrint = print
local function quiet(fn, ...)
    print = function() prints = prints + 1 end
    local okCall, result = pcall(fn, ...)
    print = realPrint
    if not okCall then error(result, 0) end
    return result
end

-- 新的一場：重新載入模組（模組狀態清空，同 ResetLua）、consumer 登記概要，再觸發 OnGameStart
local W, pages
local function session(specs)
    freshEvents()
    pages = freshModOptions()
    UI.WhatsNew, UI.CAPABILITIES.whatsNew = nil, false
    Toast._resetForTests()
    W = quiet(dofile, MOD_FILE)
    for _, spec in ipairs(specs or {}) do W.register(spec) end
    for _, fn in ipairs(handlers.OnGameStart) do quiet(fn) end
end

-- 往前走 ms 毫秒：每 100ms 一幀，跑 OnTick；prerender＝false 時不推動 Toast 動畫（佔位通知不會逾時）
local function frames(ms, prerender)
    for _ = 1, math.floor(ms / 100) do
        ctx.advance(100)
        local list = {}
        for i, fn in ipairs(handlers.OnTick) do list[i] = fn end
        for _, fn in ipairs(list) do quiet(fn) end
        if prerender ~= false then
            local act = {}
            for i, t in ipairs(Toast.active) do act[i] = t end
            for _, t in ipairs(act) do t:prerender() end
        end
    end
end

local function fileLines() return splitLines(disk[FILE] or "") end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- 畫面上的更新概要（標題來自 WhatsNew_Title）
local function notes()
    local out = {}
    for _, t in ipairs(Toast.active) do
        if type(t.titleText) == "string" and string.find(t.titleText, TITLE, 1, true) == 1 then out[#out + 1] = t end
    end
    return out
end

-- 1. 第一次（沒有紀錄檔）：只記不跳；框架自己與 require= 有框架的 MOD 都記一行，別的 MOD 不記
session({ noteA("1.0.0") })
check(UI.CAPABILITIES.whatsNew == true and UI.WhatsNew == W and type(W.register) == "function",
    "rev 24：whatsNew 翻 true、UI.WhatsNew 掛上 facade")
local opt = pages.MinidoracatUIFor42 and pages.MinidoracatUIFor42.dict.WhatsNewShow
check(opt ~= nil and opt.default == true and opt.label == "IGUI_MinidoracatUI_WhatsNew_Option"
    and opt.tooltip == "IGUI_MinidoracatUI_WhatsNew_Option_tooltip", "選項 → MODS 的框架頁多一個勾選框，預設打開")
check(#handlers.OnTick == 0, "沒有要放的概要：不掛 OnTick")
check(sameList(fileLines(), { HEADER, "MinidoracatUIFor42=", "ModA=1.0.0", "ModB=", "ModC=" }),
    "紀錄：框架自己、登記的 ModA（概要版本）、require= 有框架的 ModB（去空白）與 ModC（去反斜線）；Other 不記")
frames(20000)
check(#notes() == 0, "新安裝不跳")
check(W.register(nil) == false and W.register({}) == false
    and W.register({ modId = "X", since = "beta", text = "T" }) == false
    and W.register({ modId = "X=Y", since = "1", text = "T" }) == false
    and W.register({ modId = "X", since = "1", text = "" }) == false
    and W.register({ modId = "X", since = "1", text = "T", name = 5 }) == false,
    "spec 不對回 false、不拋錯（since 沒有數字、modId 有等號、內文鍵空白、name 不是字串）")

-- 2. 下一場：ModA 有新概要 1.1.0、ModB 第一段概要 0.5.0 → 依序放，同時只放一則
session({ noteA("1.1.0"), noteB("0.5.0") })
check(#handlers.OnTick == 1, "有概要要放：掛一個 OnTick")
frames(4900)
check(#notes() == 0, "進場 5 秒內不放")
frames(300)
local first = notes()[1]
check(first ~= nil and first.titleText == TITLE .. "|Alpha|1.1.0" and first.message == "Alpha note"
    and first.holdMs == 10000, "5 秒後放第一則：標題是 MOD 名稱與概要版本、停 10 秒")
check(sameList(fileLines(), { HEADER, "MinidoracatUIFor42=", "ModA=1.1.0", "ModB=", "ModC=" }),
    "放出去才寫紀錄：ModA 記成 1.1.0，ModB 還沒放")
frames(5000)
check(#notes() == 1 and notes()[1] == first, "第一則還在畫面上：第二則等著")
frames(6000)
local second = notes()[1]
check(second ~= nil and second ~= first and second.titleText == TITLE .. "|Bravo Mod|0.5.0"
    and second.message == "Bravo note", "第一則消失後放第二則；沒有 name 鍵時標題用 mod.info 的名稱")
check(fileLines()[4] == "ModB=0.5.0" and #handlers.OnTick == 0, "第二則放出後記下，佇列空了就拿掉 OnTick")

-- 3. 同一版再進遊戲：不再跳，也不重寫紀錄
local before = writes
session({ noteA("1.1.0"), noteB("0.5.0") })
frames(20000)
check(#notes() == 0 and writes == before and #handlers.OnTick == 0, "看過的概要不再跳、紀錄不重寫")

-- 4. 降版（since 比紀錄舊）不跳、紀錄不倒退
session({ noteA("1.0.5"), noteB("0.5.0") })
frames(20000)
check(#notes() == 0 and fileLines()[3] == "ModA=1.1.0", "降版不跳、紀錄不倒退")

-- 5. Toast 畫面滿 3 則或有排隊時等；概要不進佇列
session({ noteA("2.0.0") })
for i = 1, 4 do Toast.show({ title = "busy", message = "b" .. i, holdMs = 600000 }) end
check(#Toast.active == 3 and #Toast.pending == 1, "前置：3 則在畫面上、1 則排隊")
frames(6000, false)
check(#notes() == 0 and #Toast.pending == 1, "畫面滿而且有排隊：概要等著，不進佇列")
Toast.dismiss(Toast.active[1])
frames(600, false)
check(#notes() == 0 and #Toast.active == 3 and #Toast.pending == 0, "排隊的遞補後畫面又滿：照樣等")
Toast.dismiss(Toast.active[1])
frames(600, false)
check(#notes() == 1 and #Toast.active == 3 and #Toast.pending == 0, "有空位才放：放進畫面、不排隊")

-- 6. 選項關掉：要跳的只記不跳；之後再打開也不補跳
stored, loads = false, 0
session({ noteA("3.0.0") })
frames(20000)
check(#notes() == 0 and fileLines()[3] == "ModA=3.0.0" and loads == 1, "選項關掉：不跳、記成看過；ini 只補讀一次")
stored = true
session({ noteA("3.0.0") })
frames(20000)
check(#notes() == 0, "再打開也不補跳以前的")

-- 7. 遊戲中關掉：剩下的只記不跳
session({ noteA("4.0.0"), noteB("1.0.0") })
frames(5200)
check(#notes() == 1, "前置：第一則放出")
pages.MinidoracatUIFor42.dict.WhatsNewShow.value = false
frames(20000)
check(#notes() == 0 and fileLines()[4] == "ModB=1.0.0" and #handlers.OnTick == 0,
    "遊戲中關掉：第二則不放、記成看過、拿掉 OnTick")
stored = nil

-- 8. 內文鍵查不到（連英文都沒有）：當成沒有概要，不跳也不改紀錄；鍵補上後下一場照跳
texts.NoteA = nil
session({ noteA("5.0.0") })
frames(20000)
check(#notes() == 0 and fileLines()[3] == "ModA=4.0.0", "內文鍵查不到：不跳、紀錄不動")
texts.NoteA = "Alpha note"
session({ noteA("5.0.0") })
frames(5200)
check(#notes() == 1, "鍵補上後照跳")

-- 9. 內文最多畫 3 行，完整內文照樣進通知紀錄
texts.NoteB = string.rep("word ", 40)
session({ noteB("2.0.0") })
frames(5200)
local long = notes()[1]
check(long ~= nil and #long.lines == 3 and Toast.history[#Toast.history].message == texts.NoteB,
    "內文最多畫 3 行；通知紀錄裡是完整內文")

-- 10. 紀錄檔有雜行：註解、沒有 id、沒有等號都略過；同一個 id 以第一行為準；重寫時雜行不留
disk[FILE] = "# hand edited\r\n=9.9.9\nnoequals\rModA=6.0.0\r\nModA=1.0.0\r\n"
session({ noteA("6.0.0") })
frames(20000)
check(#notes() == 0, "雜行略過、同 id 取第一行：6.0.0 看過了")
check(sameList(fileLines(), { HEADER, "ModA=6.0.0", "MinidoracatUIFor42=", "ModB=", "ModC=" }),
    "重寫紀錄：保留原順序、補上沒見過的 MOD、雜行不留")

-- 11. 讀檔拋錯：當沒有紀錄（只記不跳），不拋錯
readerThrows = true
local okRun = pcall(session, { noteA("7.0.0") })
readerThrows = false
frames(20000)
check(okRun and #notes() == 0, "讀檔拋錯：不拋錯、不跳（最壞少跳一次）")

-- 12. 沒有 Toast：不掛能力、不掛事件
local keepToast = UI.Toast
UI.Toast = nil
require = function() error("no module") end
UI.WhatsNew, UI.CAPABILITIES.whatsNew = nil, false
freshEvents()
local loaded = dofile(MOD_FILE)
check(loaded == nil and UI.WhatsNew == nil and UI.CAPABILITIES.whatsNew == false and #handlers.OnGameStart == 0,
    "沒有 Toast：不掛 facade、不翻旗標、不掛事件")
UI.Toast = keepToast
require = saved.require

check(prints == 0, "全程零 log")

Toast._resetForTests()
for k, v in pairs(saved) do _G[k] = v end
UI.CAPABILITIES.whatsNew, UI.WhatsNew = keepCap, keepApi
return n
