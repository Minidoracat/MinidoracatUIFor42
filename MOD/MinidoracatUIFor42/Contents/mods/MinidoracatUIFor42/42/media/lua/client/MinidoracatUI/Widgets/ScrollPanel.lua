-- MinidoracatUI Widgets/ScrollPanel — 捲動容器（API rev 16，CAPABILITIES.scrollPanel）：UI.ScrollPanel。
-- 子元件照一般方式 addChild、以內容座標擺（寬度用 contentWidth()）；內容高於可視區時滾輪／拖曳捲軸捲動，
-- 超出可視區的部分用 stencil 裁掉，捲軸用 Skin 畫（theme token、rev 15 圓角、theme.alpha）。
--
--   UI.ScrollPanel.new{ x?, y?, width?, height?, theme?, font? } -> 已 initialise() 的元素（consumer addChild）
--   方法：contentWidth()（寬減右側捲軸槽）、scrollTo(el)（把子孫 el 捲進可視區；Focus 換焦點時自動呼叫）；
--         捲動位置用原生 getYScroll()／setYScroll(y)（0＝頂端、往下為負，原生 setter 自己夾範圍）
--   內容高＝可見子元件的最大下緣（每幀 prerender 量，不必呼叫任何 setter）
--   Focus（Focus.lua 讀 `_scrollPanel`）：焦點落到容器裡的控制項時自動捲到看得見；PgUp／PgDn／Home／End
--   與手把右搖桿捲容器；容器裡沒有任何焦點目標時容器本身是 kind="scroll" 目標（`_focusLabel` 當說明）。
--
-- 出處（快照 42.21.0）：
--   子元件跟著捲    UIElement.java:930-948（scrollChildren 時 getAbsoluteX/Y 加父層 scroll）、:1832-1840
--                   （滑鼠派送以 getXScrolled／getYScrolled 換算子元件座標）
--   自身繪製位移    UIElement.java:469-483（drawRect 系吃自身 yScroll）→ 捲軸畫在 y - getYScroll()；
--                   setStencilRect :1875-1890 只加 getAbsoluteX/Y（不含自身 scroll）＝可視區
--   略過可視區外    UIElement.java:1603-1614（父層 renderClippedChildren=false 時整個在父層外的子元件不畫，
--                   prerender 也不跑）；原版用例 ISGameSounds.lua:211
--   原生捲動 setter ISUIElement.lua:1627-1633（setScrollHeight）、:1646-1654（setScrollChildren 要 javaObject）、
--                   :1685-1699（setYScroll 夾在 [-(scrollHeight-高), 0]）、:1701-1719（updateScrollbars 再夾一次）
--   實例化          ISUIElement.lua instantiate 建 javaObject 後呼叫 createChildren
--   滾輪方向        ISScrollingListBox.lua:347-363（del < 0 往上）
--
-- 巢狀 stencil 照家族規則：prerender set → 子元件 → render clear → repaint 同一 rect（rendering.md）。
-- prerender／render 零 table／closure 配置。字串字面值只含 ASCII；本檔沒有自己的顯示文字。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme) or not ISPanel then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.scrollPanel 探測）
end

local Skin = UI.Skin

local BAR_W = 8            -- 捲軸寬
local GUTTER = BAR_W + 4   -- 右側保留給捲軸的槽（含與內容的間距）；永遠保留，內容寬不隨捲軸出現而跳動
local THUMB_MIN = 20       -- 拇指最小高度（長內容也抓得到）
local WHEEL_LINES = 3      -- 滾輪一格捲幾行（行高＝字高＋4，同 Focus 的捲動鍵）
local REVEAL_MARGIN = 4    -- scrollTo 多留的邊：焦點框（2px 間隙＋2px 框）也要看得見

local ScrollPanel = ISPanel:derive("MinidoracatUIScrollPanel")

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

-- 可捲的距離（內容高－可視高，至少 0）
local function room(panel)
    local h = panel:getScrollHeight() or 0
    return math.max(0, h - panel.height)
end

-- 拇指高與在可視區內的 y
local function thumb(panel, r)
    local h = panel.height
    local thumbH = math.max(THUMB_MIN, math.floor(h * h / (h + r)))
    local range = h - thumbH
    local offset = -(panel:getYScroll() or 0)
    return thumbH, range > 0 and math.floor(offset / r * range) or 0
end

function ScrollPanel:createChildren()
    ISPanel.createChildren(self)
    self:setScrollChildren(true)
    if self.javaObject.setRenderClippedChildren then
        self.javaObject:setRenderClippedChildren(false) -- 整個在可視區外的子元件不畫
    end
end

function ScrollPanel:contentWidth()
    return math.max(0, self.width - GUTTER)
end

-- 把子孫 el 捲進可視區（已完整可見不動；比可視區高或在上方就對齊頂端，在下方就對齊底端）
function ScrollPanel:scrollTo(el)
    if type(el) ~= "table" or el.getAbsoluteY == nil then
        return
    end
    local scroll = self:getYScroll() or 0
    local view = -scroll
    local top = el:getAbsoluteY() - self:getAbsoluteY() - scroll -- el 在內容座標的上緣
    local h = el.height or 0
    local y = view
    if top - REVEAL_MARGIN < view or h + REVEAL_MARGIN * 2 > self.height then
        y = top - REVEAL_MARGIN
    elseif top + h + REVEAL_MARGIN > view + self.height then
        y = top + h + REVEAL_MARGIN - self.height
    end
    if y ~= view then
        self:setYScroll(-y)
    end
end

function ScrollPanel:prerender()
    if self.isCollapsed then
        return
    end
    -- 內容高＝可見子元件的最大下緣；變了才交給原生（setScrollHeight 會把超出的捲動位置夾回來）
    local bottom = 0
    local kids = self.childrenInOrder
    if kids then
        for i = 1, #kids do
            local c = kids[i]
            if c:getIsVisible() then
                local b = (c.y or 0) + (c.height or 0)
                if b > bottom then bottom = b end
            end
        end
    end
    if bottom ~= self._contentH then
        self._contentH = bottom
        self:setScrollHeight(bottom)
    end
    self:setStencilRect(0, 0, self.width, self.height)
    self._clipped = true
end

function ScrollPanel:render()
    if not self._clipped then
        return -- prerender 沒 set（收合）：不 clear，stencil 成對
    end
    self._clipped = false
    self:clearStencilRect()
    self:repaintStencilRect(0, 0, self.width, self.height)
    local r = room(self)
    if r <= 0 then
        return
    end
    -- 自身繪製吃 yScroll（UIElement.java:469-483）：可視區座標 v 要傳 v - yScroll
    local sy = -(self:getYScroll() or 0)
    local colors = self.theme.colors
    local ca = chromeAlpha(self.theme)
    local shape = Skin.shapeOf(self.theme, "control")
    local x = self.width - BAR_W
    Skin.fill(self, x, sy, BAR_W, self.height, colors.well, shape, ca)
    local thumbH, thumbY = thumb(self, r)
    local my = self:getMouseY() - sy -- getMouseY 也扣了自身 scroll（見 viewMouseY）
    local hot = self._drag or (self:isMouseOver() and self:getMouseX() >= x and my >= thumbY and my < thumbY + thumbH)
    Skin.fill(self, x, sy + thumbY, BAR_W, thumbH, hot and colors.textMuted or colors.textFaint, shape, ca)
end

function ScrollPanel:onMouseWheel(del)
    if room(self) <= 0 then
        return false -- 不能捲：交給父層
    end
    self:setYScroll((self:getYScroll() or 0) - del * self._wheelStep)
    return true
end

-- 捲軸在可視區座標，滑鼠座標卻都是扣過自身 scroll 的內容座標：引擎傳給自己 onMouseDown 的
-- （UIElement.java:1113-1121：x - xScroll、y - yScroll），以及 ISUIElement:getMouseX/Y（ISUIElement.lua:339-351）。
-- 一律加回 getYScroll() 再和捲軸比。
local function viewMouseY(panel)
    return panel:getMouseY() + (panel:getYScroll() or 0)
end

-- 捲軸：按在拇指上拖曳，按在軌道上往該方向跳一頁（子元件先被問，捲軸槽裡沒有子元件）
function ScrollPanel:onMouseDown(x, y)
    local r = room(self)
    local scroll = self:getYScroll() or 0
    y = y + scroll
    if r > 0 and x >= self.width - BAR_W then
        local thumbH, thumbY = thumb(self, r)
        if y >= thumbY and y < thumbY + thumbH then
            self._drag, self._grab = true, y - thumbY
            self:setCapture(true)
        else
            self:setYScroll(y < thumbY and scroll + self.height or scroll - self.height)
        end
    end
    return true
end

local function drag(panel)
    if not panel._drag then
        return false
    end
    local r = room(panel)
    local thumbH = thumb(panel, r)
    local range = panel.height - thumbH
    if r > 0 and range > 0 then
        local y = math.max(0, math.min(viewMouseY(panel) - panel._grab, range))
        panel:setYScroll(-(y / range) * r)
    end
    return true
end

local function release(panel)
    if not panel._drag then
        return false
    end
    panel._drag = nil
    panel:setCapture(false)
    return true
end

function ScrollPanel:onMouseMove(dx, dy) return drag(self) end
function ScrollPanel:onMouseMoveOutside(dx, dy) return drag(self) end
function ScrollPanel:onMouseUp(x, y) return release(self) end
function ScrollPanel:onMouseUpOutside(x, y) return release(self) end

function ScrollPanel.new(opts)
    opts = opts or {}
    local o = ISPanel.new(ScrollPanel, opts.x or 0, opts.y or 0, opts.width or 200, opts.height or 200)
    o.background = false
    o.theme = opts.theme or UI.Theme.create()
    o.font = opts.font or o.theme.font or UIFont.Small
    o._wheelStep = WHEEL_LINES * math.max(16, getTextManager():getFontHeight(o.font) + 4)
    o._scrollPanel = true -- Focus 認這個標記（自動捲到焦點、翻頁鍵、右搖桿）
    o._contentH = -1
    o:initialise()
    return o
end

UI.ScrollPanel = ScrollPanel
UI.CAPABILITIES.scrollPanel = true

return ScrollPanel
