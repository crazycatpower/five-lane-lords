# 開發交接

本文件只保留維護入口與陷阱，不另存會過期的牌數、費用、勝率或待辦。歷史決策見 [企劃書](企劃書.md)；現行數值以程式為準。

## 程式入口

| 工作 | 來源 |
|---|---|
| 卡牌、領主、階級與說明 | `balance.gd` |
| 對戰、部署、傷害、技能 | `battle.gd` 及其特殊機制模組 |
| 出牌與技能 AI | `enemy_ai.gd` |
| 領主移動與索敵 | `lord.gd`、`lord_ai.gd` |
| 畫面、動畫、材質 | `game.gd` 及其載入模組 |
| 牌組驗證與隨機牌組 | `deck_store.gd` |
| 圖鑑、趣聞 | `card_library.gd`、`card_lore.gd` |
| 冒險（新手教學，5 章 × 10 關）資料、劇情、執行 | `campaign_catalog.gd`（關卡、難度、極難被動）、`campaign_story_data.gd`、`adventure.gd`、`road_toll_story.gd`、`adventure_finale.gd` |
| 冒險教學：第一章逐步指引腳本、教練（提示框、高亮、結界、新敵人說明、失敗提示） | `tutorial_lessons.gd`（純資料）、`tutorial_coach.gd`；`game.gd` 只在 `draw_battle()` 末行呼叫 `adventure.coach.paint()` |
| 一日戰役的畫面（日晷、光線、朽壞） | `day_cycle.gd`；規則在 `battle.gd` 的 `day_phase()`、`crumble_gates()`、`dawn_verdict()` |
| 開戰橫幅、結算頁 | `battle_ceremony.gd` |
| 城牆畫法 | `wall_art.gd`（`game.gd` 的 `draw_wall_section()` 只是一行呼叫） |
| 未開放的路（冒險單路／三路關卡）：五段城牆照畫，路面畫成有柵欄、樹籬的麥田 | `closed_lanes.gd`（`draw_battle()` 地面之後一行呼叫） |
| 強盜營地（冒險第一章）：取代敵方城堡、城牆段畫成木柵；關卡 `"camp":true` → 對局 meta `camp_team` | `camp_art.gd`（`draw_battle()` 畫城堡那行與 `wall_art.section()` 開頭各一個判斷） |
| 配樂、音量、設定頁 | `music_player.gd`、`settings_screen.gd`、`tools/make_music.py` |
| 建築攻擊範圍（`reach` 格子形狀、優先打部隊再打建築）、多路陣型（`footprint`）、放置預覽站位 | `grid_rules.gd` |
| 金幣怪物（花光金幣、階段表 `B.GOLD_MONSTER_STAGES`） | `gold_monster.gd` |
| 封印祭壇、瘟疫主教（收魂、封印、腐土） | `seal_altar.gd` |
| 陣營核心收益卡：咒潮法師、荊棘母獸 | `core_cards.gd` |

## 規則與陷阱

- 出牌判定只改 `play_check()`；`can_play()` 和 `play_error()` 共用它。常駐牌用 `kind_at()` 取得，不直接索引輪轉牌組。
- 陣營與常駐牌查 `B.card_faction()`、`B.home_card()`；牌組用 `DeckStore.valid(deck,lord)` 驗證，不寫死舊牌數。
- 領地來自建築本格及周圍八格，含城牆；先佔者有己方支撐就保有領地，最後支撐消失才釋出。破門不直接擴張領地。
- 普通部隊向前行軍；領主優先攔截最深入我方的可見敵軍，同樣深入取最近者。不要恢復低血撤退或換路等待。
- `snapshot()` 的戰場陣列不可由 AI 修改。`record_events=false` 仍須正常模擬；機制不可依賴繪圖事件。
- 索敵優化須保留清單順序與同距決策，否則固定種子結果可能改變。
- 測試換手牌須重設 `hand_cd`，常駐牌另有 `farm_cd`；空棋盤測試須清掉開局建築。
- 困難 AI 參數經 `weights()` 取得；留意 `EVOLVED` 與參數檔一致。技能存錢策略會抑制進攻，不能把策略問題當成卡牌強度。
- 傷害統計按兵種歸類，可能混入軍團／召喚兵，不能直接當成單一卡牌的投資報酬。
- 卡牌趣聞採完全獨立的幽默諷刺風格，徹底刪除所有暗線、陰謀伏筆與跨卡角色暗號。

- 一日戰役：入夜（`B.NIGHT_START`）後 `multiplier()` 回傳 `B.NIGHT_GOLD`，城牆每秒掉 `night_rate()`；`B.DAWN` 時 `dawn_verdict()` 以 `land()` 定勝負，平手 `winner = -1`。`night_decay = false` 可關掉整套（肉鴿與教學關已關）。讀 `winner` 的地方要能處理 -1。
- 冒險的關卡資料用 `Catalog.stages()` 取得（不是常數）；敵方領主可以是 `B.MINION_LORDS`。關卡依序解鎖（`adventure.unlocked(i)`：上一關已過）。出征領主是 `adventure.lord`，可選的牌用 `adventure.card_pool()`，不要寫死 `"adventure"`。對局一律用 `adventure.make_battle(i,deck,lord)` 建（難度、極難被動、詔令都在裡面）；本關新卡由 `with_featured()` 在出征時放進牌組，不寫回存檔。
- 冒險就是新手教學：每關只教一件事，新卡、新敵人一次一個；不要再加只在冒險出現的場地機關。第一章教學腳本的完成條件只讀對局狀態（統計、建築、領地、城牆），腳本敵軍用 `deploy` 派出；改第一章內容後跑一次 quick_test（含 1-1 照提示打完的檢查）。
- 畫面演出（轉場、音樂、結算動畫）走 `game.gd` 的 `present()`，用真實時間 `clock`，不讀也不改對局狀態。
- 僅保留 `quick_test.gd`、`test_art_palette.gd`、`test_startup.gd`、`test_net_match.gd` 四支核心測試；`test_art_palette.gd` 為 `extends RefCounted` 模組，由 `quick_test.gd` 載入，不可直接以 `-s` 執行。勿再為單一改動新增 `test_*.gd` 檔案。
- `quick_test.gd` 上限 50 項（2026-11-18 從 1493 項精簡，舊版備份在 `.runtime/quick-test-before/`）。素材檢查把比對過的原圖／衍生圖雜湊快取在 `user://art_palette_verified.json`，圖沒變就跳過解碼；第一次執行較慢。
- 新卡的接法：規則放新模組，`balance.gd`、`battle.gd`、`game.gd` 只加一行掛鉤；收益卡與陣型以資料欄位驅動（`pay_all`、`unique`、`no_opening`、`hold_cooldown`、`spell_stacks`、`thorns_aura`、`reach`、`footprint`）。
- 兩個人同時改同一個檔會互相覆蓋。新功能放新模組，`game.gd`、`battle.gd`、`balance.gd` 只留掛鉤。

## 文件與工具

- [新增卡牌指南](新增卡牌指南.md)、[數值檔次](數值檔次.md)、[資料結構](資料結構.md)。
- [美術驗收](美術驗收.md)：風格、朝向與素材準備。
- [Windows 打包](Windows打包.md)：可玩版本與發布驗收限制。
- `tools/autobalance.py --dry-run` 只量測；不加此參數會改費用。報告寫到 `tools/autobalance_runs/report.md`（不提交）。
- 定價以成對 AI 對局為準（同領主、一方必帶目標卡、交換紅藍各打一場）：約 1 金幣 ≈ 1% 勝率；`autobalance.py` 的理論費用公式實測誤差大於直接沿用現行費用，只作新卡初估。
- 報告的日期、版本、種子與牌組決定適用範圍，舊勝率不是目前強度。

測試分級以根目錄 `AGENTS.md` 為準。已完成待辦及逐次驗收流水帳已刪減，需要時查 Git 歷史。
