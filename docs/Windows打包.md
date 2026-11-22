# Windows 玩家版

目前版本 0.4.0，Godot 4.7.1。輸出於專案旁 `release/FiveLaneLords-0.4.0/FiveLaneLords.exe`，分享包為 `release/FiveLaneLords-Windows-0.4.0.zip`，更新說明在 `release/release-notes-0.4.0.md`。單一 x86_64 EXE，資源內嵌，保留所有舊版。

## 重建

新增中文字先執行 `python tools/build_font.py`，改圖先執行 `godot_console --headless --path . -s tools/prepare_assets.gd`，再 `godot_console --headless --path . --import`。
執行 `tools/build_windows.ps1 -Version 0.4.0`。模板在 `.runtime/windows-templates/windows_release_x86_64.exe`。圖示及檔案版本由 export_presets.cfg 設定。

## 2026-11-22 驗收（0.4.0）

- quick_test：50 項、0 失敗；test_startup 通過；test_net_match 22 項、0 失敗。
- 冒險 50 關、肉鴿 159 個怪各自的戰場都以雙方 AI 模擬過（冒險 120 秒、肉鴿 90 秒），無腳本錯誤；冒險關卡資料驗證 0 錯誤。
- 獨立 EXE 以隔離 APPDATA 啟動 120 幀，結束碼 0，日誌無錯誤或警告；檔案版本 0.4.0；EXE SHA256 `7711C5CFFB9D2BB5D0BC43D576EDE303008EB7D618D8F453193BAD1C3839BCF5`，364 MB，ZIP 296 MB。
- 字型子集已重切（新增弓手、四季、地形與機制、旗幟牌陣等文字）。
- 未量測冒險與肉鴿的新地形難度；按鈕滑入動畫與斬旗動畫未以真人操作確認。

## 2026-11-20 驗收（0.3.0）

- quick_test：50 項、0 失敗。
- 獨立 EXE 以隔離 APPDATA 啟動 120 幀，結束碼 0，日誌無錯誤或警告；檔案版本 0.3.0，標題版本常數 `game.gd` 的 `VERSION` 同步改為 0.3.0。
- ZIP 完整性檢查通過；包內 EXE SHA256 `571BFDFAAED89A35E80A84B655C1E4F5FF1F58D019B91705A7D3605644394411`，381 MB。
- 字型子集未重切：遊戲文字只缺 ▸ ▾（排序、牌組按鈕）及錄影工具的 emoji，Noto Serif TC 本身也沒有這些字，由系統字型代替。
- 未重拍畫面、未跑冒險難度量測；人工音樂試聽與完整冒險通關仍未做。

## 2026-11-12 驗收（0.2.0）

- quick_test：1475 項、0 失敗；加冕專項：失敗不觸發、首次勝利、存檔、返回及重打、文字範圍通過。
- 隊旗城牆、九位領主版面、加冕頁已重拍查看。
- 獨立 EXE 以隔離 APPDATA 啟動 120 幀，結束碼 0，執行日誌無錯誤。
- 匯出過程曾出現編輯器設定 safe save 警告，但匯出及 ZIP 完成，EXE 實際啟動通過。
- 尚未完成人工音樂試聽或完整冒險通關；難度初篩發現極端勝率，見冒險難度初篩報告。本版為可玩測試版，非難度已定稿。
