# Minidoracat UI Library for B42

Minidoracat 家族 MOD 共用 UI 函式庫（主題色票、圓角皮膚、單色圖示、浮動按鈕與 Toast），本體不新增遊戲內容，僅供家族 MOD 依賴使用

Project Zomboid Build 42 MOD。

## 功能（分期路線）

- **v0.1 Core**：版本化 API facade（`API_MAJOR`／`API_REVISION`／`CAPABILITIES`）、主題系統（深／淺雙色系 token 色票，各 MOD 可覆蓋）、圓角皮膚（引擎原生 9-slice，貼圖缺失自動退回直角）
- **v0.2 Widgets**：浮動按鈕（拖曳＋位置持久化）、Toast 通知（堆疊＋淡入淡出）
- **v0.3 VirtualList**：垂直固定列高虛擬清單
- **API rev 2 Icons**：8 個共用單色圖示（`sidebar`／`folder`／`document`／`chevronRight`／`chevronDown`／`language`／`reload`／`resetSize`），32×32 純白貼圖運行時染色、設計供 14–16px 顯示；`UI.Icons.get(name)`／`UI.Icons.draw(element, name, x, y, size, color, alpha)`，未知 key 或貼圖缺失一律回 `nil`／`false`，呼叫端退回原本的文字表示（詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §3.6）
- **API rev 3 Painters/Assets**：新增 `shape="pill"`、無狀態 `UI.Skin.toggle(...)` 與 `UI.Skin.slider(...)`；slider 只負責現代化 track／fill／圓形 knob，不接管 consumer 的拖曳與數值邏輯。新增 `search`／`chevronLeft`／`layers`／`pin`／`globe`／`sliders`／`gauge`／`lock`／`unlock`／`close`／`locate`／`copy` 十二個 icon key。consumer 以 `UI.API_REVISION >= 3`＋函式探測；pill 精確膠囊高度 20px，低於 20px 的 shape 退直角，toggle 幾何小於 20px 回 `false`

設計契約與 NeatUI 分析結論見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 安裝

- Steam Workshop：https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701
- 本 MOD 是給其他 MOD 用的函式庫；只有當你訂閱的 MOD 把它列為必要項目時才需要訂閱
- 手動安裝：把 `MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatUIFor42`

## 開發

- `link_workshop.bat`：手動同步、狀態檢查與歸檔卸載（實體副本）
- `PZ_Test.bat`：啟動前自動同步 MOD 與家族依賴；Steam／no-Steam／Debug／多開皆保留。資料邊界見 `../pz-family-docs/tools.md`

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.20.3-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)

### 發布到 Workshop

雙擊 `Publish_Workshop.bat`：先確認 Steam 用戶端已以作者帳號登入（未登入會喚起 Steam 並等你登入後重試），
再選擇更新 MOD 內容（含 `STEAM_CHANGELOG.md` 更新說明）／GIF 封面／簡介／全部；提交後回查 Steam，
任一不符即以非零碼結束。設定在 `scripts/workshop_publish.json`（Workshop ID、簡介語言槽來源、GIF 路徑）。

```
uv run --no-project python -B scripts/publish_workshop.py --mode all --yes       # 自動化／AI；或 content / preview / description
uv run --no-project python -B scripts/publish_workshop.py --mode all --dry-run   # 只檢查、顯示計畫
```

退出碼：`0` 成功／`2` 參數或取消／`3` 未登入、帳號不是擁有者／`4` 前置檢查失敗／`5` 提交失敗／`6` 已提交但回查不符。
網頁動態封面放 `MOD/<資料夾>/workshop/preview.gif`（不在 `Contents/`，不會下載給玩家）；遊戲內上傳器仍用 `preview.png`，
且每次會把網頁封面覆回靜態，需要動態封面時一律改用本工具發布。
