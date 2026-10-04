# Changelog

<!-- 撰寫規則摘要（完整版見 AGENTS.md「CHANGELOG 撰寫規則」）：
  - bullet 寫給玩家，會整段照貼 Workshop 更新說明：症狀先行、遊戲內名詞、
    禁檔名/函式名/行號/引擎術語；影響版本誠實寫清楚
  - 「> 技術要點：」（選用）只放管理員/modder 需要的行為事實；單次變更的完整
    技術原因寫在 commit message 本文（綁 diff、可 git log 搜尋、永不公開）
  - 紅線：不寫攻擊配方（安全修正只寫「強化了驗證」）、不寫玩家名/座標/Steam ID、
    不寫主機名/路徑/IP -->

所有重要的變更都會記錄在此檔案中。

格式基於 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號遵循 `{PZ版本}-{主版本}.{次版本}.{修訂}` 格式。

## [42.21.0-0.6.3] - 2026-10-05

### 修正

- **右上角通知不再擋住暫停與加速按鈕**：單人遊戲戴著手錶（畫面右上有時鐘）時，時鐘下方的暫停、播放、快轉按鈕剛好落在通知框底下；依賴本函式庫的 MOD 跳出通知時，這排按鈕點了沒反應，要等通知消失才按得到。自動駕駛到站後自動暫停時最明顯：遊戲停住了，卻要等幾秒通知淡出才能按播放。現在通知改排在這排按鈕下方，而且通知本身不再攔截滑鼠，就算蓋到其他介面也照常可以點。通知功能推出以來都有這個問題，更新後需完整重開客戶端

> 技術要點：Toast 建立時 `wantMouseEvents=false`（左鍵與滑鼠移動穿透），右鍵處理明確回 false；堆疊上緣在原版速度鈕可見、在 UI 清單內且與通知欄水平重疊時改為速度鈕下緣＋8px（單人、預設大時鐘時約為 y=118），否則維持 60。MP 與 Last Stand 不顯示速度鈕，位置不變。公開 API 不變，`API_REVISION` 仍為 11。

## [42.21.0-0.6.2] - 2026-10-03

### 修正

- **中日文夾英文的對話框與通知不再提早換行**：依賴本函式庫的 MOD 裡，確認對話框與多行通知的中文或日文內文夾著英文單字時（例如「之後玩家的 Steam 帳號要和帳號相符才算數…」），那一行常在英文字後面就斷掉，後面整段被擠到下一行，右邊空出一大塊。現在中日文會排滿整行才換行，英文單字仍不會從中間切開；逗號、句號、右括號不會出現在行首，左括號不會留在行尾。純英文的長句也不再偶爾少排一個剛好放得下的單字。多行通知自 0.5.0、確認對話框自 0.6.0 起都有這個問題。更新後需完整重開客戶端
- **中文介面的輸入候選提示不再黏成一句**：依賴本函式庫的 MOD 裡，輸入框下方的候選清單超過可顯示的列數時，最後一列的「還有幾個，請輸入更多字元」提示在繁體與簡體中文介面中，數字和後半句之間的刪節號顯示不出來，兩句黏在一起。現在改用逗號分隔，沒裝中文字型包的玩家也能正常閱讀。0.6.0 加入輸入候選以來都有這個問題，更新後需完整重開客戶端

> 技術要點：確認對話框內文與 `Toast.show{ maxLines > 1 }` 改用同一套斷行：截點兩側任一是中日韓字（含全形標點、補充平面字）或空白就直接斷，否則往回找最近的斷點（空白或中日韓字交界），整段都沒有斷點才硬切；行首／行尾禁則依 UAX #14 的收尾／起始標點。同一段文字的行數通常變少，禁則把前一字帶到下一行時可能多一行；對話框與通知的高度照舊依實際行數計算，`toast.lines`／`toast.message`（第一行）語意不變。單行通知（`maxLines` ≤ 1）照舊截字。公開 API 不變，`API_REVISION` 仍為 11。

## [42.21.0-0.6.1] - 2026-09-29

### 變更

- **對應遊戲 42.21.0**：已確認本函式庫在 42.21.0 正常運作，版本號前綴改為 42.21.0。最低支援版本維持 42.20.1，依賴本函式庫的 MOD 不受影響，舊版遊戲照常可用

### 修正

- **輸入框的提示文字太長時不再超出框外**：依賴本函式庫的 MOD 裡，空白輸入框會顯示灰色提示文字。提示比輸入框長時（英文介面常見，例如經濟系統對帳單的搜尋框），文字會畫到框外、壓住旁邊的標籤。現在改以省略號截短，滑鼠移到輸入框上可看到完整提示。0.6.0 加入輸入框以來都有這個問題

> 技術要點：`UI.TextField` 的 placeholder 依可用寬以 `UI.Text.fit` 截字，只在 placeholder 或寬度改變時重算。截到字且沒有手動 tooltip 時，以全文當 tooltip，規則同 Button 的自動 tooltip：`setTooltip(s)` 手動優先，`setTooltip(nil)` 交回自動。公開 API 不變，`API_REVISION` 仍為 11。

## [42.20.4-0.6.0] - 2026-09-27

### 新增

- **共用的現代視窗與控制元件**：依賴本函式庫的 MOD 可改用同一套圓角視窗、確認對話框、按鈕、輸入框、切換開關與分頁列，不再沿用遊戲原生的舊式外觀；視窗可拖曳標題列移動、可從右下角縮放並記住位置，確認對話框可用 Enter 確認、Esc 取消。介面資產缺失時自動退回直角外觀，功能不受影響
- **十六個車輛與地圖標記圖示**：加入轎車、掀背車、跑車、休旅車、皮卡、廂型車、貨運廂車、大卡車、救護車、警車、消防車、拖車的側視剪影，以及星星、愛心、旗子、皇冠標記，供依賴本函式庫的 MOD 在地圖上標示車輛並任意染色
- **共用的取色器**：依賴本函式庫的 MOD 可提供 24 色常用色卡，並能拖曳 R／G／B 三條滑桿或直接輸入 `#RRGGBB` 色碼，色卡、滑桿與色碼即時同步；色碼輸入錯誤時不會改變顏色
- **共用的滑桿**：依賴本函式庫的 MOD 可用同一款現代滑桿調整數值（例如圖示大小），可拖曳、點擊跳到指定位置或用滑鼠滾輪微調，旁邊即時顯示目前數值
- **鍵盤與手把操作**：依賴本函式庫的視窗可以不用滑鼠操作。鍵盤按 Tab／Shift+Tab 依畫面順序在按鈕、輸入框、清單、分頁與滑桿之間移動，焦點處有明顯外框；方向鍵在清單與分頁裡移動（點一下只移一格，按住才連續），Enter 或 Space 按下，Esc 收起外框；在輸入框裡按 Tab 或 Enter 也只移動一步。關掉對話框或子視窗後，下一次操作會回到開啟它的位置。沒按 Tab 時不攔任何按鍵，Enter 開聊天、Esc 開暫停選單照常。用手把的玩家開啟視窗會直接接手：方向鍵移動、A 按下、B 關閉並回到原本的操作、LB／RB 切換分頁，輸入框按 A 開遊戲的螢幕鍵盤；確認對話框同樣可用手把確認或取消
- **共用的日期選擇、表格、篩選列、物品挑選與輸入候選**：依賴本函式庫的 MOD 可提供同一套進階介面。日期欄可以直接輸入，也可以點旁邊的日曆挑選（切換年月、一鍵選今天或清除），輸入 `2026/9/7` 離開欄位後會自動整理成 `2026-09-07`；表格可點欄位標題排序，太長的內容自動截短；篩選列可依類型、關鍵字、起訖日期與排序條件過濾並分頁，視窗太小時可在「篩選條件」與結果之間切換；物品挑選視窗可依名稱或物品代碼搜尋遊戲本體與其他 MOD 的全部物品，並顯示圖示與類別；輸入玩家名稱等欄位時，下方會即時列出候選，點一下即可填入。日曆、候選清單與物品挑選同樣可用鍵盤與手把操作
- **按鈕文字放不下時自動截短**：依賴本函式庫的按鈕在窄視窗裡改以省略號截短標題，滑鼠移上去可看到完整文字；使用面板透明度設定的 MOD，介面的底色與邊框會跟著變淡，文字維持清楚

> 技術要點：API rev 6→7（純 additive，既有呼叫面不變）。新增 `Widgets/Controls.lua`：`UI.Button`（ISButton 基底、normal／primary／danger／ghost）、`UI.TextField`（內含透明原生 ISTextEntryBox，每幀比對文字觸發 `onChange`，涵蓋 IME）、`UI.Checkbox`（`Skin.toggle`）、`UI.Tabs`；`Widgets/Window.lua`：`UI.Window`（標題列拖曳、縮放下限、`SaveLayout`／`RestoreLayout` 可直接交給 `ISLayoutManager.RegisterWindow(name, UI.Window, win)`）與 `UI.Dialog.show/close`（全螢幕 guard、`onResult(ok, text)` 只呼叫一次、同時只有一個）。`CAPABILITIES.controls`／`window`／`dialog` 在對應檔載入成功後才翻 true；Controls 缺席時只提供 Window、`dialog` 維持 false。契約見 `docs/ARCHITECTURE.md` §3.7。

> 技術要點：API rev 7→8（純 additive）。Icons 新增 16 個 art key：`carSedan`／`carHatchback`／`carSports`／`carSuv`／`carPickup`／`carVan`／`carStepVan`／`carTruck`／`carAmbulance`／`carPolice`／`carFiretruck`／`carTrailer`／`markerStar`／`markerHeart`／`markerFlag`／`markerCrown`（AI 原圖 `scripts/icons/vehicle-sheet.png`，來源記錄 `vehicle-source.json`）。`Widgets/Controls.lua` 新增 `UI.ColorPicker.new{ x, y, width, color?, swatches?, theme?, font?, target?, onChange? }`，`onChange(target, color, picker)`、`getColor`／`setColor(c, silent)`／`setEnabled`、高度依內容自動計算，`CAPABILITIES.colorPicker` 載入成功才翻 true。契約見 `docs/ARCHITECTURE.md` §3.8。

> 技術要點：API rev 8→9（純 additive）。`Widgets/Controls.lua` 新增 `UI.Slider.new{ x, y, width, height?, min, max, step?, value?, theme?, font?, target?, onChange?, format? }`：`Skin.slider` 繪製、按 track 跳值並 setCapture 拖曳、滾輪 ±step（省略 step＝(max-min)/20）、值夾限並以 min 為基準依 step 量化；`onChange(target, value, slider)` 只在值實際改變時呼叫；`getValue`／`setValue(v, silent)`／`setEnabled`／`isEnabled`；`format(value)` 的文字寬以 `format(max)` 建構時量一次。`CAPABILITIES.slider` 載入成功才翻 true。`UI.ColorPicker` 的 R/G/B 數字欄改為三條 Slider（公開方法與簽章不變，高度依新版面重算）。契約見 `docs/ARCHITECTURE.md` §3.8／§3.9。

> 技術要點：API rev 9→10（純 additive）。新增 `MinidoracatUI/Focus.lua`：`UI.Focus` 鍵盤＋手把焦點引擎，收編自 MinidoracatEconomyFor42 的 `ECKeyboard`（函式名稱與語意相同：目標描述 `root:keyboardTargets()`、消耗帳本、輸入框文字焦點交接、`render(root, theme)`），另加 `onJoypadDown`／`onJoypadDir`／`takeJoypad`／`releaseJoypad`／`holdsJoypad`、`drawRing`／`drawCaption`、`collectTargets`、`pressed`／`repeatDue`（自行接 `onKeyRepeat` 的 popup 共用自動重複節奏）。相對 `ECKeyboard` 的行為修正：引擎每幀派送的 repeat 改為先等 400ms 再每 60ms 一步；輸入框放開鍵盤後，仍按著的 Tab／Enter 以 `GameKeyboard.eatKeyPress` 吞掉，不再於下一幀以新 press 到 root；目標可見判定不再要求視窗已進 UIManager 清單（`addToUIManager` 同一幀原生 `isReallyVisible` 為 false）；焦點下的控制項被移出目標清單（即使仍可見）就搬到有效目標，該次 Enter／Space／A 不啟動；手把還原對象以原生 `isReallyVisible` 判斷，螢幕鍵盤借著焦點時視窗被關也還給同一對象並放掉輸入框；手把 A 先問 `onFocusKey(KEY_RETURN)`；另一個 root 接手前記住焦點框，回來後的第一次輸入回到那個控制項。`UI.Window` 成為 root：轉發鍵盤與手把 hooks、預設依閱讀順序自動找目標、顯示時接手手把焦點且隱藏時還原；`UI.Dialog` 焦點框在其他按鈕上時 Enter 按那一顆。控制元件加 `_focusKind`、`Checkbox:forceClick`、`Tabs:selectRelative`／`onFocusKey`、`Slider:onFocusKey`；`UI.VirtualList` 新 opts `onHighlight`、`onKey`。`CAPABILITIES.focus` 載入成功才翻 true；Focus 缺席時 Window／Dialog 行為同 rev 9。契約見 `docs/ARCHITECTURE.md` §3.10。

> 技術要點：API rev 10→11（純 additive，既有呼叫面不變）。共用基礎：`UI.Text.fit(str, maxW, font)`（二分截字、不切開 surrogate pair／UTF-8 多位元組字元）、`Skin.arrow(element, x, y, up, color, alphaScale)`（7×4 排序箭頭，逐列 drawRect、無資產）；`UI.Button` 新增 `style="chip"`、`opts.active`／`setActive`／`isActive`（只有 chip 會畫出 active），標題依寬度自動截字，截到字時以全標題當 tooltip（手動 `setTooltip` 優先、`setTooltip(nil)` 交回自動）；`UI.TextField` 的 `setWidth`／`setHeight` 連內層 entry 一起重排、新增 `opts.clearButton`；`theme.alpha`（選用數值，缺省 1）由框架元件乘在 chrome（fill／border），文字與 icon 不乘，`theme:fill`／`theme:border` 便捷層不自動乘。新增五個能力（收編自 MinidoracatEconomyFor42）：`Widgets/DatePicker.lua`（`UI.Date` 純函式曆法、`UI.DateField.new{ …, onChange }`、session 共用月曆 popup 與 `UI.DatePicker.close(scope?)`，`CAPABILITIES.datePicker`）、`Widgets/Table.lua`（`UI.Table.new`＝已 initialise 的 VirtualList＋cell `onBind`／`onUnbind` 勾子、`rowBackground`、`TextCell`、`layoutColumns`；`UI.TableHeader` 拉取式排序狀態，`table`）、`Widgets/FilterBar.lua`（類型 chip 單選／多選＋extra、關鍵字、起訖日期、排序 chip、strip／inline 分頁、精簡切換；`apply(rows)` 本機過濾排序分頁，field 留 nil 即交給伺服器篩選，`filterBar`）、`Widgets/ItemPicker.lua`（`universe()` 全物品 script 宇宙＋搜尋疊層，以 `items`／`filter`／`revision`／`note` 注入 consumer 政策，`itemPicker`）、`Widgets/Autocomplete.lua`（非同步候選輸入框，`onQuery`／`setResults`／`queryFailed`，傳輸由 consumer 擁有，`autocomplete`）。各旗標在該檔與其相依（Controls／DatePicker／VirtualList／Table）載入成功才翻 true；鍵盤與手把接線依賴 `focus`，缺席時只能用滑鼠。框架翻譯新增 38 個鍵（四語）。Economy 改用這批元件後最低需求為 rev 11，框架須先於該版 Economy 發布。契約見 `docs/ARCHITECTURE.md` §3.11–§3.15（共用基礎見 §3.3／§3.7）。

## [42.20.4-0.5.0] - 2026-09-14

### 新增

- **十六個新的共用導覽圖示**：加入錢包、獎勵、商店、市場、拍賣、信箱、玩家、圖表、貨幣、整合、白名單、刊登、金流、稽核、系統與設定的實心剪影，供依賴本函式庫的 MOD 共用。
- **通知可以多行顯示**：依賴本函式庫的 MOD 可讓較長的通知自動換行（最多指定行數），不再被截成一行省略號；通知框會隨行數長高

### 修正

- 修正新增多行通知後，較長通知與其他 MOD 的單行通知同時出現會互相遮蓋；通知移除後也會依實際高度重新排列。更新後需完整重開客戶端。
- 修正共用清單自初版起在視窗縮放時未通知依賴 MOD 清理舊列的問題，讓列附帶的提示與操作狀態可正常釋放；不變更既有操作介面。更新後需完整重開客戶端。
- 修正通知原先未真正置頂、可能被後開視窗遮住的問題；浮動入口可明確維持一般視窗層級。更新後需完整重開客戶端。
- 修正共用清單單次內容更新失敗後，後續重新整理仍留下空白或舊內容的問題；正常選取與捲動方式不變。

> 技術要點：API rev 4→6。rev 5 的 `Toast.show` 新增 `maxLines`（預設 1＝原本單行截字，純 additive）；換行以 `MeasureStringX` 二分找每行最長前綴，拉丁文退到最後一個空白切，最後一行超出仍帶省略號；`toast.lines` 為各行、`toast.message` 維持第一行。rev 6 新增 16 個 `Icons` key：`wallet`、`gift`、`shop`、`market`、`auction`、`mail`、`users`、`chart`、`coins`、`plug`、`shieldCheck`、`tag`、`transactions`、`clipboardCheck`、`server`、`settings`；AI 原圖經既有 art 匯入流程轉為 32×32 純白 alpha，舊 key 與呼叫介面不變。
>
> `FloatButton.alwaysOnTop` 選項在實例化後套用，家族入口明確傳 `false` 保留原生層級；本版須搭配 MiniMap 0.28.1／NoticeBoard 0.4.1 的入口相容更新。VirtualList 綁定失敗後可重新整理恢復，正常選取與捲動介面不變。

## [42.20.4-0.4.0] - 2026-09-03

### 新增

- **十三個新的共用剪影圖示**：加入房屋、骷髏、爪印、方向盤，以及雞、牛、豬、羊、鹿、兔、浣熊、鼠、火雞的實心剪影圖示，供依賴本函式庫的 MOD 在地圖與設定視窗上共用（小地圖 MOD 的安全屋、殭屍、動物、載具圖標即改用這組）。資產缺失時依賴的 MOD 自行退回原有圖示

> 技術要點：API rev 3→4，`Icons` 新增 13 個 key（`house`／`skull`／`pawprint`／`steeringwheel`／`chicken`／`cow`／`pig`／`sheep`／`deer`／`rabbit`／`raccoon`／`rodent`／`turkey` → `mui_art_*.png`）。與既有 20 個幾何圖示不同：這批由 AI 生成剪影表（`scripts/icons/sheet.png`，codex image_generation）經 `scripts/import_icon_sheet.py` 轉 32×32 純白 alpha，`verify_mod.py` 第 12 項只驗尺寸／純白／1px 透明邊／AA／著墨比例，不比對幾何；`gen_ui_textures.py` 不生成、不覆寫這批檔。

## [42.20.4-0.3.0] - 2026-08-30

### 新增

- **共用的切換開關、滑條與膠囊外觀**：依賴本函式庫的 MOD 現在可呈現一致的膠囊、切換開關與現代滑條外觀，同時保留原有操作方式與設定範圍。介面資產缺失時自動退回直角或方形外觀，功能仍可使用
- **十二個新的共用圖示**：加入搜尋、向左箭頭、圖層、位置釘選、世界、調整、儀表、鎖定、解除鎖定、關閉、定位玩家與複製座標圖示，供依賴本函式庫的 MOD 共用

> 技術要點：`API_REVISION=3`；`Skin` additive 新增 `shape="pill"`、`toggle(element, x, y, width, height, on, colors, alphaScale)` 與 `slider(element, x, y, width, height, ratio, colors, alphaScale)`；新增 `search`／`chevronLeft`／`layers`／`pin`／`globe`／`sliders`／`gauge`／`lock`／`unlock`／`close`／`locate`／`copy` 十二個 icon key。pill 精確高度 20px；toggle 幾何不足回 `false`。toggle 固定 20px track／16px knob；slider 固定 4px track／12px knob，兩者零 per-frame table/closure 配置。consumer 以 `API_REVISION >= 3`＋函式探測；無對應資產或舊版框架仍走既有直角/文字退回。

## [42.20.4-0.2.0] - 2026-08-30

### 新增

- **共用的介面小圖示**：依賴本函式庫的 MOD 可以改用同一套小圖示（側邊欄、資料夾、文件、展開／收合箭頭、語言、重新載入、重設大小），取代各自畫的文字符號。圖示會跟著介面配色一起變色，各 MOD 的按鈕與清單不再一個 MOD 一種樣子。圖示資產若缺失，依賴的 MOD 會自動退回原本的文字顯示，功能不受影響

> 技術要點：facade 新增 `Icons`（`get(name)`／`draw(element, name, x, y, size, color, alpha)`），`API_REVISION` 由 1 升 2、`CAPABILITIES.icons=true`；純 additive，rev 1 的呼叫面未變動。八個 key：`sidebar`／`folder`／`document`／`chevronRight`／`chevronDown`／`language`／`reload`／`resetSize`，對應 32×32 純白貼圖（運行時頂點染色，設計供 14–16px 顯示），由 `gen_ui_textures.py` 確定性生成、發版閘門逐張驗證。未知 key、貼圖缺失、繪製拋錯一律回 `nil`／`false` 不拋錯，consumer 依回傳值退回文字表示。

## [42.20.4-0.1.1] - 2026-08-27

### 修正

- **虛擬清單的列表項點不動**：使用虛擬清單的介面（首個受影響者為清理系統 0.5.0 的清單管理器）會出現「滑鼠移過去有反應、點下去卻沒有動作」——點擊被清單裡的列元件自己吃掉，清單本體收不到。自 0.1.0 起存在，實機才會觸發（自動測試不模擬滑鼠事件分派）。已修正為點擊一律交回清單本體處理，依賴本函式庫的 MOD 更新後即恢復正常，無需額外設定。

> 技術要點：cell 建構時清掉 `wantMouseEvents`（引擎預設 true 會讓 ISPanel 衍生的 cell 在 onMouseDown 吞掉事件），instantiate 時同步 java 端 `setConsumeMouseEvents(false)`。煙霧 harness 的 stub 已改為忠於引擎預設值並加入對應斷言，防止此修正被無聲移除。

## [42.20.3-0.1.0] - 2026-08-25

### 新增

- **初始版本**：Minidoracat 家族 MOD 共用的介面函式庫。本體不新增任何遊戲內容、遊戲中看不到它，只讓依賴它的 MOD 共用同一套介面外觀與元件
- **統一的視窗外觀**：家族 MOD 的面板改用同一套圓角視窗與配色，各 MOD 的視窗不再各長一個樣。本函式庫未安裝或版本不符時，依賴它的 MOD 自動退回原本的直角外觀，功能不受影響
- **共用的提示訊息堆疊**：多個家族 MOD 同時彈提示時，訊息依序堆疊而不互相覆蓋
- **共用的浮動按鈕**：家族 MOD 的畫面浮鈕行為一致——可拖曳、位置自動記憶
- **長清單捲動優化**：清單只繪製畫面內看得到的項目，項目數很多時捲動仍然流暢

> 技術要點：facade `MinidoracatUI.v1`（`API_MAJOR=1`／`API_REVISION=1`），提供 Theme（雙色系 12 token）、Skin（九宮格圓角）、FloatButton、Toast（全域共用堆疊）、VirtualList。widget 逐項以 `CAPABILITIES` 探測，單一 widget 載入失敗只讓該項留 `false`，Theme／Skin 不受牽連；consumer 一律以 capability 探測而非版號硬判。
