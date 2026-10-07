-- MinidoracatUI Widgets/NavList — 分組側欄導覽（API rev 17，CAPABILITIES.navList）：UI.NavList。
-- 設定視窗左欄：群組標題（小字 textMuted）＋每列 16px 圖示＋名稱（放不下截字）＋選用開關（Skin.toggle）。
--
--   UI.NavList.new{ x?, y?, width?=160, height?, theme?, font?, target?, groups, selected?, onSelect? }
--     -> 已 initialise() 的元素（consumer addChild；長清單放進 UI.ScrollPanel）。height 省略＝內容高，setGroups 時跟著變
--   groups = { { title = <已翻譯字串|nil>, items = { { id, label, icon = <Icons key|Texture|nil>,
--                switch = { get = fn() -> bool, set = fn(bool), enabled = fn() -> bool | nil } | nil,
--                enabled = fn() -> bool | nil }, ... } }, ... }
--   方法：setGroups(groups)、setSelected(id, silent)、getSelected()、getContentHeight()、refresh()
--   回呼：onSelect(target, id, nav)——選取實際改變時（點列、Enter／Space／手把 A、非 silent 的 setSelected）
--
-- 狀態快取：switch.get／switch.enabled／enabled 只在 setGroups、refresh() 之後的下一幀、以及本元件自己切開關後讀
--   （pcall；出錯或不是布林時 get 當 false、enabled 當 true）。外部改了狀態就呼叫 refresh()。
-- 點開關：enabled 時 set(not get())，不改選取；點列其他位置：選取（停用列不動）。按下與放開在同一列同一處才算。
-- 焦點（Focus 選用，本檔不 require）：整個元件是一個 `_focusKind="button"` 目標，內部游標兩種停點——列與它的開關。
--   上／下：換到上一個／下一個可用列（到邊回 false：手把移到上一個／下一個目標）；Home／End：第一／最後一個可用列；
--   右：游標在有可用開關的列上時移到開關；左：從開關回到列（其餘回 false：手把左右移到旁邊的目標）；
--   Enter／小鍵盤 Enter／Space／手把 A：在列上＝選取，在開關上＝切換。focusRect() 回目前停點（焦點框只框它，
--   ScrollPanel:scrollTo 也只捲到它），focusLabel() 只在名稱被截字時回全名；說明位置 `_focusCaptionSide="right"`。
--   游標移動時請所有捲動容器祖先 scrollTo 自己（＝游標列）。
-- prerender 零 table／closure 配置（截字只在寬度變時重算、回呼 pcall 傳參）。字串字面值只含 ASCII；本檔沒有自己的顯示文字。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Icons and UI.Text) or not ISPanel then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.navList 探測）
end

local Skin = UI.Skin
local Icons = UI.Icons

local PAD = 8             -- 左右內距
local ICON = 16
local ICON_GAP = 6
local SWITCH_W = 32       -- Skin.toggle 的寬（高固定 20）
local SWITCH_GAP = 6      -- 名稱與開關之間
local SWITCH_SLOP = 4     -- 開關左側多算幾 px 的點擊範圍
local MARK_W = 2          -- 選中列左側的 accent 記號（選中不只靠顏色）
local GROUP_GAP = 6       -- 沒有標題的群組之間
local HEADER_TOP = 12     -- 群組標題上方留白（第一個群組只留 HEADER_FIRST）
local HEADER_FIRST = 6
local DISABLED_ALPHA = 0.45

local NavList = ISPanel:derive("MinidoracatUINavList")

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function disabledColor(colors)
    return colors.textDisabled or colors.textFaint
end

-- consumer 回呼：pcall 傳參（不建 closure）；出錯或不是布林回 fallback
local function ask(fn, fallback)
    if type(fn) ~= "function" then
        return fallback
    end
    local ok, v = pcall(fn)
    if not ok or type(v) ~= "boolean" then
        return fallback
    end
    return v
end

local function readRow(row)
    row.en = ask(row.enabledFn, true)
    if row.switch then
        row.on = ask(row.switch.get, false)
        row.swEn = row.en and ask(row.switch.enabled, true)
    end
end

local function readAll(nav)
    nav._dirty = false
    local rows = nav._rows
    for i = 1, #rows do
        if not rows[i].header then
            readRow(rows[i])
        end
    end
end

local function indexOf(nav, id)
    local rows = nav._rows
    for i = 1, #rows do
        if not rows[i].header and rows[i].id == id then
            return i
        end
    end
    return nil
end

-- 元素座標 y 落在哪一列（只回項目列）
local function rowAt(nav, y)
    local rows = nav._rows
    for i = 1, #rows do
        local row = rows[i]
        if not row.header and y >= row.y and y < row.y + row.h then
            return i
        end
    end
    return nil
end

local function switchX(nav)
    return nav.width - PAD - SWITCH_W
end

local function overSwitch(nav, row, x)
    return row.switch ~= nil and x >= switchX(nav) - SWITCH_SLOP
end

-- 名稱可用寬：圖示欄之後到開關（或右內距）之前
local function labelX()
    return PAD + ICON + ICON_GAP
end

local function refit(nav, row)
    local w = nav.width
    if row.fitW == w then
        return
    end
    row.fitW = w
    if row.header then
        row.fit = UI.Text.fit(row.title, w - PAD * 2, UIFont.Small)
        return
    end
    local avail = w - labelX() - PAD - (row.switch and SWITCH_W + SWITCH_GAP or 0)
    row.fit = UI.Text.fit(row.label, avail, nav.font)
    row.cut = row.fit ~= row.label
end

-- 捲動容器祖先都捲到游標列（ScrollPanel:scrollTo 依 focusRect 只捲那一列）
local function reveal(nav)
    local p = nav.parent
    for _ = 1, 32 do
        if type(p) ~= "table" then
            return
        end
        if p._scrollPanel and p.scrollTo then
            p:scrollTo(nav)
        end
        p = p.parent
    end
end

-- 游標往 delta 方向找下一個可用列；找不到回 false（游標不動）
local function stepCursor(nav, delta)
    local rows = nav._rows
    local i = nav._cursor or (delta > 0 and 0 or #rows + 1)
    while true do
        i = i + delta
        local row = rows[i]
        if row == nil then
            return false
        end
        if not row.header and row.en then
            nav._cursor = i
            if nav._onSwitch and not row.swEn then
                nav._onSwitch = false -- 新列沒有可用開關：停在列上；有就留在開關（連續切多個圖層）
            end
            reveal(nav)
            return true
        end
    end
end

local function jump(nav, delta)
    local keep = nav._cursor
    nav._cursor = nil
    if not stepCursor(nav, delta) then
        nav._cursor = keep
    end
    return true
end

local function toggleRow(nav, i)
    local row = nav._rows[i]
    if not (row and row.switch and row.swEn) then
        return false
    end
    pcall(row.switch.set, not row.on)
    readRow(row) -- 讀回實際狀態（set 可能被 consumer 拒絕）
    return true
end

local function drawTextureIcon(el, texture, x, y, size, a)
    el:drawTextureScaled(texture, x, y, size, size, a, 1, 1, 1)
end

function NavList:prerender()
    if self.isCollapsed then
        return
    end
    if self._dirty then
        readAll(self)
    end
    local w = self.width
    local colors = self.theme.colors
    local ca = chromeAlpha(self.theme)
    local shape = Skin.shapeOf(self.theme, "control")
    local hovered = self:isMouseOver() and rowAt(self, self:getMouseY()) or nil
    local font, fontH, smallH = self.font, self._fontH, self._smallH
    local tx = labelX()
    local sx = switchX(self)
    local rows = self._rows
    for i = 1, #rows do
        local row = rows[i]
        refit(self, row)
        local y, h = row.y, row.h
        if row.header then
            local c = colors.textMuted
            self:drawText(row.fit, PAD, y + h - smallH - 2, c.r, c.g, c.b, c.a or 1, UIFont.Small)
        else
            local en = row.en
            local color = colors.text
            if row.id == self.selected then
                Skin.fill(self, 0, y, w, h, colors.selected, shape, ca)
                local accent = colors.accent
                self:drawRect(0, y + 3, MARK_W, h - 6, (accent.a or 1) * ca, accent.r, accent.g, accent.b)
                color = accent
            elseif i == hovered and en then
                Skin.fill(self, 0, y, w, h, colors.hover, shape, ca)
            end
            if not en then
                color = disabledColor(colors)
            end
            local icon = row.icon
            local iy = y + math.floor((h - ICON) / 2)
            if type(icon) == "string" then
                Icons.draw(self, icon, PAD, iy, ICON, color, color.a or 1) -- 缺圖回 false：只少圖示
            elseif icon ~= nil then
                pcall(drawTextureIcon, self, icon, PAD, iy, ICON, en and 1 or DISABLED_ALPHA)
            end
            self:drawText(row.fit, tx, y + math.floor((h - fontH) / 2), color.r, color.g, color.b, color.a or 1, font)
            if row.switch then
                local a = (row.swEn and 1 or DISABLED_ALPHA) * ca
                if not Skin.toggle(self, sx, y, SWITCH_W, h, row.on, self._toggleColors, a) then
                    -- 開關畫不出來（列太矮或繪製出錯）：方框＋勾選時實心
                    local by = y + math.floor((h - 10) / 2)
                    local b = colors.border
                    self:drawRectBorder(sx + SWITCH_W - 10, by, 10, 10, (b.a or 1) * a, b.r, b.g, b.b)
                    if row.on then
                        local on = colors.accent
                        self:drawRect(sx + SWITCH_W - 8, by + 2, 6, 6, (on.a or 1) * a, on.r, on.g, on.b)
                    end
                end
            end
        end
    end
end

function NavList:onMouseDown(x, y)
    local i = rowAt(self, y)
    self._down = i
    self._downSwitch = i ~= nil and overSwitch(self, self._rows[i], x)
    return true
end

function NavList:onMouseUp(x, y)
    local i = self._down
    self._down = nil
    if i ~= nil and rowAt(self, y) == i and overSwitch(self, self._rows[i], x) == self._downSwitch then
        local row = self._rows[i]
        if self._downSwitch then
            if toggleRow(self, i) then
                self._cursor, self._onSwitch = i, true
            end
        elseif row.en then
            self:setSelected(row.id)
            self._cursor, self._onSwitch = i, false
        end
    end
    return true
end

function NavList:onMouseUpOutside(x, y)
    self._down = nil
end

-- 重建列（cold path，可配置）。目前選取仍在就保留，否則靜默清成 nil；游標回到選取列或第一個可用列。
function NavList:setGroups(groups)
    local rows, y, first = {}, 0, true
    local rowH, smallH = self._rowH, self._smallH
    if type(groups) == "table" then
        for g = 1, #groups do
            local group = groups[g]
            if type(group) == "table" then
                local title = group.title
                if type(title) == "string" and title ~= "" then
                    local h = smallH + (first and HEADER_FIRST or HEADER_TOP)
                    rows[#rows + 1] = { header = true, title = title, y = y, h = h }
                    y = y + h
                elseif not first then
                    y = y + GROUP_GAP
                end
                first = false
                local items = group.items
                if type(items) == "table" then
                    for k = 1, #items do
                        local it = items[k]
                        if type(it) == "table" and it.id ~= nil then
                            local sw = it.switch
                            if type(sw) ~= "table" or type(sw.get) ~= "function" then
                                sw = nil
                            end
                            rows[#rows + 1] = { id = it.id, label = type(it.label) == "string" and it.label or tostring(it.id),
                                icon = it.icon, switch = sw, enabledFn = it.enabled, y = y, h = rowH }
                            y = y + rowH
                        end
                    end
                end
            end
        end
    end
    self._rows = rows
    self._contentH = y
    self._down = nil
    readAll(self)
    if self.selected ~= nil and not indexOf(self, self.selected) then
        self.selected = nil
    end
    self._onSwitch = false
    -- 游標回到選取列或第一個可用列（不捲動：重建內容時不搶容器的捲動位置）
    local cursor = self.selected ~= nil and indexOf(self, self.selected) or nil
    for i = 1, #rows do
        if cursor ~= nil then
            break
        end
        if not rows[i].header and rows[i].en then
            cursor = i
        end
    end
    self._cursor = cursor
    if self._autoHeight then
        self:setHeight(y)
    end
end

-- 未知 id 忽略；nil＝清空選取（靜默）；相同值 no-op；silent 不回呼；不受停用限制。游標跟到選取列
function NavList:setSelected(id, silent)
    if id == self.selected then
        return
    end
    local i = nil
    if id ~= nil then
        i = indexOf(self, id)
        if i == nil then
            return
        end
    end
    self.selected = id
    if i ~= nil then
        self._cursor, self._onSwitch = i, false
    end
    if id ~= nil and not silent and self.onSelect then
        self.onSelect(self.target, id, self)
    end
end

function NavList:getSelected()
    return self.selected
end

function NavList:getContentHeight()
    return self._contentH
end

-- 下一幀重讀所有 switch.get／switch.enabled／enabled
function NavList:refresh()
    self._dirty = true
end

-- ---------- 焦點（Focus 引擎呼叫） ----------

function NavList:onFocusKey(key)
    local K = Keyboard
    if key == K.KEY_UP then
        return stepCursor(self, -1)
    elseif key == K.KEY_DOWN then
        return stepCursor(self, 1)
    elseif key == K.KEY_HOME then
        return jump(self, 1)
    elseif key == K.KEY_END then
        return jump(self, -1)
    elseif key == K.KEY_RIGHT then
        local row = self._rows[self._cursor or 0]
        if row and row.swEn and not self._onSwitch then
            self._onSwitch = true
            return true
        end
        return false
    elseif key == K.KEY_LEFT then
        if self._onSwitch then
            self._onSwitch = false
            return true
        end
        return false
    elseif key == K.KEY_RETURN or key == K.KEY_NUMPADENTER or key == K.KEY_SPACE then
        local i = self._cursor
        local row = self._rows[i or 0]
        if row ~= nil then
            if self._onSwitch then
                toggleRow(self, i)
            elseif row.en then
                self:setSelected(row.id)
            end
        end
        return true
    end
    return false
end

-- 焦點框只框目前停點：列（整列寬）或它的開關；沒有可用列時回 nil（框住整個元件）
function NavList:focusRect()
    local row = self._rows[self._cursor or 0]
    if row == nil then
        return nil
    end
    if self._onSwitch and row.switch then
        return switchX(self), row.y + math.floor((row.h - 20) / 2), SWITCH_W, 20
    end
    return 0, row.y, self.width, row.h
end

-- 名稱被截字時，焦點說明給全名；其餘不畫說明（名稱已在列上）。截字以寬度快取，還沒畫過也算得出來
function NavList:focusLabel()
    local row = self._rows[self._cursor or 0]
    if row == nil then
        return nil
    end
    refit(self, row)
    return row.cut and row.label or nil
end

function NavList.new(opts)
    opts = opts or {}
    local font = opts.font or (opts.theme and opts.theme.font) or UIFont.Small
    local tm = getTextManager()
    local fontH = tm:getFontHeight(font)
    local o = ISPanel.new(NavList, opts.x or 0, opts.y or 0, opts.width or 160, opts.height or 0)
    o.background = false
    o.theme = opts.theme or UI.Theme.create()
    o.font = font
    o.target = opts.target
    o.onSelect = opts.onSelect
    o.selected = opts.selected
    o._fontH = fontH
    o._smallH = tm:getFontHeight(UIFont.Small)
    o._rowH = math.max(24, fontH + 8) -- 放得下 16px 圖示與 20px 高的開關
    o._autoHeight = opts.height == nil
    o._focusKind = "button"
    o._focusCaptionSide = "right"
    local colors = o.theme.colors
    -- 建構時一次組好（prerender 不配置）；knob 省略＝Skin 預設白
    o._toggleColors = { off = colors.well, on = colors.accent, border = colors.border }
    o:setGroups(opts.groups)
    o:initialise()
    return o
end

UI.NavList = NavList
UI.CAPABILITIES.navList = true

return NavList
