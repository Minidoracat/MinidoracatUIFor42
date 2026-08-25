# Minidoracat UI Library for B42

Minidoracat 家族 MOD 共用 UI 函式庫（主題色票、圓角皮膚、浮動按鈕與 Toast），本體不新增遊戲內容，僅供家族 MOD 依賴使用

Project Zomboid Build 42 MOD。

## 功能（分期路線）

- **v0.1 Core**：版本化 API facade（`API_MAJOR`／`API_REVISION`／`CAPABILITIES`）、主題系統（深／淺雙色系 token 色票，各 MOD 可覆蓋）、圓角皮膚（引擎原生 9-slice，貼圖缺失自動退回直角）
- **v0.2 Widgets**：浮動按鈕（拖曳＋位置持久化）、Toast 通知（堆疊＋淡入淡出）
- **v0.3 VirtualList**：垂直固定列高虛擬清單

設計契約與 NeatUI 分析結論見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatUIFor42`

## 開發

- `link_workshop.bat`：把 repo 掛載到 `Zomboid\Workshop\` 與 `Zomboid\mods\`（符號連結，repo 改動即時生效）
- `PZ_Test.bat`：啟動測試（客戶端 / 專用伺服器 / 多客戶端組合）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.20.3-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
