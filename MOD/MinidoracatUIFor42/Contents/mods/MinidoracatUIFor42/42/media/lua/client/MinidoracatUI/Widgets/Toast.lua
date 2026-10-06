-- MinidoracatUI Widgets/Toast — 通知彈窗（v0.2）。
--
-- 契約提煉自 NoticeBoard NBToast，行為守恆：右滑入 250ms → 停留 3000ms（可調）
-- → 上飄淡出 400ms；同時最多 3 則、pending 佇列上限 5（超過即丟——徽章/紅點
-- 已足以表示「有多則」，連續彈窗違反通知輕量原則）；訊息超寬二分截字
-- （含 UTF-16 surrogate pair 防護——Kahlua string 底層是 Java UTF-16）。
--
-- 【全域共用堆疊】堆疊狀態是框架單例：所有 MOD 的 show() 進同一佇列、同一
-- 疊放位置——兩個 MOD 同時通知不會互相重疊蓋字。每則自帶 title 與色票
-- 區分來源；色票缺省用框架 dark 值。
--
-- 【避開區（rev 12，CAPABILITIES.toastAvoid）】Toast.setAvoid(owner, fn) 登記 consumer 的視窗等矩形；
-- 堆疊與它重疊時改放到它下方（放不下就左側），fn 回 nil 時照舊右上。
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
local DEFAULT_HOLD_MS = 3000
local EXIT_MS = 400
local MAX_VISIBLE = 3
local MAX_PENDING = 5
local MAX_FIT_UNITS = 512

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

-- opts: { title=, message=, colors={surface,border,text}, holdMs=, maxLines= }
-- （rev 5 起 maxLines>1 時訊息自動換行、Toast 隨行數長高；預設 1＝單行截字）
-- 或直接傳字串（僅 message、無標題列）。
-- 回傳 toast 實例；進 pending 或被丟棄時回 nil。
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
-- fn 為 nil＝取消該 owner 的登記。同一個 owner 再登記會覆寫。fn 每幀呼叫（pcall），不要在裡面配置 table。
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

-- 矩形與堆疊欄水平、垂直都重疊時：整疊放得下就移到它下方，放不下就移到它左側；左側也放不下就留原位。
local function dodge(x, top, width, stackH, screenH, ax, ay, aw, ah)
    if ax < x + width and ax + aw > x and ay < top + stackH and ay + ah > top then
        local below = ay + ah + STACK_GAP
        if below + stackH <= screenH then
            top = math.max(top, below)
        elseif ax - width - SCREEN_MARGIN >= 0 then
            x = ax - width - SCREEN_MARGIN
        end
    end
    return x, top
end

-- 堆疊欄的位置：預設右上（速度鈕下方）。先避原版時鐘，再依登記順序看每個避開區（同一套 dodge 規則）。
-- 時鐘戴錶才顯示（Clock.java:328-404，isVisible），預設大時鐘 156x62 在 y=10、落在欄內（UIManager.java:223-231）；
-- MP 沒有速度鈕把欄位推下去，60 起疊會蓋住它的下緣。Last Stand 不加進 UI 清單（UIManager.java:229-231）。
-- 避開區 fn 出錯或回非數字＝不避。
function Toast.stackOrigin(width)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = screenW - width - SCREEN_MARGIN
    local top = stackTop(x, x + width)
    local stackH = 0
    for i = 1, #Toast.active do
        stackH = stackH + Toast.active[i].height + (i > 1 and STACK_GAP or 0)
    end
    local clock = UIManager and UIManager.getClock and UIManager.getClock()
    if clock and clock:isVisible() and UIManager.getUI():contains(clock) then
        x, top = dodge(x, top, width, stackH, screenH, clock:getX(), clock:getY(), clock:getWidth(), clock:getHeight())
    end
    local list = Toast.avoid
    for i = 1, #list do
        local ok, ax, ay, aw, ah = pcall(list[i].fn)
        if ok and type(ax) == "number" and type(ay) == "number" and type(aw) == "number" and type(ah) == "number" then
            x, top = dodge(x, top, width, stackH, screenH, ax, ay, aw, ah)
        end
    end
    return x, top
end

function Toast:prerender()
    local elapsed = getTimestampMs() - self.startedAtMs
    local totalDuration = ENTER_MS + self.holdMs + EXIT_MS
    if elapsed >= totalDuration then
        Toast.dismiss(self)
        return
    end

    local index = activeIndex(self)
    local targetX, targetY = Toast.stackOrigin(self.width)
    for i = 1, index - 1 do
        targetY = targetY + Toast.active[i].height + STACK_GAP
    end
    local x, y, alpha = targetX, targetY, 1

    if elapsed < ENTER_MS then
        local fraction = elapsed / ENTER_MS
        -- 預設從螢幕外右滑入；被避開區移到左側時只短距離滑入（不從視窗上方掃過）
        local startX = getCore():getScreenWidth() + self.width
        if targetX + self.width + SCREEN_MARGIN < getCore():getScreenWidth() then
            startX = targetX + 40
        end
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
    if self.titleText then
        self:drawText(self.titleText, 8, 7,
            textColor.r, textColor.g, textColor.b, textColor.a * alpha, UIFont.NewSmall)
        for i, line in ipairs(self.lines) do
            self:drawText(line, 8, 10 + self.fontHeight * i,
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
    local height = HEIGHT + fontHeight * (#lines - 1)
    local o = ISPanel.new(Toast, x, STACK_TOP, WIDTH, height)
    o.background = false
    o.alwaysOnTop = true
    o.wantMouseEvents = false
    o.startedAtMs = getTimestampMs()
    o.fontHeight = fontHeight
    o.titleText = entry.title
    o.lines = lines
    o.message = lines[1]           -- rev 1-4 的單行欄位：第一行（測試與舊 consumer 讀它）
    o.colors = entry.colors
    o.holdMs = entry.holdMs
    return o
end

-- 只給測試用：清空堆疊與避開區（不觸碰 UIManager——harness 的 stub 不需要）
function Toast._resetForTests()
    Toast.active = {}
    Toast.pending = {}
    Toast.avoid = {}
end

UI.Toast = Toast
UI.CAPABILITIES.toast = true
UI.CAPABILITIES.toastAvoid = true

return Toast
