--[[
煙霧測試：用假的 PZ 全域載入**真正的** V1.lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/assert/xpcall，Kahlua 沒有——誤用由 scripts/verify_mod.py 靜態掃描負責
- Kahlua 專屬行為（Java field 不暴露、table 記憶體形狀）只能靠反編譯查證與實機測試

四情境（docs/ARCHITECTURE.md §7）：
1. facade 半初始化——檔案中段注入 error，斷言 MinidoracatUI.v1 從未發布
2. NinePatch 三態——E0 無全域／E1 正常（含引擎首呼叫回 nil 語意）／E2 壞掉，
   fill/border/dot 一律不拋錯、退回正確、座標 floor、自身 scroll 補償、壞名不重試
3. theme 隔離——兩實例互不污染、default 不被 mutate、light variant、token 字串解析
4. fits 邊界——round 12×12／roundTop 12×6 下限、boolean topOnly 相容、"rect" 強制退回
]]

local V1_PATH = "MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42/42/media/lua/client/MinidoracatUI/V1.lua"
local load_ = loadstring or load -- Lua 5.1 / 5.2+ 兼容

-- ===== 測試工具 =====
local failures = 0
local function check(ok, label)
    if ok then print("  PASS  " .. label)
    else failures = failures + 1; print("  FAIL  " .. label) end
end
local function nearly(a, b) return math.abs(a - b) < 1e-9 end

-- ===== 繪製落點 stub 元件 =====
local function newElement(absX, absY, scrollX, scrollY)
    local el = { rects = {}, borders = {}, tex = {} }
    function el:getAbsoluteX() return absX end
    function el:getAbsoluteY() return absY end
    function el:getXScroll() return scrollX or 0 end
    function el:getYScroll() return scrollY or 0 end
    function el:drawRect(x, y, w, h, a, r, g, b)
        el.rects[#el.rects + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
    end
    function el:drawRectBorder(x, y, w, h, a, r, g, b)
        el.borders[#el.borders + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
    end
    function el:drawTextureScaled(tex, x, y, w, h, a, r, g, b)
        el.tex[#el.tex + 1] = { tex = tex, x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
    end
    return el
end

-- ===== NinePatchTexture stub（仿引擎語意：首呼叫回 null，NinePatchTexture.java:56-63）=====
local function makeNinePatchStub(options)
    options.calls = options.calls or {}
    options.patches = options.patches or {}
    return {
        getSharedTexture = function(path)
            options.calls[path] = (options.calls[path] or 0) + 1
            if options.alwaysNil then return nil end
            if options.calls[path] == 1 then return nil end
            return {
                render = function(_, x, y, w, h, r, g, b, a)
                    if options.throwOnRender then error("simulated decode NPE") end
                    local p = options.patches
                    p[#p + 1] = { path = path, x = x, y = y, w = w, h = h, r = r, g = g, b = b, a = a }
                end,
            }
        end,
    }
end

-- ============================================================
print("情境一：facade 半初始化（中段 error 不得發布 v1）")
-- ============================================================
do
    local fh = io.open(V1_PATH, "rb")
    check(fh ~= nil, "V1.lua 存在於 MOD 樹")
    local source = fh:read("*a")
    fh:close()

    -- 正常載入：v1 存在且形狀完整
    MinidoracatUI = nil
    local chunk = load_(source, "@V1.lua")
    check(chunk ~= nil, "V1.lua 可編譯")
    local ok, ret = pcall(chunk)
    check(ok, "V1.lua 正常執行")
    check(MinidoracatUI ~= nil and MinidoracatUI.v1 ~= nil, "全域 MinidoracatUI.v1 已發布")
    local v1 = MinidoracatUI.v1
    check(ret == v1, "檔尾 return 與全域是同一實體")
    check(v1.API_MAJOR == 1 and v1.API_REVISION >= 1, "API_MAJOR/API_REVISION 形狀正確")
    check(v1.CAPABILITIES.theme == true and v1.CAPABILITIES.skin == true, "CAPABILITIES 宣告 theme/skin")
    check(v1.CAPABILITIES.floatButton == false and v1.CAPABILITIES.virtualList == false,
        "未實作能力誠實標 false")

    -- 注入 error：把 PALETTES 定義行換成 error()，模擬檔案中段失敗
    MinidoracatUI = nil
    local sabotaged, hits = source:gsub("local PALETTES = ", "error('injected mid-file failure') local PALETTES = ", 1)
    check(hits == 1, "注入點命中（PALETTES 定義）")
    local badChunk = load_(sabotaged, "@V1-sabotaged.lua")
    local badOk = pcall(badChunk)
    check(badOk == false, "中段 error 讓整檔中止")
    check(MinidoracatUI == nil or MinidoracatUI.v1 == nil,
        "半初始化時 v1 從未發布（facade 最後賦值鐵則）")

    -- 恢復正常載入供後續情境使用
    MinidoracatUI = nil
    pcall(load_(source, "@V1.lua"))
end

local UI = MinidoracatUI.v1
local Skin = UI.Skin
local Theme = UI.Theme
local SURFACE = { r = 0, g = 0, b = 0, a = 0.8 }
local BORDER_C = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 }

-- ============================================================
print("情境二：NinePatch 三態（E0 無全域／E1 正常／E2 壞掉）")
-- ============================================================
do
    -- E0：無 NinePatchTexture、無 getTexture → 全退回，不拋錯
    NinePatchTexture = nil
    getTexture = nil
    Skin._resetForTests()
    local el = newElement(100, 50)
    Skin.fill(el, 5, 6, 200, 100, SURFACE)
    Skin.border(el, 5, 6, 200, 100, BORDER_C)
    Skin.dot(el, 3, 3, 8, { r = 0.85, g = 0.15, b = 0.15, a = 1 }, { r = 0, g = 0, b = 0, a = 0.6 })
    check(#el.rects == 2 and #el.borders == 2, "E0 fill/border/dot 全落直角退回")
    check(el.rects[1].x == 5 and el.rects[1].w == 200 and nearly(el.rects[1].a, 0.8),
        "E0 退回矩形座標與 alpha 正確（相對座標、不加 absolute）")

    -- E1：正常貼圖（首呼叫回 nil 語意）＋floor＋scroll 補償＋alphaScale
    local good = {}
    NinePatchTexture = makeNinePatchStub(good)
    Skin._resetForTests()
    local el1 = newElement(1000.0, 400.0, 0, -37) -- 模擬捲動容器內：yScroll = -37
    Skin.fill(el1, 2.6, 1.4, 300, 56, SURFACE, nil, 0.4)
    check(#good.patches == 1, "E1 fill 走 9-slice")
    local p = good.patches[1]
    check(p.path == "media/ui/MinidoracatUI/mui_round_fill.png", "E1 取 round fill 貼圖")
    check(p.x == 1002 and p.y == 364, "E1 絕對座標＋自身 scroll 補償＋floor（1002.6→1002、364.4→364）")
    check(nearly(p.a, 0.8 * 0.4), "E1 alpha 乘上 alphaScale")
    check(good.calls[p.path] == 2, "E1 首呼叫 nil 語意下恰好呼叫兩次 getSharedTexture")
    Skin.fill(el1, 0, 0, 100, 40, SURFACE)
    check(good.calls[p.path] == 2, "E1 第二次 fill 命中內部快取，不再呼叫 getSharedTexture")
    Skin.fill(el1, 0, 0, 100, 40, SURFACE, true)
    check(good.patches[#good.patches].path == "media/ui/MinidoracatUI/mui_roundtop_fill.png",
        "E1 topOnly=true 取 roundtop 貼圖（boolean 相容）")
    Skin.border(el1, 0, 0, 100, 40, BORDER_C, "roundTop")
    check(good.patches[#good.patches].path == "media/ui/MinidoracatUI/mui_roundtop_border.png",
        "E1 shape 字串 roundTop 取 roundtop border")

    -- E1 dot：getTexture stub（光暈＋主點兩次繪製、白圖染色引數順序 a,r,g,b）
    getTexture = function(path) return { path = path } end
    Skin._resetForTests()
    local el2 = newElement(0, 0)
    Skin.dot(el2, 10, 20, 8, { r = 0.85, g = 0.15, b = 0.15, a = 1 }, { r = 0, g = 0, b = 0, a = 0.6 })
    check(#el2.tex == 2, "E1 dot 畫光暈＋主點兩層")
    check(el2.tex[1].x == 9 and el2.tex[1].w == 10 and nearly(el2.tex[1].a, 0.6), "E1 dot 光暈外擴 1px、alpha 用 outline")
    check(el2.tex[2].x == 10 and el2.tex[2].w == 8 and nearly(el2.tex[2].a, 1), "E1 dot 主點原位")
    Skin.dot(el2, 0, 0, 8, { r = 1, g = 1, b = 1, a = 1 })
    check(#el2.tex == 3, "E1 dot 省略 outline 只畫主點")

    -- E2a：貼圖永遠 nil → 退回＋同名不重試
    local badNil = { alwaysNil = true }
    NinePatchTexture = makeNinePatchStub(badNil)
    Skin._resetForTests()
    local el3 = newElement(0, 0)
    Skin.fill(el3, 0, 0, 100, 40, SURFACE)
    Skin.fill(el3, 0, 0, 100, 40, SURFACE)
    Skin.fill(el3, 0, 0, 100, 40, SURFACE)
    check(#el3.rects == 3, "E2a 三次 fill 全退回直角")
    check(badNil.calls["media/ui/MinidoracatUI/mui_round_fill.png"] == 2,
        "E2a 壞名只探測一輪（雙呼叫），之後 false 快取不重試")

    -- E2b：render 拋錯（PNG 損毀 NPE 路徑）→ 該幀退回、標壞、不拋出
    local badRender = { throwOnRender = true }
    NinePatchTexture = makeNinePatchStub(badRender)
    Skin._resetForTests()
    local el4 = newElement(0, 0)
    local frameOk = pcall(Skin.fill, el4, 0, 0, 100, 40, SURFACE)
    check(frameOk, "E2b render 拋錯不外洩（pcall 包住）")
    check(#el4.rects == 1, "E2b 拋錯當幀落直角退回")
    Skin.fill(el4, 0, 0, 100, 40, SURFACE)
    check(#el4.rects == 2 and badRender.calls["media/ui/MinidoracatUI/mui_round_fill.png"] == 2,
        "E2b 拋錯後標壞：下幀直接退回、不再取貼圖")

    NinePatchTexture = nil
    getTexture = nil
    Skin._resetForTests()
end

-- ============================================================
print("情境三：theme 隔離（實例互不污染、default 不可變、雙色系）")
-- ============================================================
do
    local a = Theme.create({ colors = { accent = { r = 0.1, g = 0.2, b = 0.3, a = 1 } } })
    local b = Theme.create()
    check(nearly(a.colors.accent.r, 0.1), "A 實例吃到 override")
    check(nearly(b.colors.accent.r, 1) and nearly(b.colors.accent.g, 0.85), "B 實例維持 default（不被 A 污染）")

    a.colors.surface.r = 0.99 -- 惡意就地竄改實例
    local fresh = Theme.defaultPalette("dark")
    check(nearly(fresh.surface.r, 0), "實例竄改不回滲 default palette")

    local override = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 }
    local c = Theme.create({ colors = { surface = override } })
    override.r = 0.77 -- consumer 事後改自己的 table
    check(nearly(c.colors.surface.r, 0.5), "create 拷貝 override（consumer 事後竄改不影響 theme）")

    local light = Theme.create({ variant = "light" })
    check(nearly(light.colors.surface.r, 0.92) and light.variant == "light", "light variant 拿到淺色 palette")
    check(nearly(Theme.create({ variant = "nosuch" }).colors.surface.a, 0.8), "未知 variant 退回 dark")

    -- token 字串解析：theme:fill 走 Skin（E0 環境 → 直角退回可觀測）
    local el = newElement(0, 0)
    light:fill(el, 0, 0, 50, 20, "surface")
    check(#el.rects == 1 and nearly(el.rects[1].a, 0.92), "theme:fill 以 token 字串解析色票")
    light:fill(el, 0, 0, 50, 20, { r = 1, g = 0, b = 0, a = 1 })
    check(#el.rects == 2 and nearly(el.rects[2].r, 1), "theme:fill 直接吃 color table")
    light:fill(el, 0, 0, 50, 20, "noSuchToken")
    check(#el.rects == 2, "未知 token 靜默不畫（不炸、不誤畫）")
end

-- ============================================================
print("情境四：fits 邊界與 shape 相容")
-- ============================================================
do
    check(Skin.fits(12, 12) == true, "round 下限 12x12 可畫")
    check(Skin.fits(11, 12) == false and Skin.fits(12, 11) == false, "round 低於下限退回")
    check(Skin.fits(12, 6, true) == true, "roundTop（boolean）下限 12x6 可畫")
    check(Skin.fits(12, 5, "roundTop") == false, "roundTop 低於下限退回")
    check(Skin.fits(12, 6, "roundTop") == Skin.fits(12, 6, true), "boolean topOnly 與字串 roundTop 等價")
    check(Skin.fits(500, 500, "rect") == false, "rect 形狀永遠走直角（強制退回）")

    -- 小矩形實繪驗證：貼圖存在也不走 9-slice
    local tiny = {}
    NinePatchTexture = makeNinePatchStub(tiny)
    Skin._resetForTests()
    local el = newElement(0, 0)
    Skin.fill(el, 0, 0, 11, 11, SURFACE)
    check(#el.rects == 1 and tiny.calls["media/ui/MinidoracatUI/mui_round_fill.png"] == nil,
        "尺寸不足時不取貼圖直接退回（角落重疊會疊 alpha）")
    NinePatchTexture = nil
    Skin._resetForTests()
end

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
