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

## [42.20.3-0.1.0] - 2026-08-25

### 新增

- **初始版本**：Minidoracat 家族 MOD 共用的介面函式庫。本體不新增任何遊戲內容、遊戲中看不到它，只讓依賴它的 MOD 共用同一套介面外觀與元件
- **統一的視窗外觀**：家族 MOD 的面板改用同一套圓角視窗與配色，各 MOD 的視窗不再各長一個樣。本函式庫未安裝或版本不符時，依賴它的 MOD 自動退回原本的直角外觀，功能不受影響
- **共用的提示訊息堆疊**：多個家族 MOD 同時彈提示時，訊息依序堆疊而不互相覆蓋
- **共用的浮動按鈕**：家族 MOD 的畫面浮鈕行為一致——可拖曳、位置自動記憶
- **長清單捲動優化**：清單只繪製畫面內看得到的項目，項目數很多時捲動仍然流暢

> 技術要點：facade `MinidoracatUI.v1`（`API_MAJOR=1`／`API_REVISION=1`），提供 Theme（雙色系 12 token）、Skin（九宮格圓角）、FloatButton、Toast（全域共用堆疊）、VirtualList。widget 逐項以 `CAPABILITIES` 探測，單一 widget 載入失敗只讓該項留 `false`，Theme／Skin 不受牽連；consumer 一律以 capability 探測而非版號硬判。
