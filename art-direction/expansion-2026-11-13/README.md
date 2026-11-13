# 羊皮紙戰記：52 張選定概念素材

集中保存本次對話已選定的獨立無字圖片，使用內建 image_gen 生成，沿用專案手抄本墨線及霧面顏料風格。圖片本身不加文字或註解。這批是概念素材，尚未接入遊戲、設定數值或通過正式素材驗收；以 `.gdignore` 隔離 Godot 匯入。

## 圖片

下載資料夾後，用瀏覽器開啟 [index.html](index.html)。亦可直接在 GitHub 查看各資料夾 PNG。

| 分類 | 圖片數 | 路徑 |
|---|---:|---|
| 新兵種與怪物候選 | 8 | [units](units) |
| 新建築 | 8 | [buildings](buildings) |
| 領主駐守據點 | 5 | [garrisons](garrisons) |
| 有陣營差異的可移動火器兵種 | 6 | [gunpowder](gunpowder) |
| 血奴方向的黑暗兵種、建築及法術 | 11 | [dark-blood-thralls](dark-blood-thralls) |
| 商人領主與拉錢貨車的騾馬 | 2 | [neutral-merchant](neutral-merchant) |
| 商人傭兵團 | 3 | [merchant-mercenaries](merchant-mercenaries) |
| 其他陣營叛逃傭兵 | 4 | [merchant-deserters](merchant-deserters) |
| 刺客、獵人、破法者與炸藥桶 | 5 | [merchant-specialists](merchant-specialists) |

[manifest.json](manifest.json) 記錄尺寸、檔案大小、SHA-256 與選稿狀態；各組提示詞另存 JSON 或原有 Markdown 紀錄。

## 選稿邊界

排除誤做的既有兵種重製圖、已淘汰火器初稿、腐屍方向棄稿，以及六張已知外圍霧光待清理的圖片：棘背翼獸、豐收／鐵壁／邊境駐守據點、商旅驛站、炸藥桶搬運者。它們不在此上傳包內，本機原檔仍保留。尚未畫出的馴獸領主據點也未列入。

`selected-concept` 代表依本次目視選稿收錄，不代表正式可用素材認證。所有圖片仍須逐像素透明邊緣、70–80px 顯示、隊色、肢體／道具與遮擋驗收。骷髏狗扛砲的砲口與頭部輪廓、符印輪轂師背架、引魂井吊掛等細節須在正式整合前確認。子文件保留歷史生成說明，若舊張數與本頁不同，以本頁和 manifest 為準。

## 與現行遊戲的關係

現行陣營為經典、黑暗、魔法、魔物；魔物既有貪食巢穴（`glutton_nest.gd`，當前設定 unreleased）。本包的額外怪物、經濟用途、傭兵身份與駐守收益均為提案，不覆蓋現有規則。

素材正式採用時，依 `AGENTS.md` 與 `docs/美術驗收.md` 放入 `assets/manuscript-v1/`，執行準備、匯入及相關檢查。此提交只整理概念素材，不修改程式、正式原圖或衍生素材，因此未執行 Godot 對局測試。
