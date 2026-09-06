# 現況

*更新於 2026-09-04*

已實際跑通的完整路徑：**輸入任意 FHIR base URL → 在授權伺服器輸入帳密 → 側邊欄主畫面
→ 病人切片 grid → 病人清單 → 病人詳情與生命徵象趨勢圖**。

登入是真的：密碼輸在 Keycloak 的頁面上，**app 從頭到尾看不到它**；`id_token` 的簽章
與 issuer 都驗過才採用其中的 `fhirUser`；FHIR server 會拒絕任何它沒簽過的 token。

---

## 1. 定位怎麼收斂的

`NIS-MVP-SPEC.md` 描述的是完整護理資訊系統（含寫入、離線佇列、給藥核對）。實際動工的範圍
比它小很多，原因不是做不動，而是客戶輪廓變了：

| | 原 spec 假設 | 實際 |
|---|---|---|
| 客戶 | 醫學中心病房 | **小診所** |
| 場景 | 護理推車、床位 census | 門診、病人清單 |
| 第一版 | 寫入 + 離線同步 | **唯讀 dashboard** |
| 主 server | Siming | 先接公開 server，Siming 排 Phase B |

**為什麼先做唯讀**：不寫入就沒有 conflict、沒有佇列、沒有冪等性問題，Siming 的缺口清單從
7 條剩 2 條；法規面積也趨近於零（不做診斷建議、不代管 PHI）。而寫入權限恰好是 FHIR 生態裡
最難拿到的東西。原 spec §9 自己就預見了這點，把 M2 標成「可獨立發布的 v0.5 dashboard」。

**市場脈絡**（2026-09 查證）：衛福部推的 **FHIR Box** 已於 2026-05 開始配發給醫學中心，
年底前全數完成，2027 擴到區域醫院、2028 到基層診所。上層有國家級的 SMART on FHIR 應用市集
**THAS**，首批「臺灣 50」已於 2026-04 選出，四大類別之一就是**資料視覺化**，入選案例包含
醫院自製的住院排程 dashboard。遴選有 UI/UX 驗證關卡——那是這個專案相對於傳統 SI 廠商的優勢。

⚠️ 注意時程落差：**小診所要到 2028 才有 FHIR Box**。所以人脈方目前沒有 FHIR server 可接，
demo 階段只能靠 Siming 或公開 sandbox。

---

## 2. 做完的

| 項目 | 位置 |
|---|---|
| FHIR 命名空間、LOINC 常數、Bundle helper、容錯解碼、參考範圍三態 | `App/Packages/FHIRCore`（37 個測試） |
| REST client、search builder、錯誤三分類 | `App/Packages/FHIRClient`（22 個測試） |
| SMART：discovery、能力檢查、PKCE、`state`、`aud`、token 交換、refresh 序列化、Keychain、瀏覽器授權 | `App/Packages/SmartAuth`（44 個測試） |
| 登入畫面（base URL + preset + 進階 client_id） | `Sources/Pages/ServerSetup` |
| 側邊欄主畫面（`NavigationSplitView`） | `Sources/Pages/Main` |
| 病人清單（真實資料、切片、搜尋、四態、下拉刷新） | `Sources/Pages/PatientList` |
| 主畫面兩層導航：身分 header、大分類、病人切片 grid 與計數 | `Sources/Pages/Main` |
| 病人詳情 + 生命徵象趨勢圖（Swift Charts、參考範圍帶、四態） | `Sources/Pages/PatientDetail` |
| 四張卡片各自的終點頁：病歷（identifier 依型別分辨）、就診（開放式 period）、用藥（timing 照實呈現） | `Sources/Pages/PatientRecord`、`PatientEncounters`、`PatientMedications` |
| `id_token` 簽章與 issuer 驗證（jwks、快取、驗不過只讓身分留白） | `App/Packages/SmartAuth` |
| 開發環境：Keycloak（帳密登入）+ Siming + Postgres，一個指令起完 | `Server/docker-compose.yml`、`Server/keycloak/` |
| Siming 接上（Phase B）+ 台灣示範資料 seed | `Server/seed/`（Swift executable） |

Spectra 已歸檔五個 change：`main-navigation`、`demo-data`、`patient-detail-vitals`、
`real-auth-environment`、`resource-destinations`，產出七個正式 capability（`clinical-dashboard`、
`patient-list`、`patient-detail`、`demo-data`、`patient-record`、`encounter-status`、
`medication-list`）。
其中兩條是這個產品的法規界線，現在寫在正式規格裡而非埋在某個 change 目錄：
**使用者可見文字只陳述事實不做判讀**、**超出參考值只採用 server 提供的 referenceRange**。

三個 package 共 106 個測試，app target 另有 112 個。

四張切片卡片現在各自走到不同的終點頁，一頁對應一個 FHIR resource 家族。每一頁守住一條
**記錄沒說的事就不說**的線，而且每一條都以變異測試確認過驗收會轉紅：

| 終點 | 守住的那條線 |
|---|---|
| 病歷（`Patient`） | identifier 依 type 分辨；辨識不出用途的不顯示，不讓一個裸號碼被讀成病歷號 |
| 就診（`Encounter`） | 開放式 period 呈現為尚未結束，**不以當下時間替代**；顯示記錄的 `status`，不從 period 推導 |
| 用藥（`MedicationRequest`） | `timing` 照實呈現，**絕不展開成具體時間**——「一天三次」沒有說是哪三次，那由機構的給藥常規決定，不在 FHIR 資料裡 |

測試裡值得一提的三個：PKCE 用 **RFC 7636 附錄 B 的官方測試向量**驗證（證明符合規格而非
自洽）；`aud` 參數有獨立測試（SMART 最常被漏、漏了部分 server 直接拒絕）；**10 個並發請求
撞到 token 過期只打一次 token endpoint**。

### 真實環境驗過的（不只單元測試）

開發環境現在是 **Keycloak（授權）+ Siming（資源）**，登入要輸入真實帳密。
smart-launcher-v2 已移除——它是協定模擬器，不問密碼也不驗 token，那讓下面整欄
「反方向」長期無法驗證。

| 項目 | 結果 |
|---|---|
| 完整 standalone launch（discovery → 帳密登入 → 換 token） | 通過。四項 scope 全數授予、`aud` 正確、`fhirUser` 解出對應的 practitioner |
| 帶 Bearer token 取得病人資料 | 通過 |
| **token 過期後自動換發** | 通過。壽命 300 秒，擱置超過後下拉刷新仍正常取得資料，未被踢回登入頁 |
| **無授權會被拒絕** ← 長期掛著的那條 | **通過**。不帶 token、亂編的 token、issuer 不符的 token，三者皆 401；jwks 抓不到時 Siming 直接退出，不會有請求被放行 |
| **偽造得再像也被拒絕** | 通過。`alg=none`、猜密鑰的 HS256、自己金鑰正確簽的 RS256——即使 `iss`／`aud`／`scope`／`fhirUser` 全部填對，一律 401 |
| **PKCE 有強制** | 通過。不帶 `code_verifier` 換 token 得 400 |
| **錯誤密碼不發 code** | 通過。停在登入頁，回呼網址不帶 code |

### ⚠️ 「把使用者登出」切不斷已經發出去的裝置

實測（2026-09-06）：

| 撤銷方式 | refresh token 還能用嗎 |
|---|---|
| 從管理台登出該使用者的 session | **還能用** |
| 撤銷 consent（offline token） | 400 `invalid_grant` — 切斷 |
| 停用帳號 | 400 `invalid_grant` — 切斷 |

原因是 `offline_access`：它發的是 offline token，**設計上就活過 session 登出**。

這對「共用 iPad、人員離職」是實際的問題——以為把人登出就切斷了，其實那台裝置還能
繼續讀資料直到 refresh token 自己過期。正式部署的作業程序必須寫明：**要切斷裝置，
停用帳號或撤銷 consent，不是登出。**

（`offline_access` 本身不能拿掉——沒有它，閒置一段時間就會被踢回登入頁，
那在推車與診間輪流使用的場景下不可用。）

### 實作中撞到的真實問題

**一筆不合規的資料會毀掉整批回應。** FHIR R4 要求 `dateTime` 帶了時分秒就必須帶時區，
而 HAPI 公開 server 的資料大量違反這條。FHIRModels 嚴格照規格解析，於是整個 Bundle 拋錯——
實測 MedicationRequest 查詢是 **1/307 筆**壞資料毀掉另外 306 筆。

對一個主打「連得上任何 FHIR server」的 app，這不是邊緣案例而是常態。現在改為逐筆容錯解碼，
並把跳過的筆數反映在計數的精確性上（降級為下限值）。這件事在接真實醫院資料時只會更嚴重。

## 2.5 Siming 的能力缺口（實測 2026-09-04，2026-09-05 更新）

接上 Siming 後逐項實測的結果。記在這裡而不是默默繞過——其中一項會擋住 tech spec 的核心設計。

**2026-09-05 更新**：其中三項已由 Siming 端修復並發布為 **Siming v1.1.1**——
`PractitionerRole`、刪除後仍被搜到、`date` 帶時間被忽略。已在 main 的 binary 上重灌驗證，
Tideng 的五種查詢全數正確。

| 項目 | 影響 | 現況 |
|---|---|---|
| ~~不支援 `PractitionerRole`~~ | 側邊欄取不到職位 | **已修**（Siming v1.1.0）。但只索引 `practitioner` 一個參數，其餘 12 個在路由層就被丟棄 |
| **只支援 `transaction`，沒有 `batch`** | **牴觸 `NIS-TECH-SPEC.md` §0 第二個關鍵判斷** | 未解。唯讀期無影響；離線同步動工前必須決定，見下 |
| **`_summary=count` 與一般查詢走不同 SQL** | 同一個 query string，帶不帶 `_summary=count` 會得到**互相矛盾**的答案 | 未解。24 個 store 有 20 個漂移（全部漏 `_lastUpdated` 與 `:missing`，部分漏 `identifier`） |
| **`_count` 上限實際是 100** | 送更大的值被靜默截斷，查詢不報錯但資料少一截 | app 端已對齊為 100 |
| **`_sort` 只認五個欄位**（`_lastUpdated` / `_id` / `name` / `family` / `birthdate`） | 未知欄位**靜默丟棄**，排序失效時看不出來 | 目前只用到 `family`，可用 |
| ~~搜尋會回傳已刪除的資源~~ | 畫面顯示 server 自己認定已刪除的資料，client 無從察覺 | **已修**。`_include` 也會帶回已刪除的目標資源，一併修了 |
| ~~`date` 的值帶時間就被靜默忽略~~ | 「近 24 小時」這種必須帶時分秒的查詢整批放行 | **已修**。值解析失敗現在回 400，不再靜默丟棄 |

### 三件值得單獨記的

⚠️ **`_summary=count` 的漂移是目前最危險的一項。** 它不是「少支援某個參數」，而是**同一個查詢
的兩種問法會得到不同答案**。四張切片卡片全部靠 count，所以這條直接打在最顯眼的地方。

**「搜尋回傳已刪除資源」的成因值得記住**：`deleted = false` 被套在「挑最新版本」*之前*，
所以 `DISTINCT ON` 挑到的是墓碑*前*的那一版，而不是把整筆排除。它只在查詢**不帶任何走索引的
參數**時觸發——因為 DELETE 會清掉索引列，帶了索引參數的查詢早就把它 JOIN 掉了。也就是說
「查得越隨便，錯得越明顯」，而隨手測通常會帶條件。

**純日期的時區解讀是規範沒管到的地帶，不是 server 的偏差。** R4 §3.1.1.4.7 那句「假設 server
的時區」的前提是**查詢值與資源欄位兩邊都沒有時區**；查詢送 `date=ge2026-09-05`、而
`Encounter.period.start` 帶了 `+08:00` 時，前提不成立。Siming 一律以 UTC 解讀，在 +08 的機器上
當天上午的資料會落在範圍外（實測 8 筆只回 2 筆）。**解法在 client**：`FHIRSearch` 一律送帶偏移的
時刻（`ge2026-09-05T00:00:00+08:00`），在任何解讀下都一樣。「今天」本來就是帶時區的概念，
送出去卻不講是哪個時區，就是把解讀權交給對方。

### 由此得到的通則

**凡是 UI 對使用者宣告了範圍，那個範圍就必須在 client 端守住，不能只靠 server 的查詢參數。**

server 端的過濾對這個 app 是**效能**，不是正確性。三處宣告都已照此實作：

- 「近 24 小時」→ `Observation.recorded(onOrAfter:)`，計數與清單兩處各過濾一次
- 「今日就診」→ `Encounter.started(on:)`，同樣兩處
- 趨勢圖的時序 → client 端排序，不信任 `_sort`

這條規則寫出來之後曾經漏掉「今日就診」——它一直完全信任 `Encounter?date=`，而顯示正確
純粹因為 seed 的就診剛好全是今天。**規則寫下來不等於套用到位**，這是後來補的。

⚠️ **batch 那一項是真正的阻斷點。** tech spec §0 主張同步 flush 用 `batch` 而非 `transaction`，
理由是 transaction 全有全無——佇列裡一筆壞資料會 rollback 整批，好資料被連坐、佇列卡死。
而 Siming 目前只接受 `Bundle.type == transaction`（`TransactionRoutes.swift` 第 68 行的 guard）。

也就是說：**離線同步的核心設計在自家 server 上還跑不起來。** 兩條路——Siming 補 batch，
或改用逐筆 POST 帶 `If-None-Exist`（會犧牲一次往返送多筆的效率，但保住壞資料隔離）。
這個決定要在離線同步動工前做，不是動工時才發現。

另外兩項不是缺口但值得知道：`_count` 的預設值是 20；`_summary=true` 會把 `referenceRange`
砍掉（符合 FHIR 規範，因為它不是 Σ-marked element），所以 client 不能為了省流量帶 `_summary`。

## 3. 還沒做的

- 版面粗糙處：搜尋框飄在右上角、清單列太寬
- TW Core 驗證
- 寫入路徑、離線佇列、給藥核對、AuditEvent、session 安全（背景遮罩 / 閒置鎖定）
- MDM Managed App Configuration ← 機構透過 THAS 訂閱時會需要
- IAP 的 feature-gating 介面

---

## 4. Open Questions 的回答

對應 `NIS-MVP-SPEC.md` §8。

**Q1 AppAuth-iOS vs 自寫 PKCE** → **自寫**。只需要 authorization code + PKCE 一條路徑，約
300 行。AppAuth 是 ObjC 核心、callback-based，Swift 6 strict concurrency 下要包一層適配；
而且它不懂 SMART 的 `aud`，也不解析 token response 的 `patient` / `fhirUser` / 縮減後的
`scope`——終究要在它上面再寫一層。真正難的部分（refresh 序列化）用不用它都得自己寫。已實作並驗證。

**Q2 SwiftData vs GRDB** → **GRDB**（尚未實作，決定不變）。決定性理由：flush 需要在單一
write transaction 內完成「取 N 筆 pending → 標記 syncing」，SwiftData 沒有這個 API 保證。
而且佇列是 blob + 狀態機，不需要 object graph。

**Q3 排程量測的來源** → **app 內規則**。但有個未言明的坑：app 產生的任務在 server 端不存在，
「已完成」狀態無處可存，多裝置會各自重複顯示。必須靠「該時間窗內是否已有對應 Observation」
反推，這個規則要在動工前定義。

**Q4 Conflict 預設策略** → append-only 下 last-write-wins 不會觸發。真正會發生的是**兩位
護理師對同一床同一時間窗各記一筆**——server 無從判斷是重複還是真的量兩次。這不是同步問題
是 UI 問題：輸入前檢查本地 cache 與佇列，若該時間窗已有紀錄就提示（不阻擋）。

**Q5 timing 展開的邊界** → 照 TECH-SPEC §5.4 的三檔切分。補一條缺漏：`frequency=3, period=1,
periodUnit=d` 而**沒有 `timeOfDay`**（q8h）是最常見的資料形態，它展開成哪三個時間點不是 FHIR
資料能回答的，是機構給藥政策——需要一組可設定的病房排程錨點常數，UI 標明「依病房常規」。

**Q6 FHIRModels 版本漂移** → exact pin 正確，但 diff 兩邊 `Package.resolved` 是錯的防線
（見 TECH-SPEC §2 修訂）。真正的防線是 contract test。

**Q7 第 3 週會咬人的問題** →

1. **`Encounter?location=` 很可能不能用**。`Encounter.location.location` 這個 search param
   自寫 server 常常沒實作，而整個病房 census 建立在它上面。備案：先 `Location?partof={ward}`
   取床位，再撈 in-progress Encounter 在 client 端 join。
2. **`offline_access` 未必核發**。沒有 refresh token + 閒置鎖定 = demo 中途被踢回登入頁。
   已驗證本機 launcher 與 SMART sandbox 都有給（`permission-offline`）。
3. **藥品條碼沒有資料來源**。`MedicationRequest.medication` 是院內碼的 CodeableConcept，
   藥盒上是 GTIN／健保碼，中間缺一張院內藥品主檔映射表。M5 會直接撞牆。
4. **共用 iPad 上用 Face ID 解鎖 session 是資安漏洞**。Face ID 認的是「這台裝置登記過的臉」
   不是「當前登入的護理師」——A 的 session 被鎖定後，登記過臉的 B 可以直接解鎖並以 A 的身分
   寫入 `performer`。共用模式只能用 PIN 或重新登入。**這是整份 spec 裡最嚴重的單一問題。**
5. **`Observation` 打錯了沒有更正路徑**。append-only 的代價。FHIR 正解是把 `status` 改成
   `entered-in-error`，但那是 update，會把迴避掉的 conflict 面積叫回來。需要明確寫進 non-goals。
6. **疼痛分數不是 vital-sign**。LOINC 72514-3 的 category 慣例是 `survey`，硬塞進
   vital-signs profile 會被 TW Core 驗證擋下。

---

## 5. 踩到的坑

實作層級的硬性約束（FHIR 型別撞名、Swift Testing 的 `.serialized` 範圍、巢狀 `#require`、
launcher base URL 的 `sim` 段）記在 [`../App/CLAUDE.md`](../App/CLAUDE.md)，那是每次動工都會
再遇到的東西。

## 6. 下一步

1. 對外的 README —— repo 要公開，而現在沒有一份文件說得出這個專案在展示什麼
2. 修版面粗糙處（搜尋框位置、清單列寬度）
3. TW Core profile 驗證（需啟用 HL7 Validator sidecar）

部署到公開主機是**業務決定**而非技術前置：正式環境由診所提供 FHIR server 與 IdP，
`Server/` 永遠不出貨。什麼時候需要把 iPad 留在對方手上，什麼時候再做。
