## 1. 對齊 server 的實際能力

- [ ] 1.1 生命徵象查詢的取樣上限與 Siming 的實際 `_count` 上限（100）一致，不再送出會被靜默截斷的 500。落實 design 決策「資料密度必須配合 `_count` 的實際上限」。驗證：FHIRSearchTests 斷言 `recentVitalSigns` 的 `_count` 為 100
- [ ] 1.2 Siming 的三項能力缺口記錄於文件：不支援 `PractitionerRole`、只支援 `transaction` 不支援 `batch`、`_sort` 僅認五個欄位且未知欄位靜默丟棄。落實 design 決策「Siming 的能力缺口記錄而非默默繞過」——其中 batch 的缺口需標明它與 `NIS-TECH-SPEC.md` §0 第二個關鍵判斷衝突。驗證：`docs/STATUS.md` 與 `docs/NIS-TECH-SPEC.md` 內容複查，三項缺口皆可被搜尋到且說明了後果

## 2. 開發環境接上 Siming

- [ ] 2.1 Siming 可在本機啟動並回應健康檢查，launcher 的後端指向它而非公開 server。落實 design 決策「Siming 獨立啟動，launcher 從 host 連過去」。驗證：curl Siming 的 `/metadata` 得到 CapabilityStatement，且經 launcher proxy 查詢 `Patient` 回傳 Bundle
- [ ] 2.2 伺服器 preset 涵蓋接上 Siming 的位址，且與公開 sandbox 並列可切換。驗證：模擬器上兩個 preset 各登入一次皆成功——滿足 Requirement: The same app connects to a second server unchanged
- [ ] 2.3 `Server/README.md` 說明兩段式啟動（先起 Siming、再起 launcher）與 `host.docker.internal` 的 macOS 限制。驗證：照文件從零走一次，服務可用

## 3. seed 工具

- [ ] 3.1 seed 為獨立的 Swift executable，以 ModelsR4 型別建構資源後 encode，不手寫 JSON。落實 design 決策「seed 用 Swift executable 產生，不用 shell 拼 JSON」。驗證：`swift run` 可執行並印出用法；產生的 JSON 以 FHIRModels 解碼一次確認 round-trip 無損
- [ ] 3.2 評估並決定是否引入 `TWCoreFHIRModels`：能相容 FHIRModels 0.9.3 就用它宣告 profile 與靜態檢查，不相容則退回純 ModelsR4 手填 `meta.profile`。驗證：決定與理由寫入 design 的 Open Questions 對應段落；若引入，seed 產生的 Patient 通過 `validateTWCore()`
- [ ] 3.3 seed 可重複執行不產生重複資料，以 client-assigned identifier 加 `If-None-Exist` 達成。滿足 Requirement: Seeding is repeatable。落實 design 決策「冪等性用 `If-None-Exist`，順便驗證 tech spec 的核心假設」。這同時是 `NIS-TECH-SPEC.md` §0 冪等性判斷的首次真實驗證。驗證：連跑兩次，第二次全部回報「已存在」，且 `Patient?_summary=count` 的 total 不變
- [ ] 3.4 seed 完成後回報每種 resource 的建立與已存在筆數，且 server 不可達時非零退出並指出位址。驗證：對不存在的位址執行，確認退出碼非零且訊息可辨識

## 4. 資料內容

- [ ] 4.1 產生 20 位病人，具中文姓名、台灣病歷號格式的 identifier、分佈合理的出生日期。滿足 Requirement: Demo data reads as a real Taiwanese clinic。驗證：查詢 `Patient` 後人工檢視清單，確認無佔位字串、無 0 歲、每位皆有病歷號
- [ ] 4.2 每位病人具備跨越至少 48 小時的 vital-signs 時序，使用 `FHIRCore` 既有的 LOINC 常數與 `vital-signs` category。滿足 Requirement: Vital signs form a trend, not isolated points。驗證：查詢單一病人的生命徵象，確認回傳多個時間點且 app 既有查詢無需特例即可取得
- [ ] 4.3 近 24 小時內的觀測值總數低於 100，避免被 `_count` 上限截斷；約 8 位病人有近 24 小時資料，其餘落在 24–48 小時前。驗證：`Observation?category=vital-signs&date=ge<24h前>&_summary=count` 的 total 小於 100
- [ ] 4.4 部分觀測值帶 `referenceRange` 且數值落在範圍外，另有落在範圍內者，以及刻意不帶 `referenceRange` 者。滿足 Requirement: Some observations carry a reference range and fall outside it。驗證：app 連上後「超出參考值」卡片顯示正整數；且不帶範圍的高數值病人未被計入

## 5. 端到端驗證

- [ ] 5.1 app 連上 Siming 後四張卡片皆有數字、「超出參考值」為正整數、病人清單顯示中文姓名與年齡。驗證：模擬器截圖，並與先前連公開 server 的截圖對照
- [ ] 5.2 缺少 `PractitionerRole` 時側邊欄仍顯示姓名、僅省略職位行。滿足 Requirement: Capabilities the second server lacks degrade rather than break。驗證：模擬器截圖確認 header 顯示姓名而非 raw reference
