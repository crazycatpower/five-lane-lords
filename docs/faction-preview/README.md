# v6.62 卡圖與特效驗收

12 張原圖均位於 `assets/manuscript-v1/<key>.png`：mana_spring、chain_lightning、arcane_shield、time_field、charge_horn、levy、net_hunter、watchtower、sacrifice、dread_howl、mass_grave、blood_tower。

以內建 image_gen 生成；完整提示詞見 [faction-prompts.json](../../assets/manuscript-v1/faction-prompts.json)。投網獵人補修透明留白，角色朝右。藍方統一由 `tools/prepare_assets.gd` 產生，未手改衍生圖。換色遮罩版本為 `team-material-v2`，保護獻祭血陣與鮮血塔血液，並重建 manifest 中的 67 項素材。

- `cards.png`：遊戲實際卡框與正式卡圖。
- `art-sheet.png`：淺深底、紅藍隊色及縮小圖。
- `battle-cast.png`：逐跳變細的鋸齒閃電、恐懼骷髏、衝鋒腳塵、獻祭血陣、徵召號角光圈、塔頂掃描光。
- `battle-travel.png`：雙方獻祭紅光飛向各自錢袋。
- `battle-dust.png`：徵召民兵離境消散。

以上截圖均已打開目視檢查。畫面未新增戰鬥文字或數字。

驗收使用已安裝的 Godot 4.7.1：

- `tools/test_faction_cards.gd`：86 項，0 失敗。
- `tools/test_faction_visuals.gd`：29 項，0 失敗；涵蓋雙方跳躍序號與壽命、錢袋落點、血塔連線不誤導、徵召光圈與消散、特效開關、亂數不變及血液色彩保護。
- `tools/quick_test.gd`：594 項，0 失敗，包含 `test_art_palette.gd`。
- `tools/test_startup.gd`：68 個預處理紋理參照，沒有啟動時換色。
- `tools/capture_faction_art.gd`：產出本目錄五張截圖，沒有腳本或繪圖錯誤。

與任務開始時的檔案逐字比對，`balance.gd` 只有刪除十二個 `art` 欄位；`faction_cards.gd` 的繪圖區之前（機制、規則、AI）完全相同。未跑長批次平衡、全量 smoke 或黃金對局重錄。
