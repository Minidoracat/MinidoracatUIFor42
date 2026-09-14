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
-- 動畫座標是小數：Skin 內部會 floor 絕對座標再交給 NinePatchTexture（防抖）。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin) or not ISPanel then
    return -- 核心缺席：不掛能力
end

local Skin = UI.Skin

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

-- 最多 maxLines 行的換行（rev 5）：每行二分找最長可放前綴（CJK 無空白，按字元切；
-- 拉丁文若前綴內有空白則退到最後一個空白後切），最後一行超出時交給 fitText 帶省略號。
-- 量測次數 O(lines × log n)。maxLines ≤ 1 就是原本的單行截字。
local function wrapText(text, maximumWidth, maxLines)
    if type(maxLines) ~= "number" or maxLines <= 1 then
        return { fitText(text, maximumWidth) }
    end
    local manager = getTextManager()
    if string.len(text) > MAX_FIT_UNITS * maxLines then
        text = string.sub(text, 1, MAX_FIT_UNITS * maxLines)
    end
    local lines = {}
    local rest = text
    while #lines < maxLines - 1 do
        if manager:MeasureStringX(UIFont.NewSmall, rest) <= maximumWidth then
            lines[#lines + 1] = rest
            return lines
        end
        local low, high, best = 1, string.len(rest), 1
        while low <= high do
            local mid = math.floor((low + high) / 2)
            local cut = mid
            if isHighSurrogate(string.byte(rest, cut)) then cut = cut - 1 end
            if cut >= 1 and manager:MeasureStringX(UIFont.NewSmall, string.sub(rest, 1, cut)) <= maximumWidth then
                best = cut
                low = mid + 1
            else
                high = mid - 1
            end
        end
        local head = string.sub(rest, 1, best)
        local space = nil
        for i = string.len(head), 1, -1 do
            if string.byte(head, i) == 32 then space = i break end
        end
        if space and space > 1 and string.len(rest) > best then head = string.sub(head, 1, space - 1) end
        lines[#lines + 1] = head
        rest = string.gsub(string.sub(rest, string.len(head) + 1), "^%s+", "")
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

function Toast:prerender()
    local elapsed = getTimestampMs() - self.startedAtMs
    local totalDuration = ENTER_MS + self.holdMs + EXIT_MS
    if elapsed >= totalDuration then
        Toast.dismiss(self)
        return
    end

    local index = activeIndex(self)
    local targetX = getCore():getScreenWidth() - self.width - SCREEN_MARGIN
    local targetY = STACK_TOP
    for i = 1, index - 1 do
        targetY = targetY + Toast.active[i].height + STACK_GAP
    end
    local x, y, alpha = targetX, targetY, 1

    if elapsed < ENTER_MS then
        local fraction = elapsed / ENTER_MS
        local startX = getCore():getScreenWidth() + self.width
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

function Toast._create(entry)
    local x = getCore():getScreenWidth() + WIDTH
    local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
    local lines = wrapText(entry.message, WIDTH - 16, entry.maxLines)
    local height = HEIGHT + fontHeight * (#lines - 1)
    local o = ISPanel.new(Toast, x, STACK_TOP, WIDTH, height)
    o.background = false
    o.alwaysOnTop = true
    o.startedAtMs = getTimestampMs()
    o.fontHeight = fontHeight
    o.titleText = entry.title
    o.lines = lines
    o.message = lines[1]           -- rev 1-4 的單行欄位：第一行（測試與舊 consumer 讀它）
    o.colors = entry.colors
    o.holdMs = entry.holdMs
    return o
end

-- 只給測試用：清空堆疊（不觸碰 UIManager——harness 的 stub 不需要）
function Toast._resetForTests()
    Toast.active = {}
    Toast.pending = {}
end

UI.Toast = Toast
UI.CAPABILITIES.toast = true

return Toast
