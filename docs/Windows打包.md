# Windows 玩家版

目前版本 0.2.0，Godot 4.7.1。輸出於專案旁 `release/FiveLaneLords-0.2.0/FiveLaneLords.exe`，分享包為 `release/FiveLaneLords-Windows-0.2.0.zip`。單一 x86_64 EXE，資源內嵌，保留所有舊版。

## 重建

新增中文字先執行 `python tools/build_font.py`，改圖先執行 `godot_console --headless --path . -s tools/prepare_assets.gd`，再 `godot_console --headless --path . --import`。
執行 `tools/build_windows.ps1 -Version 0.2.0`。模板在 `.runtime/windows-templates/windows_release_x86_64.exe`。圖示及檔案版本由 export_presets.cfg 設定。

## 2026-11-12 驗收

- quick_test：1475 項、0 失敗；加冕專項：失敗不觸發、首次勝利、存檔、返回及重打、文字範圍通過。
- 隊旗城牆、九位領主版面、加冕頁已重拍查看。
- 獨立 EXE 以隔離 APPDATA 啟動 120 幀，結束碼 0，執行日誌無錯誤。
- 匯出過程曾出現編輯器設定 safe save 警告，但匯出及 ZIP 完成，EXE 實際啟動通過。
- 尚未完成人工音樂試聽或完整冒險通關；難度初篩發現極端勝率，見冒險難度初篩報告。本版為可玩測試版，非難度已定稿。
