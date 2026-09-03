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

## [Unreleased]

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
