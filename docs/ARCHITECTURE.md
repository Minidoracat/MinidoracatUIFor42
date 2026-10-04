# MinidoracatUI 架構設計契約

> 定稿於 2026-08-25，基於 Claude × Codex × Grok 三方對 NeatUI Framework（Workshop 3508537032，
> modversion 1.0.8）的原始碼分析與家族 MOD（NoticeBoard／MiniMap）現況盤點。
> 本文件是實作的**權威依據**；與本文件衝突的實作即是 bug。引擎行為主張的出處以
> AGENTS.md「API 出處對照」為準（快照 42.20.3-20260817）。

## 0. 設計目標與非目標

**目標**
1. 消滅家族三類重複實作：Skin（NBSkin ↔ MiniMap_Skin 已分岔）、浮動按鈕（NBFloatButton ↔ MiniMap_FloatIcon 兩份獨立實作）、Toast（即將出現第二份）。
2. 讓未來家族 MOD 的 UI 起點是「掛依賴＋建 theme」，不是「複製貼上 300 行再改」。
3. 框架更新**永不**無聲破壞下游（版本化 API＋下游聯測閘門）。

**非目標**
- 不做通用 widget 大全（NeatUI 的 scope 滑坡教訓）；每個元件都要有 ≥1 個真實 consumer 才收。
- 控制元件的**外觀**不沿用 vanilla（2026-09-26 使用者決定：家族 UI 一律用框架的現代元素，不用官方原生的樣子）：rev 7 起 Button／TextField／Checkbox／Tabs／Window／Dialog 由框架提供現代外觀；vanilla 只作**輸入與事件基底**（`ISButton` 的點擊／搖桿語意、`ISTextEntryBox` 的 IME／游標、`ISLayoutManager` 的存讀），不重寫這些原生行為。
- 不 monkeypatch vanilla class。
- v1 不做 grid／變動列高清單／貼圖數字字型。

## 1. 依賴與解耦模型（使用者要求：盡量模組化解耦）

三層防線，任何一層失效都不得讓 consumer 的 UI 開不了：

```mermaid
graph LR
    subgraph consumer["Consumer MOD（如 NoticeBoard）"]
        A[mod.info require=MinidoracatUIFor42] --> B["adapter 檔（原 NBSkin 位置）"]
        B -->|框架存在且版本合格| C[轉呼叫框架 Skin/Theme]
        B -->|框架缺失/版本不合| D[內建直角退回：drawRect/drawRectBorder]
    end
    C --> E[MinidoracatUI.v1]
```

1. **引擎層（硬依賴）**：consumer 的 mod.info 掛 `require=MinidoracatUIFor42`——引擎保證框架先載入（`ZomboidFileSystem.java:807-833`），**框架 MOD 未安裝／PZ build 落在框架 versionMin 之外時，consumer 整個 MOD 會被引擎拒載**（`ChooseGameInfo.java:647-666`）。「玩家漏裝框架」由這一層以「缺少必要 MOD」明確擋下（Steam 訂閱會自動拉 Required Items），**不是**由退回層吸收。
2. **API 層**：consumer 檢查 `API_MAJOR`／`API_REVISION`；不合格＝**當框架不存在處理**，不得帶半套狀態運行。
3. **繪製層（退回紅線）**：consumer 的 adapter 保留最小直角退回路徑（`drawRect`／`drawRectBorder`）。它保護的情境是：**框架版本不合（API 檢查不過）、框架 Lua 初始化失敗（半初始化＝facade 未發布）、離線測試 harness**——這些情境下 UI 照開、只失去圓角。

> 解耦的代價聲明：adapter 模式意味著每個 consumer 保留 ~30 行退回碼。這是刻意的
> ——它讓 consumer 可以獨立測試、且框架壞版時不帶病運行；但注意這**不是**「不裝
> 框架也能玩」的軟依賴（引擎層是硬依賴），文件早期版本的「軟依賴」措辭以本節為準。

## 2. API 契約（v1）

唯一全域 `MinidoracatUI`。facade 形狀：

```lua
MinidoracatUI.v1 = {
    VERSION      = "0.5.0",   -- 發布字串，僅供顯示（定版 commit 時才與 modversion 同步）
    API_MAJOR    = 1,          -- 不相容變更 → 開新 MOD ID，此值永不 +1
    API_REVISION = 11,         -- additive 變更單調遞增；consumer 宣告最低需求
                               -- rev 1：首發｜rev 2：Icons｜rev 3：painters/assets｜rev 4：art icons｜rev 5：Toast maxLines｜rev 6：導覽圖示｜rev 7：現代控制元件｜rev 8：車輛／標記圖示＋ColorPicker｜rev 9：Slider（ColorPicker 的 R/G/B 改滑桿）｜rev 10：Focus 鍵盤＋手把焦點｜rev 11：收編 Economy 的日期／表格／篩選列／物品挑選／候選輸入＋共用基礎（Text.fit、Skin.arrow、chip Button、TextField 尺寸與 clearButton、theme.alpha）
    CAPABILITIES = {           -- 功能探測（分期發布的相容手段）
        theme        = true,
        skin         = true,
        icons        = true,   -- rev 2
        floatButton  = false,  -- 對應 widget 載入成功後才翻 true
        toast        = false,
        virtualList  = false,
        controls     = false,  -- rev 7：Button／TextField／Checkbox／Tabs（Widgets/Controls.lua）
        window       = false,  -- rev 7：Window（Widgets/Window.lua）
        dialog       = false,  -- rev 7：Dialog（Widgets/Window.lua，另需 controls 載入成功）
        colorPicker  = false,  -- rev 8：ColorPicker（Widgets/Controls.lua，與 controls 同檔）
        slider       = false,  -- rev 9：Slider（Widgets/Controls.lua，與 controls 同檔）
        focus        = false,  -- rev 10：Focus（Focus.lua；Window／Dialog 缺它時照常，只是沒有鍵盤導覽與手把）
        datePicker   = false,  -- rev 11：Date／DateField／DatePicker（Widgets/DatePicker.lua，另需 controls）
        table        = false,  -- rev 11：Table／TableHeader（Widgets/Table.lua，另需 virtualList）
        filterBar    = false,  -- rev 11：FilterBar（Widgets/FilterBar.lua，另需 controls＋datePicker）
        itemPicker   = false,  -- rev 11：ItemPicker（Widgets/ItemPicker.lua，另需 controls＋table）
        autocomplete = false,  -- rev 11：Autocomplete（Widgets/Autocomplete.lua，另需 controls）
    },
    Theme = <module>,
    Skin  = <module>,          -- 正式繪製 API（fill/border/dot/fits/toggle/slider/arrow），adapter 直接取用（§3.3）
    Icons = <module>,          -- 共用單色圖示（get/draw），rev 2 起新增（§3.6）
    Text  = <module>,          -- 文字量測（fit：依寬度截字＋省略號），rev 11 起新增（§3.3）
    -- 以下由 widget 檔在載入成功後掛上（對應 CAPABILITIES 旗標同時翻 true）：
    -- FloatButton／Toast／VirtualList（v0.2／v0.3）
    -- Button／TextField／Checkbox／Tabs（rev 7，controls）、Window（rev 7，window）、Dialog（rev 7，dialog）、
    -- ColorPicker（rev 8，colorPicker）、Slider（rev 9，slider）、Focus（rev 10，focus）、
    -- Date／DateField／DatePicker（rev 11，datePicker）、Table／TableHeader（rev 11，table）、
    -- FilterBar（rev 11，filterBar）、ItemPicker（rev 11，itemPicker）、Autocomplete（rev 11，autocomplete）
}
```

**規則**
- `MinidoracatUI.v1` 在**全部模組初始化成功後最後賦值**（Kahlua 半初始化風險，AGENTS.md 鐵則）。
- 同 major 只 additive；刪除／改簽章／改語意＝breaking＝開 `MinidoracatUIV2For42` 新 MOD ID。新增模組／新增 `CAPABILITIES` 旗標屬 additive：`API_REVISION` +1，既有呼叫面一字不動（rev 2 的 Icons 即是此形狀）。
- consumer 樣板：

```lua
-- PZ 的 require 不保證回傳值（原版 Lua 全樹零取值用例）——一律走全域取用：
if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")  -- 防禦：正式環境靠 mod.info require= 已先載
end
local UI = MinidoracatUI and MinidoracatUI.v1
local ok = UI ~= nil and UI.API_MAJOR == 1 and UI.API_REVISION >= 1
-- 要用 rev 2 才有的能力就把門檻寫成該能力的 revision，並一併探 CAPABILITIES：
--   local canIcon = ok and UI.API_REVISION >= 2 and UI.CAPABILITIES.icons and UI.Icons ~= nil
-- rev 3 painter 沿用 skin capability，逐函式探測：
--   local canPainters = ok and UI.API_REVISION >= 3
--       and type(UI.Skin.toggle) == "function" and type(UI.Skin.slider) == "function"
-- rev 7 控制元件逐旗標探測（Dialog 需要 dialog，不只 window）：
--   local canControls = ok and UI.API_REVISION >= 7 and UI.CAPABILITIES.controls
--   local canDialog = ok and UI.API_REVISION >= 7 and UI.CAPABILITIES.dialog
-- rev 8 車輛／標記圖示與取色器：
--   local canVehicleIcons = ok and UI.API_REVISION >= 8 and UI.CAPABILITIES.icons
--   local canColorPicker = ok and UI.API_REVISION >= 8 and UI.CAPABILITIES.colorPicker
-- rev 9 滑桿：
--   local canSlider = ok and UI.API_REVISION >= 9 and UI.CAPABILITIES.slider
-- rev 11 元件逐旗標探測（缺相依的檔不翻旗標，只探自己要的那一個即可）；共用基礎逐函式探：
--   local canTable = ok and UI.API_REVISION >= 11 and UI.CAPABILITIES.table
--   local canFit = ok and UI.API_REVISION >= 11 and UI.Text ~= nil and type(UI.Text.fit) == "function"
-- ok == false → 走 adapter 的直角退回，不帶半套狀態運行
```

## 3. 模組設計

### 3.1 檔案佈局（`42/media/lua/client/MinidoracatUI/`）

| 檔案 | 期 | 職責 |
|---|---|---|
| `V1.lua` | v0.1（rev 2／3／11 擴充） | **單檔**：Theme＋Skin＋Icons＋Text＋facade 五個 section（詳見檔頭「單檔設計」註解——分檔就得靠全域存在檢查串接，會重演 NeatUI 的隱藏載入順序依賴；單檔讓「中段 error＝facade 從未發布」自然成立） |
| `TextWrap.lua` | rev 11 修正 | **內部**斷行模組（§3.4「斷行」）：不掛 facade、不設全域，只 `return` 一張表。Toast／Window 以 `pcall(require, "MinidoracatUI/TextWrap")` 取回傳值：`LuaManager.RunLuaInternal` 把第一次執行的回傳值存在 `loadedReturn`，之後的 require 直接回它（42.20.1 起相同；原版 `shared/Sandbox/SandboxVars.lua:1` 也這樣取值）。缺席或載入失敗時 Toast 多行退回單行截字、`dialog` 維持 false |
| `Widgets/FloatButton.lua` | v0.2 | 常駐浮鈕：拖曳、位移門檻點擊判定、位置持久化回調、clamp 回螢幕；獨立檔、單向依賴 V1 全域，載入失敗只影響 `CAPABILITIES.floatButton` |
| `Widgets/Toast.lua` | v0.2 | 通知堆疊：佇列、淡入淡出、alwaysOnTop；同上 |
| `VirtualList.lua` | v0.3 | 垂直固定列高虛擬清單（§3.5） |
| `Widgets/Controls.lua` | rev 7（rev 8／9／11 擴充） | Button／TextField／Checkbox／Tabs（§3.7）＋ColorPicker（§3.8）＋Slider（§3.9）；載入失敗只影響 `CAPABILITIES.controls`／`colorPicker`／`slider` |
| `Widgets/Window.lua` | rev 7（rev 10／11 擴充） | Window／Dialog（§3.7）；開頭自行 `pcall(require, …)` 取 `"MinidoracatUI/Widgets/Controls"`、`"MinidoracatUI/Focus"` 與 `"MinidoracatUI/TextWrap"`，Controls 或 TextWrap 缺席時只提供 Window、`dialog` 維持 false；Focus 缺席時沒有鍵盤導覽與手把 |
| `Focus.lua` | rev 10 | 鍵盤＋手把焦點引擎（§3.10）；需要原生 `Keyboard`，缺席時 `CAPABILITIES.focus` 維持 false |
| `Widgets/DatePicker.lua` | rev 11 | `UI.Date`／`UI.DateField`／`UI.DatePicker`（§3.11）；自行 pcall require Controls（缺席即 return）與 Focus（選用），`CAPABILITIES.datePicker` |
| `Widgets/Table.lua` | rev 11 | `UI.Table`／`UI.TableHeader`（§3.12）；需要 `UI.Text` 與 `Skin.arrow`，自行 pcall require VirtualList（缺席即 return），`CAPABILITIES.table` |
| `Widgets/FilterBar.lua` | rev 11 | `UI.FilterBar`（§3.13）；自行 pcall require Controls、DatePicker（任一缺席即 return）與 Focus（選用），`CAPABILITIES.filterBar` |
| `Widgets/ItemPicker.lua` | rev 11 | `UI.ItemPicker`（§3.14）；自行 pcall require Controls、Table（任一缺席即 return）與 Focus（選用），`CAPABILITIES.itemPicker` |
| `Widgets/Autocomplete.lua` | rev 11 | `UI.Autocomplete`（§3.15）；自行 pcall require Controls（缺席即 return）與 Focus（選用），`CAPABILITIES.autocomplete` |

載入順序防雷：v0.1 核心單檔（無內部順序問題）；v0.2 起的 Widget 檔開頭自行檢查
`MinidoracatUI.v1` 存在、缺席時不掛能力——不重演 NeatUI「scrollview 用
`NIScrollBar` 卻不 require」的隱藏順序依賴。

### 3.2 Theme（含深/淺雙色系，v0.1 內建）

```lua
local theme = UI.Theme.create({
    variant = "dark",              -- "dark"（預設）| "light"
    colors  = {                    -- 只寫要覆蓋的 token
        accent = { r=1, g=0.85, b=0.4, a=1 },
    },
})
```

- **token 分層**：框架 default 只放跨 MOD token，**v1 共 12 個**（`surface`／`surfaceTitle`／`well`／`border`／`text`／`textMuted`／`textFaint`／`accent`／`hover`／`selected`／`errorSurface`／`errorText`——與 `V1.lua` 的 `DARK`/`LIGHT` 表逐字一致，該表是唯一權威）；MOD 自有 token（如 NoticeBoard 的 `unread`、MiniMap 的 `rowHover`）由 create 時自帶，框架不認識也不管。**未知 token 的 theme 便捷方法呼叫是靜默不畫**（fail-soft），拼錯 token＝元素消失無診斷——寫 consumer 時以 V1.lua 的表為準，勿憑記憶。
- **雙色系**：`variant` 選 default palette 起點；兩套數值都在 `V1.lua` 的 Theme section（`DARK`／`LIGHT` 表）內維護。繪製邏輯與資產完全 variant 無關（白圖×頂點染色）。深色為預設（PZ 本體與家族現有 UI 全深色）；淺色首發標 experimental。variant 由 MOD 開發者決定；玩家層級即時切換是未來項目（牽涉全 consumer token 完整性）。
- **隔離**：`create()` 深拷貝，禁止 mutate 共享 default——現有 NBSkin↔MiniMap drift 的根源就是「共用色票、各自複製」。
- **已知取捨（色票三份現況）**：兩個既有 adapter 刻意保留字面 `COLORS`（框架缺席時色票也要在、退回路徑不依賴框架），因此共通數值目前存在三份（NBSkin／MiniMap Skin／框架 DARK）。v0.1 接受此取捨——「消滅重複」在繪製碼與 PNG 已達成，色票的單一權威化留待既有 consumer 改用 `Theme.create`（自然時機：某 MOD 需要 light variant 或玩家換色時）。

### 3.3 Skin（NinePatch 生命週期全封裝）

`Skin` 的無狀態繪製函式是**正式公開 API**（受同 major additive 承諾保護），
thin adapter 直接取用；theme 實例方法是其上的便捷薄層（token 字串解析）：

```lua
-- 正式 API（adapter 用法；color 是 {r,g,b,a} table）：
UI.Skin.fill(element, x, y, w, h, color, shape, alphaScale)
UI.Skin.border(element, x, y, w, h, color, shape, alphaScale)
UI.Skin.dot(element, x, y, size, color, outline)
UI.Skin.fits(w, h, shape)
UI.Skin.toggle(element, x, y, width, rowHeight, on, colors, alphaScale)
UI.Skin.slider(element, x, y, width, rowHeight, ratio, colors, alphaScale)
UI.Skin.arrow(element, x, y, up, color, alphaScale)          -- rev 11；UI.Skin.ARROW_W＝7、ARROW_H＝4
-- 文字量測（rev 11，同在 V1.lua）：
UI.Text.fit(str, maxW, font) -- 放得下回原字串，否則「最長前綴＋...」；font 省略＝UIFont.Small
-- theme 便捷層（新 MOD 用法；color 可為 token 字串或 table）：
theme:fill(element, x, y, w, h, colorOrToken, shape, alphaScale)
-- shape: nil/false="round"（四角圓）| true/"roundTop"（上圓下直）|
--        "pill"（10px cap）| "rect"（強制直角）
--        boolean 形式與家族既有 topOnly 呼叫慣例逐位相容
```

**內建規則（caller 不必知道的事）**
- 首呼叫連呼兩次＋pcall；兩次 nil → cache `false` 永不重試 → 直角退回（`NinePatchTexture.java:42-63`）。
- `fits` 檢查內建於 shape：`round` 最小 12×12、`roundTop` 最小 12×6、`pill` 最小 20×20；不足自動退直角（角落重疊會疊 alpha，寧可誠實直角）。pill 使用獨立 10/4/10 cap 資產；高度恰好 20px 才是精確膠囊，高於 20px 是半徑 10px 的圓角矩形。
- `toggle` 不建立 widget：它是每幀可直接呼叫的無狀態 painter。track 固定高 20px、在 `rowHeight` 內垂直置中；knob 固定 16px、左右各留 2px。`colors={off,on,knob,border}` 可省略或缺項，缺色使用框架常數；貼圖缺失沿用 Skin 的直角／方點退回。幾何契約要求 `width >= 20`、`rowHeight >= 20`；較小輸入直接回 `false` 且不繪製，由 consumer 保留原文字／狀態退回。
- `slider` 同樣不建立 widget：只畫 4px track、比例填色與 12px 圓形 knob；`ratio` 夾在 0..1，`colors={track,fill,knob,border}`。拖曳、步進、上下限由呼叫端負責——要現成的可拖曳元件用 rev 9 的 `UI.Slider`（§3.9，內部即呼叫本 painter）。
- `arrow`（rev 11）是排序方向箭頭：`ARROW_W`×`ARROW_H`（7×4）的階梯三角形，逐列 `drawRect`，`up=true` 為 ▲（升冪）。不用貼圖，所以沒有缺圖退回；Icons 沒有 `chevronUp`，這是刻意不加 icon key 的替代。移植自 Economy `drawArrow`。
- `UI.Text.fit`（rev 11）：`maxW <= 0` 或連 `"..."` 都放不下回 `""`；二分搜尋前綴長度（長字串只量 log2(n) 次），切點不切開 UTF-16 surrogate pair（Kahlua 字串以 UTF-16 code unit 為單位，`string.char` 是 `(char)num`，`StringLib.java:760-768`）或 UTF-8 continuation byte（標準 Lua harness）。量測一律走 `MeasureStringX`，呼叫端負責快取結果（框架元件只在文字或寬度變了才重算）。移植自 Economy `U.fitText`。
- 座標：`getAbsoluteX/Y` ＋（在 scrolling 容器內）自身 scroll offset，再 `math.floor`——MiniMap 實戰教訓直接內建，consumer 不再各自修。
- pcall 用具名頂層函式傳參，**零 per-frame closure 配置**（MiniMap 的 GC 改良收編為標準）。
- 貼圖目錄：`42/media/ui/MinidoracatUI/`，程序化生成（§6），全主題共用同一套白圖。

### 3.4 Widgets（v0.2）

從兩份既有實作（NBFloatButton 260 行級、MiniMap_FloatIcon 260 行）提煉**行為契約**重新實作，不搬碼：

- `FloatButton`：拖曳位移門檻（≦4px＝點擊）、位置持久化（回調由 consumer 接 ModOptions／ini，框架不綁存檔機制——解耦）、每幀 clamp 回螢幕、hover 提示回調。
- `Toast`：所有 MOD 共用佇列＋堆疊上限、淡入淡出（`getTimestampMs` 計時）、alwaysOnTop；逾時自動移除，也可呼叫 `Toast.dismiss(instance)`，沒有點擊消失功能。位置累加前面每則實際高度與間距，讓單行／多行通知混用時不重疊；移除與 pending 遞補後重新計算。**只顯示、不收滑鼠**：`wantMouseEvents=false`（左鍵與移動穿透），右鍵處理明確回 false（Lua 回 nil 時引擎一律當吃掉，`UIElement.java:1513-1515,1583-1585`），蓋到的介面照常可點。**避開原版速度鈕**：單人戴錶時速度鈕移到時鐘下方、落在通知欄內（`UIManager.java:446-456`）；它在 UI 清單裡、可見且與通知欄水平重疊時，堆疊改從它下緣＋間距起算，否則從固定上緣起算。Toast 不操作 stencil，巢狀裁切的成對性由 VirtualList 驗證。
- **斷行（Toast `maxLines > 1` 與 Dialog 內文共用，內部模組 `TextWrap.lua`）**：貪婪斷行，每行以 `MeasureStringX` 二分找最長放得下的前綴（量 O(log n) 次）。截點兩側任一是空白，或任一是中日韓字（CJK 表意字與符號、假名、注音、諺文音節、全形字、補充平面字），就在截點斷；否則往回找最近的斷點（空白或中日韓字交界），整段都沒有斷點（比行寬長的拉丁單字）才在截點硬切。禁則：行首不放收尾標點（UAX #14 的 CL／CP／EX／IS／NS 與 ’ ” …），行尾不放起始標點（OP 與 ‘ “），遇到就連同前一字移到下一行。截點不切開 surrogate pair（Kahlua UTF-16）或多位元組字（harness UTF-8）；行尾與下一行開頭的空白去掉；連一個字都放不下時仍放一個字。修正前一律退回前綴裡最後一個空白：中日文夾英文時在英文字後提早斷行，截點剛好在單字結尾時也多退一個單字；新規則下同一段文字的行數通常變少，禁則推字時可能多一行，Toast 與 Dialog 的高度都依實際行數計算。

**置頂契約**：`FloatButton` 的 `alwaysOnTop` 預設仍為 true；框架在 `addToUIManager()` 完成實例化後呼叫原生 setter，Toast 同樣如此。只寫 Lua 欄位不會改變引擎排序（`ISUIElement.lua:993-1008,1319-1322`；`UIManager.java:545-556`）。一般入口要明確傳 `false`，讓後開視窗能蓋在入口上；MiniMap、NoticeBoard、Economy、DevProfiler 已採此設定，不改各自原有 bringToTop 與生命週期。發布置頂修正前，先交付已上線 consumer 的這項相容設定，避免仍使用舊 consumer 的玩家突然改變浮鈕層級。

### 3.5 VirtualList（v0.3）——對 NeatUI 的修正表

| NeatUI 實證問題 | 本框架設計 |
|---|---|
| `setDataSource(data, forceRefresh)` 靠 caller 記得 force（`nivirtualscrollview.lua:69-79`） | `setItems(items)` 內建 revision，可見綁定自動失效 |
| 同範圍原地變更不重繪（`:220-245`） | cell 記 bound revision＋index，任一變即重綁 |
| 回收 cell 殘留 hover/pressed | `bindCell` 全量重設投影；`unbindCell` 清除 consumer 持有的狀態與外部資源，框架清綁定標記並隱藏 |
| 內容高度從已移動 child 量測（`niscrollview.lua:103-117`） | `contentHeight = count × stride + padding`，純計算 |
| stencil 只 set→clear（`:354-362`） | set→draw→clear→repaint 成對 |
| selection 散在 cell | selection/focus 存 list，cell 是投影 |
| grid 塞同 class＋熱路徑 print（`nigridvirtualscrollview.lua:316`） | 不做 grid；框架預設零 log |

**解除綁定時機**：已綁定 cell 因資料縮水而隱藏，或在 `rebuildPool`（包含 resize）移除前，呼叫一次 `unbindCell(list, cell)`；回呼執行時仍可讀取舊綁定。未綁定的空 cell 不呼叫。可見 cell 捲動／revision 更新仍直接呼叫 `bindCell` 覆蓋，不新增 unbind 通知；consumer 必須在 bind 中重設舊投影，以維持既有呼叫語意。tooltip 等獨立於 cell 的資源須由 consumer 清除，不能只依賴 child 被移除。

**綁定失敗**：`boundIndex` 在回呼前可讀，`boundRevision` 在綁定期間失效、成功後才確認。回呼錯誤原樣傳出，後續 `refreshCells()` 可以重試，不把半完成列當成最新內容；不新增背景重試或捲動時的 unbind。

### 3.6 Icons（API rev 2／3）——共用單色圖示

家族 MOD 各自畫 ASCII 符號（`+`／`-`／`>`）當展開箭頭與工具列標記，同一顆按鈕在兩個 MOD
長不一樣、也無法隨主題染色。Icons 收編這一層：一套白圖、運行時染色、缺資產就退回原本的
文字表示。**只收已同意的 reusable key**（rev 2 首批 8 個由 NoticeBoard 文件樹與工具列消費；
rev 3 additive 新增 12 個），不做圖示大全——這是 §0 非目標「不做通用 widget 大全」
的同一條線。

| key | 檔名（`42/media/ui/MinidoracatUI/`） | 首個用途 |
|---|---|---|
| `sidebar` | `mui_icon_sidebar.png` | 切換側邊文件樹 |
| `folder` | `mui_icon_folder.png` | 文件樹的目錄節點 |
| `document` | `mui_icon_document.png` | 文件樹的文件節點 |
| `chevronRight` | `mui_icon_chevron_right.png` | 目錄收合狀態 |
| `chevronDown` | `mui_icon_chevron_down.png` | 目錄展開狀態 |
| `language` | `mui_icon_language.png` | 切換語言 |
| `reload` | `mui_icon_reload.png` | 重新載入內容 |
| `resetSize` | `mui_icon_reset_size.png` | 重設視窗大小 |
| `search` | `mui_icon_search.png` | 搜尋 |
| `chevronLeft` | `mui_icon_chevron_left.png` | 返回／向左導覽 |
| `layers` | `mui_icon_layers.png` | 圖層 |
| `pin` | `mui_icon_pin.png` | 釘選位置 |
| `globe` | `mui_icon_globe.png` | 世界／全域範圍 |
| `sliders` | `mui_icon_sliders.png` | 篩選／調整 |
| `gauge` | `mui_icon_gauge.png` | 儀表／效能 |
| `lock` | `mui_icon_lock.png` | 視窗鎖定狀態 |
| `unlock` | `mui_icon_unlock.png` | 視窗解除鎖定狀態 |
| `close` | `mui_icon_close.png` | 視窗關閉 |
| `locate` | `mui_icon_locate.png` | 定位／回到玩家 |
| `copy` | `mui_icon_copy.png` | 複製座標 |

```lua
UI.Icons.get(name)                                     -- Texture 或 nil
UI.Icons.draw(element, name, x, y, size, color, alpha) -- boolean：true＝已畫
-- color 省略＝純白；alpha 省略＝color.a，再省略＝1；size 同時是寬與高
```

**規則**
- 資產規格：32×32 純白 RGBA、alpha 即形狀、外圍 1px 透明邊；幾何圖示由程序生成，art 圖示由 AI 原圖匯入（§6）。
  **32px 原稿供 14–20px 顯示**：16px 是乾淨的 2:1 縮小；rev 3 標題列狀態圖示可放大
  到 20px，仍由原始 32px 抗鋸齒圖縮放，不使用放大的 16px 點陣。
- 染色同皮膚：白圖 ×`drawTextureScaled` 頂點色，一套資產服務深／淺兩色系（AGENTS.md API 表）。
- **fail-soft 紅線**：未知 key／`getTexture` 不存在（dedicated）／貼圖缺失／繪製拋錯，
  `get` 回 `nil`、`draw` 回 `false` 且不拋錯——consumer 依回傳值退回自己的 ASCII 或純文字，
  絕不因為少一張 PNG 就讓按鈕消失或視窗開不了。
- 快取與 Skin 共用（同一份檔名表）：每張只探測一次，失敗記 `false` 不重試；
  測試用 `Skin._resetForTests()` 一併清除。
- 繪製拋錯**不**把貼圖標壞：`drawTextureScaled` 失敗也可能是 element 契約破損，
  element 壞不是貼圖的錯（同 §3.3 的 E3 準則）。
- 新增 key ＝ additive：加檔名對應＋資產（幾何或 art）＋`verify_mod.py` 探針＋`API_REVISION` +1；
  **既有 key 的語意與檔名永不更動**（consumer 只認 key）。

**rev 6 導覽圖示**：新增 `wallet`／`gift`／`shop`／`market`／`auction`／`mail`／`users`／`chart`／`coins`／`plug`／`shieldCheck`／`tag`／`transactions`／`clipboardCheck`／`server`／`settings`，對應 `mui_art_<key>.png`。沿用 art 的 32×32 純白 alpha 規格，導覽顯示尺寸為 20–24px；未知 key、缺圖與繪製失敗的回傳契約不變。

**rev 8 車輛／標記圖示**：新增 `carSedan`／`carHatchback`／`carSports`／`carSuv`／`carPickup`／`carVan`／`carStepVan`／`carTruck`／`carAmbulance`／`carPolice`／`carFiretruck`／`carTrailer`（側視、車頭朝右）與 `markerStar`／`markerHeart`／`markerFlag`／`markerCrown`，對應 `mui_art_<key>.png`。用途是地圖上的車輛／自訂標記，顯示尺寸 16–24px，搭配 `UI.ColorPicker` 選色以頂點染色；回傳契約同上。

### 3.7 現代控制元件（API rev 7；rev 11 擴充）

使用者決定家族 UI 不再用 vanilla 的 `ISCollapsableWindow`／`ISButton`／`ISModalDialog`／`ISTickBox`／`ISScrollingListBox` 外觀（§0）。rev 7 提供六個元件：外觀全由 theme token＋Skin 自繪（貼圖缺失退直角、icon 缺失退文字），vanilla 只負責輸入與事件。首個 consumer：VehicleManager 車隊視窗。

**共通**：`.new(opts)` 回傳**已 `initialise()`** 的元素，consumer 以 `parent:addChild(el)`（Window 用 `el:addToUIManager()`）加入；`opts.theme` 省略＝`UI.Theme.create()`、`opts.font` 省略＝`UIFont.Small`；元素上的 `internal` 欄位留給 consumer；所有 setter 對相同值是 no-op；prerender/render 零 table／closure 配置，並自行守 `isCollapsed`。額外顏色只從 12 個既有 token 推導，不改 `DARK`／`LIGHT` 表（唯一例外：primary 按鈕的深色字是元件內常數）。

| 元件 | 建構 | 公開方法 | 回呼 |
|---|---|---|---|
| `UI.Button` | `{ x, y, width?, height?, title, icon?, style?, active?, theme?, font?, target?, onClick?, tooltip? }` | `setTitle(s)`、`fitWidth()`、`setEnabled(b)`、`isEnabled()`、`setTooltip(s)`、`setStyle(style)`、`setActive(b)`／`isActive()`（rev 11） | `onClick(target, button)`；disabled 不觸發 |
| `UI.TextField` | `{ x, y, width, height?, text?, placeholder?, theme?, font?, onlyNumbers?, maxLength?, clearButton?, onChange? }` | `getText()`、`setText(s)`、`focus()`、`isFocused()`、`setEnabled(b)`、`setTooltip(s)`、`setWidth(w)`／`setHeight(h)`（rev 11 起重排內層） | `onChange(field, text)`；`setText` 不觸發 |
| `UI.Checkbox` | `{ x, y, width, height?, label, checked?, theme?, font?, target?, onChange? }` | `getChecked()`、`setChecked(b, silent)`、`setEnabled(b)`、`setLabel(s)` | `onChange(target, checked, box)` |
| `UI.Tabs` | `{ x, y, width?, height?, items = { {id, label}, ... }, selected?, theme?, font?, target?, onSelect? }` | `setSelected(id, silent)`、`getSelected()`、`setItemVisible(id, visible)`、`setItemLabel(id, s)` | `onSelect(target, id, tabs)`；點已選中不觸發 |
| `UI.Window` | `{ x, y, width, height, title, icon?, theme?, font?, resizable?, minWidth?, minHeight?, closable?, onClose?, onResize? }` | `close()`、`titleBarHeight()`、`contentTop()`、`setTitle(s)`、`SaveLayout(name, layout)`、`RestoreLayout(name, layout)` | `onClose(win)`、`onResize(win, w, h)` |
| `UI.Dialog` | `UI.Dialog.show{ title, text, confirmText, cancelText?, danger?, input?, width?, theme?, font?, onResult? }` → dialog（Window 實例） | `UI.Dialog.close(dialog, ok)` | `onResult(ok, inputText)` 只呼叫一次 |

**行為契約**
- **Button**：`ISButton:derive` 為基底，保留原生 pressed／enable／tooltip／搖桿語意（`ISButton.lua:33-64,316-346`），prerender/render 全自繪：圓角 fill＋border、hover／pressed／disabled 三態。style：`normal`（well 底＋border）、`primary`（accent 底、深色字）、`danger`（errorSurface 底、errorText 字／框）、`ghost`（無底，hover 才有底）；未知 style 退 `normal`。寬度省略＝標題寬＋左右各 10px（有 icon 再加 16＋6），高度省略＝字高＋10；明示寬度不被原生 `ISButton:new` 撐寬（`:493-495`）。`setTitle` 只在自動寬度時重算。`icon` 是 `UI.Icons` key、畫在文字左側，Icons 失敗只畫文字。
- **TextField**：ISPanel 容器畫圓角 well＋border（focus 時 accent），內含透明、無邊框的原生 `ISTextEntryBox`（IME／游標／選取原生）；`setEditable` 會重設原生 borderColor（`ISTextEntryBox.lua:64-71`），元件每次改回透明。空字串且未 focus 時畫 textFaint placeholder；放不下時以 `UI.Text.fit` 截成「前綴＋...」，只在 placeholder 或寬度改變時重算。截到字且沒有手動 tooltip 時，全文自動當 tooltip，放得下時收掉；`setTooltip(s)` 手動優先，`setTooltip(nil)` 交回自動（同 Button）。原生清除鈕只在有文字時出現（`UITextBox2.java:188`），所以不扣它的寬。文字變化**每幀比對**（IME 組字送出不觸發原生 onTextChange），一次變化觸發一次。`setEnabled(false)`＝不可編輯＋失焦＋淡化。tooltip 交給原生 entry 顯示。
- **Checkbox**：`Skin.toggle` 畫 36px 開關（高度省略＝max(20, 字高＋4)；toggle 幾何不足時退回方框），右側 label，整列可點；disabled 不切換。
- **Tabs**：分段式頁籤列，選中為 selected 底＋accent 下緣；寬度省略＝各頁籤（標籤寬＋24）加總。`setItemVisible` 重排並在自動寬度時更新 width；隱藏的是選中項時**不自動切換**；未知 id 的 `setSelected` 忽略。
- **Window**：surface 圓角本體＋roundTop 標題列（surfaceTitle）＋可選 icon＋標題；右上關閉鈕（Icons `close`，失敗退 `x` 文字；`closable` 預設 true，按下與放開都在鈕上才關閉）。標題列拖曳走 setCapture（同 FloatButton），每幀 clamp 回螢幕；`resizable=true` 時右下角把手縮放，夾在 `minWidth`／`minHeight`（預設 240×160），尺寸有變才呼叫 `onResize`。`close()`＝`setVisible(false)` 後呼叫 `onClose(win)`，不從 UIManager 移除。標題列高＝max(24, 字高＋10)，`contentTop()` 等於它。
- **Window × ISLayoutManager**：`ISLayoutManager.RegisterWindow(name, UI.Window, win)`——存讀回呼取自第二參數、以 `funcs.RestoreLayout(target, name, layout)` 呼叫（`ISLayoutManager.lua:6-13,99-113`），故直接傳 `UI.Window`。存 x／y，`resizable` 時另存寬高；讀回後夾最小值、尺寸有變時呼叫 `onResize`，最後 clamp；不讀寫 `visible`。
- **Dialog**：先加全螢幕 guard（吃掉所有滑鼠事件、半透明黑底）再加置中視窗，兩者都在 `addToUIManager()` 後設原生 alwaysOnTop（加入順序決定視窗在 guard 之上，`UIManager.java:544-556`）。內文依寬度換行（支援 `\n`，斷行規則見 §3.4），高度依行數自動；`input={text?,placeholder?,onlyNumbers?}` 時在內文下放 TextField 並自動 focus。按鈕靠右：confirm（`danger` 則 danger，否則 primary）＋cancel（normal；省略 `cancelText`＝單鈕提示框）。按鈕、關閉鈕、Enter／Esc、`UI.Dialog.close` 全走同一收尾：只回呼一次、移除 guard 與視窗（`removeFromUIManager`）。同時只允許一個，新開先以 cancel 關舊的。
- **Enter／Esc（不 monkeypatch）**：視窗 `setWantKeyEvents(true)`，以 `onKeyPress`／`onKeyRelease`／`isKeyConsumed` 接原生 key 派送（`UIElement.java:2174-2217`，同原版 `ISBuildWindow.lua:16-21,355`）。放開必須配對到同一 dialog 收過的按下，避免「按 Enter 開窗、放開就確認」；關閉後 `isKeyConsumed` 仍回 true，同一個 Esc 不漏給後面的視窗。輸入框有焦點時 key 事件不進 UIManager（`GameKeyboard.java:32-43`），Enter 改由原生 `onCommandEntered`（`UITextBox2.java:841-845`）確認；此時 Esc 由原生輸入框處理、不經 dialog（實機行為待下游聯測確認），輸入框失焦後 Esc 才取消。

**載入與能力**：`Widgets/Controls.lua` 與 `Widgets/Window.lua` 各自檔頭自檢 facade（缺席即 return）；Controls 另需原生 `ISButton`／`ISTextEntryBox`。Window.lua 自行 `pcall(require, "MinidoracatUI/Widgets/Controls")` 與 `pcall(require, "MinidoracatUI/TextWrap")`，任一仍缺時只掛 Window（`window=true`、`dialog=false`），不依賴檔名排序。

**rev 11 擴充**（Economy 元件收編的共用基礎；既有簽章與預設外觀不變）
- **Button `style="chip"`**：`pill` 形狀（`Skin.fits` 不夠大時 fill／border 自己退直角）。未啟用＝只畫 border、字 `textMuted`，hover 補 hover 底並改 `text` 字；啟用（`active`）＝`selected` 底＋`accent` 框與字；按下沿用 selected 疊層、停用字 `textFaint`。`opts.active`／`setActive(b)`／`isActive()` 對任何樣式都可呼叫，但**只有 chip 會畫出 active 狀態**；`setActive` 不回呼、不影響 enable。
- **Button 自動截字＋自動 tooltip**：標題可用寬＝`width - 12`（有 icon 再扣 icon＋間距），放不下就以 `UI.Text.fit` 截成「前綴＋...」；只在標題或寬度變了時重算（每幀只比兩個值）。`self.title` 永遠是全標題。截到字且沒有手動 tooltip 時，以全標題當 tooltip，寬度恢復後自動收掉；`setTooltip(s)` 設的手動 tooltip 永不被覆寫，`setTooltip(nil)` 交回自動判斷。自動寬度的按鈕本來就放得下，行為與 rev 10 相同。
- **TextField 尺寸與清除鈕**：`setWidth`／`setHeight` 覆寫為連內層原生 entry 一起重排（x＝6px 內距、寬＝外框寬減兩側內距、垂直置中；原版 `ISPanel` 只動外框）。`opts.clearButton=true` 開原生輸入框右側的清除鈕（`ISTextEntryBox:setClearButton` → `UITextBox2.setClearButton`），清除走原生文字變更，照樣由每幀比對觸發一次 `onChange`。
- **`theme.alpha` 約定**：theme 上的選用數值欄位（缺省或非數字視為 1），代表 consumer 的面板不透明度。框架元件畫 **chrome**（`Skin.fill`／`border`／`slider` 等底與框）時乘 `theme.alpha`，**文字與 icon 不乘**（淡掉的面板上字仍清楚）。`theme:fill`／`theme:border` 便捷層**不**自動乘——consumer 有刻意不吃不透明度的呼叫（模態遮罩、不透明背板），自己的繪製要跟就自行乘。框架內的刻意例外：Dialog 的全螢幕遮罩、ItemPicker 的不透明背板。套用範圍：rev 7～9 全部控制元件、Window／Dialog 視窗本體，以及 rev 11 五個元件；預設 1 時外觀與 rev 10 相同。

### 3.8 ColorPicker（API rev 8；rev 9 起 R/G/B 為滑桿）

色卡格＋R/G/B 滑桿＋hex 輸入的取色元件，與 rev 7 控制元件同檔（`Widgets/Controls.lua`）、同共通契約（§3.7「共通」段）。

| 建構 | 公開方法 | 回呼 |
|---|---|---|
| `UI.ColorPicker.new{ x, y, width, color?={r,g,b}, swatches?, theme?, font?, target?, onChange? }` | `getColor()`、`setColor(c, silent)`、`setEnabled(b)`、`getHeight()` | `onChange(target, color, picker)` |

- **色值**：`{r,g,b}` 各 0–1，內部量化成 0–255 整數（滑桿與 hex 看到的就是實際值）；`getColor()` 與回呼的 `color` 都是新 table。`color` 省略＝白。`setColor` 相同（量化後）值是 no-op；`silent=true` 不回呼。
- **上半部色卡**：`swatches` 省略＝`UI.ColorPicker.DEFAULT_SWATCHES`（24 色：鮮色／深色／淡色＋黑白灰金銀，每項 `{r,g,b}`）。20px 圓角色塊、依 `width` 自動換行；與目前顏色相同的色塊畫 2px accent 外框（輸入的值剛好等於色卡也會選中），hover 畫 text 色外框。點色卡＝以非 silent 改色。建構時複製色卡，consumer 事後改表不影響已建立的元件。
- **下半部**：三列 `UI.Slider`（左側 `R`／`G`／`B` 標籤；min 0、max 255、step 1、右側顯示整數值；fill 分別為紅／綠／藍通道色），最後一列 `#` hex 欄（最多 7 字，`#` 可省、大小寫皆可）＋右側長方形預覽（寬＝兩倍欄高）。hex 須恰為 6 位十六進位才改色；空白、非法字串不變更顏色、不回呼。
- **同步不重複回呼**：點色卡、拖滑桿、輸入合法 hex 都即時同步其他控制項——滑桿以 `setValue(v, true)`、hex 以 `TextField:setText`（皆不觸發回呼）寫回；正在輸入的 hex 欄不被覆寫。一次實際改色只呼叫一次 `onChange`（拖曳中每次變色各一次）。
- **版面**：高度＝色卡列數 ×20＋列間距 6＋外框預留 4＋區隔 8（無色卡則為 0）＋三列滑桿（各 `max(20, 字高＋4)`＋間距 4）＋hex 欄高（字高＋10）；`getHeight()` 即此值。
- `setEnabled(false)`：色卡不可點、三條滑桿與 hex 欄一併停用、整體淡化。prerender 零配置（色卡、預覽色、標籤位置建構時算好）。

### 3.9 Slider（API rev 9）

可拖曳的數值滑桿，與 rev 7 控制元件同檔（`Widgets/Controls.lua`）、同共通契約（§3.7「共通」段）。首個 consumer：VehicleManager 地圖外觀視窗的圖示大小。

| 建構 | 公開方法 | 回呼 |
|---|---|---|
| `UI.Slider.new{ x, y, width, height?, min, max, step?, value?, theme?, font?, target?, onChange?, format? }` | `getValue()`、`setValue(v, silent)`、`setEnabled(b)`、`isEnabled()` | `onChange(target, value, slider)` |

- **繪製**：`UI.Skin.slider` painter（4px track、比例填色、12px knob）；track 左右內縮半顆 knob，knob 在兩端不出界。colors 取 theme token：track＝`well`（hover 或拖曳中＝`hover`）、fill＝`accent`、knob＝`text`、border＝`border`。高度省略＝max(20, 字高＋4)；`width` 省略＝160。disabled 整體淡化。
- **format**：`function(value) → string`，有給就在 track 右側畫值文字（例如 `"175%"`）；文字寬以 `format(max)` 在建構時量一次，從 track 寬扣掉，prerender 不量測也不呼叫 format（只在值變時格式化一次）。
- **值**：`setValue` 先夾在 `min..max`，再以 `min` 為基準依 `step` 四捨五入；step 除不盡範圍或浮點誤差時最多到 `max`。`step` 省略（或 ≤0）＝`(max-min)/20`；`max < min` 時視為 `max = min`。非數字忽略。量化後相同值 no-op；`silent=true` 不回呼。
- **互動**：按在 track（含兩端半顆 knob）＝跳到該值並開始拖曳，`setCapture(true)` 讓拖出元件外仍收 move／up（原生派送見 `UIElement.java:1077,1240-1242,1300`），放開 `setCapture(false)`；按在值文字區不反應。滾輪往上（`del < 0`，同 `ISScrollingListBox.lua:353`）＋step、往下 −step。`onChange` 只在值實際改變時呼叫（拖曳中每次變化一次）。
- **disabled**：`setEnabled(false)` 後按下與滾輪都不回應（滾輪回 false 讓父層捲動）；拖曳中停用立即解除 capture。

### 3.10 Focus 鍵盤＋手把焦點（API rev 10）

`MinidoracatUI/Focus.lua`，`UI.Focus`（`CAPABILITIES.focus`）。收編自 Economy 的 `ECKeyboard`（原 Economy 17 個頁面使用，行為與出處註解逐項保留），再把手把接到同一份焦點狀態。一個 session 一套引擎；焦點框同時只屬於一個 root。

| 面 | API | 說明 |
|---|---|---|
| 目標描述 | `root:keyboardTargets()` → `{ {kind, control|controls, label, focusable?, copyAll?, frame?, scrollOwner?}, ... }` 或 `nil` | kind＝group／button／entry／combo／list／scroll；`nil`＝此刻不給鍵盤（模態框蓋住）。框架 Window 預設 `Focus.collectTargets(self)`：視窗內可見、帶 `_focusKind` 的元件依閱讀順序（由上而下、上緣差不超過較矮者一半視為同列、同列由左而右）；同一 `_focusGroup` 且連續者併成 group。每個 root 重用同一組陣列與描述 table（`Focus.render` 每幀呼叫，不配置） |
| 鍵盤 hooks | `onKeyPress／onKeyRepeat／onKeyRelease／isKeyConsumed(root, key)`、`onFocus(root)`、`render(root, theme)` | 派送與消耗帳本見 `Focus.lua` 檔頭出處；Tab／Shift+Tab 走描述、方向鍵在組內或清單內、Enter／Space 啟動、Home／End／PgUp／PgDn 捲動、Ctrl+C 複製唯讀文字（框架通知 `IGUI_MinidoracatUI_Copied`／`CopyFailed`）、Esc 先問 `root:onEscape()` 再收焦點框。沒有焦點框時只認 Tab：Enter、Esc、方向鍵照常給遊戲（聊天、暫停選單、角色）。方向鍵按住照作業系統節奏自動重複：引擎在按住的每一幀都派 repeat、沒有延遲（`GameKeyboard.java:61-64`），所以先等 400ms、之後每 60ms 動一步，點一下只走一格 |
| 手把 hooks | `onJoypadDown(root, button, data)`、`onJoypadDir(root, "up"|"down"|"left"|"right", data)` | A＝Enter（先問控制項 `onFocusKey(KEY_RETURN)`，順序同鍵盤；輸入框改開原版螢幕鍵盤）、B＝`onEscape`→收下拉→`root:close()`、LB／RB＝`root:onFocusShoulder(delta)`；方向先交控制項 `onFocusKey`／清單上下／組內左右，沒處理（含清單到邊）就移到上／下一個目標 |
| 手把焦點 | `takeJoypad(root, playerNum)`、`releaseJoypad(root)`、`holdsJoypad(root)` | 開窗時玩家在用手把（`getJoypadData` 非 nil）才接手，記住原焦點；關窗只在仍持有時還原，原焦點已不在畫面上（原生 `isReallyVisible`，含祖先與 UIManager）就還給角色；螢幕鍵盤借著焦點時 root 被關，鍵盤改還給同一個對象、放掉它的輸入框並一起關掉（`ISTextEntryBox.lua:304-309`、`ISOnScreenKeyboard.lua:452-468`），prevfocus 鏈同 `setPrevFocusForPlayer` 還原（家族踩坑錄「手把焦點不是單一指標」）。沒有 `keyboardTargets` 的元件（popup）只借走手把焦點，不動焦點框 |
| 公開工具 | `eat／consumed／release`、`pressed(key)／repeatDue(key)`、`modifiers()`、`step`、`focusControl(control, showRing)`、`refocus`、`focused`、`isKeyboardFocused`、`invalidate(root)`、`blurInputs`、`clear`、`close`、`drawRing(el, x, y, w, h, theme)`、`drawCaption(...)`、`collectTargets(root)` | 名稱與語意同原 `ECKeyboard`；`pressed`／`repeatDue` 給自己接 `onKeyRepeat` 的元件（root 開的 popup）用同一套自動重複節奏；`render`／`drawRing` 的 theme 缺省取 `root.theme`，再缺用框架預設 |

**控制元件接點**：Button／Checkbox／Tabs／Slider 的 `_focusKind="button"`、TextField 的 `_focusKind="entry"`（聚焦內層原生 entry，框畫在外框）、VirtualList 的 `_focusKind="list"`；`Checkbox:forceClick()`、`Tabs:selectRelative(delta)`／`onFocusKey`（左右換頁，不循環）、`Slider:onFocusKey`（左右 ±step、Home／End）、`VirtualList` 新 opts `onHighlight(list, item, index)`（方向鍵移動反白；`onSelect` 仍只給點擊、Enter、A）與 `onKey(list, key, item, index)`（先拿到焦點框上的按鍵，例如樹狀清單展開）。consumer 自繪元件標 `_focusKind`（＋`forceClick`、選用 `_focusGroup`／`_focusLabel`）即可加入自動目標。

**輸入框交接的漏鍵**：輸入框的 Tab／Enter 由引擎在幀尾交給 `onOtherKey`／`onCommandEntered`（`GameWindow.java:702-709`、`Core.java:2044-2053`），`GameKeyboard` 下一幀才以取樣狀態派同一次按住（`GameWindow.java:310`）。輸入框在回呼裡放開鍵盤後，那次按住就變成新的 press 到 root：Tab 多走一格、Enter 把剛放手的輸入框又聚焦回去，視窗已關時（Dialog 輸入框按 Enter 確認）漏給後面的視窗與遊戲。勾子在放手後對仍按著的鍵呼叫 `GameKeyboard.eatKeyPress`（同引擎對 Escape 的 `Core.java:2049-2050` 與原版 `MapSpawnSelect.lua:950`），press 與 release 一起吞；引擎沒取樣到的極短點按不吞，否則記號沒有 release 可清，會改吞玩家的下一次按鍵。

**目標驗證**：每次按鍵與每幀 render 都核對焦點下的控制項仍在 `keyboardTargets()` 裡而且可用；不在（疊層、權限、頁面切換把它排除，即使它還看得見）就用 `invalidate` 搬到同位置的替補，那一次的 Enter／Space／手把 A 只讓玩家看到新位置，不按替補的控制項。

**焦點框回到觸發者**：另一個 root 接手（`onFocus`／`takeJoypad`）前記住目前 root 的焦點框；回到這個 root 後的第一次 Tab 或手把輸入先回到那個控制項，不從第一個目標重走（詳情、確認框、外觀視窗關掉後接著操作）。root 隱藏、失去鍵盤或 `clear` 時忘記；控制項已不在畫面上就照常從頭走。

**可見判定**：目標要自己可見、仍掛在父元件上、父元件也一樣（同 `UIElement.java:1798-1805`），但不要求頂層已在 UIManager 清單——`addToUIManager` 只排進 `toAdd`，下一次 `UIManager.update` 才加入（`UIManager.java:111-116,501-505`），開窗同一段程式裡原生 `isReallyVisible()` 對整個新視窗都答 false，手把接手與 Dialog 預設「確認」會落空。原生答 true 直接用（每幀路徑），答 false 才沿 Lua 父鏈重判。

**Window／Dialog 接線**：Window 是 root（class 方法轉發全部 hooks、`render` 最後畫焦點框、`setWantKeyEvents(true)`），`setVisible`／`addToUIManager` 顯示時 `onFocus`＋`takeJoypad(win, 0)`、隱藏時 `releaseJoypad`＋`clear`；LB／RB 切換視窗內第一個分頁列。Dialog 的 Enter／Esc 配對邏輯不變，焦點框在其他按鈕上時 Enter 按那一顆；手把玩家開啟時焦點預設在「確認」。Focus 缺席（舊框架或載入失敗）時 Window／Dialog 照常，只是沒有鍵盤導覽與手把。

**非目標**：不攔截沒有焦點框時的遊戲按鍵；不做全域熱鍵；按鍵消耗只擋 UI／Lua key 事件，不擋以按住狀態判斷的角色移動（`GameKeyboard.java:96-134`），所以導覽鍵選方向鍵與 Tab，不佔 WASD。

### 3.11 DatePicker 日期欄與月曆（API rev 11）

`Widgets/DatePicker.lua`，`CAPABILITIES.datePicker`。收編自 Economy 的 `ECDatePicker`＋`EC.parseDay`／`daysInMonth`／`utcDate`＋`U.localOffsetMinutes`。需要 Controls（DateField 由 TextField＋Button 組成），Focus 選用：缺席時月曆只能用滑鼠。

| 面 | API | 說明 |
|---|---|---|
| 曆法 | `UI.Date.daysInMonth(y, m)`、`parse(text) → y, m, d`｜`nil`、`format(y, m, d) → "YYYY-MM-DD"`、`dayStart(text, offsetMin) → ms`｜`nil`、`fromMs(ms, offsetMin) → y, m, d`、`localOffsetMinutes() → 分鐘` | 純函式。`parse` 接受 `YYYY-MM-DD` 或 `YYYY/M/D`（前後空白可），年 1..9999、月日要合法，否則 `nil`。`dayStart`＝「比 UTC 快 `offsetMin` 分鐘的時鐘上，該日 00:00」對應的 UTC 毫秒 |
| 日期欄 | `UI.DateField.new{ x?, y?, width?, height?, text?, placeholder?, theme?, font?, target?, onChange? }` | `getText()`、`setText(s)`（靜默）、`getDate() → y, m, d`、`dayStart(offsetMin?)`（省略＝本地時差）、`setWidth`／`setHeight`（重排內部）、`setEnabled(b)`／`isEnabled()`、`focus()`、`blur()`、`appendTargets(out, label) → out` |
| 回呼 | `onChange(target, text, field)` | 文字**實際改變**時一次：打字（TextField 每幀比對，涵蓋 IME）、月曆選日／今天／清除、失焦正規化 |
| 月曆 | `UI.DatePicker.close(scope?)` | `scope` 省略＝關掉開著的；否則只在月曆所屬欄位是 `scope` 本身或其子孫（沿 `parent` 最多 32 層）時才關 |

**行為契約**
- **曆法不用 `os.time`／`os.date`**：Kahlua 的 `os.date` 固定 UTC、標準 Lua 是當地時間，兩邊算出來會不同（家族 pitfalls.md）。改用 Hinnant days-from-civil；Kahlua 的 `%` 對負數往零截斷，1970 年前的星期一律用 floor 除法。`localOffsetMinutes` 以原生 `getHourMinute()`（JVM 當地時間 `"H:MM"`，`LuaManager.java:8993-8998`）減 UTC 時分，夾進 −12h..+14h、取 15 分鐘倍數吸收秒差，取不到回 0。
- **DateField**：ISPanel＝`UI.TextField`（左）＋4px 間距＋正方形 chip 日曆按鈕（右，向量畫日曆圖樣，不用貼圖）。高度省略＝字高＋10；寬度省略＝容得下 `0000-00-00` 與 placeholder 的輸入框＋間距＋按鈕；placeholder 省略＝`IGUI_MinidoracatUI_Date_Hint`。**文字框是唯一的真相**：月曆只把選到的日寫回文字框。原生 `setText` 不通知（`ISTextEntryBox.lua:109-115` → `UITextBox2.java:780-802`），所以月曆寫回後由本元件自己回呼。失焦時合法日期正規化（`2026/9/7` → `2026-09-07`），不合法的文字原樣保留（玩家可能還在打字）。`setEnabled(false)` 一併關掉自己的月曆；`blur()` 取消輸入焦點（觸發正規化）並關掉自己的月曆。
- **月曆 popup**：整個 session 共用一個，第一次開啟才建立；按日曆鈕開啟、同一顆再按關閉，開另一個欄位先關舊的。開啟前先讓欄位失焦正規化，月曆開在欄位的日期（空白或不合法＝今天所在月）。6×7 日格是畫出來的（不是子元件），週日開頭；上方 `<<` `<` `>` `>>` 為 ±1 年／±1 月 chip（tooltip 說明用途，超出 1..9999 年的方向停用），下方「今天／清除／關閉」chip。已選日＝selected 底＋accent 框；今天＝accent 字＋底線；游標＝accent 框；chrome 乘開啟它的欄位的 `theme.alpha`。
- **popup 模式**（同原版 `ISComboBox.lua:185-215,123-157,37-42,159-179`）：建立時 `setCapture(true)` 常駐（capture 中的元素先被問，`UIManager.java:472-492,661-704`），`addToUIManager` 之後才設原生 alwaysOnTop（`ISUIElement.lua:1319-1322` 只作用於已實例化的元件）；錨在欄位下方，放不下翻到上方再夾回螢幕，每幀重新定位（視窗拖曳跟著走）；在 popup 外按下即關閉，按在自己的日曆鈕上交給按鈕切換。錨點失效自動關閉：輸入框不在畫面上、祖先收合、欄位停用、日曆鈕隱藏或停用。選日／今天／清除都**先關再寫**，欄位的 `onChange` 若重排頁面，看到的是已關閉的月曆。

**焦點／手把接線**
- 框架 Window 內：DateField 的輸入框（`_focusKind="entry"`）與日曆鈕（`_focusKind="button"`，說明 `IGUI_MinidoracatUI_Date_Open`）由 `Focus.collectTargets` 自動收進目標。原生 root 用 `field:appendTargets(out, label)` 寫入兩個建構時快取的描述（輸入框、日曆鈕），不配置。
- popup 是自己的 top-level（只在 Focus 存在時 `setWantKeyEvents(true)`；key 派送倒序走 UI 清單，popup 先於視窗被問，`UIManager.java:1435-1466`）：Tab／Shift+Tab 在「日格＋可用 chip」間循環；方向鍵在日格上移動游標（±1／±7，可跨月），焦點在 chip 時左右換 chip、上下回日格；Enter／小鍵盤 Enter／Space 寫入游標日或按下 chip（`forceClick`）；Esc 關閉；PgUp／PgDn 換月；Home＝今天；Delete＝清除。只有方向鍵與 PgUp／PgDn 會連發（`Focus.repeatDue` 節奏）；按下由 `Focus` 帳本消耗，關閉後的 release 由視窗回答。
- 手把：A＝Enter、B＝Esc、LB／RB＝Shift+Tab／Tab、十字鍵＝方向鍵。欄位所在 root 正持有手把焦點（`Focus.holdsJoypad`）時 popup `takeJoypad` 借走，關閉時 `releaseJoypad` 歸還；`onJoypadBeforeDeactivate` 關閉。從鍵盤焦點開啟的月曆，關閉時焦點框回到日曆鈕。

**使用端契約**：只拿文字與回呼——需要時間界線時用 `field:dayStart()`（本機 00:00）或 `UI.Date.dayStart(text, offset)`；頁面／視窗隱藏或切頁時呼叫 `UI.DatePicker.close(頁面或視窗)`（錨點失效也會自動關，但主動關可避免殘留一幀）；伺服器端計算不要依賴本模組（Economy 伺服器仍用自己的 UTC 函式）。

**不做的事**：不選時分；不做區間月曆（起訖由兩個 DateField 組成，見 §3.13）；日期文字固定 ISO `YYYY-MM-DD`，不做在地化格式；不新增日曆 icon 資產；沒有 Focus 時不提供鍵盤操作。

### 3.12 Table 表格外殼與表頭（API rev 11）

`Widgets/Table.lua`，`CAPABILITIES.table`。收編自 Economy `ECWidgets`（`U.newTable`／`U.rowBackground`／`TableCell`）與 `ECPanelWidgets`（`listingColumns`／`MarketHeader`）。需要 VirtualList、`UI.Text`、`Skin.arrow`。

| 面 | API | 說明 |
|---|---|---|
| 表格 | `UI.Table.new{ x?, y?, width?, height?, rowHeight, cell?=UI.Table.TextCell, padding?=0, theme?, colors?, onSelect?, onHighlight?, onKey? }` → **已 `initialise()` 的 `UI.VirtualList`** | 內建 createCell／bindCell／unbindCell；`list.cols＝{}`（欄位幾何由使用端寫入）、`list.theme`；`colors` 省略＝捲軸 `{ thumb=textFaint, thumbHover=textMuted, track=selected }`；三個回呼原樣交給 VirtualList（§3.5、§3.10） |
| cell 勾子 | `cell:onBind()`、`cell:onUnbind()`（選用） | cell 是 `cell` class 的 ISPanel 實例（`background=false`），綁定時已設好 `cell.entry`／`cell.index`／`cell.list`／`cell.theme`；解綁後 `entry` 清成 nil |
| 列底 | `UI.Table.rowBackground(cell) → lit` | 偶數列斑馬紋（hover×2/3）、選取（selected）、滑鼠懸停（hover）；回傳 `lit`（選取或懸停）讓使用端提亮淡字 |
| 純文字列 | `UI.Table.TextCell`：entry＝`{ cells = {string...}, tokens = {token...}?, muted = bool? }`；`list.cols[i]＝{ x, right?, width? }` | `x` 相對 cell；`right=true` 時 `x` 是右緣；`width` 給了才截字。衍生 cell 可直接呼叫 `UI.Table.TextCell.render(self)` |
| 欄寬 | `UI.Table.layoutColumns(specs, leftX, rightX, nameMin, pad?=12) → specs` | 輸入 `key`、`title`、`sample?`、`sampleW?`（優先於 sample）、`right?`、`sortable?`（預設 true）、`soft?`、`extra?`、`wrapW?`；輸出 `x`、`w`（表頭命中區）、`textR`、`textW`（值的位置，已扣排序箭頭預留）、`wrapped` |
| 表頭 | `UI.TableHeader.new{ x?, y?, width?, height?=字高+10, theme?, font?, target?, sort?, live?, onSort? }` | `setColumns(specs)`（通常就是 layoutColumns 的輸出）、`isLive()`；`sort(target) → key, desc` 每幀拉取、`live(target) → bool`、`onSort(target, key｜nil, header)` |

**行為契約**
- **TextCell**：字型固定 `UIFont.Small`；每欄 token 取 `tokens[i]`（theme token 名，缺省 `text`），`muted` 整列改 `textFaint` 並從第一欄畫刪除線；`lit` 時 `textFaint`／`textMuted` 提亮成 `text`。截字結果快取在 cell，快取鍵是每欄實際的 `width`／`right`（外加 `list.cols` 身分與欄數）：綁定、換一張 `list.cols`、或原地改了任一欄的 `width`／`right` 都在下一幀重算；沒變時每幀只做數值比較，render 零配置。
- **layoutColumns**：`specs[1]` 是彈性欄（通常是名稱），其他欄依 `max(標題寬, sample 寬)`＋`pad`＋`extra`＋排序箭頭預留量寬；可排序欄一律在右緣預留箭頭位（排序切到它時數字不橫跳）。總寬**絕不超出** `leftX..rightX`；名稱欄不夠時依序讓出：有 sample 的非靠右欄縮到「...」→ 拿掉 `extra` → 有 `wrapW` 的欄縮到換行寬（`wrapped=true`）→ `soft` 欄只剩標題 → 仍不夠就全部按比例縮。只在版面變動時呼叫（內部用 closure，不是每幀路徑）。
- **TableHeader**：well 底（乘 `theme.alpha`）；標題依欄寬截字，靠右欄右對齊到 `textR`；目前排序欄 accent 色＋`Skin.arrow`（升冪 ▲）；`sortable=false` 的欄永遠不亮、不預留箭頭位；`live` 回 false 時標題淡化且點擊不回呼。每欄的截字標題與位置快取在表頭，鍵是該欄的 `title`／`x`／`w`／`textR`／`right`／`sortable`——使用端原地改 specs（不論有沒有再呼叫 `setColumns`）下一幀就比對出來重算，幾何沒變時每幀不呼叫 `Text.fit`。點在可排序欄上回該欄 `key`，欄外或不可排序欄回 `nil`（由使用端決定預設排序或方向）；方向與資料排序由使用端處理。
- chrome（列底、表頭底）乘 `theme.alpha`；文字、刪除線與箭頭不乘。

**焦點／手把接線**：表格本身就是 VirtualList，`_focusKind="list"` 與 `onHighlight`／`onKey`／`onSelect` 照 §3.10；框架 Window 自動收進目標。表頭不是焦點目標（排序只給滑鼠），要鍵盤排序的頁面用 FilterBar 的排序 chip（§3.13）。

**使用端契約**：業務欄位的 cell（衍生 ISPanel 或 TextCell）與列字串產生器留在 consumer；cell 的額外狀態在 `onBind` 重設、在 `onUnbind` 清掉（同 §3.5 的解除綁定時機）；表頭與表格共用同一組 `layoutColumns` 輸出（可原地重算），resize 時重跑 `layoutColumns` 並把值欄位置寫進 `list.cols`。

**不做的事**：不做欄寬拖曳、多欄排序、表頭鍵盤排序、變動列高或 grid（沿 VirtualList 限制）；不在表格內排序或過濾資料（交給 FilterBar 的 `apply` 或 consumer）。

### 3.13 FilterBar 篩選列（API rev 11）

`Widgets/FilterBar.lua`，`CAPABILITIES.filterBar`。合併移植自 Economy 的 `ECAdminFilters`（單選、extra、inline 分頁、`addControl`）與 `ECPanelFilters`（多選、關鍵字、類型翻頁、strip 分頁、精簡切換），`apply` 移植 `EC.filterPage`／`EC.sortSafe`。需要 Controls 與 DatePicker，Focus 選用。

**bar 本身不是元素**：`FilterBar.new` 回傳狀態物件，所有控制項在建構時 `addChild` 到 `opts.parent`，座標是 parent 的元素座標；標籤、排序箭頭、分頁文字由使用端在 parent 的 `render` 裡呼叫 `bar:draw(el)`／`bar:drawPager(el)` 畫出。

```lua
local bar = UI.FilterBar.new{
    parent,                 -- 必填
    theme?, font?, height?, -- height 省略＝字高＋10（每一列控制項的高度）
    target?,                -- 省略＝parent
    onChange?,              -- function(target, bar)：使用者改了類型／日期／關鍵字／排序／頁碼
    onLayout?,              -- function(target, bar)：類型翻頁、精簡切換改變了幾何，使用端要重排
    kinds? = { field?, label?(id) -> string, multi?, title?（false＝不畫標題）, extra? = { {id, label?}, ... } },
    search? = { field?="searchText", placeholder? },
    dates? = { field?, fromLabel?, toLabel? },
    sorts? = { {id, label?, field?（欄名或 function(row) -> 值）}, ... },
    perPage? = 25,
    pager? = "strip" | "inline",   -- 預設 strip
}
```

| 分類 | 方法 |
|---|---|
| 類型 | `setKinds(ids) → changed`、`syncKinds(rows) → changed`、`getKind()`（單選；nil＝全部）、`isKindSelected(id)`（id＝nil 問「全部」）、`setKind(id, silent)` |
| 其他狀態 | `getQuery()`（已 trim 並轉小寫，空白＝nil）、`getDateText() → from, to`、`setDateText(from, to, silent)`、`dateRange() → fromMs, toMs`、`getSort() → id, desc`、`setSort(id, desc, silent)`、`setPage(page, pages?, total?)`、`reset(silent)`；欄位 `page`／`pages`／`total`／`perPage`／`filtersOpen` 可讀 |
| 過濾 | `apply(rows) → pageRows` |
| 版面 | `layout(x, y, right, visible) → bottom`、`layoutViewport(x, y, right, bottom, visible, toggleY?, minListH?) → listY, listH, showingRecords`、`layoutPager(x, y, right, visible, height?)` |
| 繪製（per-frame 零配置） | `draw(el)`、`drawPager(el, hideCount?)` |
| 啟用／焦點 | `setEnabled(on)`、`addControl(control, label, focusKind)`、`blur()`、`isShown()`、`appendTargets(out) → out`、`appendPagerTargets(out) → out` |

**行為契約**
- **回呼**：每個使用者動作呼叫一次 `onChange`；除了翻頁，都先把頁碼設回 1。帶 `silent` 的 setter 在 silent 時不回呼；改篩選條件的 setter 一律把頁碼設回 1。`apply` 不回呼。
- **類型 chip**（`UI.Button{style="chip"}`，以 `setActive` 表示選取）：「全部」固定第一顆、`setKinds` 的 id 依使用端給的順序、`extra` 排最後；標題＝`label(id)` 或 `tostring(id)`。`setKinds` 集合沒變回 false；已選但被移除的類型直接丟掉，有丟就靜默設回第 1 頁。`syncKinds(rows)` 從 `rows[kinds.field]` 依首次出現順序收集（nil 與空字串略過）。chip 物件池只增不減，多的隱藏停放、不 `removeChild`。單選：點選即換；多選：各顆切換，「全部」清空；`setKind` 在多選時是「清空後只選這一顆」。一列放不下時改用 `<` `>` 翻頁（`chevronLeft`／`chevronRight` icon），類型佔到該列結尾，多選時標題旁顯示已選數。
- **extra**：可選取的額外 chip（例如「我的」），狀態由使用端解讀——`apply` 的類型過濾**不含** extra（只選 extra 等於不過濾類型）。
- **關鍵字**：`UI.TextField`（寬度依列寬 32% 夾在 140..280），每幀比對文字、trim 後沒變不算改動。`apply` 以純字串比對 `row[search.field]`（不轉換大小寫）找已轉小寫的查詢——**使用端準備的搜尋欄要先轉小寫**。
- **起訖日期**：兩個 `UI.DateField`；`dateRange()`＝本機時區的 [起日 00:00, 迄日隔天 00:00)，格式不對的那一端不算界線；`apply` 以 `tonumber(row[dates.field])`（毫秒）比對。
- **排序 chip**：點作用中那顆翻轉方向，點新的一顆從 desc（最新／最大在前）開始；箭頭由 `draw(el)` 畫在作用中 chip 內。`reset` 回第一個排序、desc。
- **apply**：關鍵字 → 類型（不含 extra）→ 日期 → 排序 → 分頁；排序為穩定插入排序（nil 排最後、型別不同轉字串比、字串一律轉小寫、相等不交換），頁碼夾到 1..pages，更新 `page`／`pages`／`total` 並回傳該頁的新 table。對象是已載入的數百列回覆；上萬列請改走伺服器分頁。
- **伺服器端篩選**：`kinds.field`／`dates.field`／`sorts[i].field` 留 nil，`apply` 就不依它過濾或排序；使用端在 `onChange` 讀狀態送出，回覆後以 `setPage(page, pages, total)` 寫回。
- **版面**：`layout` 是單一換行流——關鍵字（最先：打字時標籤仍可見）、類型、起訖日期、排序、`addControl` 的控制項、inline 分頁；`visible=false` 隱藏全部並 `blur`。`layoutViewport` 是精簡切換：篩選列會把清單擠到比 `minListH` 還矮時，篩選列與清單改成二選一，由放在 `toggleY` 的切換 chip（「篩選條件」／「返回結果」）切換，回傳清單位置與是否顯示紀錄；strip 分頁放在 `bottom` 上方一列。`layoutPager` 單獨擺 strip 分頁（頁碼文字在左、兩顆翻頁鈕接在最寬頁碼之後、筆數靠右）；inline 分頁以最寬的頁碼字樣預留寬度，換頁不重排。
- **addControl(control, label, focusKind)**：使用端自己的控制項（例如帳號 `ISComboBox`）排在排序後面、由 bar 畫標籤並跟著可見性；使用端自己 `addChild` 到 parent 並管啟用與寬度。`focusKind` 為 Focus 描述的 kind；`"entry"` 且控制項有 `_entry`（框架 TextField）時自動改指內層 entry。
- **setEnabled(on)**：權限或模態閘門——停用自己所有控制項；分頁鈕另依頁碼、類型翻頁鈕另依目前位置。`blur()` 取消關鍵字與日期的輸入焦點，並 `UI.DatePicker.close(parent)`。

**焦點／手把接線**：chip 帶 `_focusGroup`（類型、排序、分頁各一個 token）與 `_focusLabel`，框架 Window 的 `Focus.collectTargets` 會把連續同組 chip 併成一個 group（方向鍵在組內移動）；關鍵字與日期輸入框帶 `_focusLabel`（「搜尋」「從」「到」）。原生 root 用 `appendTargets(out)`（順序：精簡切換鈕、關鍵字、類型 group、起訖日期、排序 group、addControl、inline 分頁 group）與 `appendPagerTargets(out)`（strip 分頁 group），描述 table 都在建構／layout 時快取。類型翻頁、精簡切換等改變幾何時自動 `Focus.invalidate(root)`。

**使用端契約**：`onChange` 內重建清單（本機資料 `bar:apply(rows)`；伺服器資料送指令），`onLayout` 內重排 parent；parent 的 `render` 呼叫 `draw`／`drawPager`；類型標籤文字、排序語意、帳號選單等業務留在 consumer。

**不做的事**：bar 不是元素（沒有自己的底或裁切）；不擁有傳輸與狀態持久化；不提供下拉選單元件（`addControl` 接使用端的）；不做多鍵排序；關鍵字只比一個欄位的子字串，不做模糊比對。

### 3.14 ItemPicker 物品挑選疊層（API rev 11）

`Widgets/ItemPicker.lua`，`CAPABILITIES.itemPicker`。收編 Economy `ECItemPicker` 的通用部分；英文名索引、上架政策、索引載入提示留在 consumer，以 `items`／`filter`／`revision`／`note` 注入。需要 Controls 與 Table，Focus 選用。

| 面 | API | 說明 |
|---|---|---|
| 物品宇宙 | `UI.ItemPicker.universe() → { items = { record, ... }, byType = { [fullType] = record } }` | 本 session 載入的全部物品 script（原版與 MOD），record＝`{ fullType, name, category, script, search }`；整個 session 共用，**consumer 唯讀** |
| 疊層 | `UI.ItemPicker.new{ x?, y?, width?, height?, theme?, font?, title?, placeholder?, items?, filter?, revision?, note?, maxResults?=200, target?, onPick, onCancel? }` → picker（已 `initialise()` 的 ISPanel，建立時隱藏、尚未 addChild） | `items()`→array（預設 `universe().items`；record 至少要有 `fullType`／`name`／`category`／`search`，選用 `original`＝右側淡字、`script`＝圖示來源）；`filter(rec)`→bool；`revision()`→any（開著時值變了就重搜）；`note()`→string｜nil（提示列前綴） |
| 方法 | `open()`、`close()`、`isOpen()`、`cancel()`、`resize(w, h)`、`keyboardTargets()`、`dispose()` | |
| 回呼 | `onPick(target, rec, picker)`、`onCancel(target, picker)` | 疊層**先關再回呼**，只一次 |

**行為契約**
- **宇宙**：`getScriptManager():getAllItems()` 逐筆 pcall 讀取，跳過 `isHidden()`／`getObsolete()`；`name`＝`getItemNameFromFullType`（失敗退 fullType）、`category`＝`getDisplayCategory()`（空白退 `"Item"`）、`search`＝`lower(name .. " " .. fullType)`。不排序（數千筆，排序交給 consumer）。**空結果不快取**：script manager 還沒準備好時不讓 session 永遠拿到空宇宙。
- **搜尋**：打字只重設計時器，停頓 120ms 才掃一次；查詢 trim＋小寫後對 `rec.search` 做純字串子字串比對，再套 `filter`。最多列出 `maxResults` 筆，提示列顯示「共 N 項」／「顯示前 N 項，共 M 項符合…」／「沒有符合的物品」，前面接 `note()`。`revision()` 的值變了（例如 consumer 的索引剛載好）同一查詢重問一次。
- **結果列**（`UI.Table`，兩行高）：物品圖示（`getNormalTexture()`；record 沒帶 script 時 `FindItem`；取不到或繪製失敗記 `false`，session 內不再重試）、名稱、`original`（與名稱不同時畫在右側淡字）、第二行 `fullType / 類別`（類別以原版 `IGUI_ItemCat_<cat>` 翻譯，查無原字）；截字與幾何在綁定時算好，render 只畫。
- **疊層**：背板**不透明、不乘 `theme.alpha`**（只對著自己讀，不透出底下的列），內卡片與框乘 alpha；背板吃掉所有傳到它的滑鼠事件（子元件先問，搜尋框與清單照常）。`open()` 清空搜尋並把鍵盤焦點放到搜尋框；`close()` 取消輸入焦點；點列、Enter、手把 A 都走 `choose`：已關閉時不回呼，同一次點擊或 Enter 的第二個來源不會選兩次。「取消」chip＝`cancel()`。`dispose()` 關閉並放掉回呼與列。

**焦點／手把接線**：`keyboardTargets()` 開著時回快取的 `{ 搜尋框 entry, 結果 list, 取消鈕 }`，關著回空陣列；`open`／`close` 都 `Focus.invalidate(root)`。放在框架 Window 裡時，consumer 覆寫 `win.keyboardTargets`：`picker:isOpen()` 時回 `picker:keyboardTargets()`，否則回 `Focus.collectTargets(win)`——疊層開著時頁面的控制項不該被 Tab 到。

**使用端契約**：picker 在頁面所有內容之後才 `addChild`（畫在最上層），並在頁面 resize 時 `picker:resize(w, h)` 成整頁大小；自己的 record 需要英文名或政策欄位時，用 `universe()` 的 record 建出自己的陣列交給 `items`（不要改寫共用 record）。

**不做的事**：不做英文名索引、上架／交易政策、排序、多選或數量輸入；不自成視窗（是頁面內的疊層）；不快取搜尋結果以外的狀態。

### 3.15 Autocomplete 非同步候選輸入框（API rev 11）

`Widgets/Autocomplete.lua`，`CAPABILITIES.autocomplete`。移植自 Economy `ECPlayerPicker` 的通用部分：一個 `UI.TextField` 加上從它下方展開的候選清單。**本元件不擁有傳輸**：查詢經 `onQuery` 交給 consumer 送出，結果由 consumer 以 `setResults` 交回；指令名稱、requestId、context 比對都留在 consumer。需要 Controls，Focus 選用（缺席時下拉只能用滑鼠）。

```lua
local ac = UI.Autocomplete.new{ x?, y?, width?, theme?, font?, placeholder?, maxLength?=64,
    clearButton?=true, debounceMs?=250, rows?=8, minListWidth?=260, target?,
    onQuery,   -- 必填 function(target, text, ac) -> bool；false＝現在送不出，下一幀再試
    labelOf?,  -- function(row) -> string；預設 tostring(row.label or row.name)
    tagOf?,    -- function(row) -> string|nil；右側 accent 標籤（空間不夠時不畫）
    onPick,    -- 必填 function(target, row, ac)：寫入文字、blur、close 之後才回呼（只一次）
    onEnter?,  -- function(target, text, ac)：輸入框內按 Enter
}
```

| 方法 | 說明 |
|---|---|
| `ac.field`／`ac.list` | 輸入框（`UI.TextField` 子類，prerender 順便跑 debounce／查詢／下拉幾何）；繪製型下拉（`_focusKind="list"`，帶 Focus「list」描述讀的 `items`／`rowHeight`／`padding`／`height`／`getSelectedIndex`／`setSelectedIndex`／`onSelect`） |
| `addTo(parent)` | 輸入框先加、下拉後加：要在所有需要被它蓋住的兄弟之後呼叫 |
| `setText(s)`／`getText()` | `setText` 靜默（不回呼）並清掉已送出的查詢；文字真的變了就丟掉舊候選，輸入框聚焦中時為新文字排 debounce（沒聚焦時不排，下次聚焦沒有候選會立刻查）。`getText` 去頭尾空白；送給 `onQuery` 的也是去空白後的文字 |
| `setVisible(b)`／`setEnabled(b)` | 隱藏或停用都收起下拉 |
| `layout(x, y, w, maxH)`／`anchorList(maxH?)` | 擺輸入框再掛下拉到正下方；下拉寬＝max(`minListWidth`, 輸入框寬)，高度不超過 `maxH`（省略沿用上次；從未指定時只受 `rows` 限制） |
| `setResults(text, rows, total?, truncated?) → bool` | `text` 不是最後送出且仍是目前輸入的查詢時丟棄（回 false），等下一次查詢 |
| `queryFailed(retry)` | 逾時 `retry=true`（聚焦或下拉開著時重新計時）；被拒 `false`（只清掉已送出的查詢） |
| `isOpen()`、`close()`、`blur()`、`dispose()`、`appendTargets(out, fieldLabel, listLabel) → out` | `close` 收起並忘掉結果（下次聚焦重查）；`appendTargets` 給原生 root，描述 table 重用 |

**行為契約**
- **查詢時機**：每次文字變化只重設 debounce 計時器，停頓 `debounceMs` 後由 prerender 送出，快速打字最多每 `debounceMs` 一次；第一次聚焦（還沒有結果時）立刻查目前文字（通常是空字串）。送出前先記下查詢再呼叫 `onQuery`，consumer 在 `onQuery` 裡同步 `setResults` 也對得上。停用的輸入框即使被點到聚焦也不開啟、不查詢。
- **下拉可見**＝有列可畫、開啟中、元件可見，且（輸入框聚焦、滑鼠在下拉上、或 `Focus.isKeyboardFocused(list)`）。列數＝min(`rows`, maxH 容得下的列數)；結果比可顯示多（或 `total` 較大）時最後一列讓給提示「還有 N 個…」，`truncated=true` 時改成「候選尚未查完…」——只剩一列時留給第一筆候選、不顯示提示（否則沒有任何一筆可選）；非空查詢零結果時顯示「沒有符合的結果」。
- **選取**：點列、Focus 的 Enter／手把 A（`onSelect`）走同一個 pick：輸入框寫入 `labelOf(row)`、blur、close，再呼叫一次 `onPick`。`close()`（pick、Esc、換頁、失去權限）讓候選失效。
- 標籤在 `setResults` 時取好，依下拉寬度截字快取（寬度或結果變了才重算）；`tagOf` 的標籤在剩餘空間至少三個字高時才畫。每幀只做數值運算與繪製，不配置 table／closure。chrome 乘 `theme.alpha`，文字不乘。

**焦點／手把接線**：框架 Window 內輸入框（entry）與下拉（list，只在可見時）由自動目標收進；原生 root 用 `appendTargets(out, fieldLabel, listLabel)`。方向鍵在下拉內移動反白，Enter／A 選取；焦點框停在下拉上時下拉維持可見。

**使用端契約**：`onQuery` 自己送指令並回 true（送不出回 false）；回覆時比對自己的 requestId／context 後呼叫 `setResults(送出時的 text, rows, total, truncated)`；逾時或被拒呼叫 `queryFailed`；頁面切換或失去權限時 `close()`／`setEnabled(false)`。

**不做的事**：不做傳輸、requestId、結果快取或本機過濾；不驗證自由輸入的文字（只有 pick 才回呼 `onPick`）；不做多選。

## 4. NeatUI 教訓總表（設計依據，證據見 AGENTS.md 與三方報告）

| # | NeatUI 事實 | 本框架對應決策 |
|---|---|---|
| 1 | 6 個裸全域、零版本化 | 唯一全域＋`API_MAJOR/REVISION/CAPABILITIES` |
| 2 | `_NUI_hasNinePatchTextures` 死碼，缺圖直接 crash | 所有繪製 fail-soft＋直角退回紅線 |
| 3 | scrollbar 壞貼圖 `nil:render()` 永久 crash；versionMin 42.0.2 與 B42.9 才有的 NinePatch 矛盾 | versionMin 只寫**查證過**的下限（42.20.1：API 存在性與首呼叫語意已對 42.20.1-20260805 快照逐項核對，見 AGENTS.md API 表）；能力探測不假裝相容 |
| 4 | 手拼 9-slice（B42.9 前遺產） | 一律引擎原生 NinePatchTexture |
| 5 | monkeypatch `ISUIElement` | 禁止；墊片走自有 util |
| 6 | 「別直接用」的成員公開在 API | 公開面全部可依賴；測試鉤子 `_resetForTests` |
| 7 | 隱藏載入順序依賴 | v0.1 核心單檔（無內部順序）；v0.2 起 Widget 檔開頭自檢 `MinidoracatUI.v1`，缺席不掛能力 |
| 8 | 熱路徑殘留 print | 預設零 log，debug 旗標才輸出 |

## 5. 分期與完成定義

| 期 | 內容 | 完成定義（可驗證） |
|---|---|---|
| v0.1 Core | V1＋Theme（雙色系）＋Skin＋貼圖資產＋harness | NoticeBoard 與 MiniMap 皮膚改 thin adapter，刪除重複繪製碼與重複 PNG；兩 repo verify 全綠；遊戲內實測無視覺回歸 |
| v0.2 Widgets（**已完成**） | FloatButton＋Toast | 家族三份浮鈕/Toast 實作全部改用框架版 ✅（NBFloatButton／NBToast／MiniMap _FloatIcon 皆為 thin wrapper） |
| v0.3 VirtualList（**已完成**） | 垂直固定列高 | Cleaner Picker 與 Economy 表列已接用；資料重綁、回收與 resize 的行為由 harness 驗證，原生操作仍屬下游聯測閘門 |
| API rev 2 Icons（**已完成**） | 8 個共用單色圖示（§3.6） | 資產由生成器確定性重生、`verify_mod.py` 第 12 項逐張把關；NoticeBoard 文件樹與工具列改用圖示且缺資產時仍走 ASCII 退回 |
| API rev 3 Painters/Assets（**已完成**） | pill、無狀態 toggle／slider、12 個新增 icon key | toggle 20px、slider 4px track 幾何固定；缺色／缺資產 fail-soft；既有 shape、icon key 與公開簽章不變 |
| API rev 7 Modern Controls（**開發中**） | Button／TextField／Checkbox／Tabs／Window／Dialog（§3.7） | harness 情境九～十五驗證載入自檢、disabled／silent／單次回呼等邊界；VehicleManager 車隊視窗接用並遊戲內實測後定版 |
| API rev 8 車輛圖示＋ColorPicker（**開發中**） | 16 個車輛／標記 art key（§3.6）、ColorPicker（§3.8） | 圖示由 AI 原圖匯入、`verify_mod.py` 逐張把關並由 `test_icon_import.py` 重現出貨檔；harness 情境十六驗證色卡／滑桿／hex 單次回呼、互相同步不重複回呼、非法 hex 不變與 silent；VehicleManager 地圖車輛標記接用並遊戲內實測後定版 |
| API rev 9 Slider（**開發中**） | `UI.Slider`（§3.9）；ColorPicker 的 R/G/B 改用滑桿（公開面不變） | harness 情境十七驗證量化夾限、點擊跳值單次回呼、拖曳 setCapture 成對、同值不觸發、silent、滾輪步進、disabled 不回應與 format 寬度只量一次；VehicleManager 地圖外觀視窗圖示大小接用並遊戲內實測後定版 |
| API rev 10 Focus（**開發中**） | `UI.Focus`（§3.10）：鍵盤＋手把焦點；Window／Dialog 內建接線、控制元件焦點接點 | harness 情境十八驗證 Tab 閱讀順序與隱藏排除、輸入框交接、帳本消耗、Enter／Space／清單反白與啟動、分頁與滑桿、沒有焦點框時不攔鍵、手把接手／移動／A／LB／B 還原與隱藏原焦點、Dialog 手把與鍵盤、Ctrl+C、自動目標不配置；Economy 改用本引擎、VehicleManager 車隊視窗以真鍵盤與手把 hook 實機驗證後定版 |
| API rev 11 Economy 元件收編（**開發中**） | 共用基礎：`UI.Text.fit`、`Skin.arrow`、Button chip／active／自動截字與 tooltip、TextField 尺寸與 clearButton、`theme.alpha`（§3.3、§3.7）；DatePicker（§3.11）、Table（§3.12）、FilterBar（§3.13）、ItemPicker（§3.14）、Autocomplete（§3.15） | harness 情境十九驗證共用基礎，五個切片測試（`scripts/test_rev11_*.lua`）驗證各元件的回呼次數、邊界、零配置與焦點接線；Economy 刪除自己的日期／篩選／表格外殼並改用本期元件、實機驗證（日曆、篩選列、物品挑選、帳號候選、鍵盤與手把）後定版 |

首發 Workshop 在 v0.1 完成即可（照 AGENTS.md 發布流程）；每期 `API_REVISION` +1 並更新 `CAPABILITIES`。

## 6. 資產管線

- **幾何 UI 貼圖（9-slice 圓角、圓點、`mui_icon_*` 圖示）**：`scripts/gen_ui_textures.py` 程序化生成（移植 NoticeBoard 現有做法）——9-slice 切線像素要求位元級精確，幾何圖示要求重跑逐位元組相同，不走 AI 生圖；生成器不用 `ImageDraw`（跨 Pillow 版本柵格化會變），純浮點謂詞＋8×8 超取樣自算覆蓋率。`verify_mod.py` 第 12 項比對尺寸／IHDR／純白／切線（皮膚）與透明邊／對稱／探針像素／著墨比例（圖示）當閘門。
- **美術資產（poster.png、preview.png、Workshop 圖）**：AI 生成（codex／grok imagegen）到 `scripts/poster/` 再由 `finish_poster.py` 部署——首發前才做，沿用家族貓娘 mascot 流程。
- 貼圖一律純白可染色；新增貼圖＝同步新增生成器幾何與 `verify_mod.py` 檢查項（`OUTPUT_NAMES` 是唯一權威，目錄多一張少一張都會 assert）。
- **art 圖示（rev 4 起，`mui_art_*.png`）**：幾何線條畫不出可辨識的動物剪影，這批改走 AI 生成——`scripts/icons/sheet.png`（codex `image_generation`，黑底純白實心剪影、4×4 等分格、無文字）→ `scripts/import_icon_sheet.py`（亮度→alpha、去雜訊、bbox 裁切、縮 28px 置中、四邊透明）→ commit PNG。`ART_ICON_NAMES` 在 `OUTPUT_NAMES` 內但生成器不產不覆寫；verify 只驗尺寸／純白／1px 透明邊／有 AA／著墨 0.10-0.70。重生單格：`import_icon_sheet.py <cell.png> --grid 1x1 --keys cow`。
- **rev 6 導覽 art**：原圖 `scripts/icons/navigation-sheet.png`，生成來源與列序記在 `scripts/icons/navigation-source.json`；4×4 依序為 `wallet,gift,shop,market,auction,mail,users,chart,coins,plug,shieldCheck,tag,transactions,clipboardCheck,server,settings`。以既有 `import_icon_sheet.py` 指定這組 keys 匯入；不得用程序化幾何冒充 AI 原圖。新增 16 張與既有 art 同受 `verify_image` 檢查。
- **圖表排列與合法 key 分開**：`import_icon_sheet.py` 的預設排列固定服務原始 `sheet.png`，不隨全部 `ART_ICON_NAMES` 成長；其他圖表明確傳 `--keys`。`scripts/test_icon_import.py` 在暫存目錄驗證舊表預設／明示排列相同、導覽與車輛圖表可重建為出貨檔，防止新增 key 破壞舊匯入方式。
- **rev 8 車輛／標記 art**：原圖 `scripts/icons/vehicle-sheet.png`，生成來源（實際 prompt、codex thread id、匯入指令）記在 `scripts/icons/vehicle-source.json`；4×4 依序為 `carSedan,carHatchback,carSports,carSuv,carPickup,carVan,carStepVan,carTruck,carAmbulance,carPolice,carFiretruck,carTrailer,markerStar,markerHeart,markerFlag,markerCrown`。同樣不得用程序化幾何冒充 AI 原圖。

## 7. 測試策略

- `scripts/smoke_harness.lua`（標準 Lua，假 PZ 全域；由 `verify_mod.py` 第 13 項自動執行）情境：
  1. facade 半初始化（模擬中途 error → `MinidoracatUI.v1` 必須不存在）
  2. NinePatch 三態＋element 契約破損（無全域／正常／壞路徑／缺存取器）× fill/border/dot 不拋錯、退回旗標正確、element 壞不標壞貼圖
  3. theme 隔離（兩實例互不污染、default 不被 mutate、light variant、token 解析）
  4. fits 邊界與 shape 相容（boolean topOnly ≡ "roundTop"、"rect" 強制退回）
  5. rev 3 painters/assets（revision/function 探測、pill fits 與舊 shape 相容、toggle on/off
     與 slider 比例／色彩／alpha／缺資產退回；Icons 舊三十三 key、rev 6 十六個導覽 key 與 rev 8 十六個車輛／標記 key 對到約定貼圖、快取
     只探一次、未知／非字串 key、無 `getTexture`／貼圖缺失回 nil/false、錯誤不外洩）
  - 條數守門 `EXPECTED_ASSERTIONS`（家族慣例：防整段被註解仍全綠）
  - VirtualList 的 stencil 計數器成對＋repaint、資料縮水與 resize 解除綁定；FloatButton 拖曳門檻／clamp；Toast 佇列上限、混合高度與遞補間距、不收滑鼠（左右鍵）、避開速度鈕（重疊時讓位；不在 UI 清單、隱藏、水平不重疊、位在上緣以上時不讓位）。
  - rev 7 控制元件：facade 缺席／原生基底缺席／缺 Controls 時旗標維持 false；Button 自動寬度、disabled 不觸發與四種樣式；TextField 每幀變化只觸發一次、setText 靜默、placeholder；Checkbox silent；Tabs 點選中項不觸發與隱藏重排；Window 拖曳、clamp、縮放下限、關閉鈕與 ISLayoutManager 存讀；Dialog 單次回呼、移除 guard、Enter／Esc 配對與同時只有一個。原生 ISButton／ISTextEntryBox 以忠於原版語意的最小 stub 驅動。
  - rev 8／9 ColorPicker：原生基底缺席時 `colorPicker` 維持 false；點色卡、拖滑桿、合法 hex 各只回呼一次且互相同步不重複回呼、非法 hex／空白不變、`setColor` silent 同步滑桿／相同值 no-op、disabled 色卡與滑桿不回應、getColor 回拷貝。
  - rev 9 Slider：原生基底缺席時 `slider` 維持 false；step 以 min 為基準量化與夾限、點擊跳值只回呼一次、拖曳 setCapture 成對（出界仍收 move、放開後不再跟隨）、同值不觸發、silent、滾輪步進與預設 step、disabled 不回應且拖曳中停用解除 capture、format 文字寬度只量一次。
  - rev 10 Focus：Tab 依閱讀順序走、隱藏元件不算、Shift+Tab 以原始按住狀態讀；落在輸入框交出原生文字焦點、在框內 Tab 經 onOtherKey 離開並交還，同一次按住在下一幀不再走第二格（引擎時序模型）、極短點按不請引擎吞鍵、框內 Enter 放手後不被同一次按住重新聚焦且只吞實際按住的 Enter；press／release 都消耗且按住結束後不再認領；Enter 按鈕一次、Space 切換開關、清單方向鍵只呼叫 onHighlight、Enter 呼叫 onSelect、onKey 先拿鍵；點一下方向鍵在每幀 repeat 下只走一列、按住過延遲才連續；分頁右鍵、滑桿右鍵；有焦點框 Esc 收框並消耗、沒有焦點框 Enter／Esc 不消耗；滑鼠 onFocus 不畫框；背景 root 不搶 Tab；Ctrl+C 以框架通知回報；手把開窗接手、下移跳過輸入框文字焦點、清單到邊移出、A 先問 onFocusKey、A、LB、B 關窗還原（原焦點隱藏時還給角色）；Dialog 手把預設「確認」（開窗那一幀還沒進 UIManager 清單也一樣）、A／B 與焦點還原、關掉後下一次輸入回到開啟它的按鈕（手把與鍵盤）、鍵盤 Tab 到取消後 Enter 按取消、無焦點框 Enter 仍確認、輸入框 Enter 確認不漏給後面視窗；焦點下的按鈕被移出目標清單時 Enter 不按它而是搬框；螢幕鍵盤開著時視窗被關（鍵盤一起關、焦點還原、不聚焦看不見的輸入框）；開窗前焦點所在視窗已隱藏時還給角色；自動目標重用同一組 table。
  - 情境十九 rev 11 共用基礎：`Text.fit`（放得下原樣、二分截字、不切開多位元組字元、放不下 `"..."` 回空字串）、`Skin.arrow` 幾何與方向、chip 的 active／hover／按下疊層、Button 依寬度截字與自動 tooltip（手動 tooltip 不被覆寫、`setTooltip(nil)` 交回自動、寬度恢復收掉）、TextField placeholder 依寬度截字與自動 tooltip（同 Button 的四條規則、每幀不重新量測）、TextField `setWidth`／`setHeight` 重排內層與 `clearButton`、`theme.alpha` 乘在 chrome 不乘在文字。
  - **切片載入器**（`smoke_harness.lua` 檔尾）：依序 `loadfile` `scripts/test_rev11_{date,table,filter,itempicker,autocomplete}.lua` 與 `scripts/test_wrap.lua`，以 `ctx`（`check`、`nearly`、`UI`、`MOD_LUA`、時鐘與共用鍵盤／手把 stub 等，契約見 loader 上方註解）呼叫；每檔 `return` 自己實際執行的斷言條數，不符、檔案不存在或執行錯誤各記一筆失敗但不中止其他切片。切片斷言不算進 `EXPECTED_ASSERTIONS`（該值只守情境一～十九）。各切片涵蓋：
    - date：`UI.Date` 曆法（含 1970 年前、閏年、非法輸入）、DateField 回呼次數與失焦正規化、月曆開關／選日／外部點擊、導覽年份夾限與 chip 焦點停靠快取、鍵盤（Tab、方向鍵跨月、PgUp／PgDn、Home、Delete、連發節奏）、`close(scope)`、手把借焦點與歸還、零配置。
    - table：`Table.new` 的 create／bind／unbind 與勾子、`rowBackground` 三態與 `lit`、TextCell 截字／token／muted 刪除線／提亮與快取失效、`layoutColumns` 五段讓出順序與預算不超出、TableHeader 點擊回 key／nil、`live=false` 不回呼、排序箭頭。
    - filter：`setKinds`／`syncKinds`（順序、沒變回 false、丟掉已選）、多選「全部」與 extra、`apply`（關鍵字、類型、日期界線、穩定排序、分頁夾限）、每個動作回呼一次並重設頁碼、類型翻頁與精簡切換、`field=nil` 只保存狀態、焦點描述重用與繪製。
    - itempicker：缺 Table 不翻旗標、宇宙跳過 hidden／obsolete 且空結果不快取、搜尋篩選與上限、debounce、revision 重搜、選取與取消只回呼一次且先關閉、焦點目標快取。
    - autocomplete：debounce 與首次聚焦查詢、`onQuery` 回 false 下一幀重試、過期結果丟棄、More／Empty／Partial 提示列、標籤截字與 `theme.alpha`、list 契約與 pick、`queryFailed`、`setText`／`onEnter`、停用／隱藏時關閉、`appendTargets`、Focus 自動目標／方向鍵／Enter／鍵盤聚焦維持可見。
    - wrap：Dialog 內文與 Toast 多行共用的斷行，量測模型為 ASCII 7px、其他字 14px（中日文約為拉丁字兩倍寬）。涵蓋 VehicleManager 截圖那段中英混排（不在英文字後提早斷）、純英文（截到單字退到空白、剛好在單字結尾不多退）、純中文與括號禁則、中英交錯無空白（退到中英交界不切單字）、補充平面字，以及 Toast 同一段文字。harness 以 `package.preload` 只讓 `MinidoracatUI/TextWrap` 可被 require，其他 require 照舊失敗，「依賴缺席」情境不受影響。
- `scripts/verify_mod.py`：涵蓋靜態掃描、皮膚與圖示驗證、圖表匯入相容性及 Lua 煙霧測試。後者另守住原生置頂選項、通知遞補置頂，以及首次／捲動綁定失敗後可刷新恢復。本機缺 Pillow 時用 `uv run --with pillow scripts/verify_mod.py`，SKIP 不算完成；原生 GPU 視覺仍須實機確認。
- 下游 consumer 的測試以同層 repo 相對路徑（或 `MUI_LUA`）載入本框架 V1.lua；缺框架時一律 SKIP-not-PASS。
- 實機：每期完成定義都含遊戲內實測；MP 路徑在 dedicated（`getTexture` 回 null 環境）至少驗一次退回。
