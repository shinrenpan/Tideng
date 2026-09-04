## 1. 觀測值的取得與整理

- [x] 1.1 生命徵象查詢不依賴 server 排序，取回的觀測值在 client 端依時間排序。落實 design 決策「排序必須在 client 端做」。驗證：TidengTests 注入時間亂序的回應，斷言 State 中的資料點依時間遞增
- [x] 1.2 缺少數值或缺少時間的觀測值在轉換階段被濾除，不進入 State。驗證：TidengTests 注入含缺值、缺時間、正常三種觀測值的回應，斷言只有正常者留下
- [x] 1.3 觀測值依種類分組，每組帶自己的顯示名稱、單位與（若 server 有給的）參考範圍。滿足 Requirement: Vital signs are shown as a time series 的分組部分。驗證：TidengTests 斷言四種生命徵象各自成組、單位正確、有無參考範圍如實反映

## 2. 詳情頁的狀態

- [x] 2.1 詳情頁以 primitive 接收身分資料，不接收清單的 Domain Model。滿足 Requirement: The selection crosses the feature boundary as primitives。落實 design 決策「詳情頁的資料以 primitive 傳入，觀測值自己查」。驗證：TidengTests 斷言 HostController 建構參數皆為 primitive 且 State 正確反映
- [x] 2.2 身分資料的呈現與清單一致，缺漏欄位省略而非填佔位字串。滿足 Requirement: Detail shows who the patient is。驗證：TidengTests 斷言缺生日與缺病歷號時對應欄位為 nil
- [x] 2.3 生命徵象區的四態可辨，且已有內容時失敗不清空。滿足 Requirement: The vital signs section handles four states。驗證：TidengTests 涵蓋載入中、成功無資料、首次失敗、有內容時失敗四種情境

## 3. 趨勢圖

- [x] 3.1 每種生命徵象各自一張圖，標註名稱與單位，點依時間排列。落實 design 決策「每種生命徵象一張獨立的圖」。驗證：模擬器截圖確認四種項目分開呈現且橫軸為時間
- [x] 3.2 server 有提供參考範圍時畫出區間帶，沒有提供時不畫也不套用任何內建值。滿足 Requirement: Reference ranges are drawn as bounds, never as verdicts 的前兩個情境。落實 design 決策「參考範圍畫成區間帶，不對個別點著色」。驗證：截圖確認體溫等三項有帶子、血氧沒有
- [ ] 3.3 落在區間帶外的點外觀與其他點完全相同，無不同顏色、圖示或標籤。滿足同一 Requirement 的第三個情境。驗證：對 seed 中體溫超出範圍的病人截圖，確認該點與其他點無視覺差異
- [ ] 3.4 單一觀測值仍渲染為一個點，不出現空圖或破圖。驗證：以 Preview 注入只有一筆資料的種類，確認呈現正常

## 4. 導航

- [x] 4.1 病人清單的列可點擊且外觀上看得出可點，選取後開啟該病人的詳情。滿足 Requirement: List rows open the patient。驗證：模擬器操作一次進入與返回
- [ ] 4.2 從詳情返回後，清單的切片與關鍵字維持原樣。滿足 Requirement: Returning to the list preserves its state。落實 design 決策「導航沿用內容區的 NavigationStack」。驗證：模擬器操作——輸入關鍵字、進入詳情、返回，確認關鍵字與過濾結果仍在

## 5. 文案與整體驗證

- [x] 5.1 詳情頁新增的所有使用者可見文案在 en 與 zh-Hant 皆到位，且不含任何判讀用語（異常、偏高、偏低、疑似、需注意、建議）。滿足 Requirement: No interpretive wording anywhere in the view。驗證：xcstringstool sync 後 stale 為 0、未翻譯為 0，並人工複查新增條目用字
- [ ] 5.2 完整流程對 seed 資料在模擬器上以英文與繁中各跑一次並截圖，確認趨勢圖在兩種語言與深淺色下皆正確。驗證：以 -AppleLanguages 分別啟動截圖比對
