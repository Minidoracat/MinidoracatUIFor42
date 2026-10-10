-- 換行切片：Dialog 內文與 Toast 多行訊息的斷行（契約見 smoke_harness.lua 的切片載入器註解）
-- 量測模型：ASCII 7px、其他字 14px（中日文約為拉丁字兩倍寬）。Dialog 預設內寬 336px＝24 個中文字，
-- 和實機 UIFont.Small 的行寬相近（VehicleManager 截圖一行 24 字）。字串是 UTF-8；
-- 補充平面字「𠮷」（U+20BB7）是 4 位元組、算一個字。
local ctx = ...
local check, UI = ctx.check, ctx.UI

local keepTextManager = getTextManager
local function width(text)
    local w = 0
    for ch in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
        w = w + (#ch == 1 and 7 or 14)
    end
    return w
end
getTextManager = function()
    return { MeasureStringX = function(_, _, text) return width(text) end,
        getFontHeight = function() return 12 end }
end

local last
local function dialogLines(text, dialogWidth)
    last = UI.Dialog.show{ title = "T", text = text, confirmText = "OK", width = dialogWidth }
    for _, c in ipairs(last.children) do
        if c.lines then return c.lines, c.width end
    end
end

local function toastLines(message)
    UI.Toast._resetForTests()
    return UI.Toast.show({ message = message, maxLines = 3 }).lines
end

local function same(lines, want)
    if #lines ~= #want then return false end
    for i = 1, #want do
        if lines[i] ~= want[i] then return false end
    end
    return true
end

print("情境 wrap：中日文與拉丁文混排的斷行")

-- VehicleManager 身分匯入確認框（CH 原文，三段）
local vm = "匯入白名單裡所有帳號和它們的 SteamID 嗎？\n"
    .. "之後玩家的 Steam 帳號要和帳號相符才算數，改名或分割畫面都冒用不了別人的帳號。第一次匯入前，照舊以帳號名稱判定。\n"
    .. "SteamID 變過的帳號會列成衝突，你確認之前不會改。"
local lines, innerW = dialogLines(vm)
check(lines[2] == "之後玩家的 Steam 帳號要和帳號相符才算數，改名或",
    "截點落在中文字之間就直接斷，不退回前面英文字後的空白（VehicleManager 截圖）")
check(same(lines, {
    "匯入白名單裡所有帳號和它們的 SteamID 嗎？",
    "之後玩家的 Steam 帳號要和帳號相符才算數，改名或",
    "分割畫面都冒用不了別人的帳號。第一次匯入前，照舊",
    "以帳號名稱判定。",
    "SteamID 變過的帳號會列成衝突，你確認之前不會改。",
}), "其餘各行也填到行寬（中文逐字斷、SteamID 前的空白照常斷）")
local fits = true
for _, l in ipairs(lines) do
    if width(l) > innerW then fits = false end
end
check(fits, "每行都不超過內文寬")

-- 純英文：內寬 133px＝19 個字元
check(same(dialogLines("Accounts whose SteamID changed are listed as conflicts", 157),
    { "Accounts whose", "SteamID changed are", "listed as conflicts" }),
    "純英文：截點切到單字就退到空白；剛好在單字結尾就在那裡斷，不多退一個單字")

-- 純中文：內寬 238px＝17 個字。第 18 字是「，」，不放行首，連同前一字移到下一行
check(same(dialogLines("這是一段沒有任何空白的中文說明文字，用來確認換行時標點不會跑到下一行的開頭。", 262),
    { "這是一段沒有任何空白的中文說明文", "字，用來確認換行時標點不會跑到下一", "行的開頭。" }),
    "純中文：逐字斷，句讀不放在行首")
check(same(dialogLines("我們先到「安全屋」集合", 94), { "我們先到", "「安全屋」", "集合" }),
    "開括號不留在行尾，閉括號不放在行首")

-- 中英交錯、沒有空白：截點切到「Enter」時退到中文字與英文字的交界，不硬切單字
check(same(dialogLines("請先按F1開啟說明，再按Enter確認設定。", 199), { "請先按F1開啟說明，再按", "Enter確認設定。" }),
    "中英交錯：拉丁單字退到與中文字的交界，不從單字中間切開")

-- Toast（內寬 284px、maxLines 3）走同一套斷行
check(same(toastLines("之後玩家的 Steam 帳號要和帳號相符才算數，改名或分割畫面都冒用不了別人的帳號。第一次匯入前，照舊以帳號名稱判定。"),
    { "之後玩家的 Steam 帳號要和帳號相符才算", "數，改名或分割畫面都冒用不了別人的帳號。", "第一次匯入前，照舊以帳號名稱判定。" }),
    "Toast：同一段文字填滿行寬、「，」不放行首、三行放得下不帶省略號")
local kichi = "\240\160\174\183" -- 𠮷
check(same(toastLines("Owner " .. string.rep(kichi, 25)), { "Owner " .. string.rep(kichi, 17), string.rep(kichi, 8) }),
    "補充平面字：字與字之間可斷、不切開同一個字，也不退回前面的空白")

-- rev 17：小地圖設定視窗私有斷行的禁則併進框架（全形 ％、～、日文小寫假名與長音不放行首；波浪號也不放行尾）
local wrap = UI.Text.wrap
local NEW_NO_START = { 0xFF05, 0xFF5E, 0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E,
    0x3095, 0x3096, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, 0x30FC }
local bad = {}
for _, cp in ipairs(NEW_NO_START) do
    local c = utf8.char(cp)
    local got = wrap("一二三" .. c, 42) -- 三個字寬：截點正好落在 c 前面
    if not same(got, { "一二", "三" .. c }) then bad[#bad + 1] = string.format("U+%04X", cp) end
end
check(#bad == 0, "全形 ％ ～、小寫假名ぁぃぅぇぉっゃゅょゎゕゖ／ァィゥェォッャュョヮヵヶ、長音ー不放行首，連同前一字換行"
    .. (#bad > 0 and ("（失敗：" .. table.concat(bad, " ") .. "）") or ""))
local tildeOK = true
for _, cp in ipairs({ 0x301C, 0xFF5E }) do
    local c = utf8.char(cp)
    if not same(wrap("一二" .. c .. "三四", 42), { "一", "二" .. c .. "三", "四" }) then tildeOK = false end
end
check(tildeOK, "波浪號〜～也不放行尾：「10～20」這種範圍兩側都不斷開")
check(same(wrap("コンピューター", 56), { "コン", "ピュー", "ター" }),
    "片假名：ュ、ー都不放行首，往回找到能斷的位置（不是「コンピュ／ーター」）")

-- rev 18：數字與後面的中日韓單位之間的半形空白不斷（「1 件」「30 個」「1,000 倖存幣」）；截點落在那裡就退到數字前面
check(same(toastLines("每日簽到獎勵已發放到你的信箱，已領取 1 件。"), { "每日簽到獎勵已發放到你的信箱，已領取", "1 件。" }),
    "Toast：「1 件」不拆成行尾「1」與行首「件」，整組移到下一行")
local lines30 = dialogLines("背包裡的罐頭已經全部賣出，共計 30 個，收入已存入帳戶", 269)
check(lines30[1] == "背包裡的罐頭已經全部賣出，共計" and lines30[2] == "30 個，收入已存入帳戶",
    "Dialog：「30 個」不拆開，從數字前面的空白斷")
check(same(toastLines("商店結帳完成，你的帳戶餘額已扣除 1,000 倖存幣。"), { "商店結帳完成，你的帳戶餘額已扣除", "1,000 倖存幣。" }),
    "Toast：千分位數字「1,000 倖存幣」整組換行")
check(same(wrap("提高 80% 成功率", 70), { "提高", "80% 成功率" }), "數字後接 % 再接中文單位也不斷（「80% 成功率」）")
check(same(wrap("1,000 倖存幣", 45), { "1,000", "倖存幣" }), "數字加單位本身比行寬長：沒有別的斷點，照舊在空白斷")
check(same(wrap("Received 1 item", 70), { "Received 1", "item" }), "英文不受影響：數字後的空白接拉丁字照常可斷")

UI.Dialog.close(last)
UI.Toast._resetForTests()
getTextManager = keepTextManager

return 18
