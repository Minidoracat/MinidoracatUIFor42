-- rev 11 切片 D：UI.ItemPicker（Widgets/ItemPicker.lua）。契約見 smoke_harness.lua 檔尾 loader 註解。
local ctx = ...
local check, UI = ctx.check, ctx.UI

print("情境 rev11-itempicker：宇宙／篩選與上限／debounce／revision／選取與取消／焦點目標快取")

-- ---------- 載入自檢：缺 Table 不翻旗標 ----------
local keepCap, keepTable = UI.CAPABILITIES.table, UI.Table
UI.CAPABILITIES.table, UI.Table = false, nil
dofile(ctx.MOD_LUA .. "Widgets/ItemPicker.lua")
check(UI.CAPABILITIES.itemPicker == false and UI.ItemPicker == nil, "缺 Table 時 return：itemPicker 旗標維持 false")
UI.CAPABILITIES.table, UI.Table = keepCap, keepTable
if not UI.CAPABILITIES.table then
    dofile(ctx.MOD_LUA .. "Widgets/Table.lua")
end
dofile(ctx.MOD_LUA .. "Widgets/ItemPicker.lua")
check(UI.CAPABILITIES.itemPicker == true and type(UI.ItemPicker.new) == "function", "Controls＋Table 在：旗標翻 true")

-- ---------- 引擎 stub（本檔自補，檔尾還原） ----------
local keepGetText = getText
getText = function(key, a, b)
    local s = "[" .. tostring(key)
    if a ~= nil then s = s .. ":" .. tostring(a) end
    if b ~= nil then s = s .. ":" .. tostring(b) end
    return s .. "]"
end
getTextOrNull = function(key)
    if key == "IGUI_ItemCat_Food" then return "FoodCat" end
    return nil
end
local names = { ["Base.Axe"] = "Axe Name" }
getItemNameFromFullType = function(fullType)
    local n = names[fullType]
    if n == nil then error("no name") end
    return n
end
local texCalls, findCalls = 0, 0
local function script(fullType, category, hidden, obsolete)
    return {
        isHidden = function() return hidden == true end,
        getObsolete = function() return obsolete == true end,
        getFullName = function() return fullType end,
        getDisplayCategory = function() return category end,
        getNormalTexture = function() texCalls = texCalls + 1; return { tex = fullType } end,
    }
end
local scripts = {}
local javaList = { size = function() return #scripts end, get = function(_, i) return scripts[i + 1] end }
getScriptManager = function()
    return {
        getAllItems = function() return javaList end,
        FindItem = function(_, fullType) findCalls = findCalls + 1; return script(fullType, "Food") end,
    }
end
ISPanel.drawTextureScaled = function(self, tex, x, y, w, h, a, r, g, b)
    self.tex = self.tex or {}
    self.tex[#self.tex + 1] = { tex = tex, x = x, y = y, w = w, h = h }
end

-- ---------- 宇宙 ----------
local empty = UI.ItemPicker.universe()
scripts = {
    script("Base.Axe", "Tool"), script("Base.Hidden", "Tool", true), script("Base.Old", "Tool", false, true),
    script("Base.Odd", nil), script("Base.Axe", "Dup"),
}
local uni = UI.ItemPicker.universe()
check(#empty.items == 0 and #uni.items == 2, "空結果不快取：script manager 之後有資料就重掃")
check(uni.byType["Base.Hidden"] == nil and uni.byType["Base.Old"] == nil and uni.byType["Base.Axe"] == uni.items[1],
    "跳過 hidden／obsolete、重複 fullType 只收第一筆，byType 指向同一個 record")
local axe, odd = uni.byType["Base.Axe"], uni.byType["Base.Odd"]
check(axe.name == "Axe Name" and axe.category == "Tool" and axe.search == "axe name base.axe" and axe.script == scripts[1]
    and odd.name == "Base.Odd" and odd.category == "Item",
    "record：name／search 小寫／script；名稱失敗退回 fullType、空類別用 Item")
scripts = {}
check(UI.ItemPicker.universe() == uni, "非空宇宙整個 session 快取（之後不再掃描）")

-- ---------- 疊層 ----------
local records = {}
for i = 1, 250 do
    local ft = "Base.Thing" .. i
    records[i] = { fullType = ft, name = "Thing " .. i, category = "Food", search = string.lower("thing " .. i .. " " .. ft) }
end
records[1].original = "Orig One"
local itemsCalls, rev = 0, 1
local picks, cancels = {}, {}
local T = ctx.TARGET
local function newPicker(extra)
    local opts = {
        width = 600, height = 400, target = T,
        items = function() itemsCalls = itemsCalls + 1; return records end,
        filter = function(rec) return rec.fullType ~= "Base.Thing50" and rec.fullType ~= "Base.Thing100" end,
        revision = function() return rev end,
        note = function() return "NOTE" end,
        onPick = function(target, rec, picker)
            picks[#picks + 1] = { target = target, rec = rec, picker = picker, open = picker:isOpen() }
        end,
        onCancel = function(target, picker)
            cancels[#cancels + 1] = { target = target, picker = picker, open = picker:isOpen() }
        end,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return UI.ItemPicker.new(opts)
end

local win = UI.Window.new{ x = 0, y = 0, width = 700, height = 500, title = "W" }
local picker = newPicker()
win:addChild(picker)
win.keyboardTargets = function(self)
    if picker:isOpen() then return picker:keyboardTargets() end
    return UI.Focus.collectTargets(self)
end

local closedTargets = picker:keyboardTargets()
check(not picker:isOpen() and #closedTargets == 0 and picker:keyboardTargets() == closedTargets and itemsCalls == 0,
    "建構後關著：keyboardTargets 回同一個快取空表，關著時 layout 不搜尋")

picker:open()
local entry = picker.search._entry
check(picker:isOpen() and entry._focused == true and UI.Focus.focused() == entry,
    "open：焦點落在搜尋框（Focus.focusControl）")
local list = picker.list
local rows = list:getItems()
local excluded = false
for i = 1, #rows do
    if rows[i].fullType == "Base.Thing50" or rows[i].fullType == "Base.Thing100" then excluded = true end
end
check(itemsCalls == 1 and picker.total == 248 and #rows == 200 and not excluded,
    "空查詢：filter 排除 2 筆，共 248 筆、顯示預設上限 200")
check(picker.hintText == "NOTE  [IGUI_MinidoracatUI_ItemPicker_More:200:248]",
    "提示列：note 前綴＋More（顯示數、總數）")

local targets = picker:keyboardTargets()
check(targets == picker:keyboardTargets() and #targets == 3 and targets[1].kind == "entry" and targets[1].control == entry
    and targets[1].frame == picker.search and targets[2].kind == "list" and targets[2].control == list
    and targets[3].kind == "button" and targets[3].control == picker.cancelButton,
    "開著：keyboardTargets 回同一個快取（entry／list／cancel 三個描述）")

-- debounce 120ms：打字只設計時器
picker.search:setText("thing 12")
picker:prerender()
ctx.advance(119)
picker:prerender()
check(itemsCalls == 1 and #list:getItems() == 200, "改字後 119ms 尚未重搜")
ctx.advance(1)
picker:prerender()
check(itemsCalls == 2 and picker.total == 11 and picker.hintText == "NOTE  [IGUI_MinidoracatUI_ItemPicker_Count:11]",
    "滿 120ms 重搜一次：thing 12 命中 11 筆，提示列用 Count")
picker:prerender()
check(itemsCalls == 2, "同一個查詢不重複搜尋")

picker.search:setText("thing 125")
picker:prerender()
ctx.advance(100)
picker.search:setText("thing 1250")
picker:prerender()
ctx.advance(100)
picker:prerender()
check(itemsCalls == 2, "每次改字重新計時（距最後一次改字未滿 120ms 不搜）")
ctx.advance(20)
picker:prerender()
check(itemsCalls == 3 and picker.total == 0 and #list:getItems() == 0
    and picker.hintText == "NOTE  [IGUI_MinidoracatUI_ItemPicker_Empty]", "沒結果：提示列用 Empty")

-- revision：值變了同一個查詢重問一次
rev = 2
picker:prerender()
picker:prerender()
check(itemsCalls == 4, "revision 變了重搜一次，之後不再重複")

-- 結果列：名稱、右側原文、第二行 fullType / 類別翻譯、圖示依 fullType 快取
picker.search:setText("thing 1")
ctx.advance(200)
picker:prerender()
ctx.advance(200)
picker:prerender()
local cell = list.pool[1]
cell:render()
local t = cell.texts
check(cell.entry == records[1] and t[1].text == "Thing 1" and t[2].text == "Orig One"
    and t[3].text == "Base.Thing1  /  FoodCat" and #cell.tex == 1 and cell.tex[1].tex.tex == "Base.Thing1",
    "列：名稱＋右側 original＋fullType / 類別翻譯（IGUI_ItemCat_）＋圖示")
local finds = findCalls
list:setItems(list:getItems())
check(findCalls == finds, "重綁不重新找圖示（依 fullType 快取）")

-- 選取：先關閉再回呼一次
list.onSelect(list, records[3], 3)
check(#picks == 1 and picks[1].rec == records[3] and picks[1].target == T and picks[1].picker == picker
    and picks[1].open == false and not picker:isOpen() and entry._focused == false,
    "選取：疊層先關（輸入框放開焦點）再回呼 onPick(target, rec, picker)")
list.onSelect(list, records[4], 4)
check(#picks == 1, "關著時再來一次選取不回呼（只回呼一次）")
check(picker:keyboardTargets() == closedTargets, "關閉後 keyboardTargets 回同一個快取空表")

-- 取消：按鈕與 cancel() 同一條路徑
picker:open()
check(picker.search:getText() == "" and picker.total == 248, "重開：搜尋框清空、重新列出全部")
picker.cancelButton:forceClick()
check(#cancels == 1 and cancels[1].target == T and cancels[1].picker == picker and cancels[1].open == false
    and not picker:isOpen() and #picks == 1, "取消鈕：先關閉再回呼 onCancel(target, picker) 一次，不回呼 onPick")

-- maxResults 與預設宇宙
local small = newPicker({ maxResults = 5 })
small:open()
check(#small.list:getItems() == 5 and small.hintText == "NOTE  [IGUI_MinidoracatUI_ItemPicker_More:5:248]",
    "maxResults＝5：只顯示 5 筆，More 帶總數")
small:dispose()
check(not small:isOpen() and #small.list:getItems() == 0, "dispose：關閉並清空清單")
local plain = UI.ItemPicker.new{ width = 600, height = 400 }
plain:open()
check(plain.total == 2 and plain.list:getItems()[1] == axe and plain.hintText == "[IGUI_MinidoracatUI_ItemPicker_Count:2]",
    "未注入 items：預設用 universe().items，沒有 note 就只有計數")
plain:close()

-- ---------- 還原 ----------
UI.Focus.clear(win)
getText = keepGetText
getTextOrNull, getItemNameFromFullType, getScriptManager = nil, nil, nil
ISPanel.drawTextureScaled = nil

return 27
