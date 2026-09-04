## Context

目前唯一驗證過的後端是 HAPI 公開 server。它的資料是給開發者壓測用的：病人叫
`<PID.5.2>DANA</PID.5.2>`、年齡 0 歲、幾乎沒有 `referenceRange`。拿這個畫面給診所看，
對方的注意力會全部落在資料上。

Siming 已在本機且能力足夠（23 個 resource、`_include`、`_summary=count`、`total` 與
cursor 分頁、`If-None-Exist`），FHIRModels 版本鎖 0.9.3 與 app 一致。但它現有的 seed
只塞 Patient、姓名是羅馬拼音、沒有任何 Observation。

## Goals / Non-Goals

**Goals:**

- demo 畫面上的資料讀起來像台灣診所的真實紀錄
- 「超出參考值」這張卡片終於有數字可看
- 用第二台 server 實證「同一個 app 接不同 server」

**Non-Goals:**

- 不改動 app 的 capability 行為
- 不補 Siming 的 `PractitionerRole` 或 batch Bundle
- 不追求資料量——20 位病人足夠
- 不做 TW Core 的即時 profile 驗證

## Decisions

### seed 用 Swift executable 產生，不用 shell 拼 JSON

手寫 JSON template 產生資料看似最快，但我們剛剛才被資料格式坑過一次：HAPI 的
`dateTime` 缺時區導致整批解碼失敗。自己造資料時重蹈覆轍的機率不低——尤其 `dateTime`
的時區、`Quantity` 的單位系統、`CodeableConcept` 的 coding 結構都很容易寫錯，
而錯誤只有在 app 端解碼失敗時才會現形。

改用 Swift executable，以 `ModelsR4` 的型別建構資源再 encode。編譯器擋掉結構錯誤，
`FHIRDateTime` 的 encode 保證帶時區。

同時評估引入 `TWCoreFHIRModels`（同作者、涵蓋 TW Core IG 1.0.0 的 33 個 resource），
用它的 `declareProfile()` 宣告 profile、`validateTWCore()` 在送出前靜態檢查 SHALL 欄位。
若引入成本過高（例如它與 FHIRModels 0.9.3 的相容性有問題），退回只用 ModelsR4 並
手動填 `meta.profile`——那不影響 demo 的可信度，只少了自動檢查。

### 冪等性用 `If-None-Exist`，順便驗證 tech spec 的核心假設

seed 必須可重跑，否則每次調整資料都要重建資料庫。

Siming 全部 23 個 resource 都支援 `If-None-Exist`（0 match → 201 建立、1 match → 200 回既有、
多筆 → 412）。每個 seed 資源帶一個穩定的 client-assigned identifier，送出時以它做
conditional create。

這同時是 `NIS-TECH-SPEC.md` §0 第三個關鍵設計判斷（冪等性靠 client identifier +
conditional create）的**第一次真實驗證**。那條判斷是整個離線同步設計的根基，卻從未
對真的 server 跑過。seed 腳本是驗證它的低風險場合。

### 資料密度必須配合 `_count` 的實際上限

Siming 的 `_count` 上限是 **100**（route 檔硬寫；`config.yml` 裡的 `maxCount: 1000`
是死設定，`SimingConfig` 根本沒讀它）。app 端的 `recentVitalSigns` 目前送 `_count=500`，
接上 Siming 後會被靜默截到 100——查詢不會報錯，只是資料少一半，而計數會安靜地低估。

兩邊一起調整：

- app 的取樣上限從 500 改為 100，與 server 的實際能力對齊
- seed 的資料密度設計成「近 24 小時內的 vital-signs 總數低於 100」

具體配置：20 位病人，其中約 8 位有近 24 小時的觀測值（對應「今日就診」），每位 2–3 個
時間點、每次 3–5 種生命徵象，合計約 80 筆。其餘病人的觀測值落在 24–48 小時前——
它們餵給日後的趨勢圖（查單一病人，不受此上限影響），但不進入 24 小時切片。

這個分佈本來就比「每位病人每天量五種」更貼近診所實況。

### Siming 獨立啟動，launcher 從 host 連過去

不把 Siming 塞進 Tideng 的 compose 用 `build: ../../Siming`——那假設了 Siming 的 clone
位置，而那個假設在別台機器上會直接失效。

改為：Siming 用它自己的 `scripts/setup.sh` 起在 host 的 8080；Tideng 的 launcher 把
`FHIR_SERVER_R4` 指向 `http://host.docker.internal:8080`。兩個 repo 各自管自己的生命週期，
也各自可以獨立更新。

代價是多一個啟動步驟，用文件補足。

### UI 宣告的範圍必須由 client 自己守住

**實作階段發現。** Siming 的 `Observation?date=` 宣稱支援卻完全無效：參數在白名單裡、
`Prefer: handling=strict` 不報錯，但查未來時間照樣回傳全部資料。

這比「不支援」危險——不支援至少會回 400，而靜默無效會讓「近 24 小時」這個卡片文案
在使用者面前變成謊話，且沒有任何跡象。

通則：**凡是 UI 對使用者宣告了範圍，那個範圍就必須在 client 端守住。** server 的查詢
參數是效能最佳化（少傳一點資料），不是正確性的依據。

實作上加了 `Observation.recordedAt` 與 `recorded(onOrAfter:)`，在計數與清單兩處各過濾一次。
時間不明的觀測值一律不計入——寧可少算，也不要把不知道時間的資料算進一個宣告了時間範圍
的數字。而少算這件事本來就由 `.atLeast` 的計數語意承接。

### Siming 的能力缺口記錄而非默默繞過

三項缺口寫進 `docs/STATUS.md`：

1. **沒有 `PractitionerRole`** — app 已能降級（職位行消失、姓名照顯示），不需要 server 補
2. **只支援 `transaction`，沒有 `batch`** — 唯讀版無影響，但 `NIS-TECH-SPEC.md` §0 第二個
   關鍵判斷（用 batch 讓壞資料不連坐）在這台 server 上目前**行不通**。這是 tech spec 與
   實際 server 能力的落差，離線同步動工前必須解決
3. **`_sort` 只認五個欄位，未知欄位靜默丟棄** — 不報錯，所以排序失效時看不出來

## Implementation Contract

**行為**

- 執行 seed 腳本後，對 Siming 查詢 `Patient` 會得到 20 位中文姓名、帶病歷號、年齡分佈合理的病人
- 近 24 小時的 vital-signs 查詢回傳約 80 筆觀測值，其中部分帶 `referenceRange` 且數值落在範圍外
- app 連上 Siming 後，「超出參考值」卡片顯示正整數而非 `—`
- 重複執行 seed 腳本，資源總數不變

**介面與資料形狀**

- seed 為獨立的 Swift executable，不屬於 app target，不進 app 的依賴圖
- 每個 seed 資源帶一個穩定的 identifier（system 固定、value 由資源種類與序號決定），
  送出時以 `If-None-Exist: identifier=<system>|<value>` 做 conditional create
- 觀測值使用 `FHIRCore` 已宣告的 LOINC 常數與 `vital-signs` category，不另外定義字串
- 腳本輸出每種 resource 的「建立 / 已存在」筆數

**失敗模式**

- server 不可達 → 腳本非零退出並指出無法連線的位址，不留下半套資料的錯覺
- 個別資源被拒（4xx）→ 回報該資源的 identifier 與 server 的 OperationOutcome，繼續處理其餘
- 重複執行時 server 回 200（已存在）→ 計入「已存在」，不視為錯誤

**驗收準則**

- 腳本連跑兩次，第二次全部回報「已存在」，且 `Patient?_summary=count` 的 total 不變
- app 連上 Siming 後截圖：病人清單顯示中文姓名與年齡、四張卡片皆有數字、「超出參考值」為正整數
- 同一個 build 分別連公開 sandbox 與 Siming 各登入一次，兩邊都能列出病人
- `FHIRSearchTests` 斷言生命徵象查詢的 `_count` 為 100

**範圍邊界**

- 範圍內：`Server/seed/`、`Server/docker-compose.yml` 與其 README、`FHIRSearch` 的取樣上限與其測試、伺服器 preset、`docs/STATUS.md`、`docs/NIS-TECH-SPEC.md` 的缺口記錄
- 範圍外：app 的任何 capability 行為、寫入路徑、病人詳情與趨勢圖、Siming 原始碼的任何修改

## Risks / Trade-offs

- **`TWCoreFHIRModels` 可能與 FHIRModels 0.9.3 不相容**（它自己 lock 在 0.9.2） → 先試接，不行就退回純 ModelsR4 並手填 `meta.profile`；demo 可信度不受影響
- **`host.docker.internal` 在 Linux 上不通** → 開發機是 macOS，文件註明此限制
- **seed 資料的「真實感」由我判斷，沒有臨床專業背書** → 目標是不讓資料本身變成話題，不是臨床正確；真要拿去談之前應請人脈方的醫護看一眼
- **`_count` 對齊為 100 會讓連公開 server 時的取樣變小** → 公開 server 的資料本來就不進 demo，且較小的取樣讓首屏更快

## Migration Plan

無資料遷移。切換 server 只影響開發環境的 compose 設定；app 端不需要重新登入，因為
憑證是以 server profile 為 key 分開存放的。

回退方式為把 `FHIR_SERVER_R4` 指回公開 server 並重啟 launcher。

## Open Questions

- `TWCoreFHIRModels` 與 FHIRModels 0.9.3 的實際相容性未驗證，接上時才知道。
- Siming 的 TW Core profile 驗證需要 HL7 Validator sidecar（compose 裡預設註解），
  是否值得為 demo 啟用尚未評估——啟用會拖慢啟動，但能保證 seed 資料真的合規。
