-- rev 20：ItemPicker 宇宙的 name 改用 getItemName（itemPickerVehicleClass）。車輛零件的三種車型共用一個譯名，
-- 原版背包與 getItemName 才照腳本的 VehicleType 接上車型；getItemNameFromFullType 只回譯名。
-- 契約見 smoke_harness.lua 的切片載入器註解。
local ctx = ...
local ok, UI = ctx.check, ctx.UI
print("情境 rev20：挑選器宇宙的名稱含車輛零件的車型")

local n = 0
local function check(cond, label)
    n = n + 1
    ok(cond, label)
end

check(UI.API_REVISION >= 20 and UI.CAPABILITIES.itemPickerVehicleClass == true, "rev 20：itemPickerVehicleClass 翻 true")

-- 引擎 stub（本檔自補，檔尾還原）：兩個名字分開，才分得出宇宙用的是哪一個
local plain = { ["Base.BigGasTank1"] = "Gas Tank", ["Base.BigGasTank3"] = "Gas Tank", ["Base.Axe"] = "Axe" }
local class = { ["Base.BigGasTank1"] = "Standard", ["Base.BigGasTank3"] = "Sports" }
getItemNameFromFullType = function(fullType) return plain[fullType] end
getItemName = function(fullType)
    local c = class[fullType]
    if c then return plain[fullType] .. " (" .. c .. " Vehicle)" end
    return plain[fullType]
end
local function script(fullType)
    return {
        isHidden = function() return false end,
        getObsolete = function() return false end,
        getFullName = function() return fullType end,
        getDisplayCategory = function() return "VehicleMaintenance" end,
    }
end
local scripts = { script("Base.BigGasTank1"), script("Base.BigGasTank3"), script("Base.Axe") }
getScriptManager = function()
    return { getAllItems = function()
        return { size = function() return #scripts end, get = function(_, i) return scripts[i + 1] end }
    end }
end

-- 重新載入元件：宇宙整個 session 快取，rev 11 切片已經建過一份
dofile(ctx.MOD_LUA .. "Widgets/ItemPicker.lua")
local uni = UI.ItemPicker.universe()
local std, sports, axe = uni.byType["Base.BigGasTank1"], uni.byType["Base.BigGasTank3"], uni.byType["Base.Axe"]
check(std and sports and axe and std.name == "Gas Tank (Standard Vehicle)" and sports.name == "Gas Tank (Sports Vehicle)"
    and axe.name == "Axe" and string.find(sports.search, "sports vehicle", 1, true) ~= nil
    and string.find(std.search, "sports", 1, true) == nil,
    "宇宙名稱用 getItemName：三種車型分得開、search 搜得到車型；一般物品照舊")

getItemName, getItemNameFromFullType, getScriptManager = nil, nil, nil

return n
