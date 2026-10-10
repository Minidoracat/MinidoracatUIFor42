-- MinidoracatUI/TextWrap — 框架共用的斷行：Dialog 內文、Toast 多行訊息，rev 16 起另以 UI.Text.wrap 公開。
--
-- 本表是內部模組：不設全域，Widgets 以 require 取回傳值（LuaManager.RunLuaInternal 把第一次執行的回傳值
-- 存進 loadedReturn，之後的 require 直接回它）。對外只掛 UI.Text.wrap（檔尾，CAPABILITIES.textWrap）。
--
-- TextWrap.cut(text, maxWidth, font) → line, rest
--   貪婪斷行：二分找最長放得下的前綴（MeasureStringX 量 O(log n) 次）。截點能斷就在截點斷，
--   不能斷才往回找最近的斷點；整段都沒有斷點（比行寬長的拉丁單字）就在截點硬切。
--   能斷＝截點任一側是空白，或任一側是中日韓字（含全形標點與補充平面字），而且
--   右側不是行首禁則字（，。、」）等）、左側不是行尾禁則字（「（等）。
--   法文標點的空白（rev 18）不是斷點：空白後面緊接 : ; ! ? 右書名號，或前面緊接左書名號（U+00BB／U+00AB），
--   否則「Interferences : 0」會把「: 0」斷到下一行行首。不換行空白 U+00A0 本來就不是斷點。
--   line 去掉行尾空白、rest 去掉開頭空白；text 整段放得下時回 text, ""。
--   連一個字都放不下時照樣放一個字，呼叫端的迴圈一定會前進。
-- TextWrap.lines(text, maxWidth, font) → { line, ... }
--   依 "\n" 分段、每段走 cut；空段落是空行。每次呼叫都重算、回新表（Dialog 建構時用）。
-- UI.Text.wrap(text, maxWidth, font?) → { line, ... }（rev 16）
--   同 lines，但以 (font, maxWidth, text) 快取：同樣三者回同一張表（呼叫端只讀、不得修改），每幀呼叫不配置。
--   font 省略＝UIFont.Small；text 非字串以 tostring 轉。快取超過 WRAP_CACHE_MAX 筆整個清掉重來。
--
-- 截點一律落在字元邊界：Kahlua 字串是 UTF-16 code unit（不切開 surrogate pair），harness 的
-- 標準 Lua 是 UTF-8 位元組（不切開多位元組字）；字元模型的判斷同 V1.lua 的 Text.fit。
-- 本檔只能寫 ASCII 字面值（Kahlua 把字串字面值逐字截成一個位元組），字一律寫碼位。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local TextWrap = {}

local charOK, char256 = pcall(string.char, 256)
local UTF16 = charOK and string.byte(char256) == 256
local SPACE = 32
local ASTRAL = 0x10000 -- 補充平面字（surrogate pair／4 位元組 UTF-8）一律當表意字

local function set(codes)
    local t = {}
    for i = 1, #codes do
        t[codes[i]] = true
    end
    return t
end

-- 行首禁則（UAX #14 的 CL／CP／EX／IS／NS 與收尾引號；rev 17 補全形 ％、～、日文小寫假名與長音）
local NO_START = set({
    0x21, 0x29, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, 0x5D, 0x7D, -- ! ) , . : ; ? ] }
    0x2019, 0x201D, 0x2026, -- ’ ” …
    0x3001, 0x3002, 0x3005, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B, 0x301C,
    0x309B, 0x309C, 0x309D, 0x309E, 0x30A0, 0x30FB, 0x30FD, 0x30FE, -- ゛゜ゝゞ゠・ヽヾ
    0xFF01, 0xFF05, 0xFF09, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF3D, 0xFF5D, 0xFF5E, 0xFF61, 0xFF63, 0xFF64,
    0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096, -- ぁぃぅぇぉっゃゅょゎゕゖ
    0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, 0x30FC, -- ァィゥェォッャュョヮヵヶー
})
-- 行尾禁則（UAX #14 的 OP 與起始引號；rev 17 補波浪號 〜 ～：範圍「10～20」兩側都不斷）
local NO_END = set({
    0x28, 0x5B, 0x7B, -- ( [ {
    0x2018, 0x201C, -- ‘ “
    0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A, 0x301C, 0x301D,
    0xFF08, 0xFF3B, 0xFF5B, 0xFF5E, 0xFF62,
})
-- 法文排版（rev 18）：這些標點前面的空白、左書名號後面的空白黏住兩側
local FRENCH_SPACE_BEFORE = set({ 0x21, 0x3A, 0x3B, 0x3F, 0xBB }) -- ! : ; ? 右書名號
local FRENCH_SPACE_AFTER = 0xAB -- 左書名號

-- 中日韓表意字與符號、假名、注音、諺文音節、全形字、補充平面字：兩側都可以斷
local function ideographic(c)
    return (c >= 0x2E80 and c <= 0x9FFF) or (c >= 0xAC00 and c <= 0xD7AF) or (c >= 0xF900 and c <= 0xFAFF)
        or (c >= 0xFE30 and c <= 0xFE4F) or (c >= 0xFF00 and c <= 0xFFEF) or c >= ASTRAL
end

-- n 退到字元邊界：前 n 個 unit 不切開一個字
local function boundary(s, n)
    if UTF16 then
        local unit = n > 0 and string.byte(s, n) or 0
        if unit >= 0xD800 and unit <= 0xDBFF then -- 前綴結尾是 high surrogate
            n = n - 1
        end
        return n
    end
    while n > 0 do
        local unit = string.byte(s, n + 1)
        if not unit or unit < 128 or unit >= 192 then
            break
        end
        n = n - 1 -- 下一個位元組是 continuation：退到字元開頭
    end
    return n
end

-- 從第 i 個 unit 開始的那個字的碼位。補充平面字回 ASTRAL（只需要知道它是表意字）
local function codeAt(s, i)
    local unit = string.byte(s, i)
    if UTF16 then
        if unit >= 0xD800 and unit <= 0xDFFF then
            return ASTRAL
        end
        return unit
    end
    if unit < 0xC0 then
        return unit
    end
    if unit < 0xE0 then -- 2 位元組 UTF-8（法文書名號 U+00AB／U+00BB 要認得出來）
        return (unit - 0xC0) * 64 + ((string.byte(s, i + 1) or 0x80) - 0x80)
    end
    if unit >= 0xF0 then
        return ASTRAL
    end
    local b2, b3 = string.byte(s, i + 1, i + 2)
    return (unit - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
end

-- 第 n 個 unit 前後的那段空白是不是法文標點的空白：往前跳過空白看是不是左書名號、往後跳過空白看是不是
-- : ; ! ? 右書名號
local function frenchSpace(s, n)
    local i = n
    while i > 0 and string.byte(s, i) == SPACE do
        i = i - 1
    end
    if i > 0 and codeAt(s, boundary(s, i - 1) + 1) == FRENCH_SPACE_AFTER then
        return true
    end
    local j, len = n + 1, string.len(s)
    while j <= len and string.byte(s, j) == SPACE do
        j = j + 1
    end
    return j <= len and FRENCH_SPACE_BEFORE[codeAt(s, j)] == true
end

-- 能不能在第 n 個 unit 之後斷行（n 是字元邊界，後面還有字）
local function breakable(s, n)
    local left = codeAt(s, boundary(s, n - 1) + 1)
    local right = codeAt(s, n + 1)
    if left == SPACE or right == SPACE then
        return not frenchSpace(s, n)
    end
    return (ideographic(left) or ideographic(right)) and not NO_START[right] and not NO_END[left]
end

function TextWrap.cut(text, maxWidth, font)
    local manager = getTextManager()
    if manager:MeasureStringX(font, text) <= maxWidth then
        return text, ""
    end
    local low, high, best = 1, string.len(text), 0
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local n = boundary(text, mid)
        if n >= 1 and manager:MeasureStringX(font, string.sub(text, 1, n)) <= maxWidth then
            best = n
            low = mid + 1
        else
            high = mid - 1
        end
    end
    local n = best
    if best == 0 then
        repeat -- 連一個字都放不下：照樣放一個字
            n = n + 1
        until boundary(text, n) == n
    else
        while n > 0 and not breakable(text, n) do
            n = boundary(text, n - 1)
        end
        if n == 0 then -- 沒有斷點：硬切
            n = best
        end
    end
    local line = string.gsub(string.sub(text, 1, n), "%s+$", "")
    local rest = string.gsub(string.sub(text, n + 1), "^%s+", "")
    return line, rest
end

function TextWrap.lines(text, maxWidth, font)
    local lines = {}
    local start = 1
    while true do
        local nl = string.find(text, "\n", start, true)
        local paragraph = nl and string.sub(text, start, nl - 1) or string.sub(text, start)
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            local rest = paragraph
            while rest ~= "" do
                local line
                line, rest = TextWrap.cut(rest, maxWidth, font)
                lines[#lines + 1] = line
            end
        end
        if not nl then
            return lines
        end
        start = nl + 1
    end
end

-- ponytail: 超過上限整個清空，不做 LRU；面板文字通常只有數十段
local WRAP_CACHE_MAX = 256
local wrapCache, wrapCount = {}, 0

local function wrap(text, maxWidth, font)
    if type(text) ~= "string" then
        text = text == nil and "" or tostring(text)
    end
    maxWidth = tonumber(maxWidth) or 0
    font = font or UIFont.Small
    local byFont = wrapCache[font]
    local byWidth = byFont and byFont[maxWidth]
    local hit = byWidth and byWidth[text]
    if hit then
        return hit
    end
    if wrapCount >= WRAP_CACHE_MAX then
        wrapCache, wrapCount = {}, 0
        byFont, byWidth = nil, nil
    end
    if not byFont then
        byFont = {}
        wrapCache[font] = byFont
    end
    if not byWidth then
        byWidth = {}
        byFont[maxWidth] = byWidth
    end
    local lines = TextWrap.lines(text, maxWidth, font)
    byWidth[text] = lines
    wrapCount = wrapCount + 1
    return lines
end

local UI = MinidoracatUI and MinidoracatUI.v1
if UI and UI.API_MAJOR == 1 and UI.Text and UI.CAPABILITIES then
    UI.Text.wrap = wrap
    UI.CAPABILITIES.textWrap = true
end

return TextWrap
