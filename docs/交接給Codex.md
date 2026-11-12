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
| 冒險（大地圖征服）資料、劇情、執行 | `campaign_catalog.gd`、`campaign_story_data.gd`、`adventure.gd`、`road_toll_story.gd`、`adventure_finale.gd` |
| 一日戰役的畫面（日晷、光線、朽壞） | `day_cycle.gd`；規則在 `battle.gd` 的 `day_phase()`、`crumble_gates()`、`dawn_verdict()` |
| 開戰橫幅、結算頁 | `battle_ceremony.gd` |
| 城牆畫法 | `wall_art.gd`（`game.gd` 的 `draw_wall_section()` 只是一行呼叫） |
| 配樂、音量、設定頁 | `music_player.gd`、`settings_screen.gd`、`tools/make_music.py` |

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
- 冒險的領地資料用 `Catalog.stages()` 取得（不是常數）；敵方領主可以是 `B.MINION_LORDS`。能否進攻看 `adventure.unlocked(i)`：鄰居已征服，王都另需四座首府。出征領主是 `adventure.lord`，可選的牌用 `adventure.card_pool()`，不要寫死 `"adventure"`。
- 畫面演出（轉場、音樂、結算動畫）走 `game.gd` 的 `present()`，用真實時間 `clock`，不讀也不改對局狀態。
- `tools/test_*.gd` 中 `extends RefCounted` 的是模組，只能由 `quick_test.gd` 載入；直接用 `-s` 執行會在螢幕跳警告視窗。不要整批執行 `tools/test_*.gd`。
- 兩個人同時改同一個檔會互相覆蓋。新功能放新模組，`game.gd`、`battle.gd`、`balance.gd` 只留掛鉤。

## 文件與工具

- [新增卡牌指南](新增卡牌指南.md)、[數值檔次](數值檔次.md)、[資料結構](資料結構.md)。
- [美術驗收](美術驗收.md)：風格、朝向與素材準備。
- [Windows 打包](Windows打包.md)：可玩版本與發布驗收限制。
- [下一步計畫](下一步計畫.md)：目前的分工與待辦。
- `tools/autobalance.py --dry-run` 只量測；不加此參數會改費用。
- 報告的日期、版本、種子與牌組決定適用範圍，舊勝率不是目前強度。

測試分級以根目錄 `AGENTS.md` 為準。已完成待辦及逐次驗收流水帳已刪減，需要時查 Git 歷史。
