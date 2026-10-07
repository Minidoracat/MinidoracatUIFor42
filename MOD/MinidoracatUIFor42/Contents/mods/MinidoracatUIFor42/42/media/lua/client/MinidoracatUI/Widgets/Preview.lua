-- MinidoracatUI Widgets/Preview — 效果預覽框（API rev 17，CAPABILITIES.preview）：UI.Preview。
-- 圓角 well 每幀呼叫 consumer 的 draw(self, x, y, w, h)，畫在內框裡、超出的部分用 stencil 裁掉；
-- 設定視窗用它畫「調了這個選項之後地圖上長什麼樣」（與地圖共用同一組繪製函式）。
--
--   UI.Preview.new{ x?, y?, width, height, theme?, draw?, caption? } -> 已 initialise() 的元素（consumer addChild）
--   方法：setDraw(fn)、setCaption(text)
--   draw(self, x, y, w, h)：x, y, w, h 是內框（元素座標，四邊內縮 INSET）；在裡面用 self:drawRect／drawTextureScaled
--     等原生繪製即可。draw 拋錯：以 pcall 攔下、不 log，之後不再呼叫，直到 setDraw 再給一次（同一個函式也算）
--   caption：內框左上角的小字（UIFont.Small、textMuted），畫在 draw 之上；放不下截字
--
-- 巢狀 stencil 照家族規則：set → draw → clear → repaintStencilRect 同一 rect（rendering.md；做錯會讓同幀之後
-- 所有 MOD 的 UI 消失）。set 與 clear 在同一個函式裡配對、中間的 draw 以 pcall 包住，拋錯也一定 clear。
-- prerender 零 table／closure 配置（pcall 傳參）。字串字面值只含 ASCII；本檔沒有自己的顯示文字。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Text) or not ISPanel then
    return -- 核心或原生基底缺席：不掛能力（consumer 以 CAPABILITIES.preview 探測）
end

local Skin = UI.Skin

local INSET = 2       -- 內框離外框：1px 框線＋1px 留白
local CAPTION_PAD = 4 -- 說明文字離內框左上

local Preview = ISPanel:derive("MinidoracatUIPreview")

local function chromeAlpha(theme)
    local a = theme.alpha
    return type(a) == "number" and a or 1
end

function Preview:prerender()
    if self.isCollapsed then
        return
    end
    local w, h = self.width, self.height
    local colors = self.theme.colors
    local shape = Skin.shapeOf(self.theme, "control")
    local ca = chromeAlpha(self.theme)
    Skin.fill(self, 0, 0, w, h, colors.well, shape, ca)
    Skin.border(self, 0, 0, w, h, colors.border, shape, ca)
    local iw, ih = w - INSET * 2, h - INSET * 2
    if iw <= 0 or ih <= 0 then
        return
    end
    local draw = self._draw
    if draw ~= nil and not self._failed then
        self:setStencilRect(INSET, INSET, iw, ih)
        if not pcall(draw, self, INSET, INSET, iw, ih) then
            self._failed = true -- 不 log（框架預設零 log）；setDraw 之前不再呼叫
        end
        self:clearStencilRect()
        self:repaintStencilRect(INSET, INSET, iw, ih)
    end
    local caption = self._caption
    if caption ~= nil then
        if caption ~= self._capSrc or iw ~= self._capW then
            self._capSrc, self._capW = caption, iw
            self._capFit = UI.Text.fit(caption, iw - CAPTION_PAD * 2, UIFont.Small)
        end
        if self._capFit ~= "" then
            local c = colors.textMuted
            self:drawText(self._capFit, INSET + CAPTION_PAD, INSET + 1, c.r, c.g, c.b, c.a or 1, UIFont.Small)
        end
    end
end

-- 換繪製函式（nil＝只畫空框）；也清掉「已出錯」狀態，同一個函式再給一次就重試
function Preview:setDraw(fn)
    self._draw = type(fn) == "function" and fn or nil
    self._failed = nil
end

-- 說明文字（nil 或 ""＝不畫）
function Preview:setCaption(text)
    if text == "" then
        text = nil
    end
    self._caption = text
end

function Preview.new(opts)
    opts = opts or {}
    local o = ISPanel.new(Preview, opts.x or 0, opts.y or 0, opts.width or 200, opts.height or 60)
    o.background = false
    o.theme = opts.theme or UI.Theme.create()
    o:setDraw(opts.draw)
    o:setCaption(opts.caption)
    o:initialise()
    return o
end

UI.Preview = Preview
UI.CAPABILITIES.preview = true

return Preview
