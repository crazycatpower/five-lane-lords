# 開發規則

先讀 [開發交接](docs/交接給Codex.md)，按任務查相關規格。使用者最新指示優先；歷史企劃與量測不是現行數值。

- 數值唯一來源為 `balance.gd`。戰鬥數值依 `B.TIERS`；調費用、冷卻或整個檔次，不插入中間值。
- 日常與共用資料驗證只跑 `godot_console --headless --path . -s tools/quick_test.gd`（內含 `tools/test_art_palette.gd`），改動啟動或連線時再補跑 `tools/test_startup.gd`、`tools/test_net_match.gd`。純文件修改只查內容與引用。
- 減少測試數量與膨脹：除上述必要核心測試外，不要為單一改動或新卡持續新增獨立 `test_*.gd` 檔案；必要檢查優先併入 `quick_test.gd` 既有的驗證。
- 長批次模擬（如 `tools/rogue_league.gd`）留到使用者明確要求。不要每次小改動都跑。
- 重構不能改變對局結果；玩法改動造成的差異須說明，不能用重錄掩蓋問題。
- 畫面改動只重拍相關場景並打開檢查。新增遊戲顯示中文字時才重切字型及匯入；Markdown 不進入字型子集。
- 美術只維護一套手抄本原圖，部隊／領主朝右。改圖後跑 `tools/prepare_assets.gd`、`--import` 及相關素材檢查，提交原圖、衍生圖與 manifest。
- 不得全局關閉 Godot；只停止本次任務啟動且命令列可確認的測試程序。
- 不覆蓋他人未提交的修改；每項完成後只提交自己的檔案。
