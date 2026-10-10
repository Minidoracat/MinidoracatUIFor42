-- MinidoracatUI Widgets/FilterBar — 篩選列（API rev 11，CAPABILITIES.filterBar）
--
-- 一組類型 chip（單選或多選，可加 extra）／關鍵字／起訖日期／排序 chip／分頁的狀態，加上自動
-- 換行版面，以及對已載入列做過濾、穩定排序、分頁的 apply。合併移植自 Economy 的
-- ECAdminFilters（單選、extra、inline 分頁、addControl）與 ECPanelFilters（多選、關鍵字、
-- 類型翻頁、strip 分頁、精簡切換），apply 移植 EC.filterPage／EC.sortSafe。
--
-- bar 本身不是元素：所有控制項都 addChild 到 opts.parent，座標是 parent 的元素座標；
-- 標籤、排序箭頭、分頁文字由使用端在 parent 的 render 裡呼叫 draw／drawPager 畫出。
-- 伺服器端篩選：kinds／dates 的 field 留 nil，apply 就不依它過濾，狀態交給使用端自己送出。
--
-- 回呼：onChange(target, bar)＝使用者改了類型／日期／關鍵字／排序／頁碼（每個動作一次；
-- 除了翻頁，都會先把頁碼設回 1）；onLayout(target, bar)＝類型翻頁、精簡切換改變了幾何。
-- 帶 silent 參數的 setter 在 silent 時不回呼；改篩選條件的 setter 一律把頁碼設回 1。
--
-- 出處：控制項全是框架元件（Controls／DatePicker）；原生只用 ISUIElement 的 addChild
-- （ISUIElement.lua:1451）、setVisible／getIsVisible（:657,676）、setX／setY／setWidth／setHeight
-- （:195,209,230,245）、drawText。per-frame 路徑（draw／drawPager／appendTargets）零 table 配置。
--
-- rev 12（CAPABILITIES.filterBarModes，全部 opt-in）：dateToggle＝起訖日期收在「自訂日期...」chip 後面；
-- kindsDropdown＝類型 chip 改成一顆單選下拉（共用選單 popup，同 DatePicker 的 popup 模式）；
-- sortInHeader＝不畫排序 chip，由 UI.TableHeader 經 getSort／toggleSort 驅動，apply 照樣依它排序。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.filterBar 探測）
end

if not (UI.Button and UI.TextField) then
    pcall(require, "MinidoracatUI/Widgets/Controls")
end
if not (UI.DateField and UI.DatePicker and UI.Date) then
    pcall(require, "MinidoracatUI/Widgets/DatePicker")
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
if not (UI.Button and UI.TextField and UI.DateField and UI.DatePicker and UI.Date) then
    return -- 缺 controls 或 datePicker：旗標維持 false
end

local Skin = UI.Skin
local Button = UI.Button
local TextField = UI.TextField
local DateField = UI.DateField
local DateMath = UI.Date
local Focus = UI.Focus -- 選用：缺席時下拉選單只能用滑鼠

local GAP = 6          -- 流式版面的水平間距與換行間距
local LABEL_GAP = 4    -- 標籤到控制項
local CHIP_PAD = 20    -- chip 自然寬＝標題寬＋20（同 Button 的 PAD_X*2）
local SORT_EXTRA = Skin.ARROW_W + 4
local DAY_MS = 86400000
local MAX_DEPTH = 32

local FilterBar = {}
FilterBar.__index = FilterBar

local function tr(key)
    return getText("IGUI_MinidoracatUI_" .. key)
end

local function measure(font, text)
    return getTextManager():MeasureStringX(font, text or "")
end

local function drawColorText(el, text, x, y, color, font)
    el:drawText(text, x, y, color.r, color.g, color.b, color.a or 1, font)
end

-- rev 11 theme.alpha：chrome（fill／border）乘它，文字不乘（約定見 V1.lua Theme 段）
local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

local function rootOf(el)
    local depth = 0
    while el.parent ~= nil and depth < MAX_DEPTH do
        el = el.parent
        depth = depth + 1
    end
    return el
end

local function fireChange(bar)
    if bar.onChange then
        bar.onChange(bar.target, bar)
    end
end

-- 幾何變了：使用端重排，焦點清單跟著更新（控制項可能換了一批）
local function fireLayout(bar)
    if bar.onLayout then
        bar.onLayout(bar.target, bar)
    end
    if UI.Focus then
        UI.Focus.invalidate(rootOf(bar.parent))
    end
end

-- ============================================================
-- 分頁
-- ============================================================

-- 分頁按鈕的啟用與分頁文字只在 setPage／apply／setEnabled／翻頁時重算，不是每幀。
-- inline 的頁碼永不截字：筆數只在 flow 留了位置（_pagerCount）且放得下時才接在後面
local function refreshPager(bar)
    local on = bar._enabled
    bar._prev:setEnabled(on and bar.page > 1)
    bar._next:setEnabled(on and bar.page < bar.pages)
    local page = getText("IGUI_MinidoracatUI_Filter_Page", tostring(bar.page), tostring(bar.pages))
    local count = getText("IGUI_MinidoracatUI_Filter_Count", tostring(bar.total))
    bar._pageStr, bar._countStr = page, count
    local line = page
    if bar._pagerCount then
        local full = page .. "  " .. count
        if measure(bar.font, full) <= (bar._pageTextW or 0) then line = full end
    end
    bar._pageLine = line
end

-- inline 分頁鈕：文字鈕放不下就換成 chevron 圖示；全名留在 fullTitle（焦點說明）與 tooltip（滑鼠）
local function setPagerIcons(bar, icons)
    if bar._pagerIcons == icons then return end
    bar._pagerIcons = icons
    local prev, nextB = bar._prev, bar._next
    prev.icon = icons and "chevronLeft" or nil
    nextB.icon = icons and "chevronRight" or nil
    prev:setTitle(icons and "" or prev.fullTitle)
    nextB:setTitle(icons and "" or nextB.fullTitle)
    prev:setTooltip(icons and prev.fullTitle or nil)
    nextB:setTooltip(icons and nextB.fullTitle or nil)
end

local function onPageClick(bar, button)
    local page = math.max(1, math.min(bar.pages, bar.page + button.internal))
    if page == bar.page then
        return
    end
    bar.page = page
    refreshPager(bar)
    fireChange(bar)
end

-- ============================================================
-- 類型
-- ============================================================

local function kindFilterOn(bar)
    if not bar.multi then
        return bar._kind ~= nil and not bar._extraSet[bar._kind]
    end
    local n = bar._selCount
    local extras = bar._extras
    for i = 1, #extras do
        if bar._selected[extras[i].internal] then
            n = n - 1
        end
    end
    return n > 0
end

-- 下拉模式（kindsDropdown）順便更新下拉鈕：標題＝選中那顆 chip 的標題、有過濾時亮起、寬度預留給最寬的
-- 選項＋箭頭（換選項不橫跳）。只在類型狀態改變時跑，不是每幀
local function refreshKindActive(bar)
    local chips = bar._kindChips
    local dd = bar._ddButton
    local natW, title = 0, nil
    for i = 1, #chips do
        local chip = chips[i]
        local on = bar:isKindSelected(chip.internal)
        chip:setActive(on)
        if on then title = chip.title end
        if chip._natW > natW then natW = chip._natW end
    end
    if dd then
        dd:setTitle(title or bar._allChip.title)
        dd:setActive(bar._kind ~= nil)
        dd._natW = natW + SORT_EXTRA
    end
end

local function refreshKindPage(bar)
    if bar._kindPrev then
        bar._kindPrev:setEnabled(bar._enabled and bar._kindStart > 1)
        bar._kindNext:setEnabled(bar._enabled and bar._kindLast < #bar._kindChips)
    end
end

local function clearSelection(bar)
    bar._selected = {}
    bar._selCount = 0
end

local function onKindClick(bar, button)
    local id = button.internal
    if not bar.multi then
        if bar._kind == id then
            return
        end
        bar._kind = id
    elseif id == nil then
        if bar._selCount == 0 then
            return
        end
        clearSelection(bar)
    elseif bar._selected[id] then
        bar._selected[id] = nil
        bar._selCount = bar._selCount - 1
    else
        bar._selected[id] = true
        bar._selCount = bar._selCount + 1
    end
    bar.page = 1
    refreshKindActive(bar)
    fireChange(bar)
end

local function onKindPage(bar, button)
    local start = math.max(1, math.min(#bar._kindChips, bar._kindStart + button.internal))
    if start == bar._kindStart then
        return
    end
    bar._kindStart = start
    fireLayout(bar)
end

-- ============================================================
-- 排序／關鍵字／日期／精簡切換
-- ============================================================

local function refreshSortActive(bar)
    local chips = bar._sortChips
    for i = 1, #chips do
        chips[i]:setActive(i == bar._sortIdx)
    end
end

-- 點作用中那顆翻轉方向；點新的一顆從 desc（最新／最大在前）開始
local function onSortClick(bar, button)
    if bar._sortIdx == button.internal then
        bar._desc = not bar._desc
    else
        bar._sortIdx = button.internal
        bar._desc = true
        refreshSortActive(bar)
    end
    bar.page = 1
    fireChange(bar)
end

-- TextField 每幀比對文字才回呼（IME 組字也涵蓋）；trim 後沒變就不算改動
local function onSearchText(field, text)
    local bar = field._filterBar
    local raw = string.match(text or "", "^%s*(.-)%s*$")
    local query = raw ~= "" and string.lower(raw) or nil
    if query == bar._query then
        return
    end
    bar._query = query
    bar.page = 1
    fireChange(bar)
end

-- ============================================================
-- rev 12：日期收合 chip（dateToggle）
-- ============================================================

-- 今年的合法日期省略年份（MM-DD），其他年份寫全；不合法回 nil（玩家還在打字：同 dateRange 不算界線）
local function shortDay(text, year)
    local y, m, d = DateMath.parse(text)
    if y == nil then
        return nil
    end
    local s = DateMath.format(y, m, d)
    return y == year and string.sub(s, 6) or s
end

-- 有界線＝精簡區間（"09-01 ~ 09-30"、"09-01 ~"、"~ 09-30"）且 chip 亮起；沒有＝「自訂日期...」。
-- 只在日期改動時跑（不是每幀）。回傳 chip 自然寬是否變了
local function refreshDateChip(bar)
    local chip = bar._dateChip
    local year = DateMath.fromMs(getTimestampMs(), DateMath.localOffsetMinutes())
    local from = shortDay(bar._from:getText(), year)
    local to = shortDay(bar._to:getText(), year)
    local title = bar._dateChipTitle
    if from and to then
        title = from .. " ~ " .. to
    elseif from then
        title = from .. " ~"
    elseif to then
        title = "~ " .. to
    end
    chip:setTitle(title)
    chip:setActive(from ~= nil or to ~= nil)
    local natW = measure(bar.font, title) + CHIP_PAD
    local resized = natW ~= chip._natW
    chip._natW = natW
    return resized
end

-- 日期文字改了之後：更新 chip；closeIfEmpty（程式清空：setDateText／reset）時兩欄都空就收回 chip。
-- 玩家在欄位裡刪光文字不收（欄位不能在打字中消失）。chip 寬度或收合狀態變了才 onLayout
local function syncDateChip(bar, closeIfEmpty)
    if not bar._dateChip then
        return
    end
    local relayout = refreshDateChip(bar)
    if closeIfEmpty and bar._datesOpen and bar._from:getText() == "" and bar._to:getText() == "" then
        bar._datesOpen = false
        bar._from:blur()
        bar._to:blur()
        relayout = true
    end
    if relayout then
        fireLayout(bar)
    end
end

local function onDateText(bar, text, field)
    bar.page = 1
    syncDateChip(bar, false)
    fireChange(bar)
end

-- 按 chip 開／收日期列；收起時欄位失焦並關掉自己的日曆，已選的區間照樣生效（chip 顯示它）
local function onDateChipClick(bar, button)
    bar._datesOpen = not bar._datesOpen
    if not bar._datesOpen then
        bar._from:blur()
        bar._to:blur()
    end
    fireLayout(bar)
end

local function onToggleClick(bar, button)
    bar:blur() -- 含自己兩個日期欄的日曆；同一個 parent 底下別條 bar 的日曆不動
    bar.filtersOpen = not bar.filtersOpen
    fireLayout(bar)
end

-- ============================================================
-- rev 12：類型下拉（kindsDropdown）的共用選單 popup
-- ============================================================
-- 同 DatePicker 的 popup 模式（ISComboBox.lua:185-215）：整個 session 一個實例、第一次開啟才建立；
-- top-level＋setCapture，外面按下即關，按在自己的下拉鈕上交給按鈕切換；錨點（下拉鈕）隱藏、停用或 bar
-- 收起就關。選項就是 bar 的類型 chip（全部＋類型＋extra；chip 本身隱藏），列文字讀 chip.title，render 零配置。

local Menu = ISPanel:derive("MinidoracatUIFilterMenu")
local MENU_PAD = 4
local MENU_ROWS = 12 -- 一次最多顯示幾列；更多就捲動（滾輪、方向鍵）
local menu     -- 唯一實例
local menuOpen -- 開著時＝menu

local function closeMenu()
    local m = menuOpen
    if m == nil then
        return
    end
    menuOpen = nil
    local button, back = m.bar._ddButton, m.kbReturn
    m.bar, m.kbReturn = nil, nil
    m:setVisible(false)
    m:removeFromUIManager()
    if Focus ~= nil then
        Focus.releaseJoypad(m)
        if back then Focus.refocus(button) end
    end
end

local function closeMenuOf(bar)
    if menuOpen ~= nil and menuOpen.bar == bar then
        closeMenu()
    end
end

-- 游標移到第 i 列（夾在範圍內），捲動讓它看得到
local function moveCursor(m, i)
    local n = #m.bar._kindChips
    if i > n then i = n end
    if i < 1 then i = 1 end
    m.cursor = i
    if i < m.first then
        m.first = i
    elseif i > m.first + m.rows - 1 then
        m.first = i - m.rows + 1
    end
end

local function rowAt(m, y)
    if y < MENU_PAD then
        return nil
    end
    local i = m.first + math.floor((y - MENU_PAD) / m.rowH)
    if i > m.first + m.rows - 1 or i > #m.bar._kindChips then
        return nil
    end
    return i
end

-- 先關再改：onChange 若重排頁面，看到的是已關閉的選單。選同一項不回呼（同 chip 單選）
local function pickRow(m, i)
    local bar = m.bar
    local chip = bar._kindChips[i]
    closeMenu()
    if chip then
        onKindClick(bar, chip)
    end
end

function Menu:anchorAlive()
    local bar = self.bar
    if bar == nil or not bar._shown then
        return false
    end
    local b = bar._ddButton
    return b:isReallyVisible() and b.enable == true
end

-- 錨在下拉鈕下方；放不下翻到上方，再夾回螢幕內（同 DatePicker Popup:place）
function Menu:place()
    local b = self.bar._ddButton
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local x, ay = b:getAbsoluteX(), b:getAbsoluteY()
    local y = ay + b.height + 2
    if y + self.height > sh then y = ay - self.height - 2 end
    if y + self.height > sh then y = sh - self.height end
    if y < 0 then y = 0 end
    if x + self.width > sw then x = sw - self.width end
    if x < 0 then x = 0 end
    self:setX(x)
    self:setY(y)
end

function Menu:prerender()
    if not self:anchorAlive() then
        closeMenu()
        return
    end
    self:place() -- 視窗拖曳或重排時跟著走
    local bar = self.bar
    local colors = bar.theme.colors
    local ca = chromeAlpha(bar.theme)
    local w, rh = self.width, self.rowH
    if self.opaque then -- rev 18：開啟時決定（下拉鈕所在視窗不透明或 opts.opaque）
        Skin.solidFill(self, 0, 0, w, self.height, colors.surface, Skin.shapeOf(bar.theme, "control"))
    else
        Skin.fill(self, 0, 0, w, self.height, colors.surface, Skin.shapeOf(bar.theme, "control"), ca)
    end
    Skin.border(self, 0, 0, w, self.height, colors.border, Skin.shapeOf(bar.theme, "control"), ca)
    local hover = self:isMouseOver() and rowAt(self, self:getMouseY()) or nil
    local chips = bar._kindChips
    local ty = math.floor((rh - bar._fontH) / 2)
    local y = MENU_PAD
    for i = self.first, math.min(#chips, self.first + self.rows - 1) do
        local chip = chips[i]
        if i == hover or i == self.cursor then
            Skin.fill(self, 1, y, w - 2, rh, colors.selected, "rect", ca)
        end
        drawColorText(self, chip.title, MENU_PAD + 6, y + ty,
            bar:isKindSelected(chip.internal) and colors.accent or colors.text, bar.font)
        y = y + rh
    end
end

function Menu:render()
end

function Menu:onMouseDown(x, y)
    if self:isMouseOver() then
        return true -- 裡面：不漏到頁面
    end
    local b = self.bar and self.bar._ddButton
    if b and b:isReallyVisible() and b:isMouseOver() then
        return false -- 自己的下拉鈕：交給它的 click 切換開關
    end
    closeMenu()
    return false
end

function Menu:onMouseUp(x, y)
    if menuOpen ~= self or not self:isMouseOver() then
        return false
    end
    local i = rowAt(self, y)
    if i then
        pickRow(self, i)
    end
    return true
end

-- 滾輪往上（del < 0）往前捲
function Menu:onMouseWheel(del)
    if menuOpen ~= self then
        return false
    end
    local last = math.max(1, #self.bar._kindChips - self.rows + 1)
    self.first = math.max(1, math.min(last, self.first + (del < 0 and -1 or 1)))
    return true
end

-- 鍵盤：上下／PgUp／PgDn／Home／End 移游標，Enter／Space 選，Esc／Tab 關（焦點框回下拉鈕）
local function menuKey(m, key)
    local k = Keyboard
    if key == k.KEY_ESCAPE or key == k.KEY_TAB then closeMenu(); return true end
    if key == k.KEY_RETURN or key == k.KEY_NUMPADENTER or key == k.KEY_SPACE then pickRow(m, m.cursor); return true end
    if key == k.KEY_UP then moveCursor(m, m.cursor - 1); return true end
    if key == k.KEY_DOWN then moveCursor(m, m.cursor + 1); return true end
    if key == k.KEY_PRIOR then moveCursor(m, m.cursor - m.rows); return true end
    if key == k.KEY_NEXT then moveCursor(m, m.cursor + m.rows); return true end
    if key == k.KEY_HOME then moveCursor(m, 1); return true end
    if key == k.KEY_END then moveCursor(m, #m.bar._kindChips); return true end
    return false
end

-- key 事件只在 Focus 存在時要（setWantKeyEvents）；popup 是 top-level，比視窗先被問
function Menu:onKeyPress(key)
    if menuOpen ~= self then return end
    Focus.pressed(key)
    if menuKey(self, key) then Focus.eat(key) end
end

function Menu:onKeyRepeat(key)
    if menuOpen ~= self then return end
    local k = Keyboard
    if key ~= k.KEY_UP and key ~= k.KEY_DOWN and key ~= k.KEY_PRIOR and key ~= k.KEY_NEXT then return end
    if not Focus.repeatDue(key) then return end
    if menuKey(self, key) then Focus.eat(key) end
end

function Menu:onKeyRelease(key)
    Focus.release(key)
end

function Menu:isKeyConsumed(key)
    return Focus.consumed(key)
end

-- 手把：A＝Enter、B＝Esc、十字鍵上下＝方向鍵
function Menu:onJoypadDown(button, joypadData)
    if menuOpen ~= self or Joypad == nil then return end
    if button == Joypad.AButton then menuKey(self, Keyboard.KEY_RETURN)
    elseif button == Joypad.BButton then menuKey(self, Keyboard.KEY_ESCAPE) end
end
function Menu:onJoypadDirUp() if menuOpen == self then menuKey(self, Keyboard.KEY_UP) end end
function Menu:onJoypadDirDown() if menuOpen == self then menuKey(self, Keyboard.KEY_DOWN) end end
function Menu:onJoypadBeforeDeactivate() closeMenu() end

local function openMenu(bar)
    closeMenu()
    if menu == nil then
        menu = ISPanel.new(Menu, 0, 0, 100, 100)
        menu.background = false
        menu:initialise()
        menu:setCapture(true)                -- 外面的點擊先到這裡，才能關閉
        menu:setWantKeyEvents(Focus ~= nil)  -- key 事件只派給 top-level
    end
    local m = menu
    local b = bar._ddButton
    local chips = bar._kindChips
    local rh = bar._fontH + 8
    local w, cursor = b.width, 1
    for i = 1, #chips do
        local cw = chips[i]._natW + MENU_PAD * 2
        if cw > w then w = cw end
        if bar:isKindSelected(chips[i].internal) then cursor = i end
    end
    local fit = math.floor((getCore():getScreenHeight() - MENU_PAD * 2) / rh)
    m.bar, m.rowH, m.first = bar, rh, 1
    -- rev 18：下拉鈕所在頂層視窗不透明或 opts.opaque＝選單也不透明（只在開啟時沿 parent 找一次）
    m.opaque = bar._popupOpaque or rootOf(b).opaque == true
    m.rows = math.max(1, math.min(#chips, MENU_ROWS, fit))
    moveCursor(m, cursor)
    -- 記住是不是鍵盤開的：只有那樣關閉時才把焦點框還給下拉鈕
    m.kbReturn = Focus ~= nil and Focus.focused() == b
    m:setWidth(w)
    m:setHeight(m.rows * rh + MENU_PAD * 2)
    m:place()
    m:setVisible(true)
    m:addToUIManager()
    m:setAlwaysOnTop(true) -- 實例化（addToUIManager）之後才有效
    m:bringToTop()
    menuOpen = m
    -- 下拉鈕所在的視窗正持有手把焦點：選單借走，關閉時歸還
    if Focus ~= nil and Focus.holdsJoypad(rootOf(b)) then Focus.takeJoypad(m, 0) end
end

-- 同一顆再按＝關閉
local function onDropdownClick(bar, button)
    if menuOpen ~= nil and menuOpen.bar == bar then
        closeMenu()
    else
        openMenu(bar)
    end
end

-- ============================================================
-- 建構
-- ============================================================

local function newChip(bar, title, width, onClick, internal, group, label)
    local chip = Button.new{
        width = width, height = bar.height, title = title, style = "chip",
        theme = bar.theme, font = bar.font, target = bar, onClick = onClick,
    }
    chip.internal = internal
    chip._focusGroup = group
    chip._focusLabel = label
    chip._natW = width
    bar.parent:addChild(chip)
    return chip
end

-- opts 見 docs/ARCHITECTURE.md §3.13：parent（必填）、theme?、font?、height?、target?、onChange、
-- onLayout?、kinds?、search?、dates?、sorts?、perPage?=25、pager?="strip"|"inline"；
-- rev 12：dateToggle?、kindsDropdown?、sortInHeader?；rev 18：opaque?（類型選單與兩個月曆不透明，
-- 省略＝看 parent 所在頂層視窗的 opaque）
function FilterBar.new(opts)
    local parent = opts.parent
    local font = opts.font or UIFont.Small
    local theme = opts.theme or UI.Theme.create()
    local fontH = getTextManager():getFontHeight(font)
    local bar = setmetatable({
        parent = parent, theme = theme, font = font, _fontH = fontH,
        height = opts.height or (fontH + 10),
        target = opts.target or parent,
        onChange = opts.onChange, onLayout = opts.onLayout,
        _popupOpaque = opts.opaque == true,
        perPage = math.max(1, math.floor(tonumber(opts.perPage) or 25)),
        inline = opts.pager == "inline",
        page = 1, pages = 1, total = 0, pagerY = 0,
        filtersOpen = false,
        _enabled = true, _shown = false, _pagerShown = false,
        _kind = nil, _selected = {}, _selCount = 0, _extraSet = {}, _extras = {},
        _kindIds = {}, _kindPool = {}, _kindChips = {}, _kindCtl = {},
        _kindStart = 1, _kindLast = 0,
        _sortChips = {}, _sortIdx = 1, _desc = true,
        _query = nil,
        _controls = {}, _ctlDescs = {},
        -- draw 用的標籤槽（layout 時覆寫，不配置）
        _lblText = {}, _lblX = {}, _lblY = {}, _lblN = 0,
        -- 焦點 group token（Window 自動目標以同值併組）
        _kindToken = {}, _sortToken = {}, _pagerToken = {},
    }, FilterBar)

    local kinds = opts.kinds
    if kinds then
        bar.kindField = kinds.field
        bar.kindLabel = kinds.label
        bar.dropdown = opts.kindsDropdown == true
        bar.multi = kinds.multi == true and not bar.dropdown -- 下拉只做單選
        if kinds.title ~= false then
            bar.kindTitle = kinds.title or tr("Filter_Kind")
        end
        local groupLabel = bar.kindTitle or tr("Filter_Kind")
        local allTitle = tr("Filter_All")
        bar._allChip = newChip(bar, allTitle, measure(font, allTitle) + CHIP_PAD, onKindClick, nil,
            bar._kindToken, groupLabel)
        for _, e in ipairs(kinds.extra or {}) do
            local title = e.label or tostring(e.id)
            bar._extras[#bar._extras + 1] = newChip(bar, title, measure(font, title) + CHIP_PAD, onKindClick,
                e.id, bar._kindToken, groupLabel)
            bar._extraSet[e.id] = true
        end
        local pageW = math.max(26, bar.height)
        bar._kindPrev = newChip(bar, "", pageW, onKindPage, -1, bar._kindToken, tr("Filter_Prev"))
        bar._kindNext = newChip(bar, "", pageW, onKindPage, 1, bar._kindToken, tr("Filter_Next"))
        bar._kindPrev.icon, bar._kindNext.icon = "chevronLeft", "chevronRight"
        bar._kindPrev:setTooltip(tr("Filter_Prev"))
        bar._kindNext:setTooltip(tr("Filter_Next"))
        bar._kindPrev:setVisible(false)
        bar._kindNext:setVisible(false)
        bar._kindDesc = { kind = "group", controls = bar._kindCtl, label = groupLabel }
        if bar.dropdown then
            -- chip 照樣建（選單的選項與標題來源），但永遠隱藏；列上只有這顆下拉鈕
            bar._ddButton = newChip(bar, allTitle, measure(font, allTitle) + CHIP_PAD + SORT_EXTRA,
                onDropdownClick, nil, nil, groupLabel)
            bar._ddDesc = { kind = "button", control = bar._ddButton, label = groupLabel }
            bar._allChip:setVisible(false)
            for i = 1, #bar._extras do
                bar._extras[i]:setVisible(false)
            end
        end
        bar:setKinds(bar._kindIds) -- 只有「全部」＋extra
    end

    local search = opts.search
    if search then
        bar.searchField = search.field or "searchText"
        bar._searchLabel = tr("Filter_Search")
        local field = TextField.new{
            width = 200, height = bar.height, placeholder = search.placeholder,
            theme = theme, font = font, onChange = onSearchText,
        }
        field._filterBar = bar
        field._focusLabel = bar._searchLabel
        parent:addChild(field)
        bar._search = field
        bar._searchDesc = { kind = "entry", control = field._entry, frame = field, label = bar._searchLabel }
    end

    local dates = opts.dates
    if dates then
        bar.dateField = dates.field
        bar._fromLabel = dates.fromLabel or tr("Filter_From")
        bar._toLabel = dates.toLabel or tr("Filter_To")
        bar._from = DateField.new{ height = bar.height, theme = theme, font = font, target = bar, onChange = onDateText,
            opaque = opts.opaque }
        bar._to = DateField.new{ height = bar.height, theme = theme, font = font, target = bar, onChange = onDateText,
            opaque = opts.opaque }
        parent:addChild(bar._from)
        parent:addChild(bar._to)
        -- 框架 Window 的自動目標讀 _focusLabel：日期輸入框的說明用起訖標籤
        bar._from._text._focusLabel = bar._fromLabel
        bar._to._text._focusLabel = bar._toLabel
        if opts.dateToggle then
            local title = tr("Filter_CustomDate")
            bar._dateChipTitle = title
            bar._datesOpen = false
            bar._dateChip = newChip(bar, title, measure(font, title) + CHIP_PAD, onDateChipClick)
            bar._dateChipDesc = { kind = "button", control = bar._dateChip, label = title }
            bar._from:setVisible(false)
            bar._to:setVisible(false)
            refreshDateChip(bar)
        end
    end

    local sorts = opts.sorts
    if sorts and #sorts > 0 then
        bar.sorts = sorts
        bar.sortInHeader = opts.sortInHeader == true
        if not bar.sortInHeader then
            bar._sortLabel = tr("Filter_Sort")
            for i, s in ipairs(sorts) do
                local title = s.label or tostring(s.id)
                bar._sortChips[i] = newChip(bar, title, measure(font, title) + CHIP_PAD + SORT_EXTRA, onSortClick,
                    i, bar._sortToken, bar._sortLabel)
            end
            refreshSortActive(bar)
            bar._sortDesc = { kind = "group", controls = bar._sortChips, label = bar._sortLabel }
        end
    end

    local pageLabel = tr("Filter_PageNav")
    local prevTitle, nextTitle = tr("Filter_Prev"), tr("Filter_Next")
    bar._prev = newChip(bar, prevTitle, measure(font, prevTitle) + CHIP_PAD, onPageClick, -1, bar._pagerToken, pageLabel)
    bar._next = newChip(bar, nextTitle, measure(font, nextTitle) + CHIP_PAD, onPageClick, 1, bar._pagerToken, pageLabel)
    bar._prev.fullTitle, bar._next.fullTitle = prevTitle, nextTitle
    bar._prev:setVisible(false)
    bar._next:setVisible(false)
    bar._pagerDesc = { kind = "group", controls = { bar._prev, bar._next }, label = pageLabel }
    -- inline 分頁文字以最寬的形式預留，換頁不會讓整列重排；放不下時退成只有頁碼、圖示鈕
    bar._pageSampleOnly = getText("IGUI_MinidoracatUI_Filter_Page", "99", "99")
    bar._pageSample = bar._pageSampleOnly .. "  " .. getText("IGUI_MinidoracatUI_Filter_Count", "9999")
    bar._pagerIconW = math.max(26, bar.height)
    bar._pagerIcons, bar._pagerCount = false, true
    refreshPager(bar)
    return bar
end

-- ============================================================
-- 類型狀態
-- ============================================================

-- 明確指定類型集合（順序由使用端決定）；「全部」固定第一顆、extra 排最後。集合沒變回 false。
-- 已選但被移除的類型直接丟掉，有丟掉就靜默把頁碼設回 1。chip 物件池只增不減，多的停放隱藏。
function FilterBar:setKinds(ids)
    if not self._allChip then
        return false
    end
    local known = self._kindIds
    local n = #ids
    local same = self._kindChips[1] ~= nil and n == #known
    if same then
        for i = 1, n do
            if ids[i] ~= known[i] then
                same = false
                break
            end
        end
    end
    if same then
        return false
    end
    if ids ~= known then
        for i = 1, n do
            known[i] = ids[i]
        end
        for i = #known, n + 1, -1 do
            known[i] = nil
        end
    end
    local pool = self._kindPool
    local label = self.kindLabel
    for i = 1, n do
        local id = known[i]
        local title = label and label(id) or tostring(id)
        local chip = pool[i]
        if chip == nil then
            chip = newChip(self, title, 0, onKindClick, id, self._kindToken, self._kindDesc.label)
            chip:setEnabled(self._enabled)
            chip:setVisible(self._ddButton == nil) -- 下拉模式的 chip 只當選項來源，永遠隱藏
            pool[i] = chip
        end
        chip.internal = id
        chip:setTitle(title)
        chip._natW = measure(self.font, title) + CHIP_PAD
        chip:setWidth(chip._natW)
    end
    for i = n + 1, #pool do
        pool[i].internal = nil
        pool[i]:setVisible(false)
    end
    local chips = self._kindChips
    chips[1] = self._allChip
    for i = 1, n do
        chips[i + 1] = pool[i]
    end
    local extras = self._extras
    for i = 1, #extras do
        chips[n + 1 + i] = extras[i]
    end
    for i = #chips, n + 1 + #extras + 1, -1 do
        chips[i] = nil
    end

    -- 被移除的已選類型丟掉（extra 不會被移除）
    local present = {}
    for i = 1, n do
        present[known[i]] = true
    end
    local dropped = false
    if self.multi then
        local stale = {}
        for id in pairs(self._selected) do
            if not present[id] and not self._extraSet[id] then
                stale[#stale + 1] = id
            end
        end
        for i = 1, #stale do
            self._selected[stale[i]] = nil
            self._selCount = self._selCount - 1
            dropped = true
        end
    elseif self._kind ~= nil and not present[self._kind] and not self._extraSet[self._kind] then
        self._kind = nil
        dropped = true
    end
    if dropped then
        self.page = 1
    end
    self._kindStart = math.min(self._kindStart, #chips)
    refreshKindActive(self)
    return true
end

-- 從 rows[kinds.field] 依首次出現的順序收集類型（nil 與空字串略過），再交給 setKinds
function FilterBar:syncKinds(rows)
    local field = self.kindField
    local order, seen = {}, {}
    if field ~= nil then
        for i = 1, #rows do
            local k = rows[i][field]
            if k ~= nil and k ~= "" and not seen[k] then
                seen[k] = true
                order[#order + 1] = k
            end
        end
    end
    return self:setKinds(order)
end

-- 單選用：nil＝「全部」（多選模式一律回 nil，改用 isKindSelected）
function FilterBar:getKind()
    return self._kind
end

-- id 為 nil 問的是「全部」
function FilterBar:isKindSelected(id)
    if not self.multi then
        return self._kind == id
    end
    if id == nil then
        return self._selCount == 0
    end
    return self._selected[id] == true
end

-- 單選：選那一顆；多選：清空後只放這一顆（nil＝全部）
function FilterBar:setKind(id, silent)
    if self.multi then
        if (id == nil and self._selCount == 0) or (id ~= nil and self._selCount == 1 and self._selected[id]) then
            return
        end
        clearSelection(self)
        if id ~= nil then
            self._selected[id] = true
            self._selCount = 1
        end
    else
        if self._kind == id then
            return
        end
        self._kind = id
    end
    self.page = 1
    refreshKindActive(self)
    if not silent then
        fireChange(self)
    end
end

-- ============================================================
-- 其他狀態
-- ============================================================

-- 已 trim 並轉小寫；空白＝nil
function FilterBar:getQuery()
    return self._query
end

function FilterBar:getDateText()
    if not self._from then
        return "", ""
    end
    return self._from:getText(), self._to:getText()
end

-- 兩欄都清空時，dateToggle 的日期列收回「自訂日期...」chip（已經是空的也收）
function FilterBar:setDateText(from, to, silent)
    if not self._from then
        return
    end
    from, to = from or "", to or ""
    local changed = from ~= self._from:getText() or to ~= self._to:getText()
    if changed then
        self._from:setText(from)
        self._to:setText(to)
        self.page = 1
    end
    syncDateChip(self, true)
    if changed and not silent then
        fireChange(self)
    end
end

-- 本機時區的 [起日 00:00, 迄日隔天 00:00)；格式不對的日期不算界線（玩家可能還在打字）
function FilterBar:dateRange()
    if not self._from then
        return nil, nil
    end
    local offset = DateMath.localOffsetMinutes()
    local from = DateMath.dayStart(self._from:getText(), offset)
    local to = DateMath.dayStart(self._to:getText(), offset)
    return from, to and (to + DAY_MS) or nil
end

function FilterBar:getSort()
    local s = self.sorts and self.sorts[self._sortIdx]
    return s and s.id, self._desc
end

function FilterBar:setSort(id, desc, silent)
    local sorts = self.sorts
    if not sorts then
        return
    end
    local idx = nil
    for i = 1, #sorts do
        if sorts[i].id == id then
            idx = i
            break
        end
    end
    desc = desc ~= false
    if idx == nil or (idx == self._sortIdx and desc == self._desc) then
        return
    end
    self._sortIdx, self._desc = idx, desc
    refreshSortActive(self)
    self.page = 1
    if not silent then
        fireChange(self)
    end
end

-- rev 12 sortInHeader：可直接當 UI.TableHeader 的 onSort（target＝bar，sort＝FilterBar.getSort）。
-- key＝nil（點在欄外或不可排序欄）不動；點作用中那欄翻轉方向，點新的一欄從 desc 開始（同排序 chip）
function FilterBar:toggleSort(key)
    if key == nil then
        return
    end
    local id, desc = self:getSort()
    if id == key then
        self:setSort(key, not desc)
    else
        self:setSort(key, true)
    end
end

-- 伺服器分頁時由使用端寫回
function FilterBar:setPage(page, pages, total)
    self.page = page
    self.pages = pages or self.pages
    self.total = total or self.total
    refreshPager(self)
end

-- 類型回「全部」、清空日期（dateToggle 收回 chip）與關鍵字、排序回預設 desc、頁碼 1
function FilterBar:reset(silent)
    self._kind = nil
    clearSelection(self)
    if self._allChip then
        refreshKindActive(self)
    end
    if self._from then
        self._from:setText("")
        self._to:setText("")
        syncDateChip(self, true)
    end
    if self._search then
        self._search:setText("")
        self._query = nil
    end
    if self.sorts then
        self._sortIdx, self._desc = 1, true
        refreshSortActive(self)
    end
    self.page = 1
    refreshPager(self)
    if not silent then
        fireChange(self)
    end
end

-- ============================================================
-- apply：關鍵字 → 類型（不含 extra）→ 日期 [from, to+1日) → 排序 → 分頁
-- ============================================================

local function sortValue(row, field)
    if type(field) == "function" then
        return field(row)
    end
    return row[field]
end

-- 規則同 EC.filterPage：nil 排最後；型別不同轉字串比；字串一律轉小寫；相等不算在前
local function before(av, bv, desc)
    if av == nil or bv == nil then
        return av ~= nil and bv == nil
    end
    if type(av) ~= type(bv) then
        av, bv = tostring(av), tostring(bv)
    end
    if type(av) == "string" then
        av, bv = string.lower(av), string.lower(bv)
    end
    if av == bv then
        return false
    end
    if desc then
        return av > bv
    end
    return av < bv
end

-- ponytail: O(n²) insertion sort; rows are a reply of a few hundred lines
local function sortRows(rows, field, desc)
    for i = 2, #rows do
        local v = rows[i]
        local vk = sortValue(v, field)
        local j = i - 1
        while j >= 1 and before(vk, sortValue(rows[j], field), desc) do
            rows[j + 1] = rows[j]
            j = j - 1
        end
        rows[j + 1] = v
    end
end

-- 依目前狀態過濾、排序、分頁已載入的列；更新 page／pages／total，不觸發 onChange
function FilterBar:apply(rows)
    local query = self._query
    local searchField = self.searchField
    local kindField = self.kindField
    local kindOn = kindField ~= nil and self._allChip ~= nil and kindFilterOn(self)
    local single, selected, extraSet = self._kind, self._selected, self._extraSet
    local multi = self.multi
    local timeField = self.dateField
    local fromMs, toMs = nil, nil
    if timeField ~= nil then
        fromMs, toMs = self:dateRange()
    end
    local out = {}
    for i = 1, rows and #rows or 0 do
        local row = rows[i]
        local ok = true
        if query ~= nil then
            local hay = row[searchField]
            ok = type(hay) == "string" and string.find(hay, query, 1, true) ~= nil
        end
        if ok and kindOn then
            local k = row[kindField]
            if multi then
                ok = selected[k] == true and not extraSet[k]
            else
                ok = k == single
            end
        end
        if ok and (fromMs or toMs) then
            local t = tonumber(row[timeField])
            ok = t ~= nil and (fromMs == nil or t >= fromMs) and (toMs == nil or t < toMs)
        end
        if ok then
            out[#out + 1] = row
        end
    end
    local s = self.sorts and self.sorts[self._sortIdx]
    if s and s.field ~= nil then
        sortRows(out, s.field, self._desc)
    end
    local total = #out
    local perPage = self.perPage
    local pages = math.max(1, math.ceil(total / perPage))
    local page = math.max(1, math.min(pages, math.floor(tonumber(self.page) or 1)))
    local pageRows = {}
    for i = (page - 1) * perPage + 1, math.min(total, page * perPage) do
        pageRows[#pageRows + 1] = out[i]
    end
    self.page, self.pages, self.total = page, pages, total
    refreshPager(self)
    return pageRows
end

-- ============================================================
-- 版面
-- ============================================================

local function addLabel(bar, text, x, y)
    local n = bar._lblN + 1
    bar._lblN = n
    bar._lblText[n], bar._lblX[n], bar._lblY[n] = text, x, y
end

local function showAll(list, visible)
    for i = 1, #list do
        list[i]:setVisible(visible)
    end
end

-- 單一換行流：關鍵字、類型、起訖日期、排序、addControl、inline 分頁。不 blur（layoutViewport
-- 的量測趟也走這裡）。回傳最後一列的底邊。
local function flow(bar, x, y, right, visible)
    local band = bar.height
    local fontH = bar._fontH
    local font = bar.font
    local ty = math.floor((band - fontH) / 2)
    local cx, cy = x, y
    bar._lblN = 0
    bar._shown = visible

    local function place(w)
        if cx > x and cx + w > right then
            cx = x
            cy = cy + band + GAP
        end
        local at = cx
        cx = cx + w + GAP
        return at
    end
    local function midY(el)
        return cy + math.floor((band - el.height) / 2)
    end
    local function labelAt(text)
        local at = place(measure(font, text))
        addLabel(bar, text, at, cy + ty)
    end
    local function labelled(label, el)
        local labelW = label and (measure(font, label) + LABEL_GAP) or 0
        local at = place(labelW + el.width)
        if label then
            addLabel(bar, label, at, cy + ty)
        end
        el:setVisible(visible)
        el:setX(at + labelW)
        el:setY(midY(el))
    end

    -- 關鍵字最先：玩家最常找它，打字時標籤仍看得到（placeholder 一有字就消失）
    local search = bar._search
    if search then
        search:setWidth(math.max(140, math.min(280, math.floor((right - x) * 0.32))))
        labelled(bar._searchLabel, search)
    end

    local chips = bar._kindChips
    local ctl = bar._kindCtl
    local nCtl = 0
    if bar._ddButton then
        -- 下拉模式：chip 只當選項來源（永遠隱藏），列上只有「類型」標籤＋下拉鈕
        showAll(chips, false)
        bar._kindPrev:setVisible(false)
        bar._kindNext:setVisible(false)
        local dd = bar._ddButton
        dd:setWidth(dd._natW)
        labelled(bar.kindTitle, dd)
    elseif bar._allChip then
        local title = bar.kindTitle
        local titleW = title and (measure(font, title) + GAP) or 0
        local natural = titleW
        for i = 1, #chips do
            natural = natural + chips[i]._natW + GAP
        end
        local prev, nextB = bar._kindPrev, bar._kindNext
        local paged = natural > right - x
        prev:setVisible(visible and paged)
        nextB:setVisible(visible and paged)
        if paged then
            -- 溢出：用 < > 翻頁，類型佔到該列結尾，後面的控制項從下一列開始
            local countText = nil
            if bar.multi and bar._selCount > 0 then
                countText = "(" .. tostring(bar._selCount) .. ")"
            end
            local minimum = titleW + prev.width + nextB.width + measure(font, "...") + 28
                + (countText and (measure(font, countText) + GAP) or 0)
            if cx > x and right - cx < minimum then
                cx = x
                cy = cy + band + GAP
            end
            if title then
                labelAt(title)
            end
            if countText then
                labelAt(countText)
            end
            prev:setX(cx)
            prev:setY(midY(prev))
            cx = cx + prev.width + GAP
            nextB:setX(right - nextB.width)
            nextB:setY(prev.y)
            nCtl = 1
            ctl[1] = prev
            local limit, last, full = nextB.x - GAP, 0, false
            local start = bar._kindStart
            for i = 1, #chips do
                local b = chips[i]
                if i >= start and last > 0 and cx + b._natW > limit then
                    full = true
                end
                local show = i >= start and not full
                b:setVisible(visible and show)
                if show then
                    b:setWidth(math.max(1, math.min(b._natW, limit - cx)))
                    b:setX(cx)
                    b:setY(midY(b))
                    cx, last = cx + b.width + GAP, i
                    nCtl = nCtl + 1
                    ctl[nCtl] = b
                end
            end
            nCtl = nCtl + 1
            ctl[nCtl] = nextB
            bar._kindLast = last
            cx, cy = x, cy + band + GAP
        else
            bar._kindStart = 1
            bar._kindLast = #chips
            if title then
                labelAt(title)
            end
            for i = 1, #chips do
                local b = chips[i]
                b:setVisible(visible)
                b:setWidth(b._natW)
                b:setX(place(b.width))
                b:setY(midY(b))
                nCtl = nCtl + 1
                ctl[nCtl] = b
            end
        end
        refreshKindPage(bar)
    end
    for i = #ctl, nCtl + 1, -1 do
        ctl[i] = nil
    end

    local dateChip = bar._dateChip
    if dateChip then
        -- dateToggle：日期欄收在 chip 後面，打開時在整個流的最後自成一列（見檔尾）
        dateChip:setVisible(visible)
        dateChip:setWidth(dateChip._natW)
        dateChip:setX(place(dateChip.width))
        dateChip:setY(midY(dateChip))
    elseif bar._from then
        labelled(bar._fromLabel, bar._from)
        labelled(bar._toLabel, bar._to)
    end

    local sortChips = bar._sortChips
    if #sortChips > 0 then
        local labelW = measure(font, bar._sortLabel) + GAP
        local width = labelW - GAP
        for i = 1, #sortChips do
            width = width + GAP + sortChips[i]._natW
        end
        local at = place(width)
        addLabel(bar, bar._sortLabel, at, cy + ty)
        at = at + labelW
        for i = 1, #sortChips do
            local b = sortChips[i]
            b:setVisible(visible)
            b:setWidth(b._natW)
            b:setX(at)
            b:setY(midY(b))
            at = at + b.width + GAP
        end
    end

    local controls = bar._controls
    for i = 1, #controls do
        local c = controls[i]
        labelled(c._filterLabel, c)
    end

    local prev, nextB = bar._prev, bar._next
    if bar.inline then
        -- 什麼都不截字：文字鈕＋頁碼＋筆數 → 圖示鈕＋頁碼＋筆數 → 圖示鈕＋頁碼（筆數是次要資訊）。
        -- 先試本列剩下的空間，三種都放不下才換到新的一列重試（換列會吃掉清單一列高）
        local textW = prev._natW + 4 + nextB._natW
        local iconW = bar._pagerIconW * 2 + 4
        local fullW, pageW = measure(font, bar._pageSample), measure(font, bar._pageSampleOnly)
        local icons, counted = true, false
        for room = right - cx, right - x, math.max(1, cx - x) do
            if fullW + 8 + textW <= room then icons, counted = false, true break end
            if fullW + 8 + iconW <= room then icons, counted = true, true break end
            if pageW + 8 + iconW <= room then break end
        end
        setPagerIcons(bar, icons)
        bar._pagerCount = counted
        bar._pageTextW = counted and fullW or pageW
        local btnW = icons and bar._pagerIconW or nil
        place(bar._pageTextW + 8 + (icons and iconW or textW))
        nextB:setWidth(btnW or nextB._natW)
        nextB:setX(right - nextB.width)
        nextB:setY(midY(nextB))
        prev:setWidth(btnW or prev._natW)
        prev:setX(nextB.x - 4 - prev.width)
        prev:setY(nextB.y)
        prev:setVisible(visible)
        nextB:setVisible(visible)
        bar._pageTextRight, bar._pageTextY = prev.x - 8, cy + ty
        refreshPager(bar)
    end
    if dateChip then
        if bar._datesOpen then
            if cx > x then
                cx = x
                cy = cy + band + GAP
            end
            labelled(bar._fromLabel, bar._from)
            labelled(bar._toLabel, bar._to)
        else
            bar._from:setVisible(false)
            bar._to:setVisible(false)
        end
    end
    if not visible then
        bar._lblN = 0
    end
    return cy + band
end

-- visible=false 會隱藏全部並 blur；回傳最後一列的底邊
function FilterBar:layout(x, y, right, visible)
    if not visible then
        self:blur()
    end
    return flow(self, x, y, right, visible)
end

-- 精簡切換：篩選列把清單擠到比 minListH 還矮時，篩選列與清單改成二選一，由右上的切換鈕
-- （標題 Filter_Open／Filter_Results，放在 toggleY）切換。回傳 listY, listH, showingRecords。
function FilterBar:layoutViewport(x, y, right, bottom, visible, toggleY, minListH)
    local pagerH = self.height
    local filterBottom = flow(self, x, y, right, false) + GAP
    local compact = bottom - pagerH - 2 - filterBottom < (minListH or 0)
    local showingFilters = visible and (not compact or self.filtersOpen)
    local showingRecords = visible and (not compact or not self.filtersOpen)
    self:layout(x, y, right, showingFilters)
    if visible and not self._toggle then
        self._toggle = Button.new{
            title = tr("Filter_Open"), style = "chip", height = self.height,
            theme = self.theme, font = self.font, target = self, onClick = onToggleClick,
        }
        self._toggle:setEnabled(self._enabled)
        self._toggleDesc = { kind = "button", control = self._toggle, label = nil }
        self.parent:addChild(self._toggle)
    end
    local toggle = self._toggle
    if toggle then
        toggle:setTitle(tr((compact and self.filtersOpen) and "Filter_Results" or "Filter_Open"))
        toggle:setVisible(visible and compact)
        toggle:setX(right - toggle.width)
        toggle:setY(toggleY or y)
    end
    local listY = compact and y or filterBottom
    self:layoutPager(x, bottom - pagerH, right, showingRecords, pagerH)
    return listY, math.max(0, bottom - pagerH - 2 - listY), showingRecords
end

-- strip 模式：頁碼文字在左、兩顆分頁鈕接在最寬頁碼之後、筆數靠右
function FilterBar:layoutPager(x, y, right, visible, height)
    height = height or self.height
    self._pagerShown = visible
    self.pagerY = y
    self._pagerX, self._pagerRight, self._pagerH = x, right, height
    local cx = x + measure(self.font, getText("IGUI_MinidoracatUI_Filter_Page", "99", "99")) + 10
    local prev, nextB = self._prev, self._next
    prev:setVisible(visible)
    prev:setWidth(prev._natW)
    prev:setX(cx)
    prev:setY(y + math.floor((height - prev.height) / 2))
    cx = cx + prev.width + GAP
    nextB:setVisible(visible)
    nextB:setWidth(nextB._natW)
    nextB:setX(cx)
    nextB:setY(prev.y)
end

-- ============================================================
-- 繪製（per-frame，零配置）
-- ============================================================

function FilterBar:draw(el)
    if not self._shown then
        return
    end
    local colors = self.theme.colors
    local font = self.font
    local muted = colors.textMuted
    local texts, xs, ys = self._lblText, self._lblX, self._lblY
    for i = 1, self._lblN do
        drawColorText(el, texts[i], xs[i], ys[i], muted, font)
    end
    local disabled = colors.textDisabled or colors.textFaint
    local chip = self._sortChips[self._sortIdx]
    if chip and chip:getIsVisible() then
        Skin.arrow(el, chip.x + chip.width - Skin.ARROW_W - 8,
            chip.y + math.floor((chip.height - Skin.ARROW_H) / 2), not self._desc,
            chip.enable and colors.accent or disabled)
    end
    local dd = self._ddButton
    if dd and dd:getIsVisible() then
        -- 下拉鈕的箭頭：關著 ▼、開著 ▲
        local open = menuOpen ~= nil and menuOpen.bar == self
        local c = disabled
        if dd.enable then
            c = (open or dd:isActive()) and colors.accent or colors.textMuted
        end
        Skin.arrow(el, dd.x + dd.width - Skin.ARROW_W - 8,
            dd.y + math.floor((dd.height - Skin.ARROW_H) / 2), open, c)
    end
    if self.inline then
        local line = self._pageLine
        drawColorText(el, line, self._pageTextRight - measure(font, line), self._pageTextY, muted, font)
    end
end

function FilterBar:drawPager(el, hideCount)
    if not self._pagerShown then
        return
    end
    local colors = self.theme.colors
    local font = self.font
    local ty = self.pagerY + math.floor((self._pagerH - self._fontH) / 2)
    drawColorText(el, self._pageStr, self._pagerX, ty, colors.textMuted, font)
    if not hideCount then
        local count = self._countStr
        drawColorText(el, count, self._pagerRight - measure(font, count), ty, colors.textMuted, font)
    end
end

-- ============================================================
-- 啟用／焦點／使用端控制項
-- ============================================================

-- 權限或模態閘門：自己的所有控制項；分頁鈕另外依頁碼、類型翻頁鈕依目前位置
function FilterBar:setEnabled(on)
    on = on ~= false
    self._enabled = on
    if self._allChip then
        self._allChip:setEnabled(on)
        local pool, extras = self._kindPool, self._extras
        for i = 1, #pool do
            pool[i]:setEnabled(on)
        end
        for i = 1, #extras do
            extras[i]:setEnabled(on)
        end
        refreshKindPage(self)
    end
    if self._ddButton then
        self._ddButton:setEnabled(on)
        if not on then
            closeMenuOf(self)
        end
    end
    if self._dateChip then
        self._dateChip:setEnabled(on)
    end
    local sortChips = self._sortChips
    for i = 1, #sortChips do
        sortChips[i]:setEnabled(on)
    end
    if self._search then
        self._search:setEnabled(on)
    end
    if self._from then
        self._from:setEnabled(on)
        self._to:setEnabled(on)
    end
    if self._toggle then
        self._toggle:setEnabled(on)
    end
    refreshPager(self)
end

-- 使用端的控制項（例：ISComboBox）排在排序後面、畫標籤、跟著可見性；使用端自己 addChild 到
-- parent，並自己管啟用與寬度。focusKind 為 Focus 描述的 kind（"combo"／"button"／"entry"…）。
function FilterBar:addControl(control, label, focusKind)
    control._filterLabel = label
    self._controls[#self._controls + 1] = control
    local desc = { kind = focusKind, control = control, label = label }
    if focusKind == "entry" and control._entry ~= nil then
        desc.control, desc.frame = control._entry, control
    end
    self._ctlDescs[#self._ctlDescs + 1] = desc
end

-- 取消自己所有輸入框的焦點，關掉自己日期欄開著的日曆（DateField:blur 以自己為 scope 關）與自己的類型選單。
-- 不以 parent 為 scope：同一個 parent 可以掛好幾條 bar（例：經濟中心的錢包／市場紀錄／拍賣紀錄），
-- 隱藏中的 bar 在 layout(visible=false) 時 blur，不能收掉另一條 bar 正開著的日曆。
function FilterBar:blur()
    local search = self._search
    if search and search:isFocused() then
        search._entry:unfocus()
    end
    if self._from then
        self._from:blur()
        self._to:blur()
    end
    closeMenuOf(self)
end

function FilterBar:isShown()
    return self._shown
end

-- 依序：精簡切換鈕、關鍵字、類型 group（下拉模式＝下拉鈕）、起訖日期（dateToggle＝chip，打開時接兩欄）、
-- 排序 group（sortInHeader 時沒有）、addControl、inline 分頁 group。描述 table 都是建構／layout 時快取的，只寫進 out。
function FilterBar:appendTargets(out)
    local toggle = self._toggle
    if toggle and toggle:getIsVisible() then
        out[#out + 1] = self._toggleDesc
    end
    if not self._shown then
        return out
    end
    if self._search then
        out[#out + 1] = self._searchDesc
    end
    if self._ddButton then
        out[#out + 1] = self._ddDesc
    elseif self._kindDesc and #self._kindCtl > 0 then
        out[#out + 1] = self._kindDesc
    end
    if self._dateChip then
        out[#out + 1] = self._dateChipDesc
        if self._datesOpen then
            self._from:appendTargets(out, self._fromLabel)
            self._to:appendTargets(out, self._toLabel)
        end
    elseif self._from then
        self._from:appendTargets(out, self._fromLabel)
        self._to:appendTargets(out, self._toLabel)
    end
    if self._sortDesc then
        out[#out + 1] = self._sortDesc
    end
    local descs = self._ctlDescs
    for i = 1, #descs do
        out[#out + 1] = descs[i]
    end
    if self.inline then
        out[#out + 1] = self._pagerDesc
    end
    return out
end

-- strip 模式的分頁 group
function FilterBar:appendPagerTargets(out)
    if self._pagerShown then
        out[#out + 1] = self._pagerDesc
    end
    return out
end

-- 測試鉤子：類型下拉的共用選單實例（尚未開過為 nil）
function FilterBar._menuForTests()
    return menu
end

UI.FilterBar = FilterBar
UI.CAPABILITIES.filterBar = true
UI.CAPABILITIES.filterBarModes = true
UI.CAPABILITIES.opaquePopup = true -- rev 18：類型選單跟著不透明視窗或 opts.opaque

return FilterBar
