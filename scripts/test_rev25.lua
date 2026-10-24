-- 切片 rev 25：ItemPicker 多選模式（Widgets/ItemPicker.lua，itemPickerMulti）。契約見 smoke_harness.lua 的切片載入器註解。
-- 重新 dofile 元件（宇宙整個 session 快取，前面的切片建過別的一份）；getText 換成帶參數的版本，才分得出計數字。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev25：ItemPicker 多選（勾選切換、上限、預先勾選、完成、取消、單選照舊、零配置）")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

-- ---------- 引擎 stub（本檔自補，檔尾還原） ----------
local keepGetText = getText
getText = function(key, a, b)
    local s = "[" .. tostring(key)
    if a ~= nil then s = s .. ":" .. tostring(a) end
    if b ~= nil then s = s .. ":" .. tostring(b) end
    return s .. "]"
end
getTextOrNull = function() return nil end
getItemName = function(fullType) return fullType end
local function script(fullType)
    return {
        isHidden = function() return false end,
        getObsolete = function() return false end,
        getFullName = function() return fullType end,
        getDisplayCategory = function() return "Food" end,
    }
end
local scripts = { script("Base.UniOnly"), script("Base.C1") }
getScriptManager = function()
    return { getAllItems = function()
        return { size = function() return #scripts end, get = function(_, i) return scripts[i + 1] end }
    end }
end

dofile(ctx.MOD_LUA .. "Widgets/ItemPicker.lua")
check(UI.API_REVISION == 25 and UI.CAPABILITIES.itemPicker == true and UI.CAPABILITIES.itemPickerMulti == true,
    "API_REVISION 是 25，載入成功後 itemPickerMulti 與 itemPicker 一起翻 true")
local uni = UI.ItemPicker.universe()

-- consumer 自己的 record（多帶 tag，宇宙的 record 沒有）
local records = {}
for i = 1, 12 do
    local ft = "Base.C" .. i
    records[i] = { fullType = ft, name = "C " .. i, category = "Food", search = string.lower("c " .. i .. " " .. ft),
        tag = i }
end
local itemsCalls = 0
local manyCalls, picks, cancels = {}, {}, {}
local T = ctx.TARGET
local function newPicker(extra)
    local opts = {
        width = 600, height = 400, target = T,
        items = function() itemsCalls = itemsCalls + 1; return records end,
        onPick = function(target, rec, picker)
            picks[#picks + 1] = { target = target, rec = rec, open = picker:isOpen() }
        end,
        onPickMany = function(target, recs, picker)
            manyCalls[#manyCalls + 1] = { target = target, recs = recs, picker = picker, open = picker:isOpen() }
        end,
        onCancel = function(target, picker)
            cancels[#cancels + 1] = { target = target, open = picker:isOpen() }
        end,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return UI.ItemPicker.new(opts)
end
local function order(picker)
    return table.concat(picker._order, ",")
end

local win = UI.Window.new{ x = 0, y = 0, width = 700, height = 500, title = "W" }
local picker = newPicker({ multi = true, maxPicks = 3 })
win:addChild(picker)

-- ---------- 版面與焦點目標 ----------
picker:open()
local targets = picker:keyboardTargets()
check(#targets == 4 and targets[1].kind == "entry" and targets[1].control == picker.search._entry
    and targets[2].control == picker.list and targets[3].kind == "button" and targets[3].control == picker.doneButton
    and targets[4].control == picker.cancelButton and picker:keyboardTargets() == targets,
    "多選 keyboardTargets：搜尋框、清單、完成鈕、取消鈕（快取同一張表）")
local single = newPicker()
single:open()
local done = picker.doneButton
check(done.title == "[IGUI_MinidoracatUI_ItemPicker_Done]" and done.y + done.height == picker.height - 24
    and picker.list.height == single.list.height - (done.height + 6)
    and picker.list.y + picker.list.height + 6 == done.y,
    "底部一列：完成鈕（預設標題走翻譯鍵）貼卡片下緣，清單高度扣掉這一列")
check(newPicker({ multi = true, doneTitle = "OK" }).doneButton.title == "OK", "doneTitle 覆寫完成鈕標題")

-- ---------- 勾選切換 ----------
check(order(picker) == "" and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:0:3]",
    "沒給 picked：開啟時沒有勾選，計數用 PickedMax（已選 0／3）")
local list = picker.list
list.onSelect(list, records[2], 2)
list.onSelect(list, records[5], 5)
check(picker:isOpen() and order(picker) == "Base.C2,Base.C5" and #manyCalls == 0 and #picks == 0
    and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:2:3]",
    "點列＝勾選：疊層不關、不回呼，計數字跟著重組")
list.onSelect(list, records[2], 2)
check(order(picker) == "Base.C5" and not picker._picked["Base.C2"]
    and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:1:3]", "再點一次＝取消勾選")
picker:choose(records[1])
picker:choose(records[7])
picker:choose(records[9])
check(order(picker) == "Base.C5,Base.C1,Base.C7" and not picker._picked["Base.C9"] and picker._pickWarn == true
    and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:3:3]",
    "達 maxPicks：拒勾新列（列維持未勾、計數不變）並標記警示")
picker:prerender()
local warn = UI.Theme.create().colors.warning
local warnDrawn = false
for _, t in ipairs(picker.texts) do
    if t.y == picker._footerTextY and t.r == warn.r and t.g == warn.g and t.b == warn.b then warnDrawn = true end
end
check(warnDrawn, "被拒時計數字畫成 warning 色")
picker:choose(records[1])
check(order(picker) == "Base.C5,Base.C7" and picker._pickWarn == false, "取消一列後警示解除")
picker:choose(records[1])

-- 搜尋重建不清勾選
local calls = itemsCalls
picker.search:setText("c 1")
picker:prerender()
ctx.advance(200)
picker:prerender()
check(itemsCalls == calls + 1 and order(picker) == "Base.C5,Base.C7,Base.C1", "搜尋重建清單（rebuild）不清掉勾選")

-- 列首勾選框：勾了才有實心方塊
picker.search:setText("")
ctx.advance(200)
picker:prerender()
ctx.advance(200)
picker:prerender()
local boxOn, boxOff
for _, cell in ipairs(list.pool) do
    if cell.entry == records[1] then boxOn = cell elseif cell.entry == records[2] then boxOff = cell end
end
boxOn.rects, boxOn.borders = {}, {}
boxOff.rects, boxOff.borders = {}, {}
boxOn:render()
boxOff:render()
local accent = picker.theme.colors.accent
local function hasFill(cell)
    for _, r in ipairs(cell.rects) do
        if r.x == 15 and r.w == 8 and r.r == accent.r and r.g == accent.g and r.b == accent.b then return true end
    end
    return false
end
local function hasBox(cell)
    for _, b in ipairs(cell.borders) do
        if b.x == 12 and b.w == 14 and b.h == 14 then return true end
    end
    return false
end
check(hasBox(boxOn) and hasBox(boxOff) and hasFill(boxOn) and not hasFill(boxOff) and boxOn._nameX > 12 + 14 + 8 + 28,
    "列首畫勾選框（勾選＝框內 accent 實心方塊），圖示與名稱往右讓位")

-- ---------- 完成 ----------
picker.doneButton:forceClick()
local call = manyCalls[1]
check(#manyCalls == 1 and call.open == false and not picker:isOpen() and call.target == T and call.picker == picker,
    "完成鈕：疊層先關，再回呼 onPickMany(target, recs, picker) 一次")
check(#call.recs == 3 and call.recs[1] == records[5] and call.recs[2] == records[7] and call.recs[3] == records[1]
    and call.recs[3] ~= uni.byType["Base.C1"] and call.recs[3].tag == 1,
    "recs 依勾選先後，且是 consumer items() 的 record（宇宙也有同 fullType 時仍用 consumer 的）")
picker:done()
check(#manyCalls == 1 and #picks == 0, "疊層關著時 done() 不做事（只回呼一次），也不會回呼 onPick")

-- ---------- open(picked) ----------
picker:open({ "Base.C3", "Base.C3", 42, "Base.UniOnly", "Base.Ghost", "Base.C4" })
check(order(picker) == "Base.C3,Base.UniOnly,Base.Ghost" and picker._picked["Base.C4"] == nil
    and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:3:3]",
    "open(picked)：重複與非字串略過、超過 maxPicks 截斷，計數照預先勾選")
picker:done()
local recs = manyCalls[2].recs
check(#manyCalls == 2 and #recs == 2 and recs[1] == records[3] and recs[2] == uni.byType["Base.UniOnly"],
    "consumer 沒有的退回 universe().byType，兩邊都沒有（Base.Ghost）就略過")
picker:open()
check(order(picker) == "" and picker.pickedText == "[IGUI_MinidoracatUI_ItemPicker_PickedMax:0:3]",
    "每次開啟都重設勾選：沒給 picked 就清空")
picker:close()
picker:open({ "Base.C1" })
picker:open({ "Base.C2" })
check(order(picker) == "Base.C1", "已開著時再 open 不做事（不重設勾選）")

-- ---------- 取消 ----------
picker.cancelButton:forceClick()
check(#cancels == 1 and cancels[1].open == false and cancels[1].target == T and not picker:isOpen()
    and order(picker) == "" and #manyCalls == 2, "取消：關閉後回呼 onCancel 一次，勾選作廢，不回呼 onPickMany")
picker:done()
check(#manyCalls == 2, "取消後 done() 不回呼")

-- ---------- 不限上限、非法 maxPicks ----------
local free = newPicker({ multi = true, maxPicks = 0 })
free:open()
for i = 1, 5 do free:choose(records[i]) end
check(free.maxPicks == nil and #free._order == 5 and free.pickedText == "[IGUI_MinidoracatUI_ItemPicker_Picked:5]",
    "maxPicks 不是 >= 1 的數字＝不限，計數改用 Picked（已選 N 項）")
free:dispose()
check(free.onPickMany == nil and not free:isOpen(), "dispose 也放掉 onPickMany")

-- ---------- 單選照舊 ----------
local plain = newPicker({ multi = "yes", maxPicks = 2 })
plain:open({ "Base.C1" })
check(plain.multi == nil and plain._order == nil and plain.doneButton == nil and plain.maxPicks == nil
    and #plain:keyboardTargets() == 3 and plain:keyboardTargets()[3].control == plain.cancelButton
    and plain.list.height == single.list.height and plain._pickedFit == nil,
    "multi 不為 true：多選欄位全部忽略，版面與焦點目標同單選")
plain:done()
check(plain:isOpen() and #manyCalls == 2, "單選時 done() 不做事")
plain:prerender()
local cell = plain.list.pool[1]
cell:render()
check(cell._boxSize == nil and cell._iconX == 12 and cell._nameX == 12 + 28 + 8, "單選的列沒有勾選框、圖示位置不變")
plain.list.onSelect(plain.list, records[4], 4)
check(#picks == 1 and picks[1].rec == records[4] and picks[1].open == false and not plain:isOpen(),
    "單選 choose 照舊：疊層先關再回呼 onPick")
single:close()

-- ---------- 零配置 ----------
local zp = newPicker({ multi = true, maxPicks = 2 })
zp:open({ "Base.C1", "Base.C2" })
zp:choose(records[3]) -- 被拒：警示色路徑
local noop = function() end
zp.drawRect, zp.drawRectBorder, zp.drawText = noop, noop, noop
for _, c in ipairs(zp.list.pool) do
    c.drawRect, c.drawRectBorder, c.drawText = noop, noop, noop
end
local cells = zp.list.pool
local function round()
    zp:prerender()
    for i = 1, #cells do cells[i]:render() end
end
collectgarbage("collect")
collectgarbage("stop")
round()
local kb = collectgarbage("count")
for _ = 1, 50 do round() end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(grew == 0, "多選 prerender＋列 render（勾選框、警示色計數）50 輪不配置記憶體")
zp:dispose()

-- ---------- 還原 ----------
UI.Focus.clear(win)
getText = keepGetText
getTextOrNull, getItemName, getScriptManager = nil, nil, nil

return n
