## Why

現在拿給診所看的畫面上，病人叫 `<PID.5.2>DANA</PID.5.2>` 和 `????? ???????`，年齡是 0 歲，而「超出參考值」永遠顯示 `—`。那不是介面的問題，是資料的問題——HAPI 公開 server 的測試資料本來就是給開發者壓測用的，不是給人看的。

對方看到那種畫面，注意力會全部跑到資料上，看不到我們真正想讓他評估的東西。Demo 的資料品質決定了對話能不能進行到第二層。

同時這也是把 Siming 接上的時機（tech spec 的 Phase B）。目前唯一驗證過的後端是公開 server，而「同一個 app 接不同 server」是這個產品的核心主張——沒有第二個 server 實測過，那句話只是說說。

## What Changes

- 開發環境從「launcher → HAPI 公開 server」切換為「launcher → Siming」，切換方式為改一個環境變數
- 新增 seed 腳本，產生可 demo 的台灣診所資料：中文姓名、台灣病歷號格式、合理的年齡分布、48 小時的 vital-signs 時序，且部分觀測值帶 `referenceRange` 並落在範圍外
- seed 的病人資料宣告 TW Core profile；產生方式評估使用 `TWCoreFHIRModels`（同作者的 client 端 TW Core 擴充庫，涵蓋 IG 1.0.0 全部 33 個 resource）
- 生命徵象查詢的取樣上限從 500 對齊到 100——Siming 的 `_count` 實際上限是 100（route 檔硬寫），設定檔裡的 1000 是死設定不會被讀取
- 把 Siming 的能力缺口記進 `docs/STATUS.md`：不支援 `PractitionerRole`、只支援 `transaction` 不支援 `batch`、`_sort` 僅認五個欄位且未知欄位靜默丟棄

## Non-Goals

- **不改動 app 的任何 capability 行為**。`clinical-dashboard` 與 `patient-list` 的規格不變——這個 change 讓既有行為終於有資料可呈現，不是改變行為
- **不做寫入路徑**。seed 由腳本直接對 server 灌入，app 端維持唯讀
- **不補 Siming 的 `PractitionerRole`**。那是 server 端的工作，且 app 已能在缺它時優雅降級（職位行消失、姓名照顯示）
- **不補 Siming 的 batch Bundle 支援**。唯讀版用不到；但這個缺口會影響 tech spec 的離線同步設計，故列入文件而非默默略過
- **不做 TW Core profile 的即時驗證**。Siming 的 profile 驗證要靠 HL7 Validator sidecar，預設是關的；seed 資料的合規性以產生時的靜態檢查為準
- **不追求資料量**。目標是「看起來像真的診所」，不是壓測——20 位病人足夠，300 位反而讓 demo 難以聚焦

## Capabilities

### New Capabilities

- `demo-data`: 可信的示範資料。定義 seed 資料必須滿足哪些條件，才能讓 demo 展示的是產品而不是資料的缺陷

### Modified Capabilities

(none)

## Impact

- Affected specs: `demo-data`
- Affected code:
  - New:
    - Server/seed/seed.sh
    - Server/seed/README.md
  - Modified:
    - Server/docker-compose.yml
    - Server/README.md
    - App/Packages/FHIRClient/Sources/FHIRClient/FHIRSearch.swift
    - App/Packages/FHIRClient/Tests/FHIRClientTests/FHIRSearchTests.swift
    - App/Sources/Pages/ServerSetup/ServerSetupViewModel+Models.swift
    - docs/STATUS.md
    - docs/NIS-TECH-SPEC.md
  - Removed: (none)
