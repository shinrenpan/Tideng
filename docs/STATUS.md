# 現況

*更新於 2026-09-04*

第一個 PoC 已完成並實際跑通：**輸入任意 FHIR base URL → SMART standalone 登入 → 側邊欄
主畫面 + 病人清單**。登入不是模擬的——`Practitioner` reference 由 `id_token` 的 `fhirUser`
claim 解出，病人清單帶著 Bearer token 從 FHIR server 取得。

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
| FHIR 命名空間、LOINC 常數、Bundle helper | `App/Packages/FHIRCore` |
| REST client、search builder、錯誤三分類 | `App/Packages/FHIRClient`（11 個測試） |
| SMART：discovery、能力檢查、PKCE、`state`、`aud`、token 交換、refresh 序列化、Keychain、瀏覽器授權 | `App/Packages/SmartAuth`（31 個測試） |
| 登入畫面（base URL + preset + 進階 client_id） | `Sources/Pages/ServerSetup` |
| 側邊欄主畫面（`NavigationSplitView`） | `Sources/Pages/Main` |
| 病人清單（真實資料、切片、搜尋、四態、下拉刷新） | `Sources/Pages/PatientList` |
| 主畫面兩層導航：身分 header、大分類、病人切片 grid 與計數 | `Sources/Pages/Main` |
| 本機 SMART launcher | `Server/docker-compose.yml` |

Spectra 的第一個 change `main-navigation` 已完成並歸檔，產出兩個正式 capability
（`clinical-dashboard`、`patient-list`，共 13 條 requirement、40 個 scenario）。
其中兩條是這個產品的法規界線，現在寫在正式規格裡而非埋在某個 change 目錄：
**使用者可見文字只陳述事實不做判讀**、**超出參考值只採用 server 提供的 referenceRange**。

測試裡值得一提的三個：PKCE 用 **RFC 7636 附錄 B 的官方測試向量**驗證（證明符合規格而非
自洽）；`aud` 參數有獨立測試（SMART 最常被漏、漏了部分 server 直接拒絕）；**10 個並發請求
撞到 token 過期只打一次 token endpoint**。

### 真實環境驗過的（不只單元測試）

| 項目 | 結果 |
|---|---|
| 完整 standalone launch（discovery → 授權 → 換 token） | 通過，`Practitioner` reference 從 `id_token` 解出並顯示 |
| 帶 Bearer token 取得病人資料 | 通過。launcher 對帶進來的 token 會做 JWT 驗證（亂編的 token 回 `401 Invalid token: jwt malformed`），所以拿到 200 就代表 token 有效 |
| **token 過期後自動換發** | 通過。access token 壽命設 5 分鐘（`ACCESS_TOKEN_LIFETIME`），擱置超過後下拉刷新仍正常取得資料，未被踢回登入頁 |

尚未驗證的反方向：**無授權會被拒絕**。launcher 在完全不帶 token 時放行（開發模式），
要驗證強制授權得等 Phase B 接上 Siming，或用 launcher 的 `auth_error` 模擬。

### 實作中撞到的真實問題

**一筆不合規的資料會毀掉整批回應。** FHIR R4 要求 `dateTime` 帶了時分秒就必須帶時區，
而 HAPI 公開 server 的資料大量違反這條。FHIRModels 嚴格照規格解析，於是整個 Bundle 拋錯——
實測 MedicationRequest 查詢是 **1/307 筆**壞資料毀掉另外 306 筆。

對一個主打「連得上任何 FHIR server」的 app，這不是邊緣案例而是常態。現在改為逐筆容錯解碼，
並把跳過的筆數反映在計數的精確性上（降級為下限值）。這件事在接真實醫院資料時只會更嚴重。

## 3. 還沒做的

- Siming 接上（Phase B）+ 台灣 seed 資料 ← **下一步**。現在「超出參考值」永遠顯示 `—`，
  因為 HAPI 的 Observation 幾乎不帶 `referenceRange`；而 `<PID.5.2>DANA</PID.5.2>` 那種
  髒資料拿給診所看會扣分
- 病人詳情 + 生命徵象趨勢圖（需要 seed 的時序資料才看得出效果）
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

1. **Siming 接上 + 台灣 seed 資料**——順序刻意排在趨勢圖之前：趨勢圖要有 48 小時的時序
   資料才看得出效果，而那要靠 seed；反過來做的話，圖會畫在一堆 `????? ???????` 上
2. 病人詳情 + 生命徵象趨勢圖（Swift Charts）——dashboard 真正的賣點
3. 修版面粗糙處
