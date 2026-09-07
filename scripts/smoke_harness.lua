--[[
煙霧測試：用假的 PZ 全域載入**真正的** V1.lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/assert/xpcall，Kahlua 沒有——誤用由 scripts/verify_mod.py 靜態掃描負責
- Kahlua 專屬行為（Java field 不暴露、table 記憶體形狀）只能靠反編譯查證與實機測試

八情境（docs/ARCHITECTURE.md §7）：
1. facade 半初始化——檔案中段注入 error，斷言 MinidoracatUI.v1 從未發布
2. NinePatch 三態——E0 無全域／E1 正常（含引擎首呼叫回 nil 語意）／E2 壞掉，
   fill/border/dot 一律不拋錯、退回正確、座標 floor、自身 scroll 補償、壞名不重試
3. theme 隔離——兩實例互不污染、default 不被 mutate、light variant、token 字串解析
4. fits 邊界——round／roundTop／pill 下限、boolean topOnly 相容、"rect" 強制退回
5. rev 3 painters/assets——toggle／slider 幾何、色彩、alpha、缺資產退回與二十個 icon key
（6-8 為 widget：FloatButton／Toast／VirtualList）
]]

local V1_PATH = "MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42/42/media/lua/client/MinidoracatUI/V1.lua"
local load_ = loadstring or load -- Lua 5.1 / 5.2+ 兼容

-- ===== 測試工具 =====
local failures = 0
local assertionCount = 0
local function check(ok, label)
    assertionCount = assertionCount + 1
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
    check(v1.API_MAJOR == 1 and v1.API_REVISION == 5, "API v1 revision 5 已發布")
    check(v1.CAPABILITIES.theme == true and v1.CAPABILITIES.skin == true, "CAPABILITIES 宣告 theme/skin")
    check(v1.CAPABILITIES.floatButton == false and v1.CAPABILITIES.toast == false
        and v1.CAPABILITIES.virtualList == false, "未實作能力（floatButton/toast/virtualList）誠實標 false")

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
    Skin.fill(el1, 0, 0, 44, 20, SURFACE, "pill")
    check(good.patches[#good.patches].path == "media/ui/MinidoracatUI/mui_pill_fill.png",
        "E1 shape 字串 pill 取專用 fill 貼圖")
    Skin.border(el1, 0, 0, 44, 20, BORDER_C, "pill")
    check(good.patches[#good.patches].path == "media/ui/MinidoracatUI/mui_pill_border.png",
        "E1 shape 字串 pill 取專用 border 貼圖")

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

    -- E3：element 契約破損（缺 getXScroll 的畸形 stub）——紅線：錯誤不得穿透到
    -- 呼叫端；且 element 壞不是貼圖的錯，貼圖不得被標壞（下一個正常 element 仍走 9-slice）
    local e3 = {}
    NinePatchTexture = makeNinePatchStub(e3)
    Skin._resetForTests()
    local broken = newElement(0, 0)
    broken.getXScroll = nil
    local okBroken = pcall(Skin.fill, broken, 0, 0, 100, 40, SURFACE)
    check(okBroken and #broken.rects == 1, "E3 element 缺存取器：不炸、當幀退回直角")
    local intact = newElement(0, 0)
    Skin.fill(intact, 0, 0, 100, 40, SURFACE)
    check(#e3.patches == 1 and #intact.rects == 0,
        "E3 element 壞不標壞貼圖：正常 element 隨後仍走 9-slice")

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
    check(Skin.fits(20, 20, "pill") == true, "pill 下限 20x20 可畫")
    check(Skin.fits(19, 20, "pill") == false and Skin.fits(20, 19, "pill") == false,
        "pill 低於 20px cap 下限退回")
    check(Skin.fits(12, 12, "round") == Skin.fits(12, 12), "pill 新增不改 round 相容行為")
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

-- ============================================================
print("情境五：rev 3 toggle／slider 與 Icons（二十 key、快取、缺圖退回）")
-- ============================================================
do
    local toggleColors = {
        off = { r = 0.1, g = 0.2, b = 0.3, a = 0.8 },
        on = { r = 0.2, g = 0.7, b = 0.4, a = 0.9 },
        knob = { r = 0.9, g = 0.8, b = 0.7, a = 1 },
        border = { r = 0.6, g = 0.5, b = 0.4, a = 0.5 },
    }
    local togglePatches = {}
    NinePatchTexture = makeNinePatchStub(togglePatches)
    getTexture = function(path) return { path = path } end
    Skin._resetForTests()
    local offEl = newElement(0, 0)
    check(Skin.toggle(offEl, 10, 20, 44, 30, false, toggleColors, 0.5) == true
        and #togglePatches.patches == 2, "toggle off 畫 pill fill/border 且回 true")
    check(togglePatches.patches[1].y == 25 and togglePatches.patches[1].h == 20,
        "20px track 在 30px row 內垂直置中")
    check(offEl.tex[2].x == 12 and offEl.tex[2].y == 27
        and nearly(offEl.tex[2].r, 0.9), "toggle off knob 在左側 2px inset 且使用 knob 色")
    check(nearly(togglePatches.patches[1].r, 0.1) and nearly(togglePatches.patches[2].r, 0.6),
        "toggle off track/border 使用各自色彩")

    local onEl = newElement(0, 0)
    check(Skin.toggle(onEl, 10, 20, 44, 30, true, toggleColors, 0.5) == true
        and onEl.tex[2].x == 36 and nearly(onEl.tex[2].g, 0.8),
        "toggle on knob 在右側 2px inset 且色彩不變")
    check(nearly(togglePatches.patches[3].g, 0.7) and nearly(togglePatches.patches[3].a, 0.45)
        and nearly(onEl.tex[2].a, 0.5), "toggle on 色彩與 alphaScale 套用到 track/knob")

    local sliderColors = {
        track = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
        fill = { r = 0.9, g = 0.6, b = 0.2, a = 0.9 },
        knob = { r = 0.8, g = 0.9, b = 1, a = 1 },
        border = { r = 0.4, g = 0.5, b = 0.6, a = 0.5 },
    }
    local sliderEl = newElement(0, 0)
    check(type(Skin.slider) == "function"
        and Skin.slider(sliderEl, 10, 20, 100, 30, 0.5, sliderColors, 0.5) == true,
        "rev 3 slider painter 可探測且回 true")
    check(#sliderEl.rects == 2 and #sliderEl.borders == 1 and #sliderEl.tex == 2,
        "slider 畫 track、fill、border 與圓形 knob")
    check(sliderEl.rects[1].y == 33 and sliderEl.rects[2].w == 50
        and sliderEl.tex[2].x == 54 and sliderEl.tex[2].y == 29,
        "slider 50%% 幾何置中且 knob 落在半程")
    check(nearly(sliderEl.rects[1].a, 0.4) and nearly(sliderEl.rects[2].r, 0.9)
        and nearly(sliderEl.tex[2].a, 0.5),
        "slider 色票與 alphaScale 套用到 track/fill/knob")
    local clampedSlider = newElement(0, 0)
    check(Skin.slider(clampedSlider, 0, 0, 100, 20, 2, nil, 1) == true
        and clampedSlider.tex[2].x == 94,
        "slider ratio 夾在 0..1，max knob 中心對齊原生 hit endpoint")
    check(Skin.slider(newElement(), 0, 0, 10, 10, 0 / 0, nil, 1) == false,
        "slider 非有限 ratio／過小幾何 fail-soft 回 false")

    NinePatchTexture = nil
    getTexture = nil
    Skin._resetForTests()
    local fallback = newElement(0, 0)
    check(Skin.toggle(fallback, 0, 0, 40, 20, false, nil, 1) == true,
        "toggle 缺 colors 與全部資產時不拋錯")
    check(#fallback.rects == 2 and #fallback.borders == 2
        and nearly(fallback.rects[1].r, 0.25) and nearly(fallback.rects[2].r, 1),
        "toggle 資產失敗經 Skin 直角路徑退回並使用安全預設色")
    local fallbackSlider = newElement(0, 0)
    check(Skin.slider(fallbackSlider, 0, 0, 100, 20, 0.5, nil, 1) == true
        and #fallbackSlider.rects == 3 and #fallbackSlider.borders == 2,
        "slider 缺資產仍以直線 track／方形 knob 完整退回")
    check(Skin.toggle(nil, 0, 0, 40, 20, false, nil, 1) == false,
        "toggle 無 element 時 fail-soft 回 false")
    check(Skin.toggle(newElement(), 0, 0, 19, 19, false, nil, 1) == false,
        "toggle 小於 pill 幾何下限時 fail-soft 回 false")

    check(UI.API_REVISION >= 3 and type(UI.Skin.toggle) == "function",
        "rev 3 可由 revision 與 Skin.toggle 函式共同探測")
    check(UI.CAPABILITIES.icons == true and UI.Icons ~= nil, "CAPABILITIES.icons 為 true 且 Icons 已公開")

    -- E1：getTexture 正常
    local loads = {}
    getTexture = function(path)
        loads[path] = (loads[path] or 0) + 1
        return { path = path }
    end
    Skin._resetForTests()
    local el = newElement(0, 0)
    local folderPath = "media/ui/MinidoracatUI/mui_icon_folder.png"
    local tex = UI.Icons.get("folder")
    check(tex ~= nil and tex.path == folderPath, "get 依 key 對應到約定檔名")
    check(UI.Icons.get("folder") == tex and loads[folderPath] == 1,
        "第二次 get 命中 Skin 共用快取，不重複呼叫 getTexture")

    local keys = { "sidebar", "folder", "document", "chevronRight",
        "chevronDown", "language", "reload", "resetSize", "search", "chevronLeft",
        "layers", "pin", "globe", "sliders", "gauge", "lock", "unlock", "close",
        "locate", "copy", "house", "skull", "pawprint", "steeringwheel", "chicken", "cow",
        "pig", "sheep", "deer", "rabbit", "raccoon", "rodent", "turkey" }
    local expectedPaths = {
        sidebar = "media/ui/MinidoracatUI/mui_icon_sidebar.png",
        folder = "media/ui/MinidoracatUI/mui_icon_folder.png",
        document = "media/ui/MinidoracatUI/mui_icon_document.png",
        chevronRight = "media/ui/MinidoracatUI/mui_icon_chevron_right.png",
        chevronDown = "media/ui/MinidoracatUI/mui_icon_chevron_down.png",
        language = "media/ui/MinidoracatUI/mui_icon_language.png",
        reload = "media/ui/MinidoracatUI/mui_icon_reload.png",
        resetSize = "media/ui/MinidoracatUI/mui_icon_reset_size.png",
        search = "media/ui/MinidoracatUI/mui_icon_search.png",
        chevronLeft = "media/ui/MinidoracatUI/mui_icon_chevron_left.png",
        layers = "media/ui/MinidoracatUI/mui_icon_layers.png",
        pin = "media/ui/MinidoracatUI/mui_icon_pin.png",
        globe = "media/ui/MinidoracatUI/mui_icon_globe.png",
        sliders = "media/ui/MinidoracatUI/mui_icon_sliders.png",
        gauge = "media/ui/MinidoracatUI/mui_icon_gauge.png",
        lock = "media/ui/MinidoracatUI/mui_icon_lock.png",
        unlock = "media/ui/MinidoracatUI/mui_icon_unlock.png",
        close = "media/ui/MinidoracatUI/mui_icon_close.png",
        locate = "media/ui/MinidoracatUI/mui_icon_locate.png",
        copy = "media/ui/MinidoracatUI/mui_icon_copy.png",
        house = "media/ui/MinidoracatUI/mui_art_house.png",
        skull = "media/ui/MinidoracatUI/mui_art_skull.png",
        pawprint = "media/ui/MinidoracatUI/mui_art_pawprint.png",
        steeringwheel = "media/ui/MinidoracatUI/mui_art_steeringwheel.png",
        chicken = "media/ui/MinidoracatUI/mui_art_chicken.png",
        cow = "media/ui/MinidoracatUI/mui_art_cow.png",
        pig = "media/ui/MinidoracatUI/mui_art_pig.png",
        sheep = "media/ui/MinidoracatUI/mui_art_sheep.png",
        deer = "media/ui/MinidoracatUI/mui_art_deer.png",
        rabbit = "media/ui/MinidoracatUI/mui_art_rabbit.png",
        raccoon = "media/ui/MinidoracatUI/mui_art_raccoon.png",
        rodent = "media/ui/MinidoracatUI/mui_art_rodent.png",
        turkey = "media/ui/MinidoracatUI/mui_art_turkey.png",
    }
    local seen = {}
    for i = 1, #keys do
        local key = keys[i]
        local t = UI.Icons.get(key)
        check(t ~= nil and t.path == expectedPaths[key],
            key .. " 必須對到穩定契約指定的貼圖")
        seen[t.path] = true
    end
    local distinct = 0
    for _ in pairs(seen) do
        distinct = distinct + 1
    end
    check(distinct == 33, "三十三個 key 必須各自對到一張不重複的貼圖")

    check(UI.Icons.get("noSuchIcon") == nil, "未知 key 回 nil")
    check(UI.Icons.get(nil) == nil and UI.Icons.get(42) == nil, "非字串 key 回 nil（不炸）")

    check(UI.Icons.draw(el, "document", 4, 9, 16) == true and #el.tex == 1,
        "draw 成功回 true 且落一次 drawTextureScaled")
    local d = el.tex[1]
    check(d.x == 4 and d.y == 9 and d.w == 16 and d.h == 16, "draw 座標原樣傳遞、尺寸取正方形")
    check(d.r == 1 and d.g == 1 and d.b == 1 and nearly(d.a, 1), "未給 color 時預設純白、alpha 1")

    UI.Icons.draw(el, "document", 0, 0, 14, { r = 0.2, g = 0.4, b = 0.6, a = 0.5 })
    check(nearly(el.tex[2].r, 0.2) and nearly(el.tex[2].b, 0.6) and nearly(el.tex[2].a, 0.5),
        "color 進頂點染色、alpha 取 color.a")
    UI.Icons.draw(el, "document", 0, 0, 14, { r = 1, g = 1, b = 1, a = 0.5 }, 0.25)
    check(nearly(el.tex[3].a, 0.25), "顯式 alpha 蓋過 color.a")
    UI.Icons.draw(el, "document", 0, 0, 14, { r = 1, g = 0, b = 0 })
    check(nearly(el.tex[4].a, 1), "color 未帶 a 時 alpha 退回 1")
    check(UI.Icons.draw(el, "noSuchIcon", 0, 0, 16) == false and #el.tex == 4,
        "未知 key 不畫、回 false")

    -- E0：無 getTexture（dedicated／harness 環境）
    getTexture = nil
    Skin._resetForTests()
    local el0 = newElement(0, 0)
    check(UI.Icons.get("folder") == nil, "無 getTexture 全域時 get 回 nil")
    check(UI.Icons.draw(el0, "folder", 0, 0, 16) == false and #el0.tex == 0,
        "無貼圖時 draw 回 false 且完全不畫（呼叫端據此走 ASCII 退回）")

    -- E2：貼圖檔缺失（getTexture 回 nil）→ 只探測一次
    local probes = 0
    getTexture = function() probes = probes + 1 return nil end
    Skin._resetForTests()
    check(UI.Icons.get("reload") == nil, "getTexture 回 nil 時 get 回 nil")
    UI.Icons.get("reload")
    check(probes == 1, "缺圖只探測一次，之後 false 快取不重試")

    -- E3：繪製拋錯（element 契約破損）→ 不外洩、回 false
    getTexture = function(path) return { path = path } end
    Skin._resetForTests()
    local broken = newElement(0, 0)
    broken.drawTextureScaled = function() error("simulated draw failure") end
    local okCall, result = pcall(UI.Icons.draw, broken, "language", 0, 0, 16)
    check(okCall and result == false, "draw 拋錯被 pcall 攔下、回 false（錯誤不外洩）")

    getTexture = nil
    Skin._resetForTests()
end

-- ============================================================
-- Widget 情境共用 stub：最小 ISPanel 面＋可控滑鼠/時間/螢幕
-- ============================================================
local mouseX, mouseY = 0, 0
local nowMs = 5000000 -- 大數起跳：週期邏輯 lastAt 初值 0 的家族慣例
getMouseX = function() return mouseX end
getMouseY = function() return mouseY end
getTimestampMs = function() return nowMs end
getCore = function()
    return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end }
end
getTextManager = function()
    return {
        -- 每字元 10px 的可控量測（fitText 二分可測）；字型高 12
        MeasureStringX = function(_, _, text) return string.len(text) * 10 end,
        getFontHeight = function() return 12 end,
    }
end
UIFont = { NewSmall = "NewSmall", Small = "Small", Medium = "Medium" }
getText = function(key) return "[" .. tostring(key) .. "]" end
local playerPresent = true
getSpecificPlayer = function() if playerPresent then return {} end return nil end

ISPanel = {}
ISPanel.__index = ISPanel
function ISPanel:derive(name)
    local class = setmetatable({ Type = name }, self)
    class.__index = class
    return class
end
function ISPanel.new(class, x, y, w, h)
    local o = setmetatable({}, class)
    o.x, o.y, o.width, o.height = x, y, w, h
    o.visible = true
    o.children = {}
    o.stencil = { set = 0, clear = 0, repaint = 0 }
    o.rects, o.borders = {}, {}
    -- 忠於 ISUIElement.lua:1998 的預設：cell 若不清掉這個旗標就會吞滑鼠事件
    o.wantMouseEvents = true
    return o
end
function ISPanel:initialise() end
function ISPanel:setX(x) self.x = x end
function ISPanel:setY(y) self.y = y end
function ISPanel:getX() return self.x end
function ISPanel:getY() return self.y end
function ISPanel:setWidth(w) self.width = w end
function ISPanel:setHeight(h) self.height = h end
function ISPanel:getWidth() return self.width end
function ISPanel:getHeight() return self.height end
function ISPanel:getAbsoluteX() return self.x end
function ISPanel:getAbsoluteY() return self.y end
function ISPanel:getXScroll() return 0 end
function ISPanel:getYScroll() return 0 end
function ISPanel:setVisible(v) self.visible = v end
function ISPanel:getIsVisible() return self.visible end
function ISPanel:addToUIManager() end
function ISPanel:removeFromUIManager() end
function ISPanel:bringToTop() end
function ISPanel:setCapture(v) self.captured = v end
function ISPanel:isMouseOver() return self._mouseOver == true end
function ISPanel:getMouseX() return mouseX - self.x end
function ISPanel:getMouseY() return mouseY - self.y end
function ISPanel:addChild(c) self.children[#self.children + 1] = c end
function ISPanel:removeChild(c)
    for i = #self.children, 1, -1 do
        if self.children[i] == c then table.remove(self.children, i) end
    end
end
function ISPanel:setStencilRect() self.stencil.set = self.stencil.set + 1 end
function ISPanel:clearStencilRect() self.stencil.clear = self.stencil.clear + 1 end
function ISPanel:repaintStencilRect() self.stencil.repaint = self.stencil.repaint + 1 end
function ISPanel:drawText() end
function ISPanel:drawTextCentre() end
function ISPanel:drawRect(x, y, w, h, a, r, g, b)
    self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end
function ISPanel:drawRectBorder(x, y, w, h, a, r, g, b)
    self.borders[#self.borders + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end

-- 載入三個 widget 檔（V1 已在情境一載入；E0 環境＝無 NinePatchTexture，皮膚走直角）
local MOD_LUA = "MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42/42/media/lua/client/MinidoracatUI/"
dofile(MOD_LUA .. "Widgets/FloatButton.lua")
dofile(MOD_LUA .. "Widgets/Toast.lua")
dofile(MOD_LUA .. "VirtualList.lua")

-- ============================================================
print("情境六：FloatButton（拖曳門檻／點擊／右鍵守衛／clamp／能力旗標）")
-- ============================================================
do
    check(UI.CAPABILITIES.floatButton == true and UI.FloatButton ~= nil,
        "FloatButton 載入成功且 capability 翻 true")

    local clicks, moves, rights = 0, 0, {}
    local btn = UI.FloatButton.new{
        size = 40, x = 100, y = 100,
        onClick = function() clicks = clicks + 1 end,
        onRightClick = function() rights[#rights + 1] = nowMs end,
        onMoved = function(_, x, y) moves = { x = x, y = y } end,
    }
    check(btn.width == 40 and btn:getX() == 100, "建構尺寸與位置正確")

    -- 點擊：門檻內位移（3px）仍算點擊
    mouseX, mouseY = 110, 110
    btn:onMouseDown(10, 10)
    mouseX = 113 -- 位移 3 ≤ 門檻 4
    btn:onMouseMove(3, 0)
    btn:onMouseUp(13, 10)
    check(clicks == 1 and type(moves) ~= "table", "門檻內位移＝點擊（onClick 觸發、onMoved 未觸發）")
    check(btn:getX() == 100, "門檻內位移不移動按鈕")

    -- 拖曳：超過門檻 → 移動＋onMoved、不觸發 onClick
    mouseX, mouseY = 110, 110
    btn:onMouseDown(10, 10)
    mouseX, mouseY = 160, 130 -- 位移 (50,20)
    btn:onMouseMove(50, 20)
    btn:onMouseUp(60, 30)
    check(clicks == 1, "拖曳不觸發 onClick")
    check(type(moves) == "table" and moves.x == 150 and moves.y == 120,
        "拖曳落點經 onMoved 回報（100+50, 100+20）")

    -- clamp：拖出右緣 → 夾回（螢幕 1920、寬 40 → max x=1880）
    mouseX, mouseY = 160, 130
    btn:onMouseDown(10, 10)
    mouseX, mouseY = 3000, 130
    btn:onMouseMove(0, 0)
    btn:onMouseUp(0, 0)
    check(btn:getX() == 1880 and moves.x == 1880, "拖出螢幕右緣夾回 1880")

    -- 右鍵：800ms 內配對觸發；過期丟棄
    btn:onRightMouseDown(0, 0)
    nowMs = nowMs + 500
    btn:onRightMouseUp(0, 0)
    check(#rights == 1, "右鍵 500ms 內配對觸發")
    btn:onRightMouseDown(0, 0)
    nowMs = nowMs + 900
    btn:onRightMouseUp(0, 0)
    check(#rights == 1, "右鍵 900ms 過期不觸發")

    -- 左鍵拖曳中不接右鍵
    mouseX, mouseY = btn:getX() + 5, btn:getY() + 5
    btn:onMouseDown(5, 5)
    btn:onRightMouseDown(0, 0)
    nowMs = nowMs + 100
    btn:onRightMouseUp(0, 0)
    check(#rights == 1, "左鍵按住期間右鍵被忽略")
    btn:onMouseUp(5, 5)

    -- 未按下的 move/release 是 no-op（防護自 MiniMap test_key_migration J 情境遷入）
    local beforeClicks, beforeX = clicks, btn:getX()
    check(btn:onMouseMove(5, 5) == false and btn:onMouseUp(0, 0) == false,
        "未按下時 move/release 回 false 無副作用")
    check(clicks == beforeClicks and btn:getX() == beforeX, "未按下不觸發 onClick 也不動位置")

    -- 跨過門檻後縮回原點仍屬拖曳（_dragged 黏著；自 test_key_migration K 情境遷入）
    mouseX, mouseY = btn:getX() + 5, btn:getY() + 5
    btn:onMouseDown(5, 5)
    mouseX = mouseX + 10 -- 跨門檻
    btn:onMouseMove(10, 0)
    mouseX = mouseX - 10 -- 縮回原點
    btn:onMouseMove(-10, 0)
    local clicksBeforeRelease = clicks
    btn:onMouseUp(0, 0)
    check(clicks == clicksBeforeRelease, "跨門檻後縮回原點仍是拖曳（黏著），不誤判點擊")

    -- setPosition 夾回＋無玩家自我隱藏
    btn:setPosition(-50, 9999)
    check(btn:getX() == 0 and btn:getY() == 1040, "setPosition 夾回螢幕（0, 1080-40）")
    playerPresent = false
    btn:prerender()
    check(btn:getIsVisible() == false, "無玩家時 prerender 自我隱藏")
    playerPresent = true
end

-- ============================================================
print("情境七：Toast（佇列上限／遞補／動畫時序／截字）")
-- ============================================================
do
    check(UI.CAPABILITIES.toast == true and UI.Toast ~= nil, "Toast 載入成功且 capability 翻 true")
    local Toast = UI.Toast
    Toast._resetForTests()

    -- MAX_VISIBLE=3：前三則 active、第 4-8 進 pending、第 9 丟棄
    local made = {}
    for i = 1, 9 do
        made[i] = Toast.show({ title = "T", message = "msg " .. i })
    end
    check(made[1] ~= nil and made[3] ~= nil and #Toast.active == 3, "前三則進 active")
    check(made[4] == nil and #Toast.pending == 5, "第 4-8 則進 pending（上限 5）")
    check(made[9] == nil and #Toast.pending == 5, "pending 滿後丟棄（回 nil、不增長）")

    -- dismiss → pending 遞補
    Toast.dismiss(Toast.active[1])
    check(#Toast.active == 3 and #Toast.pending == 4, "dismiss 後 pending 遞補一則")

    -- 字串簡寫＋空訊息拒絕
    Toast._resetForTests()
    check(Toast.show("plain") ~= nil, "字串簡寫可用")
    check(Toast.show("") == nil and Toast.show(nil) == nil, "空訊息拒絕")

    -- 動畫時序：進場中 x 介於 start 與 target；總時長後自動 dismiss
    Toast._resetForTests()
    nowMs = 6000000
    local t = Toast.show({ message = "anim", holdMs = 1000 })
    nowMs = nowMs + 100 -- 進場 100/250ms
    t:prerender()
    local targetX = 1920 - 300 - 16
    check(t:getX() > targetX and t:getX() < 1920 + 300, "進場中 x 介於畫面外與定位點之間")
    nowMs = nowMs + 5000 -- 總時長 250+1000+400 遠超
    t:prerender()
    check(#Toast.active == 0, "超過總時長自動 dismiss")

    -- 截字：寬 284px、每字 10px → 超過 28 字截斷帶 ...
    Toast._resetForTests()
    local long = string.rep("A", 60)
    local t2 = Toast.show({ message = long })
    check(string.len(t2.message) < 60 and string.sub(t2.message, -3) == "...",
        "超寬訊息二分截字帶省略號")
    -- rev 5 換行：maxLines=3、每字 10px、寬 284 → 60 字切成 28+28+4，不帶省略號、高度長兩行
    Toast._resetForTests()
    local t3 = Toast.show({ message = long, maxLines = 3 })
    check(#t3.lines == 3 and string.len(t3.lines[1]) == 28 and string.len(t3.lines[3]) == 4 and t3.message == t3.lines[1],
        "maxLines=3 換成三行且 message 仍是第一行")
    check(t3.height == 56 + t3.fontHeight * 2, "Toast 高度隨行數增加")
    local t4 = Toast.show({ message = string.rep("B", 100), maxLines = 2 })
    check(#t4.lines == 2 and string.sub(t4.lines[2], -3) == "...", "超過 maxLines 時最後一行帶省略號")
    local t5 = Toast.show({ message = "aaaa bbbb cccc dddd eeee ffff gggg hhhh", maxLines = 2 })
    check(string.sub(t5.lines[1], -1) ~= " " and string.find(t5.lines[1], " ", 1, true) ~= nil and string.sub(t5.lines[2], 1, 1) ~= " ",
        "拉丁文在空白處換行、下一行不以空白開頭")
    Toast._resetForTests()
    check(#Toast.show({ message = "short", maxLines = 3 }).lines == 1, "放得下就一行")
    Toast._resetForTests()
end

-- ============================================================
print("情境八：VirtualList（revision 重綁／回收／選取／滾動／stencil 成對）")
-- ============================================================
do
    check(UI.CAPABILITIES.virtualList == true and UI.VirtualList ~= nil,
        "VirtualList 載入成功且 capability 翻 true")

    local binds, unbinds = 0, 0
    local Cell = ISPanel:derive("TestCell")
    local items = {}
    for i = 1, 100 do items[i] = { label = "item " .. i } end

    local list = UI.VirtualList.new{
        x = 0, y = 0, width = 200, height = 240, rowHeight = 24, padding = 0,
        createCell = function() return ISPanel.new(Cell, 0, 0, 0, 0) end,
        bindCell = function(_, cell, item, index)
            binds = binds + 1
            cell.boundLabel = item.label
        end,
        unbindCell = function(_, cell)
            unbinds = unbinds + 1
            cell.boundLabel = nil
        end,
    }
    list:initialise()
    check(#list.pool == math.ceil(240 / 24) + 2, "pool = 可見列數 + 2（12）")
    check(list.pool[1].wantMouseEvents == nil,
        "pool cell 清掉 wantMouseEvents（點擊冒泡回 list 做選取，不被 cell 吞掉）")

    list:setItems(items)
    check(binds == 10, "初始只綁可見 10 列（100 筆資料不全綁）")
    check(list.pool[1].boundLabel == "item 1" and list.pool[1]:getY() == 0, "第一列綁 item 1、y=0")

    -- revision：同一顆 items 原地改內容 → setItems 重傳 → 可見列全部重綁
    items[1].label = "CHANGED"
    local before = binds
    list:setItems(items)
    check(binds == before + 10, "重傳同一 items 觸發可見列重綁（revision 失效機制）")
    check(list.pool[1].boundLabel == "CHANGED", "重綁後看到新內容")

    -- 滾動：一次滾輪 = 3 列；捲到底 clamp
    list:onMouseWheel(1)
    check(list.scrollOffset == 72, "滾輪一格 = 3 列（72px）")
    list:setScrollOffset(999999)
    check(list.scrollOffset == 100 * 24 - 240, "捲動夾在 maxScrollOffset（2160）")
    check(list.pool[1].boundLabel ~= nil, "捲到底仍有綁定列")

    -- 注意：滾動不觸發 unbind——pool cell 是「重綁覆蓋」（bindCell 全量重設投影），
    -- unbindCell 只在 cell 變不可見時觸發（資料縮水／resize），見下方縮水斷言

    -- 選取：狀態在 list；資料縮水清懸空選取
    local selected
    list.onSelect = function(_, item, index) selected = index end
    list:setScrollOffset(0)
    mouseX, mouseY = 0, 0
    list:onMouseDown(10, 30) -- 第 2 列（24-47px）
    check(selected == 2 and list:isSelected(2), "點擊第 2 列選取（狀態在 list）")
    check(list:getSelectedItem() == items[2], "getSelectedItem 對應資料")
    list:setItems({ items[1] })
    check(list:getSelectedIndex() == nil, "資料縮水後懸空選取清除")
    check(unbinds >= 9, "資料縮水（100→1）讓失效 cell 走 unbindCell 回收")
    check(list.pool[2].boundLabel == nil, "回收後 consumer 狀態被 unbind 清掉")

    -- indexAt 邊界：padding 間隙不選
    local padded = UI.VirtualList.new{
        x = 0, y = 0, width = 200, height = 240, rowHeight = 20, padding = 4,
        createCell = function() return ISPanel.new(Cell, 0, 0, 0, 0) end,
        bindCell = function() end,
    }
    padded:initialise()
    local three = { {}, {}, {} }
    padded:setItems(three)
    check(padded:indexAt(10, 4) == 1 and padded:indexAt(10, 23) == 1, "列身命中（含首列 padding 後）")
    check(padded:indexAt(10, 25) == nil, "列間 padding 間隙不選取")
    check(padded:indexAt(10, 999) == nil and padded:indexAt(10, -1) == nil, "越界回 nil")

    -- resize：pool 重算
    list:setItems(items)
    list:resize(200, 480)
    check(#list.pool == math.ceil(480 / 24) + 2, "resize 後 pool 重算（22）")

    -- stencil 成對＋repaint（家族踩坑錄：只 set→clear 會吃掉外層 clip）
    local s = list.stencil
    s.set, s.clear, s.repaint = 0, 0, 0
    list:prerender()
    list:render()
    check(s.set == 1 and s.clear == 1 and s.repaint == 1,
        "一幀 set/clear/repaint 各一次（成對＋還回父層）")

    -- scrollToIndex：目標列完整可見
    list:scrollToIndex(50)
    local top = (50 - 1) * 24
    check(list.scrollOffset <= top and top + 24 <= list.scrollOffset + 480,
        "scrollToIndex 讓目標列完整落在 viewport 內")
end

-- 條數守門（家族慣例，同 test_nbpanel）：整段情境被 `if false then` 包掉或誤刪時，
-- 數字會變小但不會有任何東西紅。加測試把這個數字一起改大（改小要說得出刪了什麼）。
local EXPECTED_ASSERTIONS = 173
print()
if assertionCount ~= EXPECTED_ASSERTIONS then
    print("斷言條數不符：預期 " .. EXPECTED_ASSERTIONS .. "、實際 " .. assertionCount
        .. "（有測試被刪掉或跳過？）")
    os.exit(1)
end
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過（" .. assertionCount .. " 斷言）")
