-- MinidoracatUI Widgets/Toast — 通知彈窗（v0.2；rev 21 改位置、計時與紀錄）。
--
-- 契約提煉自 NoticeBoard NBToast：右滑入 250ms → 停留 DEFAULT_HOLD_MS（consumer 可用 holdMs 指定）
-- → 上飄淡出 400ms；同時最多 3 則、pending 佇列上限 5（超過就不顯示，但每則都先寫進紀錄）；
-- 訊息超寬二分截字（含 UTF-16 surrogate pair 防護——Kahlua string 底層是 Java UTF-16）。
-- 標題超寬時換行（rev 19，CAPABILITIES.toastTitleWrap）：最多 TITLE_LINES 行，最後一行放不下帶省略號；
-- 以前只畫一行、不截字，長標題（拉丁語系帶名稱的標題常見）會畫到框外。
--
-- 【全域共用堆疊】堆疊狀態是框架單例：所有 MOD 的 show() 進同一佇列、同一
-- 疊放位置——兩個 MOD 同時通知不會互相重疊蓋字。每則自帶 title 與色票
-- 區分來源；色票缺省用框架 dark 值。
--
-- 【位置（rev 21）】自動位置是右上一欄：右緣在原版 moodle 欄與 Dock 預設位置的左邊（columnRight），
-- 從 STACK_TOP 或速度鈕下緣起往下疊。避開區（rev 12，Toast.setAvoid）與時鐘只會把整欄往下推：
-- 判斷重疊用固定的預留高度 RESERVED_H（三則單行），不用目前則數，所以位置不會因為多一則而跳；
-- 推下去放不下就留在原位（疊在視窗上，通知不吃滑鼠）。rev 20 以前放不下會整疊移到障礙物左邊，
-- Dock＋右側小地圖時第二則一來就跳到畫面中間。玩家用移動模式（ToastHistory.lua）放過位置後，
-- 固定在 Toast.anchor、不再避開；錨點在下半部時往上疊。位置存 layout.ini（ISLayoutManager，每種解析度一份）。
--
-- 【紀錄（rev 21）】show() 先把每則寫進 Toast.history（最多 MAX_HISTORY 則、只在記憶體），
-- 排不進佇列被丟掉的也記；紀錄視窗在 ToastHistory.lua（CAPABILITIES.toastHistory）。
-- 【停留（rev 21）】預設 5 秒；停留階段游標在框內時暫停計時（每幀比 getMouseX/Y，不收滑鼠事件）。
--
-- 動畫座標是小數：Skin 內部會 floor 絕對座標再交給 NinePatchTexture（防抖）。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin) or not ISPanel then
    return -- 核心缺席：不掛能力
end

local Skin = UI.Skin
-- 共用斷行（內部模組）；缺席時 maxLines 退回單行截字
local wrapOK, TextWrap = pcall(require, "MinidoracatUI/TextWrap")
TextWrap = wrapOK and type(TextWrap) == "table" and TextWrap or nil

local Toast = ISPanel:derive("MinidoracatUIToast")

local WIDTH = 300
local HEIGHT = 56
local SCREEN_MARGIN = 16
local STACK_TOP = 60
local STACK_GAP = 8
local ENTER_MS = 250
local DEFAULT_HOLD_MS = 5000 -- rev 21：3000 → 5000（逾時的通知至少停 5 秒）
local EXIT_MS = 400
local MAX_VISIBLE = 3
local MAX_PENDING = 5
local MAX_FIT_UNITS = 512
local TITLE_LINES = 2 -- rev 19：標題最多兩行
local MAX_HISTORY = 100 -- rev 21：紀錄只留最近 100 則
local RESERVED_H = MAX_VISIBLE * HEIGHT + (MAX_VISIBLE - 1) * STACK_GAP -- rev 21：閃避只看三則單行的預留高度
local MOODLE_EDGE = 10 -- UIManager.java:417 moodle 欄 setX(sw - (10 + width))
local MOODLE_DEFAULT = 32 -- MoodlesUI 寬＝圖示邊長（MoodlesUI.java:53）；讀不到時用預設選項的 32
local DOCK_LANE = 12 + 48 -- Dock 預設在 moodle 欄左邊 12px、寬 48（Dock.lua applyDefault）
local SLIDE_IN = 40 -- 進場從定位點右邊這麼遠滑進來
local LAYOUT_KEY = "MinidoracatUIToast"

local FALLBACK = {
    surface = { r = 0, g = 0, b = 0, a = 0.85 },
    border = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 },
    text = { r = 1, g = 1, b = 1, a = 1.0 },
}

-- 全域共用堆疊（框架單例；重載防重）
Toast.active = Toast.active or {}
Toast.pending = Toast.pending or {}
-- rev 12 避開區：{ owner, fn } 依登記順序；fn() → x, y, w, h（螢幕座標）或 nil
Toast.avoid = Toast.avoid or {}
-- rev 21 紀錄：{ title, message, border, atMs }，舊的在前；historyCount 是累計寫入筆數（紀錄視窗用它判斷要不要重排）
Toast.history = Toast.history or {}
Toast.historyCount = Toast.historyCount or 0
Toast.MAX_HISTORY = MAX_HISTORY
-- rev 21 唯讀常數：移動模式的範例框照一則單行通知畫（ToastHistory.lua）
Toast.WIDTH, Toast.HEIGHT, Toast.STACK_GAP, Toast.MAX_VISIBLE = WIDTH, HEIGHT, STACK_GAP, MAX_VISIBLE

local function isHighSurrogate(unit)
    return unit ~= nil and unit >= 55296 and unit <= 56319
end

-- 超寬訊息二分截字：逐字遞減是 O(n²)（每輪一次 MeasureStringX），超長訊息會
-- 凍結主執行緒數秒；先硬截 MAX_FIT_UNITS 再二分，量測次數 O(log n)。
-- 截點落在 surrogate pair 中間會畫出孤立 surrogate——回退一位。
local function fitText(text, maximumWidth)
    local manager = getTextManager()
    if manager:MeasureStringX(UIFont.NewSmall, text) <= maximumWidth then
        return text
    end
    if string.len(text) > MAX_FIT_UNITS then
        local cut = MAX_FIT_UNITS
        if isHighSurrogate(string.byte(text, cut)) then
            cut = cut - 1
        end
        text = string.sub(text, 1, cut)
    end
    local suffix = "..."
    local low, high, best = 0, string.len(text), nil
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local cut = mid
        if cut > 0 and isHighSurrogate(string.byte(text, cut)) then
            cut = cut - 1
        end
        local candidate = string.sub(text, 1, cut) .. suffix
        if manager:MeasureStringX(UIFont.NewSmall, candidate) <= maximumWidth then
            best = candidate
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return best or suffix
end

-- 最多 maxLines 行的換行（rev 5）：前 maxLines-1 行走共用斷行 TextWrap.cut（中日文逐字斷、
-- 拉丁文不切單字、句讀禁則），最後一行超出時交給 fitText 帶省略號。
-- maxLines ≤ 1（或共用斷行缺席）就是原本的單行截字。
local function wrapText(text, maximumWidth, maxLines)
    if type(maxLines) ~= "number" or maxLines <= 1 or not TextWrap then
        return { fitText(text, maximumWidth) }
    end
    if string.len(text) > MAX_FIT_UNITS * maxLines then
        text = string.sub(text, 1, MAX_FIT_UNITS * maxLines)
    end
    local lines = {}
    local rest = text
    while #lines < maxLines - 1 do
        local line
        line, rest = TextWrap.cut(rest, maximumWidth, UIFont.NewSmall)
        lines[#lines + 1] = line
        if rest == "" then return lines end
    end
    lines[#lines + 1] = fitText(rest, maximumWidth)
    return lines
end

local function activeIndex(toast)
    for index = 1, #Toast.active do
        if Toast.active[index] == toast then
            return index
        end
    end
    return 1
end

local function activate(entry)
    local toast = Toast._create(entry)
    toast:initialise()
    toast:addToUIManager()
    toast:setAlwaysOnTop(toast.alwaysOnTop)
    toast:setVisible(true)
    Toast.active[#Toast.active + 1] = toast
    return toast
end

function Toast.dismiss(toast)
    for index = #Toast.active, 1, -1 do
        if Toast.active[index] == toast then
            table.remove(Toast.active, index)
            break
        end
    end
    toast:setVisible(false)
    toast:removeFromUIManager()
    if #Toast.pending > 0 and #Toast.active < MAX_VISIBLE then
        activate(table.remove(Toast.pending, 1))
    end
end

-- rev 21：每則都先記一筆（show 時一次，不在每幀的路徑上）。標題與色條照 show 收到的；訊息是完整原文。
local function record(entry)
    local list = Toast.history
    list[#list + 1] = {
        title = entry.title ~= nil and tostring(entry.title) or nil,
        message = entry.message,
        border = entry.colors.border,
        atMs = getTimestampMs(),
    }
    if #list > MAX_HISTORY then
        table.remove(list, 1)
    end
    Toast.historyCount = Toast.historyCount + 1
end

-- opts: { title=, message=, colors={surface,border,text}, holdMs=, maxLines= }
-- （rev 5 起 maxLines>1 時訊息自動換行、Toast 隨行數長高；預設 1＝單行截字。
-- rev 19 起 title 放不下時換成最多兩行，同樣隨行數長高）
-- 或直接傳字串（僅 message、無標題列）。
-- 回傳 toast 實例；進 pending 或被丟棄時回 nil（兩者都已寫進紀錄）。
function Toast.show(opts)
    if type(opts) == "string" then
        opts = { message = opts }
    end
    if type(opts) ~= "table" or type(opts.message) ~= "string" or opts.message == "" then
        return nil
    end
    local entry = {
        title = opts.title,
        message = opts.message,
        colors = opts.colors or {},
        holdMs = opts.holdMs or DEFAULT_HOLD_MS,
        maxLines = opts.maxLines,
    }
    record(entry) -- 先記：下面排不進佇列、被丟掉的也留在紀錄
    if #Toast.active >= MAX_VISIBLE then
        if #Toast.pending >= MAX_PENDING then
            return nil
        end
        Toast.pending[#Toast.pending + 1] = entry
        return nil
    end
    return activate(entry)
end

-- 原版速度鈕（單人）在戴錶、時鐘顯示時移到時鐘正下方（UIManager.java:446-456），落在右上
-- 通知欄裡；欄位與它水平重疊時改從它下緣往下疊。只認真的在 UI 清單裡的速度鈕：MP 與
-- Last Stand 不加進清單（UIManager.java:217-219），物件卻仍在、isVisible 也是 true。
local function stackTop(left, right)
    local sc = UIManager and UIManager.getSpeedControls and UIManager.getSpeedControls()
    if not (sc and sc:isVisible() and UIManager.getUI():contains(sc)) then return STACK_TOP end
    local x = sc:getX()
    if x >= right or x + sc:getWidth() <= left then return STACK_TOP end
    return math.max(STACK_TOP, sc:getY() + sc:getHeight() + STACK_GAP)
end

-- rev 12：登記一個要避開的矩形（例：consumer 開著的視窗）。fn() 回螢幕座標 x, y, w, h，回 nil＝此刻不用避；
-- fn 為 nil＝取消該 owner 的登記。同一個 owner 再登記會覆寫。fn 每幀可能被呼叫多次（pcall），不要在裡面配置 table。
function Toast.setAvoid(owner, fn)
    if owner == nil then
        return
    end
    local list = Toast.avoid
    for i = 1, #list do
        if list[i].owner == owner then
            if fn == nil then
                table.remove(list, i)
            else
                list[i].fn = fn
            end
            return
        end
    end
    if fn ~= nil then
        list[#list + 1] = { owner = owner, fn = fn }
    end
end

-- 自動欄位的右緣：最右邊 moodle 欄的左界（UIManager.java:417，x＝螢幕寬 −（10＋moodle 寬）），再空出 Dock
-- 預設位置那一格。rev 20 以前右緣是螢幕寬 − 16，第 2、3 則的右邊 26px 疊在 moodle 圖示上（moodle 從 y=120 起，
-- MoodlesUI.java:51-52）。moodle 寬＝目前的圖示邊長（MoodlesUI.java:53，跟著遊戲選項）。
local function columnRight()
    local size = MOODLE_DEFAULT
    local m = UIManager and UIManager.getMoodleUI and UIManager.getMoodleUI(0)
    if m then
        local w = m:getWidth()
        if type(w) == "number" and w > 0 then size = w end
    end
    return getCore():getScreenWidth() - (MOODLE_EDGE + size) - DOCK_LANE - SCREEN_MARGIN
end

-- 矩形與預留區（欄寬 × RESERVED_H）水平、垂直都重疊時，整個預留區放得下就移到它下方；放不下就留原位。
-- 只往下：rev 20 以前放不下會整疊移到矩形左邊，小地圖寬時落到畫面中間。
local function dodgeDown(x, top, width, screenH, ax, ay, aw, ah)
    if ax < x + width and ax + aw > x and ay < top + RESERVED_H and ay + ah > top then
        local below = ay + ah + STACK_GAP
        if below + RESERVED_H <= screenH then
            return math.max(top, below)
        end
    end
    return top
end

-- 一趟：時鐘（有的話）＋每個登記的避開區各比一次。fn 出錯或回非數字＝不避。
local function dodgeAllDown(x, top, width, screenH, clock)
    if clock then
        top = dodgeDown(x, top, width, screenH, clock:getX(), clock:getY(), clock:getWidth(), clock:getHeight())
    end
    local list = Toast.avoid
    for i = 1, #list do
        local ok, ax, ay, aw, ah = pcall(list[i].fn)
        if ok and type(ax) == "number" and type(ay) == "number" and type(aw) == "number" and type(ah) == "number" then
            top = dodgeDown(x, top, width, screenH, ax, ay, aw, ah)
        end
    end
    return top
end

-- 堆疊的位置 → x, top, up。up＝false：top 是第一則的上緣、往下疊；up＝true：top＋HEIGHT 是第一則的下緣、往上疊。
-- 玩家放過的位置（Toast.anchor）優先、不避開。自動位置：columnRight 那一欄、速度鈕下方，再避原版時鐘與登記的避開區。
-- 時鐘戴錶才顯示（Clock.java:328-404，isVisible），預設大時鐘 156x62 在 y=10、落在欄內（UIManager.java:223-231）；
-- MP 沒有速度鈕把欄位推下去，60 起疊會蓋住它的下緣。Last Stand 不加進 UI 清單（UIManager.java:229-231）。
-- 單趟依登記順序會讓結果看順序：先比到的區域不重疊、被後面的推下去後才重疊，所以反覆整趟比到位置不再改變；
-- top 只會變大，最多（區域數＋2）趟。
function Toast.stackOrigin(width)
    local a = Toast.anchor
    if a then
        return a.x, a.y, a.up
    end
    local screenH = getCore():getScreenHeight()
    local x = columnRight() - width
    local top = stackTop(x, x + width)
    local clock = UIManager and UIManager.getClock and UIManager.getClock()
    if not (clock and clock:isVisible() and UIManager.getUI():contains(clock)) then
        clock = nil
    end
    for _ = 1, #Toast.avoid + 2 do
        local ntop = dodgeAllDown(x, top, width, screenH, clock)
        if ntop == top then
            break
        end
        top = ntop
    end
    return x, top, false
end

-- ===== rev 21：玩家放的位置（移動模式在 ToastHistory.lua）=====

-- 夾回螢幕內（第一則整個看得到）；中心在下半部就往上疊。只在設定或讀回時配置一次。
local function clampAnchor(x, y)
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    x = math.max(0, math.min(math.floor(x), sw - WIDTH))
    y = math.max(0, math.min(math.floor(y), sh - HEIGHT))
    return { x = x, y = y, up = y + HEIGHT / 2 > sh / 2 }
end

local function layoutRegistered()
    local LM = ISLayoutManager
    return LM ~= nil and type(LM.windows) == "table" and LM.windows[LAYOUT_KEY] ~= nil
end

-- 立刻寫 layout.ini（遊戲每次存檔走的同一條，ISLayoutManager.lua:191-229；同 Dock 的 persist）
local function persist()
    if layoutRegistered() and ISLayoutManager.OnPostSave then pcall(ISLayoutManager.OnPostSave) end
end

-- x, y＝第一則（單行）通知左上角的螢幕座標；任一不是數字＝回到自動位置。設完立刻存檔。
-- 給移動模式與「恢復預設位置」用：位置是玩家的偏好，consumer 不要呼叫。
function Toast.setAnchor(x, y)
    if type(x) == "number" and type(y) == "number" then
        Toast.anchor = clampAnchor(x, y)
    else
        Toast.anchor = nil
    end
    persist()
end

-- ISLayoutManager.RegisterWindow(name, funcs, target) 以 funcs.SaveLayout/RestoreLayout(target, name, layout)
-- 呼叫（ISLayoutManager.lua:6-13,99-113）；layout.ini 依解析度分段，讀回的值是字串。
local AnchorLayout = {}

function AnchorLayout.SaveLayout(target, name, layout)
    local a = Toast.anchor
    layout.x = a and a.x or nil -- 自動位置：這一行只剩名字
    layout.y = a and a.y or nil
end

function AnchorLayout.RestoreLayout(target, name, layout)
    local x, y = tonumber(layout.x), tonumber(layout.y)
    Toast.anchor = (x and y) and clampAnchor(x, y) or nil
end

local function registerLayout()
    if layoutRegistered() or not (ISLayoutManager and ISLayoutManager.RegisterWindow) then return end
    pcall(ISLayoutManager.RegisterWindow, LAYOUT_KEY, AnchorLayout, Toast)
end

-- 換解析度：先回自動位置，新解析度存過才讀回（同 Dock 的 onResolutionChange）
local function onResolutionChange()
    Toast.anchor = nil
    if layoutRegistered() and ISLayoutManager.TryRestore then pcall(ISLayoutManager.TryRestore, LAYOUT_KEY) end
end

-- ===== 繪製 =====

-- 停留階段游標在框內就暫停計時。讀全域 getMouseX/Y（LuaManager.java:8011-8046），不收滑鼠事件，點擊照樣穿過去。
-- 用上一幀的位置判斷（這一幀的位置在下面才算出來）。
local function hovered(toast)
    if not (getMouseX and getMouseY) then return false end
    local mx, my = getMouseX(), getMouseY()
    return mx >= toast.x and mx < toast.x + toast.width and my >= toast.y and my < toast.y + toast.height
end

function Toast:prerender()
    local now = getTimestampMs()
    local elapsed = now - self.startedAtMs - self.pausedMs
    if elapsed >= ENTER_MS and elapsed < ENTER_MS + self.holdMs and hovered(self) then
        self.pausedMs = self.pausedMs + (now - self.lastMs)
        elapsed = now - self.startedAtMs - self.pausedMs
    end
    self.lastMs = now
    local totalDuration = ENTER_MS + self.holdMs + EXIT_MS
    if elapsed >= totalDuration then
        Toast.dismiss(self)
        return
    end

    local index = activeIndex(self)
    local targetX, top, up = Toast.stackOrigin(self.width)
    local offset = 0
    for i = 1, index - 1 do
        offset = offset + Toast.active[i].height + STACK_GAP
    end
    local targetY = up and (top + HEIGHT - offset - self.height) or (top + offset)
    local x, y, alpha = targetX, targetY, 1

    if elapsed < ENTER_MS then
        local fraction = elapsed / ENTER_MS
        -- 從定位點右邊 SLIDE_IN 滑進來：欄位不貼螢幕右緣，從螢幕外滑入會掃過 moodle 與 Dock
        local startX = targetX + SLIDE_IN
        x = startX + (targetX - startX) * fraction
        alpha = fraction
    elseif elapsed >= ENTER_MS + self.holdMs then
        local fraction = (elapsed - ENTER_MS - self.holdMs) / EXIT_MS
        alpha = 1 - fraction
        y = targetY - 10 * fraction
    end

    self:setX(x)
    self:setY(y)

    local colors = self.colors
    local textColor = colors.text or FALLBACK.text
    Skin.fill(self, 0, 0, self.width, self.height,
        colors.surface or FALLBACK.surface, false, alpha)
    Skin.border(self, 0, 0, self.width, self.height,
        colors.border or FALLBACK.border, false, alpha)
    if self.titleLines then
        for i, line in ipairs(self.titleLines) do
            self:drawText(line, 8, 7 + self.fontHeight * (i - 1),
                textColor.r, textColor.g, textColor.b, textColor.a * alpha, UIFont.NewSmall)
        end
        local top = 10 + self.fontHeight * (#self.titleLines - 1)
        for i, line in ipairs(self.lines) do
            self:drawText(line, 8, top + self.fontHeight * i,
                textColor.r, textColor.g, textColor.b, textColor.a * alpha, UIFont.NewSmall)
        end
    else
        -- 無標題：訊息置中於垂直空間
        local top = (self.height - self.fontHeight * #self.lines) / 2
        for i, line in ipairs(self.lines) do
            self:drawText(line, 8, top + self.fontHeight * (i - 1),
                textColor.r, textColor.g, textColor.b, textColor.a * alpha, UIFont.NewSmall)
        end
    end
end

-- 通知只顯示、不收滑鼠：置頂的通知吃掉點擊時，蓋到的原版速度鈕（放開才觸發，
-- HUDButton.java:112-127）等介面會點不到（到站自動暫停後按不了繼續）。左鍵與移動靠
-- wantMouseEvents=false（instantiate 同步成 Java consumeMouseEvents，ISUIElement.lua:1004；
-- UIElement.java:1122-1123,1248,1340-1341）；右鍵在 Lua 回 nil 時一律被吞
-- （UIElement.java:1513-1515,1583-1585），要明確回 false。
function Toast:onRightMouseDown() return false end
function Toast:onRightMouseUp() return false end

function Toast._create(entry)
    local x = getCore():getScreenWidth() + WIDTH
    local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
    local lines = wrapText(entry.message, WIDTH - 16, entry.maxLines)
    -- 標題與訊息同一套斷行（斷行模組缺席時一樣退回單行截字），多出的標題行算進高度
    local titleLines = entry.title ~= nil and wrapText(tostring(entry.title), WIDTH - 16, TITLE_LINES) or nil
    local height = HEIGHT + fontHeight * (#lines - 1 + (titleLines and #titleLines - 1 or 0))
    local o = ISPanel.new(Toast, x, STACK_TOP, WIDTH, height)
    o.background = false
    o.alwaysOnTop = true
    o.wantMouseEvents = false
    o.startedAtMs = getTimestampMs()
    o.lastMs = o.startedAtMs -- rev 21：游標停留暫停用的上一幀時間與累計暫停
    o.pausedMs = 0
    o.fontHeight = fontHeight
    o.titleText = entry.title      -- rev 1-18 的欄位：原始標題（測試與舊 consumer 讀它）
    o.titleLines = titleLines
    o.lines = lines
    o.message = lines[1]           -- rev 1-4 的單行欄位：第一行（測試與舊 consumer 讀它）
    o.colors = entry.colors
    o.holdMs = entry.holdMs
    return o
end

-- 只給測試用：清空堆疊、避開區、紀錄與玩家位置（不觸碰 UIManager——harness 的 stub 不需要）
function Toast._resetForTests()
    Toast.active = {}
    Toast.pending = {}
    Toast.avoid = {}
    Toast.history = {}
    Toast.historyCount = 0
    Toast.anchor = nil
end

local function on(name, fn)
    local event = Events and Events[name]
    if event and event.Add then event.Add(fn) end
end

-- 位置存讀在遊戲中才有（ISLayoutManager 在 Tutorial 不動作）；登記時就讀回這個解析度存過的位置
on("OnGameStart", registerLayout)
on("OnResolutionChange", onResolutionChange)

UI.Toast = Toast
UI.CAPABILITIES.toast = true
UI.CAPABILITIES.toastAvoid = true
UI.CAPABILITIES.toastTitleWrap = true

return Toast
