# Tideng（提燈）— 技術規格與實作細節（TECH-SPEC）

> 本文件是 `NIS-MVP-SPEC.md`（產品 spec）的配套。產品 spec 定義「做什麼」，本文件定義「怎麼做」。
> 給 Claude Code：本文件的設計決策已含理由；若你不同意某項決策，提出反對理由後再改，不要靜默偏離。

---

## 0. 三個貫穿全文的關鍵設計判斷

1. **MVP 的所有寫入都是 append-only（create），沒有 update。**
   生命徵象 = 新 `Observation`；給藥紀錄 = 新 `MedicationAdministration`。
   → 離線同步的 conflict 面積趨近於零（兩台裝置各自 create 不互斥），`If-Match`/ETag 樂觀鎖降級為「未來編輯功能的前置」而非 MVP 阻斷項。這大幅簡化同步引擎，也縮小 Siming 的缺口清單。

2. **同步 flush 用 `batch` Bundle，不用 `transaction`。**
   `transaction` 是全有全無——佇列裡一筆壞資料會 rollback 整批，造成好資料被連坐、佇列卡死。
   `batch` 每個 entry 獨立成敗、獨立回應狀態 → 逐筆標記 synced/failed，壞資料隔離重試。

   > ⚠️ **實測落差（2026-09-04）**：Siming 目前**只接受 `Bundle.type == transaction`**，
   > 不支援 batch（`TransactionRoutes.swift` 的 guard）。這條判斷在自家 server 上還跑不起來。
   >
   > 兩條路：Siming 補 batch 語意，或改用逐筆 POST 帶 `If-None-Exist`——後者犧牲「一次往返
   > 送多筆」的效率，但保住壞資料隔離這個真正重要的性質。**離線同步動工前必須先決定**，
   > 不是寫到一半才發現。

3. **冪等性用 client-assigned identifier + conditional create 解。**
   斷網重送的經典災難：server 已寫入但 response 沒回來 → client 重送 → 重複資料。
   解法：每筆佇列項目在資源裡帶 client UUID identifier，送出時用
   `If-None-Exist: identifier=urn:tideng:queue|{uuid}` 做 conditional create。
   重送時 server 回 200（已存在）而非再建一筆。**這需要 Siming 支援 conditional create——列入 server 缺口檢查。**

---

## 1. 開發環境拓撲

> **修訂（實作後）**：Phase A 的後端改接公開 FHIR server，不再等 Siming 就位。
> 理由：launcher 可以 proxy 到任何 R4 server，先接公開的就能立刻開發登入流程；
> 而且「先對外部 server 開發」能避免把 Siming 的特殊行為寫死進 client。
> Siming 退成 Phase B——切換只需改 `FHIR_SERVER_R4` 一個環境變數。

```
Phase A（現行）
┌─────────────┐                       ┌──────────────────────┐
│  iPad App   │ ────────────────────► │ smart-launcher-v2     │
│             │  base URL 填 :8090    │ :8090 (auth 模擬+proxy)│
└─────────────┘                       └──────────┬───────────┘
                                                 │
                                      ┌──────────▼───────────┐
                                      │ hapi.fhir.org (公開)  │
                                      └──────────────────────┘

Phase B（Siming 接上後）
                                      ┌──────────▼───────────┐
                                      │ Siming :8080          │
                                      │ (SMART 驗證 Phase A 關)│
                                      └──────────┬───────────┘
                                      ┌──────────▼───────────┐
                                      │ PostgreSQL            │
                                      └──────────────────────┘
```

docker-compose 追加片段（併入 Siming 的 compose）：

```yaml
smart-launcher:
  image: smartonfhir/smart-launcher-2:latest
  ports: ["8090:80"]
  environment:
    FHIR_SERVER_R4: "http://siming:8080"     # docker 內部網路名
    # launcher 對外簽發的 issuer/URL 必須是 iPad 可達的 LAN 位址
    # 依 launcher 文件設定 base/public URL 為 http://192.168.0.200:8090
```

**注意事項**
- iPad 填的 FHIR base URL 是 launcher 的 proxy 路徑，不是 `:8080`，**也不是 `/v/r4/fhir`**。
  路徑裡必須有 `sim/<base64>` 這一段，裝的是 launch options：

  ```
  http://localhost:8090/v/r4/sim/e30/fhir
                              ^^^ base64url("{}")，最小的 launch options
  ```

  ⚠️ **少了 sim 段時 discovery 仍會成功**（`.well-known/smart-configuration` 完整回傳、
  capabilities 也對），但 authorize 會回
  `Invalid launch options: SyntaxError: Unexpected end of JSON input`。
  問題會一路潛伏到使用者按下登入才爆——實測踩過，故列在此。
- Phase A：Siming 的 SMART JWT bearer 驗證**關閉**（信任邊界在 launcher）。
- Phase B（Siming 原生 auth）：iPad 只換 base URL 回 `:8080`，client 程式碼零修改。
- ATS：Info.plist 對 `192.168.0.200` 加 `NSExceptionAllowsInsecureHTTPLoads`（僅 DEBUG configuration，用 xcconfig 分離；Release build 不含例外）。
- 先驗風險：launcher 的 patient/provider picker 會對 backend 打 search（`Patient?...`、`Practitioner?...`）——起服務後先確認與 Siming search 相容，再寫任何 client 碼。

---

## 2. App 模組切分

> **修訂（實作後）**：原本規劃把每個 feature 也切成 SPM package，與 MVVMC 規範衝突——
> 該規範要求 feature 住在 `Sources/Pages/<Feature>/`。改為**基礎設施切 package、feature 走 MVVMC**。
> 另外 repo 上層分成 `App/` 與 `Server/`，後者放「怎麼把後端跑起來」（compose、seed），
> 不放後端原始碼——Siming 留在自己的 repo，複製進來會變成兩份互相漂移的真相。

```
Tideng/
├── App/
│   ├── project.yml            # XcodeGen 是唯一真相，不手改 .xcodeproj
│   ├── Sources/
│   │   ├── App/               # AppRouter、Deeplink、SceneDelegate、AppConfiguration
│   │   ├── Pages/             # MVVMC features，一個 feature 一個目錄
│   │   │   ├── ServerSetup/   # 輸入 base URL、SMART 登入
│   │   │   ├── Main/          # NavigationSplitView 側邊欄容器
│   │   │   └── PatientList/
│   │   └── Shared/            # 只放與業務無關的基礎設施
│   └── Packages/
│       ├── FHIRCore/          # FHIR 命名空間、LOINC 常數、Bundle helper
│       ├── FHIRClient/        # REST、search builder、錯誤三分類
│       ├── SmartAuth/         # discovery、PKCE、TokenStore、Keychain、瀏覽器授權
│       ├── SyncEngine/        # （未實作）佇列、狀態機、flush
│       └── LocalStore/        # （未實作）GRDB schema、DAO、migration
├── Server/                    # docker-compose、seed 腳本
└── docs/
```

### 依賴方向

```
Sources/Pages/*  →  SmartAuth  →  FHIRClient  →  FHIRCore
```

**`SmartAuth → FHIRClient`，不是反過來**（原 spec 寫「SmartAuth 只被 App 與 FHIRClient 用」，已推翻）。
`FHIRClient` 定義 `protocol TokenProviding`，`SmartAuth` 的 `TokenStore` 實作它。

why：讓 FHIRClient 對 SMART 流程一無所知。反過來寫會把 auth 生命週期滲進 REST 層，
FHIRClient 就再也無法脫離 auth 單獨測試，換登入方式也得動到 client。

### FHIR 型別一律走 `FHIR.` 命名空間

**不得使用 `@_exported import ModelsR4`。** FHIR R4 的 resource 名稱與 Swift／Foundation 大量撞名：

| FHIR resource | 撞到 | 後果 |
|---|---|---|
| `Observation` | Swift Observation framework | `@Observable` 展開失敗，錯誤訊息指向完全無關的地方 |
| `Task` | Swift Concurrency | `Task { }` 被解析成 FHIR resource |
| `Bundle` | `Foundation.Bundle` | 讀不到 app resource |
| `Group` / `Media` / `Signature` | SwiftUI / Foundation | 靜默解析錯 |

`FHIRCore` 提供 `enum FHIR` 承載 typealias，需要新型別時加在那裡。

### 版本鎖定

FHIRModels 鎖 `exact: "0.9.3"`，Siming 必須同版。
~~CI diff 兩邊 `Package.resolved`~~ 已放棄——那會讓兩個 repo 互相耦合，而 FHIRModels 在 minor
版之間改的是型別 optionality（編譯期就會炸），wire format 其實穩定。真正的防線是 §8 的 contract test。

---

## 3. SmartAuth 實作規格

### 3.1 Discovery

```
GET {base}/.well-known/smart-configuration
```

必要欄位驗證：`authorization_endpoint`、`token_endpoint`、`capabilities`（需含 `launch-standalone`）、`code_challenge_methods_supported` 含 `S256`。
缺 well-known 時的 fallback（讀 CapabilityStatement 的 security extension）**MVP 不做**——回明確錯誤「此 server 不支援 SMART discovery」。

### 3.2 Authorize（PKCE）

- `code_verifier`：128 chars，`SecRandomCopyBytes` 產生後 base64url
- `code_challenge = base64url(SHA256(verifier))`，method `S256`
- Authorize URL query 參數：
  `response_type=code`、`client_id`、`redirect_uri=tideng://smart/callback`、
  `scope`（見產品 spec 4.2）、`state`（隨機，回來必驗）、
  **`aud={FHIR base URL}`** ← SMART 規格要求、最常被漏掉、漏掉時部分 server 直接拒絕
- `ASWebAuthenticationSession`：`prefersEphemeralWebBrowserSession = true`
  （共用 iPad 不留 SSO cookie，每次乾淨登入；代價是不能記住帳號——此場景下是 feature 不是 bug）

### 3.3 Token 交換與管理

- `POST token_endpoint`：`grant_type=authorization_code` + `code` + `redirect_uri` + `client_id` + `code_verifier`（public client，無 secret）
- 回應解析：`access_token`、`refresh_token`、`id_token`、`patient`（如有）、`scope`（**以 server 實際授予的為準**，UI 依此隱藏無權模組）
- `fhirUser`：從 `id_token` claim 取出 `Practitioner/{id}` reference。MVP 解析 claims 即可；簽章驗證（jwks）列 Phase B。信任邊界註記：Phase A 的 id_token 來自模擬器，本來就不可信。
- `TokenStore` 為 **actor**：refresh 序列化（多個 request 同時撞 401 時只跑一次 refresh，其餘 await 同一個 task）。這是最容易寫出 race 的地方，必須有測試。
- 401 處理鏈：401 → refresh → 重試一次 → 再 401 → session 標記過期 → UI 進入「需重新登入」狀態，**離線佇列不動**，重登後恢復 flush。
- Keychain：以 server profile UUID 為 key 存 token set，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。

---

## 4. FHIRClient 實作規格

- 薄封裝 `URLSession`（async/await），統一注入 `Authorization: Bearer`、`Accept: application/fhir+json`
- Search 用型別安全 builder，MVP 需要的查詢就三條，直接列為驗收：

| 用途 | 查詢 |
|---|---|
| 病房 census | `Encounter?status=in-progress&location={locId}&_include=Encounter:subject&_include=Encounter:location` |
| 生命徵象趨勢 | `Observation?patient={id}&category=vital-signs&_sort=-date&_count=100` |
| 今日給藥 | `MedicationRequest?patient={id}&status=active&_include=MedicationRequest:medication` |

- 分頁：跟隨 `Bundle.link[rel=next]`（Siming 是 cursor 分頁，client 不自己拼 offset）
- 錯誤模型三分類：`transport`（可重試）/ `auth`（走 3.3 鏈）/ `operationOutcome`（解析 server 的 OperationOutcome 呈現給使用者）

---

## 5. LocalStore + SyncEngine 實作規格

### 5.1 儲存選型：GRDB（建議，理由如下；Claude Code 可反駁）

- 佇列的核心要求是**背景寫入可靠 + 顯式交易 + WAL**——GRDB 在這三項成熟穩定
- SwiftData 在 Swift 6 strict concurrency 下的背景 context 行為仍有粗糙處，佇列這種「不能丟」的元件不適合當它的試驗場
- Cache（census、observations 唯讀快取）可隨佇列同用 GRDB，一套 migration

### 5.2 佇列 schema

```sql
CREATE TABLE sync_queue (
  id            TEXT PRIMARY KEY,      -- UUID，同時是 resource 裡的冪等 identifier
  created_at    INTEGER NOT NULL,
  server_profile TEXT NOT NULL,        -- 綁定 server，換 server 不混流
  resource_type TEXT NOT NULL,         -- Observation / MedicationAdministration / AuditEvent
  payload       BLOB NOT NULL,         -- FHIR JSON（已含 identifier=urn:tideng:queue|{id}）
  state         TEXT NOT NULL,         -- pending|syncing|synced|failed_retryable|failed_terminal
  retry_count   INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT,
  patient_ref   TEXT NOT NULL          -- 供 UI 按病人顯示未同步標記
);
```

### 5.3 狀態機與 flush 規則

```
pending ──flush──► syncing ──2xx──► synced（保留 7 天後清除）
                     │
                     ├─ 網路/5xx ──► failed_retryable（指數退避：30s→2m→10m→30m，上限後停待手動）
                     └─ 4xx（400/422 驗證錯）──► failed_terminal（UI 紅標，需人工處理，不自動重試）
```

- 觸發：`NWPathMonitor` 恢復連線、app 回前景、成功寫入後、手動下拉
- Flush：FIFO 取至多 50 筆組 **batch** Bundle 送出；逐 entry 讀回應狀態分別轉移狀態
- 每個 entry request：`POST {type}` + header `If-None-Exist: identifier=urn:tideng:queue|{id}`
- App 遭殺恢復：啟動時把殘留的 `syncing` 重置為 `pending`（靠 If-None-Exist 保證重送安全）
- 線上時的「即時寫入」= 同一條路（入佇列→立即 flush），**不存在旁路直寫**——單一寫入路徑,行為一致、測試面減半

### 5.4 給藥排程展開（app 內規則引擎）

- 讀 `MedicationRequest.dosageInstruction[].timing.repeat`：支援 `frequency/period(+periodUnit=d)` 與 `timeOfDay`
- `asNeeded == true`（PRN）→ 不展開為排程任務，另列 PRN 區塊（僅顯示,MVP 不做 PRN 給藥流程）
- range dose、tapering、複雜 timing（`dayOfWeek`、`when`）→ MVP 顯示原始 dosage 文字,不展開,標記「需人工判讀」
- 不用 `ServiceRequest` 建模排程量測——MVP 用 app 內固定規則（如 q8h 病房常規）,遷移成本之後再付

---

## 6. Siming 端缺口檢查清單（動工前勾完）

> **實測結果（2026-09-04）**：S1、S2、S3、S5 已實際驗過，逐項結果記在
> [`STATUS.md` §2.5](STATUS.md)。摘要：S2 conditional create 可用（seed 靠它做冪等）；
> S1 缺 `PractitionerRole`；S3 的 `Observation?date=` **宣稱支援但完全無效**；
> **S5 batch 不支援**——那一項就是 §0 第二個關鍵判斷的阻斷點。

| # | 檢查項 | 驗證方法 | 不足時的動作 |
|---|---|---|---|
| S1 | 8 個 resource types 齊備：Patient, Practitioner, Encounter, Location, Observation, MedicationRequest, MedicationAdministration, AuditEvent | 看 CapabilityStatement | generator 補 type |
| S2 | **Conditional create（`If-None-Exist`）** | curl 重送同 identifier 兩次,第二次應 200 不重建 | **必補——冪等性的根基** |
| S3 | 上述三條 search 查詢可跑、`_include` 正確展開 | curl 實測 | 補 search extractor |
| S4 | `timing`/`dosageInstruction` 欄位在 MedicationRequest 正常存取 | seed 一筆複雜 dosage 讀回 | 修 serialization |
| S5 | batch Bundle（非 transaction）逐 entry 回狀態 | 送一批含一筆壞資料,確認好資料成功 | 補 batch 語意 |
| S6 | smart-launcher-v2 的 picker search 相容 | 起 launcher 走一次登入 | 修相容性 |
| S7 | （可延後）ETag + `If-Match` 412 | curl | Phase B 前補 |

## 7. Seed 資料腳本（scripts/seed-ward.sh）

> **修訂（實作後）**：實際做成 **`Server/seed/` 的 Swift executable**，不是 shell 腳本。
> 理由：資源要用 FHIRModels 建構才能保證型別與欄位合規，用 shell 拼 JSON 等於把型別檢查
> 丟掉；而且 seed 與 app 共用同一套 `FHIRCore`，型別漂移會在編譯期就爆。
>
> 內容也隨客戶輪廓改變而不同——**小診所沒有病房與床位**，所以沒有 `Location` 樹、沒有
> in-progress `Encounter` census，改成門診就診紀錄。灌入方式不是 transaction Bundle 而是
> **逐筆 POST 帶 `If-None-Exist`**（Siming 不支援 batch，見 §0 第二點）。
>
> 實際產出與三種資料形狀的用意見 [`../Server/README.md`](../Server/README.md)。

- 1 個 `Location`（病房）+ 20 張床（Location partOf）
- 20 個 `Patient` + 對應 in-progress `Encounter`（TW Core profile）
- 每床 2–4 筆 active `MedicationRequest`（含 q8h、bid、PRN 各數筆,含一筆複雜 tapering 當邊界測試）
- 每床過去 48h 的 vital-signs `Observation` 時序資料（給趨勢圖用）
- 3 個 `Practitioner`（登入角色）
- 全部以 transaction Bundle 灌入,腳本可重跑（conditional create）

## 8. 測試策略

- **SmartAuth**：`URLProtocol` stub 假 authorization server——測 PKCE 參數正確性、`aud` 存在、state 驗證、401→refresh 序列化（並發 10 request 只 refresh 一次）
- **SyncEngine**：狀態機全轉移路徑單元測試;「殺 app 恢復」「重送冪等」「壞資料隔離」三個情境測試
- **Contract test**：CI 起 docker（Siming + seed）跑三條 search + batch flush 的整合測試——這同時是 S1–S5 的自動化回歸
- **給藥展開**：timing 展開純函式,表格驅動測試（含 PRN、跨午夜、DST 邊界）

---

*Tech spec version: 0.1 — 2026-09-03，配套 NIS-MVP-SPEC.md v0.2*
