# 第二集｜符文與獸群

符文領主 × 馴獸領主；延續第一集的手抄本戰場、章節字幕與卡牌特寫。

## 交付檔案
- episode02_rune_vs_beast.mp4：正式成片，1600×900、60 fps。
- episode02_rune_cover.png：無時間碼片頭截圖。
- episode02_rune_vs_beast.md：實際出牌、大招與破城時間表。
- episode02_rune_vs_beast.json：逐事件影格資料，seconds 為原始對局時間，film_seconds 為成片對應位置。
- ../tools/episode2_director.gd：可重現錄製的獨立導演腳本。

## 編導與節奏
種子 22，符文對馴獸。普通 AI 對局；符文方在原始對局第 65 秒開始保留金幣，達到原生技能條件才施放符文前線，再恢復 AI。馴獸方全程普通 AI。未修改任何金幣、冷卻、傷害或勝負。

開場正常速度，一般行軍以三倍速呈現；首次卡牌特寫與破城恢復正常速度三秒，領主技能恢復正常速度五秒。每一步仍使用原本的 60 Hz 戰鬥更新，不跳過模擬。保留結算六秒。未添加旁白，沿用遊戲配樂與音效。

## 重現
在專案根目錄執行，log 與電影輸出建議使用絕對路徑：

```powershell
godot_console --headless --path . --log-file recordings/ep2_verify.log -s tools/episode2_director.gd -- --verify
godot_console --path . --minimized --log-file recordings/ep2_render.log --write-movie recordings/ep2_render.avi --fixed-fps 60 --disable-vsync -s tools/episode2_director.gd
```

用 FFmpeg skill 的 export.py --preset youtube --no-scale 將 AVI 轉為 H.264/AAC MP4。

## 驗收

核心檢查：831 項通過，0 失敗。正式錄製的 162 個事件、26,269 個模擬影格與勝負完全符合驗證對局。

原生長身龍吐息繪圖偶爾回報多邊形三角化警告，為既有 battle_details.gd 特效；本集未修改共享戰鬥或特效程式。
