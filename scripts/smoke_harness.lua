--[[
煙霧測試：用假的 PZ 全域載入**真正的** V1.lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/xpcall，Kahlua 沒有——誤用由 scripts/verify_mod.py 靜態掃描負責
- Kahlua 專屬行為（Java field 不暴露、table 記憶體形狀）只能靠反編譯查證與實機測試

十九情境（docs/ARCHITECTURE.md §7）＋切片測試（檔尾 loader：rev 11 五個元件與換行 test_wrap，ctx 契約見 loader 上方註解）：
1. facade 半初始化——檔案中段注入 error，斷言 MinidoracatUI.v1 從未發布
2. NinePatch 三態——E0 無全域／E1 正常（含引擎首呼叫回 nil 語意）／E2 壞掉，
   fill/border/dot 一律不拋錯、退回正確、座標 floor、自身 scroll 補償、壞名不重試
3. theme 隔離——兩實例互不污染、default 不被 mutate、light variant、token 字串解析
4. fits 邊界——round／roundTop／pill 下限、boolean topOnly 相容、"rect" 強制退回
5. painters/assets——toggle／slider 幾何、色彩、alpha、缺資產退回與六十五個 icon key
（6-8 為 widget：FloatButton／Toast／VirtualList；9-15 為 rev 7 控制元件：載入自檢／Button／
 TextField／Checkbox／Tabs／Window／Dialog；16 為 rev 8 ColorPicker（rev 9 起 R/G/B 為滑桿）；
 17 為 rev 9 Slider；18 為 rev 10 Focus 鍵盤＋手把焦點；19 為 rev 11 共用基礎：Text.fit／Skin.arrow／
 chip Button／截字與自動 tooltip／TextField 尺寸與 clearButton／theme.alpha）
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

    local navigationKeys = { "wallet", "gift", "shop", "market", "auction", "mail",
        "users", "chart", "coins", "plug", "shieldCheck", "tag", "transactions",
        "clipboardCheck", "server", "settings" }
    check(UI.API_MAJOR == 1 and UI.API_REVISION >= 6, "導覽圖示能力可由 rev 6 探測")
    for _, key in ipairs(navigationKeys) do
        local texture = UI.Icons.get(key)
        check(texture ~= nil and texture.path == "media/ui/MinidoracatUI/mui_art_" .. key .. ".png",
            key .. " 導覽圖示對應正確")
    end
    local vehicleKeys = { "carSedan", "carHatchback", "carSports", "carSuv", "carPickup", "carVan",
        "carStepVan", "carTruck", "carAmbulance", "carPolice", "carFiretruck", "carTrailer",
        "markerStar", "markerHeart", "markerFlag", "markerCrown" }
    local vehicleOk = UI.API_REVISION >= 8
    for _, key in ipairs(vehicleKeys) do
        local texture = UI.Icons.get(key)
        vehicleOk = vehicleOk and texture ~= nil
            and texture.path == "media/ui/MinidoracatUI/mui_art_" .. key .. ".png"
    end
    check(vehicleOk, "rev 8：十六個車輛／標記 key 各自對到 mui_art_<key>.png")

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
    -- 忠於 ISUIElement.lua:1473-1474：原版 children 以 ID 為鍵、順序陣列是 childrenInOrder；
    -- stub 只有陣列，兩個名稱指向同一份（Focus 走訪 childrenInOrder）
    o.childrenInOrder = o.children
    o.javaObject = {}
    o.stencil = { set = 0, clear = 0, repaint = 0 }
    o.rects, o.borders, o.texts = {}, {}, {}
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
function ISPanel:addToUIManager()
    self._nativeAlwaysOnTop = self._nativeAlwaysOnTop or false
    self.inUIManager = true
end
function ISPanel:setAlwaysOnTop(value)
    -- 原版 setter 只作用於已建立的 Java 元件，不讀 Lua 的 alwaysOnTop 欄位。
    if self._nativeAlwaysOnTop ~= nil then self._nativeAlwaysOnTop = value end
end
function ISPanel:removeFromUIManager() self.inUIManager = false end
function ISPanel:setWantKeyEvents(v) self.wantKeyEvents = v end
function ISPanel:bringToTop() end
function ISPanel:setCapture(v) self.captured = v end
function ISPanel:isMouseOver() return self._mouseOver == true end
function ISPanel:getMouseX() return mouseX - self.x end
function ISPanel:getMouseY() return mouseY - self.y end
function ISPanel:addChild(c) self.children[#self.children + 1] = c; c.parent = self end
-- 忠於 ISUIElement.lua:690 起：自己與所有祖先都可見才算
function ISPanel:isReallyVisible()
    local e = self
    while e do
        if not e.visible then return false end
        e = e.parent
    end
    return true
end
function ISPanel:removeChild(c)
    for i = #self.children, 1, -1 do
        if self.children[i] == c then table.remove(self.children, i) end
    end
end
function ISPanel:setStencilRect() self.stencil.set = self.stencil.set + 1 end
function ISPanel:clearStencilRect() self.stencil.clear = self.stencil.clear + 1 end
function ISPanel:repaintStencilRect() self.stencil.repaint = self.stencil.repaint + 1 end
function ISPanel:drawText(text, x, y, r, g, b, a)
    self.texts[#self.texts + 1] = { text = text, x = x, y = y, r = r, g = g, b = b, a = a }
end
function ISPanel:drawTextCentre(text, x, y, r, g, b, a)
    self.texts[#self.texts + 1] = { text = text, x = x, y = y, r = r, g = g, b = b, a = a }
end
function ISPanel:drawRect(x, y, w, h, a, r, g, b)
    self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end
function ISPanel:drawRectBorder(x, y, w, h, a, r, g, b)
    self.borders[#self.borders + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b }
end

-- 載入三個 widget 檔（V1 已在情境一載入；E0 環境＝無 NinePatchTexture，皮膚走直角）
local MOD_LUA = "MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42/42/media/lua/client/MinidoracatUI/"
-- 框架內部模組 TextWrap 以 require 取回傳值：只讓它找得到（preload），其他 require 照舊失敗，
-- 「依賴缺席」情境（Controls／V1／Table 未載入）才模擬得出來
package.preload["MinidoracatUI/TextWrap"] = function() return dofile(MOD_LUA .. "TextWrap.lua") end
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
    check(btn._nativeAlwaysOnTop == true, "預設浮鈕在原生層級置頂")
    local regular = UI.FloatButton.new({ alwaysOnTop = false })
    check(regular._nativeAlwaysOnTop == false, "浮鈕可明確選擇一般視窗層級")

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
    check(made[1]._nativeAlwaysOnTop == true, "通知在原生層級置頂")
    check(made[4] == nil and #Toast.pending == 5, "第 4-8 則進 pending（上限 5）")
    check(made[9] == nil and #Toast.pending == 5, "pending 滿後丟棄（回 nil、不增長）")

    -- dismiss → pending 遞補
    Toast.dismiss(Toast.active[1])
    check(#Toast.active == 3 and #Toast.pending == 4, "dismiss 後 pending 遞補一則")
    check(Toast.active[3]._nativeAlwaysOnTop == true, "遞補的通知同樣在原生層級置頂")

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

    -- 同一佇列混合 consumer 的不同通知高度；包含 pending 遞補。
    Toast._resetForTests()
    local tall = Toast.show({ message = long, maxLines = 3 })
    local short = Toast.show("short")
    local last = Toast.show("last")
    Toast.show({ message = long, maxLines = 3 })
    nowMs = nowMs + 300
    tall:prerender(); short:prerender(); last:prerender()
    check(tall.y == 60 and short.y == tall.y + tall.height + 8,
        "三行通知後的單行通知保留八像素間距")
    check(last.y == short.y + short.height + 8, "第三則累加所有前則高度")
    Toast.dismiss(tall)
    local promoted = Toast.active[3]
    nowMs = nowMs + 300
    short:prerender(); last:prerender(); promoted:prerender()
    check(short.y == 60 and last.y == 124, "移除後單行通知保留原有堆疊位置")
    check(promoted.y == last.y + last.height + 8 and #promoted.lines == 3,
        "待顯示的多行通知遞補在單行通知之後")
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
    local oldPool, beforeUnbind = list.pool, unbinds
    list:resize(200, 480)
    check(#list.pool == math.ceil(480 / 24) + 2, "resize 後 pool 重算（22）")
    check(unbinds == beforeUnbind + 10, "resize 對十個已綁定列各解除一次，空列不解除")
    local cleared = true
    for _, cell in ipairs(oldPool) do
        if cell.boundLabel ~= nil or cell.boundIndex ~= nil or cell.boundRevision ~= nil
            or cell:getIsVisible() then cleared = false end
    end
    check(cleared, "resize 丟棄的列已解除 consumer 狀態並隱藏")
    check(list.pool[1].boundLabel == "CHANGED" and list.pool[20].boundLabel == "item 20",
        "resize 後新列完整重綁目前資料")
    list:refreshCells()
    check(unbinds == beforeUnbind + 10, "後續 refresh 不重複解除已移除列")

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

    -- bind 失敗不可留下已完成標記；同 revision 捲動重綁也必須可重試。
    local failBind = true
    local recoverable = UI.VirtualList.new{
        x = 0, y = 0, width = 200, height = 24, rowHeight = 24,
        createCell = function() return ISPanel.new(Cell, 0, 0, 0, 0) end,
        bindCell = function(_, cell, item)
            if failBind then error("simulated bind failure") end
            cell.boundLabel = item.label
        end,
    }
    recoverable:initialise()
    local bound, bindError = pcall(recoverable.setItems, recoverable,
        { { label = "first" }, { label = "second" } })
    check(not bound and string.find(bindError, "simulated bind failure", 1, true) ~= nil,
        "首次綁定錯誤原樣傳出，不假裝完成")
    failBind = false
    recoverable:refreshCells()
    check(recoverable.pool[1].boundLabel == "first" and recoverable.pool[1]:getIsVisible(),
        "首次綁定失敗後 refresh 可恢復可見內容")
    failBind = true
    local scrolled, scrollError = pcall(recoverable.setScrollOffset, recoverable, 24)
    check(not scrolled and string.find(scrollError, "simulated bind failure", 1, true) ~= nil,
        "捲動重綁錯誤原樣傳出")
    failBind = false
    recoverable:refreshCells()
    check(recoverable.pool[1].boundLabel == "second" and recoverable.pool[1]:getIsVisible(),
        "同 revision 的捲動重綁失敗後 refresh 仍可恢復正確資料")
end

-- ============================================================
-- rev 7 控制元件共用 stub：原生 ISButton／ISTextEntryBox 的最小語意面
-- ============================================================
getSoundManager = function() return { playUISound = function() end } end
Keyboard = { KEY_ESCAPE = 1, KEY_RETURN = 28, KEY_NUMPADENTER = 156 }

ISButton = ISPanel:derive("ISButton")
function ISButton.new(class, x, y, w, h, title, target, onclick)
    -- 忠於 ISButton.lua:493-495：過窄的寬度撐到標題寬＋10
    local minW = getTextManager():MeasureStringX(UIFont.Small, title) + 10
    local o = ISPanel.new(class, x, y, math.max(w, minW), h)
    o.title, o.target, o.onclick, o.onClickArgs = title, target, onclick, {}
    o.enable, o.font, o.pressed = true, UIFont.Small, false
    return o
end
-- 忠於 ISButton.lua:33-64：down 記 pressed；up 只在 pressed 且 enable 時呼叫 onclick(target, button)
function ISButton:onMouseDown()
    if not self:getIsVisible() then return end
    self.pressed = true
end
function ISButton:onMouseUp()
    if not self:getIsVisible() then return end
    local process = self.pressed == true
    self.pressed = false
    if self.onclick == nil then return end
    if self.enable and process then
        getSoundManager():playUISound("UIActivateButton")
        self.onclick(self.target, self, self.onClickArgs[1], self.onClickArgs[2])
    end
end
function ISButton:onMouseUpOutside() self.pressed = false end
-- 忠於 ISButton.lua:70-79：forceClick 檢查 visible＋enable，只呼叫一次 onclick
function ISButton:forceClick()
    if not self:getIsVisible() or not self.enable or self.onclick == nil then return end
    self.onclick(self.target, self, self.onClickArgs[1], self.onClickArgs[2])
end
function ISButton:updateTooltip() self.tooltipPasses = (self.tooltipPasses or 0) + 1 end

ISTextEntryBox = ISPanel:derive("ISTextEntryBox")
function ISTextEntryBox:new(title, x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.title = title
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end
function ISTextEntryBox:instantiate()
    self.javaObject = {}
    self._text = self.title
    self._editable = true
end
function ISTextEntryBox:getInternalText() return self._text end
function ISTextEntryBox:setText(s) self._text = s or ""; self.title = self._text end
function ISTextEntryBox:focus() self._focused = true end
function ISTextEntryBox:unfocus() self._focused = false end
function ISTextEntryBox:isFocused() return self._focused == true end
-- 忠於 ISTextEntryBox.lua:64-71：setEditable 會重設 borderColor（元件必須再藏回去）
function ISTextEntryBox:setEditable(e)
    self._editable = e
    self.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = e and 1 or 0.5 }
end
function ISTextEntryBox:setOnlyNumbers(b) self._onlyNumbers = b end
function ISTextEntryBox:setMaxTextLength(n) self._maxLen = n end
function ISTextEntryBox:setTextRGBA(r, g, b, a) self._textColor = { r = r, g = g, b = b, a = a } end
function ISTextEntryBox:setTooltip(t) self.tooltip = t end
-- 忠於 ISTextEntryBox.lua:101-103：轉呼叫 javaObject:setClearButton
function ISTextEntryBox:setClearButton(b) self._clearButton = b end

-- ============================================================
print("情境九：rev 7 載入自檢（facade 缺席／原生基底缺席／缺 Controls 時旗標維持 false）")
-- ============================================================
do
    check(UI.API_REVISION == 11, "API_REVISION 進到 11")
    check(UI.CAPABILITIES.controls == false and UI.CAPABILITIES.window == false
        and UI.CAPABILITIES.dialog == false and UI.CAPABILITIES.colorPicker == false
        and UI.CAPABILITIES.slider == false and UI.CAPABILITIES.focus == false
        and UI.CAPABILITIES.datePicker == false and UI.CAPABILITIES.table == false
        and UI.CAPABILITIES.filterBar == false and UI.CAPABILITIES.itemPicker == false
        and UI.CAPABILITIES.autocomplete == false,
        "rev 7／8／9／10／11 能力在 widget 檔載入前誠實標 false")

    local saved = MinidoracatUI
    MinidoracatUI = nil
    local okC = pcall(dofile, MOD_LUA .. "Widgets/Controls.lua")
    local okW = pcall(dofile, MOD_LUA .. "Widgets/Window.lua")
    check(okC and okW and MinidoracatUI == nil,
        "facade 未發布（半初始化）時 Controls／Window 靜默 return、不建立殘缺全域")

    local fh = io.open(V1_PATH, "rb")
    local src = fh:read("*a")
    fh:close()
    load_(src, "@V1.lua")()
    local fresh = MinidoracatUI.v1
    local keepButton = ISButton
    ISButton = nil
    dofile(MOD_LUA .. "Widgets/Controls.lua")
    ISButton = keepButton
    check(fresh.CAPABILITIES.controls == false and fresh.Button == nil
        and fresh.CAPABILITIES.colorPicker == false and fresh.ColorPicker == nil
        and fresh.CAPABILITIES.slider == false and fresh.Slider == nil,
        "原生 ISButton 缺席時 controls／colorPicker／slider 維持 false、不掛元件")
    dofile(MOD_LUA .. "Widgets/Window.lua")
    check(fresh.CAPABILITIES.window == true and fresh.Window ~= nil, "Window 不依賴 Controls，可單獨提供")
    check(fresh.CAPABILITIES.dialog == false and fresh.Dialog == nil,
        "Controls 缺席時 dialog 維持 false（無隱藏載入順序依賴）")

    MinidoracatUI = saved
    dofile(MOD_LUA .. "Widgets/Controls.lua")
    dofile(MOD_LUA .. "Widgets/Window.lua")
    check(UI.CAPABILITIES.controls and UI.CAPABILITIES.window and UI.CAPABILITIES.dialog
        and UI.CAPABILITIES.colorPicker and UI.CAPABILITIES.slider and UI.Button and UI.TextField
        and UI.Checkbox and UI.Tabs and UI.ColorPicker and UI.Slider and UI.Window and UI.Dialog,
        "正常載入後五旗標為 true 且八元件掛上 facade")
end

local TARGET = {}

-- ============================================================
print("情境十：Button（自動寬度／點擊／disabled 不觸發／樣式繪製）")
-- ============================================================
do
    local clicks = {}
    local btn = UI.Button.new{ x = 0, y = 0, title = "Save", target = TARGET,
        onClick = function(target, button) clicks[#clicks + 1] = { target = target, button = button } end }
    check(btn.width == 60 and btn.height == 22, "省略寬高：標題 40px＋左右 padding 20、字高 12＋10")
    check(UI.Button.new{ title = "Save", icon = "close" }.width == 82, "有 icon 時寬度加 icon 16＋間距 6")
    check(UI.Button.new{ title = "LongTitle", width = 30 }.width == 30, "明示寬度不被原生撐寬")

    btn:onMouseDown(5, 5)
    btn:onMouseUp(5, 5)
    check(#clicks == 1 and clicks[1].target == TARGET and clicks[1].button == btn,
        "點擊呼叫 onClick(target, button)")
    btn:setEnabled(false)
    btn:onMouseDown(5, 5)
    btn:onMouseUp(5, 5)
    check(#clicks == 1 and btn:isEnabled() == false, "disabled 時點擊不觸發 onClick")
    btn:setEnabled(true)
    btn:onMouseDown(5, 5)
    btn:onMouseUp(5, 5)
    check(#clicks == 2 and btn:isEnabled() == true, "重新啟用後恢復點擊")

    btn:setTitle("Hi")
    check(btn.width == 40, "setTitle 在自動寬度下重算寬度")
    local fixed = UI.Button.new{ title = "A", width = 90 }
    fixed:setTitle("Much longer")
    check(fixed.width == 90, "setTitle 不改明示寬度")
    fixed:setStyle("bogus")
    check(fixed.style == "normal", "未知 style 退回 normal")

    local primary = UI.Button.new{ title = "Go", style = "primary" }
    primary:prerender()
    check(nearly(primary.rects[1].r, 1) and nearly(primary.rects[1].g, 0.85)
        and nearly(primary.texts[1].r, 0.1), "primary：accent 底、深色字")
    local danger = UI.Button.new{ title = "Del", style = "danger" }
    danger:prerender()
    check(nearly(danger.rects[1].r, 0.3) and nearly(danger.borders[1].r, 0.9)
        and nearly(danger.texts[1].r, 0.9), "danger：errorSurface 底、errorText 框與字")
    local ghost = UI.Button.new{ title = "G", style = "ghost" }
    ghost:prerender()
    local idleGhost = #ghost.rects
    ghost._mouseOver = true
    ghost:prerender()
    check(idleGhost == 0 and #ghost.rects == 1 and nearly(ghost.rects[1].a, 0.06),
        "ghost：平時無底、hover 才有底")

    btn._mouseOver, btn.pressed = true, true
    btn:prerender()
    check(#btn.rects == 2 and nearly(btn.rects[2].a, 0.12), "hover＋按住疊 selected 色")
    btn:setEnabled(false)
    btn.rects, btn.texts = {}, {}
    btn._mouseOver, btn.pressed = true, true
    btn:prerender()
    check(#btn.rects == 1 and nearly(btn.rects[1].a, 0.5 * 0.45) and nearly(btn.texts[1].r, 0.55),
        "disabled：淡化、無 hover／pressed 疊色、textFaint 字")

    btn:setTooltip("tip")
    btn:prerender()
    check(btn.tooltip == "tip" and btn.tooltipPasses == 1, "setTooltip 後 prerender 跑原生 tooltip 流程")
    btn:setTooltip(nil)
    check(btn.tooltip == nil, "setTooltip(nil) 清除")
end

-- ============================================================
print("情境十一：TextField（每幀變化只觸發一次／setText 靜默／placeholder／disabled）")
-- ============================================================
do
    local changes = {}
    local field = UI.TextField.new{ x = 0, y = 0, width = 200, text = "abc", placeholder = "Search",
        onlyNumbers = true, maxLength = 8,
        onChange = function(f, text) changes[#changes + 1] = { field = f, text = text } end }
    local entry = field._entry
    check(field:getText() == "abc" and field.height == 22, "初始文字與預設高度（字高＋10）")
    check(entry._onlyNumbers == true and entry._maxLen == 8, "onlyNumbers／maxLength 交給原生 entry")
    check(entry.backgroundColor.a == 0 and entry.borderColor.a == 0, "原生 entry 透明、無邊框")
    field:prerender()
    check(#changes == 0, "文字未變不觸發 onChange")
    entry._text = "abcd" -- 模擬 IME 組字送出：不經原生 onTextChange
    field:prerender()
    field:prerender()
    check(#changes == 1 and changes[1].text == "abcd" and changes[1].field == field,
        "每幀比對：一次變化只觸發一次 onChange(field, text)")
    field:setText("xyz")
    field:prerender()
    check(#changes == 1 and field:getText() == "xyz", "setText 不觸發 onChange")

    field:setText("")
    field.texts = {}
    field:prerender()
    check(#field.texts == 1 and field.texts[1].text == "Search" and nearly(field.texts[1].r, 0.55),
        "空字串且未 focus 時畫 textFaint placeholder")
    field:focus()
    field.texts, field.borders = {}, {}
    field:prerender()
    check(#field.texts == 0 and field:isFocused() and nearly(field.borders[1].g, 0.85),
        "focus 時不畫 placeholder、邊框改 accent")

    field:setEnabled(false)
    check(entry._editable == false and entry.borderColor.a == 0 and not field:isFocused(),
        "setEnabled(false)：不可編輯、失焦、原生邊框維持隱藏")
    field:focus()
    check(not field:isFocused(), "disabled 時 focus() 無效")
    field:setTooltip("hint")
    check(entry.tooltip == "hint", "setTooltip 交給原生 entry 顯示")
end

-- ============================================================
print("情境十二：Checkbox（整列點擊／silent／disabled）")
-- ============================================================
do
    local events = {}
    local box = UI.Checkbox.new{ x = 0, y = 0, label = "Auto", target = TARGET,
        onChange = function(target, checked, b) events[#events + 1] = { target = target, checked = checked, box = b } end }
    check(box.height == 20 and box.width == 84, "預設高 max(20, 字高＋4)、寬＝開關＋間距＋標籤")
    box:onMouseDown(60, 5)
    box:onMouseUp(60, 5)
    check(#events == 1 and events[1].target == TARGET and events[1].checked == true
        and events[1].box == box and box:getChecked() == true, "點標籤也切換並呼叫 onChange(target, checked, box)")
    box:setChecked(false, true)
    check(#events == 1 and box:getChecked() == false, "setChecked silent 不觸發 onChange")
    box:setChecked(false)
    check(#events == 1, "setChecked 相同值是 no-op")
    box:setEnabled(false)
    box:onMouseDown(5, 5)
    box:onMouseUp(5, 5)
    check(#events == 1 and box:getChecked() == false, "disabled 時點擊不切換")
    box:setLabel("Manual")
    local drew = pcall(box.prerender, box)
    check(drew and box.texts[#box.texts].text == "Manual" and box.texts[#box.texts].x == 44,
        "繪製不拋錯、標籤畫在開關右側")
end

-- ============================================================
print("情境十三：Tabs（選取／點選中項不觸發／隱藏重排）")
-- ============================================================
do
    local picks = {}
    local tabs = UI.Tabs.new{ x = 0, y = 0, selected = "a", target = TARGET,
        items = { { id = "a", label = "Alpha" }, { id = "b", label = "Be" }, { id = "c", label = "Cee" } },
        onSelect = function(target, id, t) picks[#picks + 1] = { target = target, id = id, tabs = t } end }
    check(tabs.width == 180 and tabs.height == 24, "自動寬度＝各頁籤（標籤＋24）加總＋間距與內距")
    tabs:onMouseDown(83, 5)
    check(#picks == 1 and picks[1].id == "b" and picks[1].target == TARGET and picks[1].tabs == tabs
        and tabs:getSelected() == "b", "點頁籤呼叫 onSelect(target, id, tabs)")
    tabs:onMouseDown(83, 5)
    check(#picks == 1, "點已選中的頁籤不觸發")
    tabs:setSelected("c", true)
    check(#picks == 1 and tabs:getSelected() == "c", "setSelected silent 不觸發")
    tabs:setSelected("nope")
    check(tabs:getSelected() == "c", "未知 id 忽略")
    tabs:setItemVisible("b", false)
    check(tabs.width == 134, "隱藏頁籤後重排並更新自動寬度")
    tabs:onMouseDown(83, 5)
    check(#picks == 1, "重排後該位置是已選中的 c，不觸發")
    tabs:setItemVisible("c", false)
    check(tabs:getSelected() == "c" and tabs.width == 78, "隱藏選中項不自動切換")
    tabs:setItemLabel("a", "A")
    check(tabs.width == 38, "setItemLabel 重算寬度")
    check(pcall(tabs.prerender, tabs), "繪製不拋錯")
end

-- ============================================================
print("情境十四：Window（拖曳／clamp／縮放下限／關閉／ISLayoutManager 存讀）")
-- ============================================================
do
    local resizes, closes = {}, 0
    local win = UI.Window.new{ x = 100, y = 100, width = 300, height = 200, title = "Fleet",
        resizable = true,
        onClose = function(w) if w then closes = closes + 1 end end,
        onResize = function(w, width, height) resizes[#resizes + 1] = { width = width, height = height } end }
    check(win:titleBarHeight() == 24 and win:contentTop() == 24, "標題列高 max(24, 字高＋10)")

    mouseX, mouseY = 150, 110
    win:onMouseDown(50, 10)
    check(win.captured == true, "按住標題列 setCapture")
    mouseX, mouseY = 250, 160
    win:onMouseMoveOutside(0, 0)
    win:onMouseUpOutside(0, 0)
    check(win:getX() == 200 and win:getY() == 150 and win.captured == false,
        "拖出視窗外仍跟隨，放開釋放 capture")
    win:setX(5000)
    win:prerender()
    check(win:getX() == 1620, "每幀 clamp 回螢幕（1920-300）")

    mouseX, mouseY = 1620 + 298, 150 + 198
    win:onMouseDown(298, 198)
    mouseX, mouseY = mouseX - 500, mouseY - 500
    win:onMouseMove(0, 0)
    win:onMouseUp(0, 0)
    local last = resizes[#resizes]
    check(win.width == 240 and win.height == 160 and last.width == 240 and last.height == 160,
        "右下把手縮放夾在 minWidth／minHeight 並呼叫 onResize(win, w, h)")

    win:onMouseDown(235, 5)
    win:onMouseUp(235, 5)
    check(win:getIsVisible() == false and closes == 1, "關閉鈕：隱藏並呼叫 onClose(win)")
    win:setVisible(true)
    win:onMouseDown(235, 5)
    win:onMouseUp(100, 100)
    check(win:getIsVisible() == true and closes == 1, "在關閉鈕按下、別處放開不關閉")
    check(pcall(win.render, win), "繪製（邊框、關閉鈕、把手）不拋錯")

    local layout = {}
    UI.Window.SaveLayout(win, "fleet", layout)
    check(layout.x == win:getX() and layout.width == 240 and layout.height == 160,
        "SaveLayout 存 x／y 與可縮放時的寬高")
    local before = #resizes
    UI.Window.RestoreLayout(win, "fleet", { x = "10", y = "20", width = "100", height = "500" })
    check(win:getX() == 10 and win:getY() == 20 and win.width == 240 and win.height == 500
        and #resizes == before + 1, "RestoreLayout（RegisterWindow 的 funcs 形狀）夾最小值並通知 onResize")

    local fixedWin = UI.Window.new{ x = 0, y = 0, width = 300, height = 100, title = "x", closable = false }
    local fixedLayout = {}
    UI.Window.SaveLayout(fixedWin, "fixed", fixedLayout)
    UI.Window.RestoreLayout(fixedWin, "fixed", { x = "5", y = "6", width = "900", height = "900" })
    check(fixedLayout.width == nil and fixedWin.width == 300 and fixedWin:getX() == 5,
        "不可縮放視窗只存讀位置")
    fixedWin:onMouseDown(295, 5)
    fixedWin:onMouseUp(295, 5)
    check(fixedWin:getIsVisible() == true, "closable=false 時右上角不是關閉鈕")
end

-- ============================================================
print("情境十五：Dialog（單次回呼／移除 guard／Enter・Esc／同時只有一個）")
-- ============================================================
do
    local results = {}
    local function record(ok, text) results[#results + 1] = { ok = ok, text = text } end

    local d = UI.Dialog.show{ title = "T", text = "Hello\nWorld", confirmText = "OK",
        cancelText = "Cancel", onResult = record }
    local guard = d._guard
    check(d.inUIManager and guard.inUIManager and d._nativeAlwaysOnTop == true
        and guard._nativeAlwaysOnTop == true and d.wantKeyEvents == true,
        "guard 與視窗都加入 UIManager 並置頂、視窗收 key 事件")
    check(d.children[1].lines[1] == "Hello" and d.children[1].lines[2] == "World",
        "內文依 \\n 分行")
    check(guard:onMouseDown() == true and guard:onMouseWheel() == true, "guard 吃掉滑鼠事件")
    check(d.height == 24 + 12 + 2 * 12 + 12 + 22 + 12, "高度依行數自動計算")
    check(d:getX() == math.floor((1920 - 360) / 2), "視窗水平置中")

    d._confirm:onMouseDown(1, 1)
    d._confirm:onMouseUp(1, 1)
    check(#results == 1 and results[1].ok == true and results[1].text == nil,
        "確認按鈕 onResult(true, nil)")
    check(d.inUIManager == false and guard.inUIManager == false, "結束時移除視窗與 guard")
    d._cancel:onMouseDown(1, 1)
    d._cancel:onMouseUp(1, 1)
    UI.Dialog.close(d, false)
    d:close()
    check(#results == 1, "onResult 只呼叫一次（再按鈕／close／關閉鈕都不重複）")

    local esc = UI.Dialog.show{ title = "T", text = "x", confirmText = "OK", cancelText = "C", onResult = record }
    esc:onKeyRelease(1)
    check(#results == 1, "沒有對應的按下就不處理放開（開窗那一下的按鍵不誤觸）")
    esc:onKeyPress(1)
    esc:onKeyRelease(1)
    check(#results == 2 and results[2].ok == false, "Esc＝取消")
    check(esc:isKeyConsumed(1) == true, "關閉後仍消耗同一個 Esc（不漏給後面的視窗）")

    local enter = UI.Dialog.show{ title = "T", text = "x", confirmText = "OK", cancelText = "C", onResult = record }
    enter:onKeyPress(28)
    enter:onKeyRelease(28)
    check(#results == 3 and results[3].ok == true, "Enter＝確認")

    local ask = UI.Dialog.show{ title = "T", text = "x", confirmText = "OK", cancelText = "C",
        input = { text = "5", onlyNumbers = true }, onResult = record }
    local input = ask._input
    check(input:isFocused() and input._entry._onlyNumbers == true and input:getText() == "5",
        "input：TextField 自動 focus 並帶初始值／onlyNumbers")
    input._entry._text = "42"
    input._entry:onCommandEntered()
    check(#results == 4 and results[4].ok == true and results[4].text == "42",
        "輸入框內 Enter 經原生 onCommandEntered 確認並回傳文字")

    local closer = UI.Dialog.show{ title = "T", text = "x", confirmText = "OK", cancelText = "C", onResult = record }
    closer:close()
    check(#results == 5 and results[5].ok == false and closer._guard.inUIManager == false,
        "關閉鈕視同取消並移除 guard")

    local first = UI.Dialog.show{ title = "T", text = "x", confirmText = "OK", cancelText = "C", onResult = record }
    local second = UI.Dialog.show{ title = "T", text = string.rep("A", 50), confirmText = "Delete",
        danger = true, onResult = record }
    check(#results == 6 and results[6].ok == false and first.inUIManager == false and second.inUIManager,
        "新開 Dialog 先以 cancel 關掉舊的")
    check(second._cancel == nil and second._confirm.style == "danger", "省略 cancelText＝單鈕提示、danger 樣式")
    check(#second.children[1].lines == 2, "長文字依寬度自動換行")
    UI.Dialog.close(second, true)
    check(#results == 7 and results[7].ok == true, "Dialog.close(dialog, ok) 走同一收尾路徑")
end

-- ============================================================
print("情境十六：ColorPicker（色卡／滑桿／hex 單次回呼、互相同步不重複回呼、hex 非法不變、silent）")
-- ============================================================
do
    local changes = {}
    local picker = UI.ColorPicker.new{ x = 0, y = 0, width = 200, color = { r = 1, g = 0, b = 0 },
        target = TARGET, onChange = function(target, color, p)
            changes[#changes + 1] = { target = target, color = color, picker = p }
        end }
    local sl, hex = picker._sliders, picker._hex
    local function texts()
        return sl[1]:getValue() .. "," .. sl[2]:getValue() .. "," .. sl[3]:getValue() .. "," .. hex:getText()
    end
    local function tick() hex:prerender() end
    check(#UI.ColorPicker.DEFAULT_SWATCHES == 24 and picker:getHeight() == 204,
        "預設 24 色；寬 200 → 7 欄 4 列，高度＝色卡 102＋間距 8＋三列滑桿 72＋hex 22")
    check(texts() == "255,0,0,#FF0000" and #changes == 0 and sl[1]._text == "255",
        "初始色寫入滑桿與 hex，建構不回呼")

    local s = picker._swatches[1]
    picker:onMouseDown(s.x + 1, s.y + 1)
    tick()
    tick()
    local c = changes[1] and changes[1].color
    check(#changes == 1 and changes[1].target == TARGET and changes[1].picker == picker
        and nearly(c.r, 230 / 255) and nearly(c.g, 51 / 255),
        "點色卡回呼一次 onChange(target, color, picker)；寫回滑桿／hex 不引起重複回呼")
    check(texts() == "230,51,51,#E63333" and sl[2]._text == "51", "點色卡同步寫回 R/G/B 滑桿與 hex")

    -- 拖 R 滑桿：track 內縮 6、寬 186-12-36=138；按在最左＝0，拖到最右＝255，拖出界仍 255
    local r = sl[1]
    r:onMouseDown(6, 10)
    mouseX = r.x + 6 + 138
    r:onMouseMove(0, 0)
    mouseX = r.x + 900
    r:onMouseMoveOutside(0, 0)
    r:onMouseUpOutside(0, 0)
    tick()
    check(#changes == 3 and nearly(changes[2].color.r, 0) and nearly(changes[3].color.r, 1)
        and texts() == "255,51,51,#FF3333" and r.captured == false,
        "拖滑桿每次實際變色回呼一次、出界同值不回呼；hex 同步且不重複回呼")

    hex._entry._text = "#GG0000"
    tick()
    hex._entry._text = "#FFF"
    tick()
    hex._entry._text = ""
    tick()
    check(#changes == 3 and texts() == "255,51,51,", "非法 hex／空白不變更顏色與滑桿")

    hex._entry._text = "#00ff80"
    tick()
    tick()
    check(#changes == 4 and nearly(changes[4].color.b, 128 / 255) and texts() == "0,255,128,#00ff80"
        and sl[3]._text == "128", "合法 hex（大小寫皆可）回呼一次並同步三條滑桿（silent）")

    picker:setColor({ r = 0, g = 0, b = 1 }, true)
    tick()
    check(#changes == 4 and nearly(picker:getColor().b, 1) and texts() == "0,0,255,#0000FF",
        "setColor silent 不回呼、滑桿與 hex 同步且不重複回呼")
    picker:setColor({ r = 0, g = 0, b = 1 })
    check(#changes == 4, "setColor 相同值 no-op")
    picker:setColor({ r = 1, g = 1, b = 1 })
    check(#changes == 5 and picker._selected == 24, "setColor 非 silent 回呼；等於色卡的顏色標為選中")

    local copy = picker:getColor()
    copy.r = 0
    check(picker:getColor().r == 1 and copy ~= changes[5].color, "getColor／回呼的 color 皆為新 table")

    picker:setEnabled(false)
    picker:onMouseDown(s.x + 1, s.y + 1)
    r:onMouseDown(6, 10)
    check(#changes == 5 and r:isEnabled() == false and sl[3]:isEnabled() == false and hex._enabled == false
        and r.captured == false, "disabled：色卡與滑桿不回應、hex 一併停用")
    picker:setEnabled(true)

    picker.rects, picker.borders = {}, {}
    picker:prerender()
    check(#picker.rects == 25 and #picker.borders == 27,
        "prerender：24 色塊＋預覽、各自邊框＋選中 2 層 accent 外框")
end

-- ============================================================
print("情境十七：Slider（量化夾限／點擊跳值／拖曳 capture 成對／同值不觸發／silent／滾輪／disabled／format 只量一次）")
-- ============================================================
do
    local measured = {}
    local keepTextManager = getTextManager
    getTextManager = function()
        local tm = keepTextManager()
        local inner = tm.MeasureStringX
        tm.MeasureStringX = function(self, font, text)
            measured[#measured + 1] = text
            return inner(self, font, text)
        end
        return tm
    end
    local events = {}
    local s = UI.Slider.new{ x = 0, y = 0, width = 200, min = 50, max = 200, step = 25, value = 110,
        target = TARGET, format = function(v) return v .. "%" end,
        onChange = function(target, v, slider) events[#events + 1] = { target = target, v = v, slider = slider } end }
    local captures = {}
    function s:setCapture(v) self.captured = v; captures[#captures + 1] = v end
    -- format(max)="200%" 量 40px＋間距 6 → track 寬 200-12-46=142，從 x=6 起
    check(s:getValue() == 100 and #events == 0 and s.height == 20 and #measured == 1 and measured[1] == "200%",
        "建構：110 依 step 以 min 為基準量化成 100、不回呼；預設高 20；format(max) 量一次")

    s:setValue(999)
    s:setValue(-5)
    check(#events == 2 and events[1].v == 200 and events[2].v == 50 and events[1].target == TARGET
        and events[1].slider == s, "setValue 夾在 min..max 並回呼 onChange(target, value, slider)")
    s:setValue(62)
    s:setValue(63)
    check(#events == 3 and s:getValue() == 75, "量化後同值不回呼（62→50）；63 四捨五入到 75")
    s:setValue(125, true)
    s:setValue("x")
    check(#events == 3 and s:getValue() == 125 and s._text == "125%", "setValue silent 不回呼；非數字忽略")

    s:onMouseDown(6 + 142, 10)
    s:onMouseUp(6 + 142, 10)
    check(#events == 4 and events[4].v == 200 and #captures == 2 and captures[1] == true and captures[2] == false,
        "點 track 跳值只回呼一次；按下 setCapture(true)、放開 setCapture(false)")

    s:onMouseDown(6, 10)
    mouseX = s.x + 6 + 71
    s:onMouseMove(0, 0)
    mouseX = s.x + 80
    s:onMouseMove(0, 0)
    mouseX = s.x + 900
    s:onMouseMoveOutside(0, 0)
    local capturedWhileOutside = s.captured
    s:onMouseUpOutside(0, 0)
    s:onMouseMove(0, 0)
    check(#events == 7 and events[5].v == 50 and events[6].v == 125 and events[7].v == 200
        and capturedWhileOutside == true and #captures == 4 and captures[4] == false,
        "拖曳：每次值變回呼一次、同格不回呼；出界仍收 move、放開後 capture 成對解除且不再跟隨")

    s:onMouseDown(170, 10)
    check(#events == 7 and #captures == 4, "按在值文字區不跳值、不 capture")

    s:setValue(100, true)
    local wheeled = s:onMouseWheel(-1)
    s:onMouseWheel(1)
    s:onMouseWheel(1)
    s:setValue(200, true)
    s:onMouseWheel(-1)
    check(wheeled == true and #events == 10 and events[8].v == 125 and events[9].v == 100 and events[10].v == 75,
        "滾輪往上 +step、往下 -step；到頂同值不回呼")
    local d = UI.Slider.new{ x = 0, y = 0, width = 100, min = 0, max = 1 }
    d:onMouseWheel(-1)
    check(nearly(d:getValue(), 0.05) and d._text == nil, "未給 step＝(max-min)/20；未給 format 不畫值")

    s:setEnabled(false)
    s:onMouseDown(6, 10)
    local wheelDisabled = s:onMouseWheel(-1)
    check(#events == 10 and wheelDisabled == false and #captures == 4 and s:isEnabled() == false,
        "disabled：按下不跳值不 capture、滾輪不吃事件")
    s:setEnabled(true)
    s:onMouseDown(6, 10)
    s:setEnabled(false)
    check(s.captured == false and #captures == 6, "拖曳中停用立即解除 capture")

    local theme = UI.Theme.create()
    s.rects, s.texts = {}, {}
    s:prerender()
    local faded = s.rects[1].a
    s:setEnabled(true)
    s._mouseOver = true
    s.rects, s.texts = {}, {}
    s:prerender()
    check(nearly(faded, theme.colors.well.a * 0.45) and nearly(s.rects[1].a, theme.colors.hover.a)
        and s.texts[1].text == "50%" and s.texts[1].x == 160,
        "繪製：disabled 淡化、hover 換 track 色、值文字畫在 track 右側")
    check(#measured == 1, "拖曳／改值／繪製全程 format 文字寬度只量一次")
    getTextManager = keepTextManager
end

-- ============================================================
-- rev 10 起鍵盤／手把共用 stub（情境十八與 rev 11 切片測試共用；ctx 契約見 rev 11 loader）
-- ============================================================
-- 鍵盤：可控按住狀態＋LWJGL 鍵碼（值只需互不相同）
local held = {}
Keyboard.KEY_TAB, Keyboard.KEY_SPACE, Keyboard.KEY_C = 15, 57, 46
Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT = 200, 208, 203, 205
Keyboard.KEY_HOME, Keyboard.KEY_END, Keyboard.KEY_PRIOR, Keyboard.KEY_NEXT = 199, 207, 201, 209
Keyboard.KEY_LSHIFT, Keyboard.KEY_RSHIFT, Keyboard.KEY_LCONTROL, Keyboard.KEY_RCONTROL = 42, 54, 29, 157
Keyboard.isKeyDown = function(k) return held[k] == true end
Keyboard.next = function() return false end
local keyQueue = {}
local eatKey = {}
GameKeyboard = { getEventQueue = function() return keyQueue end, isKeyDownRaw = function(k) return held[k] == true end,
    eatKeyPress = function(k) eatKey[k] = true end }
local clip = nil
Clipboard = { setClipboard = function(s) clip = s end }
function ISTextEntryBox:isEditable() return self._editable == true end
-- 手把：忠於 JoyPadSetup.lua:537-583 的焦點鏈（setJoypadFocus 推 prevfocus；不呼叫 gain／lose）
Joypad = { AButton = 0, BButton = 1, LBumper = 4, RBumper = 5 }
local joy = {}
getJoypadData = function(p) return joy[p + 1] end
getJoypadFocus = function(p) return joy[p + 1] and joy[p + 1].focus or nil end
setJoypadFocus = function(p, control)
    local d = joy[p + 1]
    if not d then return end
    if control ~= nil and control ~= d.focus then
        d.prevprevfocus = d.prevfocus
        d.prevfocus = d.focus
    end
    d.focus = control
end

-- 引擎派送順序（UIElement.java:2174-2219）：onKeyPress→isKeyConsumed；onKeyRelease→isKeyConsumed
local function press(win, key)
    win:onKeyPress(key)
    local consumed = win:isKeyConsumed(key)
    win:onKeyRelease(key)
    return consumed, win:isKeyConsumed(key)
end
-- 引擎時序（GameWindow.java:310,702-709；GameKeyboard.java:37-41,71-77）：輸入框的文字事件在幀尾處理，
-- 同一次按住下一幀才以取樣狀態派 press／release；被 eatKeyPress 吃掉就兩個都跳過（release 時清掉
-- 記號）。回 true＝有一半沒被視窗消耗，漏到遊戲按鍵（OnKeyStartPressed／OnKeyPressed）。
local function nextFrame(win, key)
    if eatKey[key] then eatKey[key] = nil; return false end
    local pc, rc = press(win, key)
    return not (pc and rc)
end

-- ============================================================
print("情境十八：rev 10 Focus（帳本／Tab 閱讀順序／Enter・Space／清單反白與啟動／分頁與滑桿／輸入框交接／手把接手與還原／Dialog／Ctrl+C）")
-- ============================================================
do
    dofile(MOD_LUA .. "Focus.lua")
    check(UI.CAPABILITIES.focus == true and UI.Focus ~= nil, "Focus 載入成功且 capability 翻 true")
    dofile(MOD_LUA .. "Widgets/Window.lua") -- 重新載入：Window／Dialog 接上 Focus
    local F, K = UI.Focus, Keyboard

    -- 輸入框持有文字焦點時按鍵不進 UIManager，Tab 走輸入框的 onOtherKey（Core.java:2049-2053）
    local function tab(win)
        local e = F.focused()
        if e and e.isFocused and e:isFocused() and e.onOtherKey then e.onOtherKey(e, K.KEY_TAB); return end
        press(win, K.KEY_TAB)
    end

    local clicks, selects, highlights, picks = 0, {}, {}, {}
    local win = UI.Window.new{ x = 0, y = 0, width = 400, height = 300, title = "T" }
    local tabs = UI.Tabs.new{ x = 10, y = 30, selected = "a", target = TARGET,
        onSelect = function(_, id) picks[#picks + 1] = id end,
        items = { { id = "a", label = "A" }, { id = "b", label = "B" } } }
    local search = UI.TextField.new{ x = 200, y = 30, width = 150 }
    local list = UI.VirtualList.new{ x = 10, y = 70, width = 150, height = 200, rowHeight = 20,
        createCell = function() return ISPanel.new(ISPanel, 0, 0, 1, 1) end, bindCell = function() end,
        onSelect = function(_, item) selects[#selects + 1] = item end,
        onHighlight = function(_, item) highlights[#highlights + 1] = item end,
        onKey = function(_, key) return key == K.KEY_LEFT end }
    list:initialise()
    list:setItems({ "r1", "r2", "r3" })
    local ok = UI.Button.new{ x = 170, y = 80, title = "OK", target = TARGET, onClick = function() clicks = clicks + 1 end }
    local other = UI.Button.new{ x = 260, y = 80, title = "Other" }
    local box = UI.Checkbox.new{ x = 170, y = 120, label = "Auto" }
    local hidden = UI.Button.new{ x = 170, y = 160, title = "Hidden" }
    hidden:setVisible(false)
    local slider = UI.Slider.new{ x = 170, y = 200, width = 100, min = 0, max = 10, step = 1, value = 5 }
    for _, c in ipairs({ other, ok, list, search, tabs, box, hidden, slider }) do win:addChild(c) end
    win:addToUIManager()

    local order = {}
    for i = 1, 7 do tab(win); order[i] = F.focused() end
    check(order[1] == tabs and order[2] == search._entry and order[3] == list and order[4] == ok
        and order[5] == other and order[6] == box and order[7] == slider,
        "Tab 依閱讀順序走框架控制項（由上而下、同列由左而右），隱藏的不算")
    check(not search._entry:isFocused(), "離開輸入框時交還原生文字焦點")
    local a, b = F.collectTargets(win), F.collectTargets(win)
    check(a == b and a[1] == b[1], "自動目標重用同一組 table（Focus.render 每幀呼叫不配置）")
    local pc, rc = press(win, K.KEY_TAB)
    check(pc and rc and not win:isKeyConsumed(K.KEY_TAB), "Tab 的 press 與 release 都消耗，按住結束後不再認領")
    check(F.focused() == tabs, "最後一個再按 Tab 繞回第一個")
    held[K.KEY_LSHIFT] = true
    press(win, K.KEY_TAB)
    held[K.KEY_LSHIFT] = nil
    check(F.focused() == slider, "Shift+Tab 往回走（修飾鍵以原始按住狀態讀）")

    F.focusControl(search._entry, true)
    check(search._entry:isFocused(), "鍵盤落在輸入框時交出原生文字焦點（可直接打字）")
    held[K.KEY_TAB] = true
    search._entry.onOtherKey(search._entry, K.KEY_TAB)
    nextFrame(win, K.KEY_TAB)
    held[K.KEY_TAB] = nil
    check(F.focused() == list and not search._entry:isFocused(),
        "在輸入框裡按 Tab 只走一格：輸入框放手後，下一幀同一次按住不會再以 press 多走一格")
    F.focusControl(search._entry, true)
    search._entry.onOtherKey(search._entry, K.KEY_TAB) -- 引擎取樣前就放開的極短點按
    check(F.focused() == list and eatKey[K.KEY_TAB] == nil,
        "極短點按不請引擎吞鍵（沒有 release 清掉記號，會吞掉玩家下一次 Tab）")
    F.focusControl(search._entry, true)
    held[K.KEY_RETURN] = true
    search._entry:onCommandEntered()
    nextFrame(win, K.KEY_RETURN)
    held[K.KEY_RETURN] = nil
    check(F.focused() == search._entry and not search._entry:isFocused() and eatKey[K.KEY_NUMPADENTER] == nil,
        "輸入框內 Enter 放手後，同一次按住不會把它重新聚焦；沒按的另一個 Enter 不被吞")

    F.focusControl(ok, true)
    local enterConsumed = press(win, K.KEY_RETURN)
    check(clicks == 1 and enterConsumed, "焦點框在按鈕上時 Enter 按下一次並消耗（不漏給聊天）")
    F.focusControl(box, true)
    press(win, K.KEY_SPACE)
    check(box:getChecked() == true, "Space 切換開關（Checkbox:forceClick，與點擊同一路徑）")
    -- 目標清單是動態的：焦點下的按鈕被移出清單（仍看得見）就不再是目標
    F.focusControl(ok, true)
    local before = clicks
    local only = { { kind = "button", control = other } }
    win.keyboardTargets = function() return only end
    press(win, K.KEY_RETURN)
    win.keyboardTargets = nil
    check(clicks == before and F.focused() == other,
        "焦點下的按鈕被移出目標清單（仍看得見）：Enter 不按它，焦點框移到清單裡的目標")

    F.focusControl(list, true)
    list:setSelectedIndex(1)
    press(win, K.KEY_DOWN)
    check(list:getSelectedIndex() == 2 and highlights[1] == "r2" and #selects == 0,
        "清單方向鍵只移動反白並呼叫 onHighlight，不觸發 onSelect")
    press(win, K.KEY_RETURN)
    check(#selects == 1 and selects[1] == "r2", "清單上的 Enter 呼叫 onSelect（與點擊同一個，只一次）")
    local leftConsumed = press(win, K.KEY_LEFT)
    check(leftConsumed and F.focused() == list, "清單的 onKey 先拿到按鍵（例如樹狀收合）")
    -- 引擎在按住的每一幀都派 repeat（GameKeyboard.java:61-64）：80ms 的點按在 240 FPS 下是 20 次
    list:setSelectedIndex(1)
    win:onKeyPress(K.KEY_DOWN)
    for _ = 1, 20 do nowMs = nowMs + 4; win:onKeyRepeat(K.KEY_DOWN) end
    check(list:getSelectedIndex() == 2, "點一下方向鍵只走一列（自動重複延遲內每幀的 repeat 不動）")
    for _ = 1, 100 do nowMs = nowMs + 4; win:onKeyRepeat(K.KEY_DOWN) end
    win:onKeyRelease(K.KEY_DOWN)
    win:isKeyConsumed(K.KEY_DOWN)
    check(list:getSelectedIndex() == 3, "按住超過自動重複延遲後繼續往下走")

    F.focusControl(tabs, true)
    press(win, K.KEY_RIGHT)
    check(picks[#picks] == "b", "分頁列上的右鍵切到下一頁")
    F.focusControl(slider, true)
    press(win, K.KEY_RIGHT)
    check(slider:getValue() == 6, "滑桿上的右鍵加一步")

    local esc1 = press(win, K.KEY_ESCAPE)
    check(esc1 and F.focused() == nil, "焦點框亮著時 Esc 收掉焦點框並消耗")
    local enter2 = press(win, K.KEY_RETURN)
    local esc2 = press(win, K.KEY_ESCAPE)
    check(not enter2 and not esc2, "沒有焦點框時 Enter／Esc 不消耗（聊天與暫停選單照常）")
    tab(win)
    win:onFocus()
    check(not F.isKeyboardFocused(F.focused()), "滑鼠按進視窗（onFocus）時不畫焦點框")

    -- 兩個 root：作用中的是最後開啟／點擊的那個，背景視窗不搶按鍵
    local reader = ISPanel.new(ISPanel, 10, 30, 100, 40)
    reader.getInternalText = function() return "hello" end
    local win2 = UI.Window.new{ x = 0, y = 0, width = 200, height = 100, title = "R" }
    win2:addChild(reader)
    win2.keyboardTargets = function() return { { kind = "scroll", control = reader } } end
    win2:addToUIManager()
    check(not press(win, K.KEY_TAB), "另一個視窗作用中時，背景視窗不消耗 Tab")
    press(win2, K.KEY_TAB)
    local lastToast = nil
    local keepShow = UI.Toast.show
    UI.Toast.show = function(o) lastToast = o.message end
    held[K.KEY_LCONTROL] = true
    press(win2, K.KEY_C)
    held[K.KEY_LCONTROL] = nil
    UI.Toast.show = keepShow
    check(clip == "hello" and lastToast == "[IGUI_MinidoracatUI_Copied]", "Ctrl+C 複製唯讀文字並以框架通知回報")
    win2:setVisible(false)

    -- 手把：開窗接手、方向移動、A 啟動、LB 切頁、B 關窗還原
    local prev = ISPanel.new(ISPanel, 0, 0, 10, 10)
    joy[1] = { player = 0, focus = prev }
    win:setVisible(false)
    win:setVisible(true)
    check(getJoypadFocus(0) == win and F.focused() == tabs and F.isKeyboardFocused(tabs),
        "用手把的玩家開窗：接手手把焦點、焦點框落在第一個目標")
    win:onJoypadDirDown(joy[1])
    check(F.focused() == search._entry and not search._entry:isFocused(),
        "手把移到輸入框時不交出鍵盤文字焦點（改由 A 開螢幕鍵盤）")
    win:onJoypadDirDown(joy[1])
    list:setSelectedIndex(1)
    win:onJoypadDirDown(joy[1])
    check(F.focused() == list and list:getSelectedIndex() == 2, "清單上手把往下移動反白")
    local asked, selected = false, #selects
    list.onKey = function(_, key)
        if key == K.KEY_RETURN then asked = true; return true end
        return key == K.KEY_LEFT
    end
    win:onJoypadDown(Joypad.AButton, joy[1])
    check(asked and #selects == selected, "手把 A 先問控制項的 onFocusKey（同鍵盤 Enter）：自訂 Enter 的清單不改走 onSelect")
    list:setSelectedIndex(3)
    win:onJoypadDirDown(joy[1])
    check(F.focused() == ok, "清單到底再往下：移到下一個目標")
    win:onJoypadDown(Joypad.AButton, joy[1])
    check(clicks == 2, "手把 A 按下焦點下的按鈕（只一次）")
    win:onJoypadDown(Joypad.LBumper, joy[1])
    check(picks[#picks] == "a", "手把 LB 切到上一頁")
    win:onJoypadDown(Joypad.BButton, joy[1])
    check(not win:getIsVisible() and getJoypadFocus(0) == prev and joy[1].prevfocus == nil,
        "手把 B 關窗，焦點還給開窗前的元件、prevfocus 鏈還原")
    prev:setVisible(false)
    win:setVisible(true)
    win:onJoypadDown(Joypad.BButton, joy[1])
    check(getJoypadFocus(0) == nil, "開窗前的元件已隱藏：關窗後焦點還給角色，不卡在看不見的 UI")
    -- 螢幕鍵盤借著焦點時視窗被別的事件關掉（ISTextEntryBox.lua:304-309、ISOnScreenKeyboard.lua:452-468）
    local oskShown = false
    local osk = {}
    function osk.hide(self)
        oskShown = false
        if self.textEntryBox then self.textEntryBox:focus() end
        joy[1].focus = self.prevFocus or self.textEntryBox
    end
    OnScreenKeyboard = { instance = osk, IsVisible = function() return oskShown end }
    local anchor = ISPanel.new(ISPanel, 0, 0, 10, 10)
    joy[1].focus = anchor
    win:setVisible(true)
    oskShown, osk.prevFocus, osk.textEntryBox = true, joy[1].focus, search._entry
    joy[1].focus = osk
    search._entry:unfocus()
    win:setVisible(false)
    OnScreenKeyboard = nil
    check(not oskShown and getJoypadFocus(0) == anchor and not search._entry:isFocused(),
        "螢幕鍵盤開著時視窗被關：鍵盤一起關、手把焦點還給開窗前的元件、不聚焦看不見的輸入框")
    local holder = ISPanel.new(ISPanel, 0, 0, 50, 50)
    local inner = ISPanel.new(ISPanel, 0, 0, 10, 10)
    holder:addChild(inner)
    joy[1].focus = inner
    win:setVisible(true)
    holder:setVisible(false)
    win:onJoypadDown(Joypad.BButton, joy[1])
    check(getJoypadFocus(0) == nil, "開窗前的焦點所在視窗已隱藏（元件自己仍標可見）：關窗後焦點還給角色")

    local results = {}
    local function record(okv) results[#results + 1] = okv end
    win:setVisible(true)
    F.focusControl(ok, true) -- 焦點框在「開啟對話框」的按鈕上
    -- 原版 addToUIManager 只排進 toAdd、下一次 UIManager.update 才進清單（UIManager.java:111-116,501-505）：
    -- 開窗那一幀原生 isReallyVisible 對整個新視窗都答 false（UIElement.java:1798-1805）
    local keepReal = ISPanel.isReallyVisible
    ISPanel.isReallyVisible = function() return false end
    local dlg = UI.Dialog.show{ title = "Q", text = "Sure?", confirmText = "Yes", cancelText = "No", onResult = record }
    ISPanel.isReallyVisible = keepReal
    check(getJoypadFocus(0) == dlg and F.focused() == dlg._confirm,
        "對話框接手手把焦點，預設在「確認」（開窗那一幀還沒進 UIManager 清單也一樣）")
    dlg:onJoypadDown(Joypad.AButton, joy[1])
    check(#results == 1 and results[1] == true and getJoypadFocus(0) == win, "A 確認只回呼一次，焦點還給原視窗")
    win:onJoypadDirDown(joy[1])
    check(F.focused() == ok, "手把關掉對話框後，下一次輸入把焦點框放回開啟它的按鈕（不從第一個目標重走）")
    dlg = UI.Dialog.show{ title = "Q", text = "Sure?", confirmText = "Yes", cancelText = "No", onResult = record }
    dlg:onJoypadDown(Joypad.BButton, joy[1])
    check(results[2] == false and getJoypadFocus(0) == win, "B 取消並把焦點還給原視窗")

    joy[1] = nil -- 鍵盤滑鼠玩家
    dlg = UI.Dialog.show{ title = "Q", text = "Sure?", confirmText = "Yes", cancelText = "No", onResult = record }
    press(dlg, K.KEY_TAB)
    check(F.focused() == dlg._cancel, "對話框裡 Tab 依閱讀順序先到「取消」")
    dlg:onKeyPress(K.KEY_RETURN)
    dlg:onKeyRelease(K.KEY_RETURN)
    check(results[3] == false, "焦點框在「取消」時 Enter 按取消，不是確認")
    dlg = UI.Dialog.show{ title = "Q", text = "Sure?", confirmText = "Yes", cancelText = "No", onResult = record }
    dlg:onKeyPress(K.KEY_RETURN)
    dlg:onKeyRelease(K.KEY_RETURN)
    check(results[4] == true, "沒有焦點框時 Enter 仍是確認")
    dlg = UI.Dialog.show{ title = "Q", text = "Name?", confirmText = "Yes", cancelText = "No",
        onResult = record, input = { text = "x" } }
    F.render(dlg) -- 每幀 render 替畫面上的輸入框掛勾（observe）
    held[K.KEY_RETURN] = true
    dlg._input._entry:onCommandEntered()
    local leaked = nextFrame(win, K.KEY_RETURN)
    held[K.KEY_RETURN] = nil
    check(results[5] == true and not leaked, "對話框輸入框按 Enter 確認後，同一次 Enter 不漏給後面的視窗與遊戲按鍵")
    F.focusControl(ok, true)
    dlg = UI.Dialog.show{ title = "Q", text = "Sure?", confirmText = "Yes", cancelText = "No", onResult = record }
    dlg:onKeyPress(K.KEY_ESCAPE)
    dlg:onKeyRelease(K.KEY_ESCAPE)
    press(win, K.KEY_TAB)
    check(results[6] == false and F.focused() == ok, "鍵盤關掉對話框後，第一次 Tab 回到開啟它的按鈕")
end

-- ============================================================
print("情境十九：rev 11 共用基礎（Text.fit／Skin.arrow／chip Button／截字與自動 tooltip／TextField 尺寸與 clearButton／theme.alpha）")
-- ============================================================
do
    local fit = UI.Text.fit -- stub 量測：每位元組 10px
    check(fit("Hello", 50) == "Hello" and fit("Hello", 49) == "H..." and fit("HelloWorld", 80) == "Hello...",
        "Text.fit：剛好放得下回原字串，差 1px 就截成最長前綴＋...")
    check(fit("Hello", 30) == "..." and fit("Hello", 29) == "" and fit("Hello", 0) == ""
        and fit("Hello", -5) == "" and fit(nil, 50) == "",
        "Text.fit：只放得下 ... 時回 ...、連 ... 都放不下或 maxW<=0 回空字串、nil 當空字串")
    -- 標準 Lua 是 UTF-8："中文字" 9 位元組；前綴只能停在字元開頭（位元組 0／3／6）
    check(fit("\228\184\173\230\150\135\229\173\151", 60) == "\228\184\173..."
        and fit("\228\184\173\230\150\135\229\173\151", 50) == "...",
        "Text.fit：不切開 UTF-8 多位元組字元（continuation byte 往前退）")

    check(UI.Skin.ARROW_W == 7 and UI.Skin.ARROW_H == 4, "Skin.ARROW_W／ARROW_H 為 7×4")
    local el = newElement(0, 0)
    UI.Skin.arrow(el, 10, 20, true, { r = 1, g = 0.5, b = 0, a = 0.8 }, 0.5)
    local r = el.rects
    check(#r == 4 and r[1].w == 1 and r[1].x == 13 and r[1].y == 20 and r[4].w == 7 and r[4].x == 10
        and r[4].y == 23, "Skin.arrow up：四列 drawRect、由上往下 1／3／5／7 寬置中（▲）")
    check(nearly(r[1].a, 0.4) and nearly(r[4].a, 0.4) and r[2].r == 1 and r[2].g == 0.5,
        "Skin.arrow：alpha＝color.a×alphaScale，顏色原樣")
    el = newElement(0, 0)
    UI.Skin.arrow(el, 0, 0, false, { r = 1, g = 1, b = 1 })
    check(#el.rects == 4 and el.rects[1].w == 7 and el.rects[4].w == 1 and el.rects[4].x == 3
        and el.rects[1].a == 1, "Skin.arrow down：7／5／3／1（▼），color.a 與 alphaScale 缺省為 1")

    -- chip：E0 環境（無 NinePatch）走直角，rects＝fill、borders＝border
    local chip = UI.Button.new{ title = "Chip", style = "chip" }
    chip:prerender()
    check(#chip.rects == 0 and #chip.borders == 1 and nearly(chip.borders[1].r, 0.4)
        and nearly(chip.texts[1].r, 0.62), "chip 閒置：無底、border 框、textMuted 字")
    chip._mouseOver = true
    chip.rects, chip.borders, chip.texts = {}, {}, {}
    chip:prerender()
    check(#chip.rects == 1 and nearly(chip.rects[1].a, 0.06) and nearly(chip.texts[1].r, 1),
        "chip hover：只有一層 hover 底（不重複疊）、text 字")
    chip._mouseOver = false
    chip:setActive(true)
    chip.rects, chip.borders, chip.texts = {}, {}, {}
    chip:prerender()
    check(chip:isActive() and #chip.rects == 1 and nearly(chip.rects[1].a, 0.12)
        and nearly(chip.borders[1].g, 0.85) and nearly(chip.texts[1].g, 0.85),
        "chip active：selected 底、accent 框與字")
    chip._mouseOver, chip.pressed = true, true
    chip.rects = {}
    chip:prerender()
    check(#chip.rects == 2 and nearly(chip.rects[2].a, 0.12), "chip 按下：疊一層 selected")
    chip:setEnabled(false)
    chip.borders, chip.texts = {}, {}
    chip:prerender()
    check(nearly(chip.borders[1].a, 0.45) and nearly(chip.texts[1].r, 0.55),
        "chip 停用：chrome 淡化、textFaint 字")
    local normal = UI.Button.new{ title = "N" }
    normal:setActive(true)
    normal:prerender()
    check(normal:isActive() and nearly(normal.rects[1].a, 0.5) and nearly(normal.borders[1].r, 0.4)
        and nearly(normal.texts[1].r, 1), "非 chip 樣式 setActive 只記狀態、外觀不變")

    -- 截字：寬 60 → 可用 48 → "L..."（40px）
    local measures = 0
    local keepTM = getTextManager
    getTextManager = function()
        return { MeasureStringX = function(_, _, text) measures = measures + 1; return string.len(text) * 10 end,
            getFontHeight = function() return 12 end }
    end
    local long = UI.Button.new{ title = "LongTitle", width = 60 }
    long:prerender()
    check(long.texts[1].text == "L..." and long.title == "LongTitle" and long.tooltip == "LongTitle",
        "寬度不足：畫截字標題、title 保留全文、全標題自動成為 tooltip")
    measures = 0
    long.texts = {}
    long:prerender()
    check(measures == 0 and long.texts[1].text == "L...", "標題與寬度沒變：每幀不重新量測")
    long:setWidth(120)
    long.texts = {}
    long:prerender()
    check(long.texts[1].text == "LongTitle" and long.tooltip == nil, "寬度恢復：全標題、自動 tooltip 收掉")
    long:setWidth(60)
    long:setTitle("Another")
    long:prerender()
    check(long.tooltip == "Another", "截字中改標題：自動 tooltip 跟著換")
    long:setTooltip("mine")
    long:prerender()
    long:setWidth(120)
    long:prerender()
    check(long.tooltip == "mine", "setTooltip 設的手動 tooltip 不被截字覆寫、寬度恢復也不收掉")
    long:setWidth(60)
    long:prerender()
    local stillManual = long.tooltip == "mine"
    long:setTooltip(nil) -- 標題與寬度都沒變：交回自動仍要在下一幀重判
    long:prerender()
    check(stillManual and long.tooltip == "Another", "setTooltip(nil) 交回自動：仍截字時下一幀補回全標題")
    local manual = UI.Button.new{ title = "LongTitle", width = 60, tooltip = "manual" }
    manual:prerender()
    check(manual.tooltip == "manual" and manual.texts[1].text == "L...", "建構時的 tooltip 是手動的，截字不覆寫")
    local auto = UI.Button.new{ title = "LongTitle" }
    auto:prerender()
    check(auto.texts[1].text == "LongTitle" and auto.tooltip == nil, "自動寬度永不截字")

    -- TextField placeholder：寬 120 → 可用 120-16=104 → "Placeho..."（100px）；原本整段畫到框外
    local pf = UI.TextField.new{ width = 120, placeholder = "Placeholder" }
    pf:prerender()
    check(pf.texts[1].text == "Placeho..." and string.len(pf.texts[1].text) * 10 <= 104
        and pf.placeholder == "Placeholder" and pf._entry.tooltip == "Placeholder",
        "placeholder 放不下：畫截字（不超出輸入區）、placeholder 保留全文、全文自動成為 tooltip")
    measures = 0
    pf.texts = {}
    pf:prerender()
    check(measures == 0 and pf.texts[1].text == "Placeho...", "placeholder 與寬度沒變：每幀不重新量測")
    pf:setWidth(200)
    pf.texts = {}
    pf:prerender()
    check(pf.texts[1].text == "Placeholder" and pf._entry.tooltip == nil, "寬度夠：畫全文、自動 tooltip 收掉")
    pf:setWidth(120)
    pf:setTooltip("mine")
    pf.texts = {}
    pf:prerender()
    local keptManual = pf._entry.tooltip == "mine" and pf.texts[1].text == "Placeho..."
    pf:setWidth(200)
    pf:prerender()
    check(keptManual and pf._entry.tooltip == "mine", "setTooltip 設的手動 tooltip 不被截字覆寫、寬度恢復也不收掉")
    pf:setWidth(120)
    pf:prerender()
    pf:setTooltip(nil)
    pf:prerender()
    check(pf._entry.tooltip == "Placeholder", "setTooltip(nil) 交回自動：仍截字時下一幀補回全文")
    getTextManager = keepTM

    local field = UI.TextField.new{ x = 0, y = 0, width = 200, clearButton = true }
    local entry = field._entry
    check(entry._clearButton == true and UI.TextField.new{ width = 100 }._entry._clearButton == nil,
        "opts.clearButton 轉呼叫原生 setClearButton(true)，未指定時不呼叫")
    field:setWidth(300)
    check(field.width == 300 and entry.x == 6 and entry.width == 288, "setWidth：內層 entry 寬度跟著外框（兩側內距 6）")
    field:setHeight(40)
    check(field.height == 40 and entry.y == 12 and entry.x == 6, "setHeight：內層 entry 垂直置中（(40-16)/2）")

    local faded = UI.Theme.create()
    faded.alpha = 0.5
    local fb = UI.Button.new{ title = "A", theme = faded }
    fb:prerender()
    check(nearly(fb.rects[1].a, 0.25) and nearly(fb.borders[1].a, 0.5) and nearly(fb.texts[1].a, 1),
        "theme.alpha：Button 的 fill／border 乘 0.5，文字不乘")
    local ff = UI.TextField.new{ width = 100, placeholder = "P", theme = faded }
    ff:prerender()
    check(nearly(ff.rects[1].a, 0.25) and nearly(ff.borders[1].a, 0.5) and nearly(ff.texts[1].a, 1),
        "theme.alpha：TextField 的 fill／border 乘 0.5，placeholder 不乘")
    local ft = UI.Tabs.new{ selected = "a", items = { { id = "a", label = "A" } }, theme = faded }
    ft:prerender()
    check(nearly(ft.rects[1].a, 0.25) and nearly(ft.borders[1].a, 0.5) and nearly(ft.texts[1].a, 1),
        "theme.alpha：Tabs 的 well／border 乘 0.5，頁籤文字不乘")
    local fw = UI.Window.new{ x = 0, y = 0, width = 300, height = 200, title = "W", theme = faded }
    fw:prerender()
    fw:render()
    check(nearly(fw.rects[1].a, 0.4) and nearly(fw.rects[2].a, 0.05) and nearly(fw.borders[1].a, 0.5)
        and nearly(fw.texts[1].a, 1), "theme.alpha：Window 本體／標題列／邊框乘 0.5，標題文字不乘")
end

--[[
切片測試載入器（本檔之後不必為了切片再改）：
  依序 loadfile scripts/test_rev11_{date,table,filter,itempicker,autocomplete}.lua 與 scripts/test_wrap.lua；
  檔案不存在記一筆失敗（六個切片都已落地）。
  檔案寫法：
      local ctx = ...
      local check, UI = ctx.check, ctx.UI
      dofile(ctx.MOD_LUA .. "Widgets/DatePicker.lua")
      print("情境 rev11-date：...")
      ... check(...) ...
      return 42   -- 本檔實際執行的 check 條數；不符記一筆失敗（取代 EXPECTED_ASSERTIONS 的守門）
  執行錯誤（語法／runtime）記一筆失敗，不中止其他切片。切片斷言不算進 EXPECTED_ASSERTIONS。
  ctx 欄位：
    check(ok, label)          斷言（計數＋PASS/FAIL 輸出）
    nearly(a, b)              浮點比較（誤差 1e-9）
    UI                        MinidoracatUI.v1；Controls／Window／Dialog／Focus／VirtualList 已載入
    MOD_LUA                   ".../media/lua/client/MinidoracatUI/"（結尾有 /）
    TARGET                    共用的 onClick target 哨兵 table
    now() / setNow(ms) / advance(ms)   getTimestampMs() 回傳的時間（起點遠大於 0）
    setMouse(x, y)            螢幕滑鼠座標；ISPanel stub 的 getMouseX() = x - self.x（不含父層）
    held                      按住中的鍵：held[Keyboard.KEY_X] = true（Keyboard.isKeyDown／GameKeyboard.isKeyDownRaw 讀它）
    joy                       手把資料：joy[1] = { focus = nil } 表示玩家 0 用手把；joy[1] = nil＝鍵盤滑鼠
    eatKey                    GameKeyboard.eatKeyPress 記下的鍵（nextFrame 會消化）
    press(win, key)           依引擎順序派 press→isKeyConsumed→release→isKeyConsumed，回傳兩次 consumed
    nextFrame(win, key)       下一幀模型（被 eat 就跳過）；回 true＝有一半漏給遊戲按鍵
    newElement(absX, absY, scrollX?, scrollY?)   純繪製落點 stub（rects／borders／tex）
    clipboard()               Clipboard.setClipboard 最後寫入的字串
  共用全域 stub（切片直接用，不要改語意）：ISPanel（x/y/width/height、children＝childrenInOrder、
    rects／borders／texts 繪製紀錄、_mouseOver 控 isMouseOver、stencil 計數、isReallyVisible 走父鏈）、
    ISButton（pressed／enable／onclick、forceClick、updateTooltip 計 tooltipPasses）、ISTextEntryBox
    （_text／_focused／_editable、setClearButton → _clearButton）、Keyboard.KEY_*、Joypad、GameKeyboard、
    getText（回 "[key]"，忽略參數）、getTextManager（每位元組 10px、字高 12）、UIFont、getCore（1920×1080）、
    getSpecificPlayer、getJoypadData／getJoypadFocus／setJoypadFocus。環境是 E0（無 NinePatchTexture）：
    Skin.fill → drawRect、Skin.border → drawRectBorder。
  切片缺的全域（getTextOrNull、ScriptManager、ISScrollingListBox…）自己在檔內補；暫時換掉的既有全域
  （例如 getTextManager）用完還原。
]]
local sliceCtx = {
    check = check, nearly = nearly, UI = UI, MOD_LUA = MOD_LUA, TARGET = TARGET,
    now = function() return nowMs end,
    setNow = function(v) nowMs = v end,
    advance = function(ms) nowMs = nowMs + ms end,
    setMouse = function(x, y) mouseX, mouseY = x, y end,
    held = held, joy = joy, eatKey = eatKey, press = press, nextFrame = nextFrame,
    newElement = newElement,
    clipboard = function() return clip end,
}
local sliceAssertions = 0
for _, slice in ipairs({ "rev11_date", "rev11_table", "rev11_filter", "rev11_itempicker", "rev11_autocomplete", "wrap" }) do
    local path = "scripts/test_" .. slice .. ".lua"
    local fh = io.open(path, "rb")
    if not fh then
        check(false, path .. " 不存在：切片測試被刪或改名")
    else
        fh:close()
        local before = assertionCount
        local chunk, err = loadfile(path)
        local ok, declared = false, err
        if chunk then
            ok, declared = pcall(chunk, sliceCtx)
        end
        local ran = assertionCount - before
        sliceAssertions = sliceAssertions + ran
        if not ok then
            failures = failures + 1
            print("  FAIL  " .. path .. " 執行錯誤：" .. tostring(declared))
        elseif declared ~= ran then
            failures = failures + 1
            print("  FAIL  " .. path .. " 斷言條數不符：宣告 " .. tostring(declared) .. "、實際 " .. ran)
        end
    end
end

-- 條數守門（家族慣例，同 test_nbpanel）：整段情境被 `if false then` 包掉或誤刪時，
-- 數字會變小但不會有任何東西紅。加測試把這個數字一起改大（改小要說得出刪了什麼）。
-- rev 11 切片檔的斷言由各檔 return 的條數自己守，不算在這裡。
local EXPECTED_ASSERTIONS = 392
print()
if assertionCount - sliceAssertions ~= EXPECTED_ASSERTIONS then
    print("斷言條數不符：預期 " .. EXPECTED_ASSERTIONS .. "、實際 " .. (assertionCount - sliceAssertions)
        .. "（有測試被刪掉或跳過？）")
    os.exit(1)
end
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過（" .. assertionCount .. " 斷言）")
