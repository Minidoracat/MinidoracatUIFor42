-- MinidoracatUI V1 — 家族共用 UI 函式庫核心（Theme 雙色系 + Skin 圓角繪製 + 版本化 facade）。
--
-- 【單檔設計】Theme／Skin／facade 刻意放同一檔：PZ 的 require 不保證回傳值（原版 Lua
-- 全樹零取值用例），跨檔共享只能靠全域；分檔就得靠「全域存在檢查」串接，正是 NeatUI
-- 隱藏載入順序依賴的坑（其 scrollview 用 NIScrollBar 卻只 require ISUIElement）。單檔
-- 讓「任何一段 error ＝ 整檔中止 ＝ facade 從未發布」自然成立（Kahlua 執行失敗的檔案
-- 仍會被標記 loaded、同 session 不重試，LuaManager.java:1383-1402——半初始化 table
-- 是真實風險，不是潔癖）。v0.2 起的 Widget 各自成檔、單向依賴本檔的全域。
--
-- 【API 契約】（docs/ARCHITECTURE.md §2）
--   唯一全域 `MinidoracatUI`；`MinidoracatUI.v1` 在檔尾全部成功後才賦值。
--   同 major 只做 additive 變更、API_REVISION 單調遞增；breaking ＝ 開新 MOD ID。
--   consumer 樣板：
--     require "MinidoracatUI/V1"
--     local UI = MinidoracatUI and MinidoracatUI.v1
--     if not (UI and UI.API_MAJOR == 1 and UI.API_REVISION >= 1) then
--         -- 當框架不存在處理：走 adapter 的直角退回，不得帶半套狀態運行
--     end
--
-- 【繪製紅線】任何貼圖缺失／NinePatchTexture 不可用（dedicated、測試 harness、
-- 壞檔），一律退回 drawRect／drawRectBorder 直角路徑——絕不讓視窗開不了或畫面空白。
--
-- 【引擎出處】（AGENTS.md API 表，快照 42.20.3-20260817）
--   NinePatchTexture.getSharedTexture 首呼叫必回 null（NinePatchTexture.java:56-63，
--   第二次才命中 :46-48）；壞路徑進 s_nullTextures 永久黑名單（:43-44,:53,:57-58）。
--   npt:render 吃絕對螢幕座標、不 floor（:149-222）；getAbsoluteX/Y 只含 parent 鏈
--   scroll、不含自身（UIElement.java:930-948）→ 手補 getXScroll/getYScroll 再 floor。
--   drawTextureScaled 的 r/g/b 直接進頂點色（UIElement.java DrawTextureScaledCol）
--   → 全部貼圖純白、運行時染色，一套資產服務所有主題。

-- ============================================================
-- Skin — 無狀態圓角繪製核心
-- ============================================================
-- shape 參數（fill／border／fits 共用）：
--   nil / false / "round"  → 四角圓 r=6（最小 12×12）
--   true / "roundTop"      → 上兩角圓、下方直角（最小 12×6）
--   "rect"                 → 強制直角退回（不取貼圖）
-- boolean 形式與家族既有 topOnly 呼叫慣例逐位相容——adapter 零翻譯。

local Skin = {}

local TEXTURE_DIR = "media/ui/MinidoracatUI/"
local CORNER = 6 -- 貼圖角落＝圓角半徑（切線 6/4/6；規格 docs/UI_SKIN_TEXTURES.md）

-- 檔名 -> NinePatchTexture／Texture；false = 載入失敗，session 內不再重試
-- （引擎那端同名已進永久黑名單，重試只是每幀白繳一次 pcall）
local textures = {}

-- 只給測試用：在「沒有 NinePatchTexture／有／壞掉」環境間切換時清掉載入狀態
function Skin._resetForTests()
    textures = {}
end

local function shapeName(shape)
    if shape == true or shape == "roundTop" then
        return "roundTop"
    end
    if shape == "rect" then
        return "rect"
    end
    return "round"
end

-- 矩形夠不夠大到能走 9-slice。太小不縮角落也不讓角落重疊（重疊帶的半透明填色會
-- 疊成雙倍 alpha；NeatUI 式的等比縮角落則把 AA 弧線拉糊）——直角是最誠實的降級。
function Skin.fits(width, height, shape)
    local kind = shapeName(shape)
    if kind == "rect" then
        return false
    end
    local minimumHeight = CORNER * 2
    if kind == "roundTop" then
        minimumHeight = CORNER
    end
    return width >= CORNER * 2 and height >= minimumHeight
end

local function ninePatch(name)
    local cached = textures[name]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    if not NinePatchTexture or not NinePatchTexture.getSharedTexture then
        textures[name] = false
        return nil
    end
    local ok, loaded = pcall(function()
        local path = TEXTURE_DIR .. name
        -- 首呼叫載入完直接回 null、第二次才命中快取；已在快取時 or 短路不多呼叫。
        -- 兩次都 nil＝檔案不存在或已進黑名單。
        return NinePatchTexture.getSharedTexture(path)
            or NinePatchTexture.getSharedTexture(path)
    end)
    if not ok or not loaded then
        textures[name] = false
        return nil
    end
    textures[name] = loaded
    return loaded
end

local function plainTexture(name)
    local cached = textures[name]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    if type(getTexture) ~= "function" then
        textures[name] = false
        return nil
    end
    local ok, loaded = pcall(getTexture, TEXTURE_DIR .. name)
    if not ok or not loaded then
        textures[name] = false
        return nil
    end
    textures[name] = loaded
    return loaded
end

-- pcall 用具名頂層函式＋傳參：inline closure 會在每次 fill/border 配置一個捕捉
-- 外層變數的匿名函式——皮膚視窗每幀 3+ 呼叫＝穩定 GC 壓力；pcall(fn, args...) 零配置。
local function renderNine(npt, ax, ay, w, h, r, g, b, a)
    npt:render(ax, ay, w, h, r, g, b, a)
end

-- 回 true＝已用 9-slice 畫完；false＝呼叫端走直角退回。
local function drawNinePatch(element, name, x, y, width, height, color, alpha)
    local npt = ninePatch(name)
    if not npt then
        return false
    end
    -- 絕對座標＋自身捲動位移：getAbsoluteX/Y 只含 parent 鏈 scroll、不含自身，
    -- 而 drawRect 系繪製上下文吃自身 scroll——9-slice 走絕對螢幕座標必須手補，
    -- 否則捲動清單內的列高亮會錯位（非捲動視窗 getXScroll()=0 無害）。
    -- floor 必做：render 不 floor，GL_NEAREST 遇半像素在邊上抖 1px（動畫座標是小數）。
    local ax = math.floor(element:getAbsoluteX() + element:getXScroll() + x)
    local ay = math.floor(element:getAbsoluteY() + element:getYScroll() + y)
    local ok = pcall(renderNine, npt, ax, ay, math.floor(width), math.floor(height),
        color.r, color.g, color.b, alpha)
    if not ok then
        -- PNG 檔在但解碼失敗時 load 仍回非 null 資產（內部 texture 為 null），
        -- render 才 NPE——只有這條路徑會拋。標壞，之後同名直接退回。
        textures[name] = false
        return false
    end
    return true
end

-- 圓角填色。alphaScale 是動畫用的 alpha 乘數。
function Skin.fill(element, x, y, width, height, color, shape, alphaScale)
    local alpha = (color.a or 1) * (alphaScale or 1)
    if Skin.fits(width, height, shape) then
        local name = shapeName(shape) == "roundTop"
            and "mui_roundtop_fill.png" or "mui_round_fill.png"
        if drawNinePatch(element, name, x, y, width, height, color, alpha) then
            return
        end
    end
    element:drawRect(x, y, width, height, alpha, color.r, color.g, color.b)
end

-- 1px 圓角邊框。roundTop＝上圓、底邊開放的 3 邊框（頁籤形）。
function Skin.border(element, x, y, width, height, color, shape, alphaScale)
    local alpha = (color.a or 1) * (alphaScale or 1)
    if Skin.fits(width, height, shape) then
        local name = shapeName(shape) == "roundTop"
            and "mui_roundtop_border.png" or "mui_round_border.png"
        if drawNinePatch(element, name, x, y, width, height, color, alpha) then
            return
        end
    end
    element:drawRectBorder(x, y, width, height, alpha, color.r, color.g, color.b)
end

-- 圓點（未讀徽章等）：外圈放大 1px 當光暈（描邊色），再疊主點。
-- 貼圖走 GL_LINEAR，16→8 是 2:1 縮小、每像素平均 2×2 texel，邊緣乾淨。
-- 貼圖缺時退回方點＋描邊。outline 可省略（只畫主點）。
function Skin.dot(element, x, y, size, color, outline)
    local texture = plainTexture("mui_dot.png")
    if texture then
        if outline then
            element:drawTextureScaled(texture, x - 1, y - 1, size + 2, size + 2,
                outline.a or 1, outline.r, outline.g, outline.b)
        end
        element:drawTextureScaled(texture, x, y, size, size,
            color.a or 1, color.r, color.g, color.b)
        return
    end
    element:drawRect(x, y, size, size, color.a or 1, color.r, color.g, color.b)
    if outline then
        element:drawRectBorder(x, y, size, size,
            outline.a or 1, outline.r, outline.g, outline.b)
    end
end

-- ============================================================
-- Theme — token 化色票（深／淺雙色系），每 MOD 一個實例
-- ============================================================
-- 跨 MOD token（framework default 只認這些；名單見 docs/ARCHITECTURE.md §3.2）：
--   surface / surfaceTitle / well / border / text / textMuted / textFaint /
--   accent / hover / selected / errorSurface / errorText
-- MOD 自有 token（unread、rowHover…）由 create 的 colors 自帶，框架原樣收下。
-- create() 逐 token 深拷貝——共享 default 永不被 mutate（NBSkin↔MiniMap 色票
-- 複製分岔的根源就是「共用色票、各自持有可變引用」）。

local Theme = {}

-- 深色（預設）：數值提煉自家族現況（NBSkin.COLORS／MiniMap Skin.COLORS 的共通部分），
-- 遷移後視覺逐位不變。
local DARK = {
    surface      = { r = 0,    g = 0,    b = 0,    a = 0.8 },
    surfaceTitle = { r = 1,    g = 1,    b = 1,    a = 0.10 },
    well         = { r = 0,    g = 0,    b = 0,    a = 0.5 },
    border       = { r = 0.4,  g = 0.4,  b = 0.4,  a = 1.0 },
    text         = { r = 1,    g = 1,    b = 1,    a = 1.0 },
    textMuted    = { r = 0.62, g = 0.62, b = 0.62, a = 1.0 },
    textFaint    = { r = 0.55, g = 0.55, b = 0.55, a = 1.0 },
    accent       = { r = 1,    g = 0.85, b = 0.4,  a = 1.0 },
    hover        = { r = 1,    g = 1,    b = 1,    a = 0.06 },
    selected     = { r = 1,    g = 1,    b = 1,    a = 0.12 },
    errorSurface = { r = 0.3,  g = 0.05, b = 0.05, a = 0.5 },
    errorText    = { r = 0.9,  g = 0.35, b = 0.3,  a = 1.0 },
}

-- 淺色（experimental，v0.1 首發後依實測調值）：白色疊層族改黑色疊層、
-- 琥珀在亮底上加深以保持對比。
local LIGHT = {
    surface      = { r = 0.92, g = 0.92, b = 0.90, a = 0.92 },
    surfaceTitle = { r = 0,    g = 0,    b = 0,    a = 0.08 },
    well         = { r = 0,    g = 0,    b = 0,    a = 0.08 },
    border       = { r = 0.35, g = 0.35, b = 0.35, a = 1.0 },
    text         = { r = 0.08, g = 0.08, b = 0.08, a = 1.0 },
    textMuted    = { r = 0.35, g = 0.35, b = 0.35, a = 1.0 },
    textFaint    = { r = 0.45, g = 0.45, b = 0.45, a = 1.0 },
    accent       = { r = 0.75, g = 0.55, b = 0.1,  a = 1.0 },
    hover        = { r = 0,    g = 0,    b = 0,    a = 0.05 },
    selected     = { r = 0,    g = 0,    b = 0,    a = 0.10 },
    errorSurface = { r = 0.9,  g = 0.75, b = 0.75, a = 0.7 },
    errorText    = { r = 0.6,  g = 0.1,  b = 0.08, a = 1.0 },
}

local PALETTES = { dark = DARK, light = LIGHT }

local function copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

-- 取 default palette 的拷貝（供檢視／測試；回傳值可任意改，不影響框架）
function Theme.defaultPalette(variant)
    local base = PALETTES[variant or "dark"]
    if not base then
        return nil
    end
    local copy = {}
    for token, color in pairs(base) do
        copy[token] = copyColor(color)
    end
    return copy
end

-- theme 實例方法（共享 prototype，零 per-instance 配置）。
-- fill/border/dot 的 color 參數接受 token 字串（查 self.colors）或 color table
-- （直接用）；未知 token 靜默不畫（fail-soft：不畫也不炸）。
local ThemeProto = {}
ThemeProto.__index = ThemeProto

local function resolveColor(self, color)
    if type(color) == "string" then
        return self.colors[color]
    end
    return color
end

function ThemeProto:fill(element, x, y, width, height, color, shape, alphaScale)
    local resolved = resolveColor(self, color)
    if not resolved then
        return
    end
    Skin.fill(element, x, y, width, height, resolved, shape, alphaScale)
end

function ThemeProto:border(element, x, y, width, height, color, shape, alphaScale)
    local resolved = resolveColor(self, color)
    if not resolved then
        return
    end
    Skin.border(element, x, y, width, height, resolved, shape, alphaScale)
end

function ThemeProto:dot(element, x, y, size, color, outline)
    local resolved = resolveColor(self, color)
    if not resolved then
        return
    end
    Skin.dot(element, x, y, size, resolved, resolveColor(self, outline))
end

-- 建立 theme：opts = { variant = "dark"|"light"（預設 dark）, colors = { token = {r,g,b,a}, ... } }
-- colors 的每顆 color table 都被拷貝（consumer 事後改自己的 table 不影響 theme）；
-- 覆蓋是整顆 token 替換，不做 r/g/b/a 欄位級合併。
function Theme.create(opts)
    opts = opts or {}
    local variant = opts.variant or "dark"
    local base = PALETTES[variant]
    if not base then
        variant = "dark"
        base = DARK
    end
    local colors = {}
    for token, color in pairs(base) do
        colors[token] = copyColor(color)
    end
    if opts.colors then
        for token, color in pairs(opts.colors) do
            colors[token] = copyColor(color)
        end
    end
    return setmetatable({ variant = variant, colors = colors }, ThemeProto)
end

-- ============================================================
-- facade — 全部成功後才發布（本檔任何一處 error 都會讓 v1 從未存在）
-- ============================================================

MinidoracatUI = MinidoracatUI or {}
MinidoracatUI.v1 = {
    VERSION = "0.1.0",
    API_MAJOR = 1,
    API_REVISION = 1,
    CAPABILITIES = {
        theme = true,
        skin = true,
        floatButton = false, -- v0.2
        toast = false,       -- v0.2
        virtualList = false, -- v0.3
    },
    Theme = Theme,
    Skin = Skin,
}

return MinidoracatUI.v1
