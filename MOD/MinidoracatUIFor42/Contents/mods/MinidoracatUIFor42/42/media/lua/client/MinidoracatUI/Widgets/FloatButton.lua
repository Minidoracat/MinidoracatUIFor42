-- MinidoracatUI Widgets/FloatButton — 常駐浮動按鈕（v0.2）。
--
-- 契約提煉自家族兩份實作（NoticeBoard NBFloatButton＋MiniMap _FloatIcon），
-- 取兩者之長：
--   * setCapture 五件套拖曳（MiniMap）：拖出元件外仍收 Move/Up，不會半路丟事件
--   * 拖曳門檻（MiniMap）：滑鼠絕對位移 ≤ threshold＝點擊，防手抖誤拖
--   * 每幀 clamp 回螢幕（兩者共通）：解析度改變／存檔位置超界自動夾回
--   * hover 疊色＋圓角皮膚（NoticeBoard）：走框架 Skin，貼圖缺退直角
--   * 右鍵動作＋800ms 過期守衛（MiniMap）：z-order 高的元件吃掉右鍵放開時
--     旗標不殘留；左鍵拖曳中不接右鍵
--   * tooltip（MiniMap）：hover 顯示、500ms 節流重建、按住不顯示；
--     consumer 不給 getTooltip 就完全不碰 ISToolTip
--   * 無玩家自我隱藏（MiniMap）：回主選單後 UIManager 元件仍存活，自動藏
--
-- 位置持久化是**回調式**：拖曳落點經 onMoved(btn, x, y) 交 consumer 自存
-- （ModOptions／ISLayoutManager／ini 皆可），框架不綁任何存檔機制。
--
-- 載入自檢：本檔可獨立於 V1.lua 之外失敗——失敗只代表 CAPABILITIES.floatButton
-- 維持 false，consumer 探測後走自己的退回，不影響 Theme/Skin。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.floatButton 探測）
end

local Skin = UI.Skin

local FloatButton = ISPanel:derive("MinidoracatUIFloatButton")

local DEFAULT_SIZE = 40
local DEFAULT_THRESHOLD = 4
local RIGHT_CLICK_EXPIRE_MS = 800
local TOOLTIP_THROTTLE_MS = 500

-- 內建 fallback 色（consumer 沒給 colors 時仍可用；數值＝框架 dark palette）
local FALLBACK = {
    surface = { r = 0, g = 0, b = 0, a = 0.8 },
    hover = { r = 1, g = 1, b = 1, a = 0.06 },
    border = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 },
}

-- 夾回螢幕內；prerender 每幀呼叫，純數值比較成本可忽略
local function clampToScreen(btn)
    local x = math.max(0, math.min(btn:getX(), getCore():getScreenWidth() - btn.width))
    local y = math.max(0, math.min(btn:getY(), getCore():getScreenHeight() - btn.height))
    if x ~= btn:getX() then btn:setX(x) end
    if y ~= btn:getY() then btn:setY(y) end
end

-- tooltip：consumer 給 getTooltip(btn) -> desc[, maxLineWidth] 才啟用。
-- 500ms 節流重建；按住（點擊/拖曳中）不顯示；隱藏路徑同步收掉。
local function updateTooltip(btn)
    if not btn.getTooltipText then
        return
    end
    if btn:isMouseOver() and not btn._down and ISToolTip then
        if not btn._tooltipUI then
            local tip = ISToolTip:new()
            tip:setOwner(btn)
            tip:setVisible(false)
            tip:setAlwaysOnTop(true)
            btn._tooltipUI = tip
        end
        local tip = btn._tooltipUI
        local firstShow = not tip:getIsVisible()
        if firstShow then
            tip:addToUIManager()
            tip:setVisible(true)
        end
        local nowMs = getTimestampMs()
        if firstShow or not btn._tipNextMs or nowMs >= btn._tipNextMs then
            btn._tipNextMs = nowMs + TOOLTIP_THROTTLE_MS
            local desc, maxLineWidth = btn.getTooltipText(btn)
            tip.description = desc or ""
            tip.maxLineWidth = maxLineWidth or 300
        end
        tip:setDesiredPosition(getMouseX(), btn:getAbsoluteY() + btn:getHeight() + 8)
    else
        btn:hideTooltip()
    end
end

function FloatButton:hideTooltip()
    if self._tooltipUI and self._tooltipUI:getIsVisible() then
        self._tooltipUI:setVisible(false)
        self._tooltipUI:removeFromUIManager()
    end
end

function FloatButton:prerender()
    -- 回主選單後 UIManager 元件仍存活：無玩家即自我隱藏（consumer 的
    -- OnGameStart／可見性收斂點再開回）。隱藏後 prerender 停跑，tip 須同步收
    if self.autoHideWithoutPlayer and type(getSpecificPlayer) == "function"
        and not getSpecificPlayer(0) then
        self:hideTooltip()
        self:setVisible(false)
        return
    end
    clampToScreen(self)
    updateTooltip(self)

    local colors = self.colors
    Skin.fill(self, 0, 0, self.width, self.height, colors.surface or FALLBACK.surface)
    if self:isMouseOver() then
        Skin.fill(self, 0, 0, self.width, self.height, colors.hover or FALLBACK.hover)
    end
    Skin.border(self, 0, 0, self.width, self.height, colors.border or FALLBACK.border)

    if self.drawContent then
        self.drawContent(self)
    end
end

-- ===== 拖曳（setCapture 五件套＋門檻）=====
-- 門檻判定用滑鼠絕對座標位移（非 dx/dy 累積）：≤ threshold＝點擊、超過＝拖曳

local function moveButton(btn)
    if not btn._down then
        return false
    end
    local mx, my = getMouseX(), getMouseY()
    if not btn._dragged then
        if math.abs(mx - btn._downX) <= btn.dragThreshold
            and math.abs(my - btn._downY) <= btn.dragThreshold then
            return true
        end
        btn._dragged = true
    end
    btn:setX(btn._origX + (mx - btn._downX))
    btn:setY(btn._origY + (my - btn._downY))
    btn:bringToTop()
    return true
end

local function releaseButton(btn)
    if not btn._down then
        return false
    end
    btn._down = nil
    btn:setCapture(false)
    if btn._dragged then
        btn._dragged = nil
        clampToScreen(btn)
        if btn.onMoved then
            btn.onMoved(btn, btn:getX(), btn:getY())
        end
    elseif btn.onClick then
        btn.onClick(btn)
    end
    return true
end

function FloatButton:onMouseDown(x, y)
    if not self:getIsVisible() then
        return false
    end
    self._down = true
    self._dragged = nil
    self._downX, self._downY = getMouseX(), getMouseY()
    self._origX, self._origY = self:getX(), self:getY()
    self:setCapture(true)
    self:bringToTop()
    return true
end

function FloatButton:onMouseMove(dx, dy) return moveButton(self) end
function FloatButton:onMouseMoveOutside(dx, dy) return moveButton(self) end
function FloatButton:onMouseUp(x, y) return releaseButton(self) end
function FloatButton:onMouseUpOutside(x, y) return releaseButton(self) end

-- ===== 右鍵（可選）=====
-- down/up 配對＋800ms 過期：引擎 right-up 依放開位置派送、不追蹤 press owner，
-- z-order 高的元件吃掉放開時旗標會殘留——過期即棄。左鍵拖曳中不接右鍵。

function FloatButton:onRightMouseDown(x, y)
    if self.onRightClick and not self._down then
        self._rDown = true
        self._rDownAt = getTimestampMs()
    end
    return true
end

function FloatButton:onRightMouseUp(x, y)
    if self.onRightClick and self._rDown
        and getTimestampMs() - (self._rDownAt or 0) < RIGHT_CLICK_EXPIRE_MS then
        self._rDown = nil
        self.onRightClick(self)
    end
    self._rDown = nil
    return true
end

function FloatButton:onRightMouseUpOutside(x, y)
    self._rDown = nil
end

-- 外部設定位置（consumer 的持久化還原路徑）；夾回螢幕
function FloatButton:setPosition(x, y)
    self:setX(x)
    self:setY(y)
    clampToScreen(self)
end

-- opts:
--   size（預設 40）、x/y（預設右緣中段）、colors={surface,hover,border}（color table）、
--   dragThreshold（預設 4）、alwaysOnTop（預設 true）、autoHideWithoutPlayer（預設 true）、
--   onClick(btn)、onRightClick(btn)、onMoved(btn,x,y)、drawContent(btn)、
--   getTooltip(btn)->desc[,maxLineWidth]
-- 回傳已 initialise＋addToUIManager 的實例。
function FloatButton.new(opts)
    opts = opts or {}
    local size = opts.size or DEFAULT_SIZE
    local x = opts.x or (getCore():getScreenWidth() - size - 16)
    local y = opts.y or (getCore():getScreenHeight() / 2 - size / 2)
    local o = ISPanel.new(FloatButton, x, y, size, size)
    o.background = false
    o.alwaysOnTop = opts.alwaysOnTop ~= false
    o.autoHideWithoutPlayer = opts.autoHideWithoutPlayer ~= false
    o.colors = opts.colors or {}
    o.dragThreshold = opts.dragThreshold or DEFAULT_THRESHOLD
    o.onClick = opts.onClick
    o.onRightClick = opts.onRightClick
    o.onMoved = opts.onMoved
    o.drawContent = opts.drawContent
    o.getTooltipText = opts.getTooltip
    o:initialise()
    o:addToUIManager()
    return o
end

UI.FloatButton = FloatButton
UI.CAPABILITIES.floatButton = true

return FloatButton
