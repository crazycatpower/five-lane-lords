# Codex 收官壓榨執行計畫（2026-11-13）

> 目標：在 Codex 會員到期前，把剩餘額度全數集中在**高算力、高迭代、需要大量對局模擬與枯燥重構**的工作，把所有可量化的系統一次收斂到位，人類製作人之後只需試玩拍板與聽音樂。

## 全程鐵律（給 Codex 必守規則）

1. **禁止測試膨脹**：遵守 `AGENTS.md`，**不得新增任何 `test_*.gd` 檔案**。所有改動驗證只跑既有 4 支核心測試：
   - `godot_console --headless --path . -s tools/quick_test.gd`（含 `test_art_palette.gd`）
   - `godot_console --headless --path . -s tools/test_startup.gd`
   - `godot_console --headless --path . -s tools/test_net_match.gd`
2. **確定性不可破壞**：重構與表現層改動（特效／UI／音效）**絕對不可讀取或消耗 `model.rng`**，所有純重構前後同種子模擬結果必須完全一致。
3. **數值只用既有檔次**：`balance.gd` 調平衡只調 `cost`、`cooldown` 或 `B.TIERS` 既有檔次，不插中間值。
4. **檔案分工互斥**：若多視窗並行，禁止兩個任務同時編輯 `balance.gd`、`battle.gd`、`game.gd`。

---

## 第一梯隊：高算力批處理（最吃機時／最值錢，優先跑）

### 任務 1｜AI 針對新卡盲點排查 + 全陣營 114 卡再平衡
- **背景現況**：
  - `docs/企劃書.md` 記錄擴充 46 卡後曾出現嚴重失衡（經典 67%、魔物 57%、黑暗 26–44%、魔法 26%）。
  - 本次已將 `axe_thrower`、`barricade`、`catapult`、`rain`、`fire` 調回中立，並修復 `beekeeper`（`net_slow`）與 `observatory`（`range` 加成）失效 bug，急需整套重測。
- **執行步驟**：
  1. 先審查 `expansion_more.gd` 的 `ai_score()` 與 `enemy_ai.gd`，排查魔法／黑暗新卡（`astrolabe_surveyor`、`sigil_weaver`、`orrery_walker`、`grave_exchange`、`borrowed_bones`、`mourning_shroud`、`blood_altar`、`soul_well`）是否有 AI 亂放、空放或忽略建築條件的問題，先修 AI 邏輯再調費。
  2. 以 `python tools/autobalance.py --dry-run` 進行全域基準量測（涵蓋全部 113 張可選卡、4 陣營與 9 位領主交叉對打，建議每組 ≥200 場）。
  3. 依據量測報告執行 2–3 輪 `cost`／`cooldown`／整檔調整（只改 `balance.gd`），每次調完重測確認收斂，並將最終數據整理進 `docs/` 報告。
- **驗收門檻**：
  - 四大陣營（`normal` / `dark` / `magic` / `beast`）平均勝率收斂在 **46%–54%**。
  - 9 位領主對戰無極端離群值（目標 **42%–58%**）。

### 任務 2｜困難 AI（`EVOLVED`）針對現行 114 卡＋入夜機制重訓演化
- **背景現況**：
  - 現有 `tools/evolved_ai.json` 與 `enemy_ai.gd` 的 `EVOLVED` 權重是 2026-10-29（v6.10，當時僅 30 卡、城門 400 HP、尚無入夜城牆朽壞與擴充機制）跑出的舊權重，已嚴重過時。
- **執行步驟**：
  1. 檢查並升級 `tools/evolve_ai.py` 與 `enemy_ai.gd` 基因表，加入現行版本關鍵決策維度（例如：入夜前後攻防節奏、支援建築密度與優先度、低血防線／控場保留）。
  2. 確認演化對局池使用目前完整正式卡池（4 陣營＋中立＋9 位領主）。
  3. 執行多代演化（建議 `--generations 10 --children 12 --seeds 24`）＋ 200 場未見種子紅藍互換雙盲驗證。
  4. 若新權重對現行困難 AI 勝率顯著提升（≥58% 且雙邊平均無顯著退化），更新 `enemy_ai.gd` 的 `EVOLVED` 與 `tools/evolved_ai.json`，並更新 `docs/AI演化報告.md`。
- **驗收門檻**：新 `EVOLVED` 對舊版勝率顯著過半（95% CI 下界 > 50%），且 `quick_test.gd` 全過。

### 任務 3｜肉鴿全名單強度聯賽重分階 ＋ 雙領主開荒壓測
- **背景現況**：
  - 新增 46 卡、9 位正式領主（含 `beast`）與 5 張中立回歸後，`roguelike_catalog.gd` 的小怪 `tier 1/2/3` 與 雙領主起始組合尚未以全卡池重測。
- **執行步驟**：
  1. 執行 `godot_console --headless --path . -s tools/rogue_league.gd -- --opponents=6 --workers=4 --apply`，以 Bradley–Terry 強度重寫 `roguelike_catalog.gd` 的小怪分段。
  2. 執行 `--duo` 模式掃描全部「內政 × 戰鬥」領主配對對早期 T1 小怪的勝率，排查勝率低於 55% 或明顯卡死的起始組合／小怪關卡並微調 `roguelike_catalog.gd`。
  3. 跑 15–20 輪 AI 模擬完整 8 關肉鴿（含精英路線與商店修理／強化），輸出各階層勝率統計。
- **驗收門檻**：`roguelike_catalog.validate()` 0 錯誤，一般 AI 通關率落在 **35%–55%**，無無解起始搭檔或壞死小怪。

### 任務 4｜冒險征服 15 塊領地逐關難度調平
- **背景現況**：
  - `docs/冒險難度初篩-2026-11-12.md` 顯示目前 **15 關裡有 8 關 0% 勝率、5 關 100% 勝率**（第一塊農田與十字驛站 0/3，四首府與王都卻 3/3）。
- **執行步驟**：
  1. 升級 `tools/campaign_probe.gd`：每關樣本由 3 場提高至 8–10 場（確保粒度細於 12.5%），同時模擬更貼近玩家行為的路線（解鎖首府後切換領主與高性價比卡池）。
  2. 僅調整 `campaign_catalog.gd` 各關的 `ai` 等級、敵方 `enemy_deck` 或預置 `buildings`（**不改動全域卡牌數值**），逐輪收斂難度。
  3. 更新 `docs/冒險難度初篩` 量測表。
- **驗收門檻**：15 塊領地 **沒有任何 0% 或 100%**（除教學機制固定設計外）；前哨達 **60%–80%**、四首府 **40%–60%**、王都 **30%–50%**。

---

## 第二梯隊：工程清理、技術債與細節收尾（高性價比機械性勞務）

### 任務 5｜未完結內容與殘留技術債一鍵掃除
- **刪除死碼**：移除已無任何引用的 `bridge_story.gd`（及 `.uid`）。
- **術語統一**：「城門」→「城牆」（目前正式 `.gd` 仍殘留 15 處：`balance.gd` 4 處、`campaign_catalog.gd` 1 處、`card_lore.gd` 4 處、`card_upgrades.gd` 1 處、`roguelike.gd` 5 處），統一改為「城牆」，並確認是否有新增未切割中文字（若有則跑 `python tools/build_font.py` 與 `--import`）。
- **未開放卡收尾**：盤點 `balance.gd` 尚帶 `"unreleased":true` 的 `glutton_nest`（貪食巢穴）及對應 `glutton_nest.gd`，確認機制／AI／肉鴿敵人／圖鑑完整後，決定正式釋出或封存整理。

### 任務 6｜核心大檔模組拆分瘦身（提升後續自己維護的可讀性）
- **背景現況**：目前 `game.gd` 達 **2,323 行**、`battle.gd` 達 **1,382 行**，違反 `docs/交接給Codex.md` 鼓勵的小模組原則。
- **執行方式**：
  - 將 `game.gd` 中高內聚的區塊抽離成獨立輔助腳本（例如：選牌／收藏頁渲染與事件處理、戰場特效／投射物渲染、或是結算統計面板）；`game.gd` 只保留對外協調與掛鉤。
  - 若對 `battle.gd` 做同樣拆檔（例如 AI 快照／尋路或法術效果），**必須以多組隨機種子跑 5 分鐘對戰，驗證重構前後終局勝敗、時間與 `rng.state` 逐位元一致**。

### 任務 7｜46 張新擴充卡戰鬥回饋與音效覆蓋審查
- 逐一檢查 `sound_bank.gd`、`game.gd`、`faction_visuals.gd` 與 46 張新卡機制的對應：
  - 補齊缺乏明顯回饋的能力事件（如戰吼／衝鋒撞擊、反傷與吸血提示、劫掠往返車入帳、建築光環節拍、陣營投射物／粒子區分）。
  - 確保 `fx_enabled == false` 與 `record_events == false` 模式下完全不消耗額外算力與任何 RNG。

### 任務 8｜最終打包與 Git 整理
- 將所有尚未歸檔的改動按主題整理成清楚的本地 Git commit（不擅自 push）。
- 檢查 `export_presets.cfg` 與版本號，執行 `tools/build_windows.ps1` 產出新版封測 ZIP，並以隔離 `APPDATA` 啟動獨立 `.exe` 實測無崩潰、無錯誤日誌。

---

## 建議調度順序（時間＆額度最省路線）

1. **並行啟動背景運算（先吃算力）**：
   - 視窗 A：**任務 4**（`campaign_probe.gd` ＋ `campaign_catalog.gd`）——獨立檔案，不撞車。
   - 視窗 B：**任務 3**（`rogue_league.gd` ＋ `roguelike_catalog.gd`）——獨立檔案，不撞車。
   - 視窗 C：**任務 5＋任務 7** 的前期文字／特效整理（先避開 `balance.gd`）。
2. **集中改數值與 AI（避免同時改 `balance.gd` / `enemy_ai.gd`）**：
   - **任務 1**（先修新卡 `ai_score`，再多輪 `autobalance.py` 調定 `balance.gd`）。
3. **終極壓榨（數值穩定後再訓練 AI）**：
   - **任務 2**（用調完後的 `balance.gd` 跑完整 `evolve_ai.py` 重訓 `EVOLVED`，這輪最耗時也最吃算力，最適合掛機跑整晚）。
4. **收尾封箱**：
   - **任務 6**（大檔安全拆檔＋確定性比對） → 跑完 4 支核心測試 → **任務 8**（整理 Commit ＋ 打包 EXE）。

---

## 可直接貼給 Codex 的執行提示詞模板

> **階段 A（任務 1：AI 修復＋全陣營平衡）**
> 「請閱讀 `AGENTS.md`、`docs/交接給Codex.md` 與 `docs/Codex收官壓榨計畫.md` 的任務 1。依序檢查 `expansion_more.gd`、`enemy_ai.gd` 對新增魔法／黑暗卡的決策邏輯並修補盲點，再用 `python tools/autobalance.py` 分輪跑大樣本量測與調費（只改 `balance.gd` 既有檔次與費用，不動測試、不新增任何 `test_*.gd`）。目標四陣營平均勝率收斂至 46%–54%。完成後跑 `quick_test.gd`、`test_startup.gd`、`test_net_match.gd` 並更新平衡報告。」

> **階段 B（任務 2：重訓困難 AI）**
> 「請閱讀 `AGENTS.md` 與 `docs/Codex收官壓榨計畫.md` 的任務 2。擴充 `tools/evolve_ai.py` 與 `enemy_ai.gd` 加入現行入夜機制與支援建築權重基因，使用完整卡池執行多代演化（`--generations 10 --children 12 --seeds 24`）及 200 場獨立種子雙盲驗證。確認勝率顯著提升後寫回 `EVOLVED` 與 `tools/evolved_ai.json`，更新 `docs/AI演化報告.md` 並跑核心測試。」

> **階段 C（任務 3 & 4：肉鴿聯賽＋冒險 15 關調平）**
> 「請分開處理 `docs/Codex收官壓榨計畫.md` 的任務 3（只改 `roguelike_catalog.gd` 與 `tools/rogue_league.gd`）與任務 4（只改 `campaign_catalog.gd` 與 `tools/campaign_probe.gd`），不要修改全域卡牌數值，也禁止新增任何 `test_*.gd`。調整至肉鴿 AI 通關率 35%–55%、冒險 15 關全數脫離 0%/100% 並寫出量測表。」
