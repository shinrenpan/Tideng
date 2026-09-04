# Tideng（提燈）— iPad NIS MVP Spec & Evaluation Prompt

> **本文件的定位（先讀這段）**
>
> 這份 spec 描述的是**完整的護理資訊系統**，也就是 v1.0 的藍圖。它沒有被取消，只是往後挪。
>
> **實際動工的範圍已經收斂**：客戶輪廓從醫學中心改成小診所，第一版做的是唯讀的臨床
> dashboard，不含寫入、離線佇列與給藥核對。目前做到哪裡、實際結構長什麼樣，見
> [`STATUS.md`](STATUS.md)；技術決策的修訂見 `NIS-TECH-SPEC.md` 各節的「修訂（實作後）」。
>
> 本文件保留原樣是刻意的——收斂後的範圍改動不該把原本的思考一起刪掉。
> 下面第 8 節的 Open Questions 已在 STATUS.md 逐題回答。

---

## 1. 專案名與定位

> **Tideng (提燈)** — 南丁格爾提燈夜巡，逐床看顧。提燈記錄，司命掌冊（後端：[Siming](https://github.com/shinrenpan/Siming)）。


**Practitioner-facing 的 iPad 原生護理資訊系統（NIS）client：使用者輸入任意 FHIR R4 base URL，透過 SMART App Launch (standalone) 登入後執行護理點照護工作流，支援離線輸入與自動同步。**

不是 patient app、不是 FHIR browser、不是 web app 的殼。

## 2. 目標平台與技術約束

| 項目 | 決定 | 備註 |
|---|---|---|
| 平台 | iPadOS 17+，**iPad only**（`TARGETED_DEVICE_FAMILY = 2`） | iPhone 螢幕放不下 dashboard，不跟 |
| 方向 | **支援四個方向**（橫向仍是設計主軸） | 見下方註 |
| 語言 | Swift 6（strict concurrency） | |
| UI | SwiftUI | |
| FHIR 模型 | [apple/FHIRModels](https://github.com/apple/FHIRModels)（R4） | 與後端 Siming 共用同一套型別 |
| OAuth | `ASWebAuthenticationSession` + 自行實作 PKCE，或評估 AppAuth-iOS | 由你評估後建議，理由要寫 |
| 本地儲存 | SwiftData 或 GRDB——由你評估後建議 | 離線佇列 + cache，需可靠的 migration 路徑 |
| Token 儲存 | Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`） | |
| 最低網路要求 | 允許 HTTP 的內網開發例外（ATS exception 白名單），正式僅 HTTPS | |
| IAP | **MVP 不做**。但架構要預留 feature-gating 層（module entitlement 的介面先留） | 之後用 StoreKit 2 |

> **方向的修訂（實作後）**：原本打算只鎖橫向（推車、護理站的實際擺法）。放棄的理由有二：
>
> 1. iPadOS 26 起 `UIRequiresFullScreen` 已廢棄，Xcode 直接警告「即將被忽略，且即將要求支援
>    所有方向」。實測鎖定仍部分生效，但呈現方式變成把 app 塞進一個上下補黑的橫向視窗——
>    看起來像壞掉。
> 2. 更實際的理由：客戶輪廓改成小診所後，「iPad 固定在推車上」這個前提本身就不成立了。
>
> 作法是**宣告支援四個方向，但不為直向做第二套版面**——置中卡片與 `NavigationSplitView`
> 本來就會自適應，確認不崩壞即可。視窗下限改用 `windowScene.sizeRestrictions.minimumSize`。

## 3. Server 環境（已存在，不在本專案範圍內開發）

1. **Siming** — 自寫的 Swift FHIR R4 server（Hummingbird 2 + PostgresNIO + FHIRModels），TW Core IG v1.0.0 驗證通過，支援 transaction bundle、SMART JWT bearer 驗證（resource server 端）。跑在內網 `http://192.168.0.200:8080`。
   （**修訂**：開發期實際跑在 `localhost:8080`，資料庫另開 `siming_demo` 不動既有資料，
   啟動方式見 [`../Server/README.md`](../Server/README.md)。）
2. **smart-launcher-v2**（SMART Health IT，自架 Docker）— 擋在 Siming 前面模擬 SMART authorize/token/discovery 流程。開發期的 auth 由它負責。
3. **SMART Health IT 公開 sandbox**（`launcher.smarthealthit.org`）— 用來驗證 client 實作對其他 server 的相容性。

> Client 端的 SMART 實作必須照 [SMART App Launch v2.x](https://hl7.org/fhir/smart-app-launch/) 規格寫，
> 之後從 launcher 切換到 Siming 原生 auth 時，client 不得需要修改。

## 4. MVP 功能範圍（照優先序）

### 4.1 Server 連線設定
- 首次啟動：輸入 FHIR base URL + client_id（client_id 收在「進階」摺疊區）
- 內建 server profiles（預設帶 Siming 內網、SMART sandbox 兩組），可新增/編輯/切換
- 讀取 `{base}/.well-known/smart-configuration` 做 discovery；驗證回應格式後才使用
- （加分，非必要）QR code 掃描帶入 `{fhir_base, client_id}` 設定
- 支援 MDM **Managed App Configuration**：機構可經 MDM 推送 `{fhir_base, client_id}`，app 啟動時優先讀取，使用者免手動設定

### 4.2 SMART Standalone Launch 登入
- Authorization Code Flow + PKCE（public client）
- Scopes：`openid fhirUser launch/patient user/*.read user/Observation.write user/MedicationAdministration.write offline_access`
- Callback：custom URL scheme
- Refresh token 自動更新；401 時的重試/重登策略要定義
- 從 `fhirUser` claim 解析出 `Practitioner` reference，作為後續所有寫入的 `performer`

### 4.3 病房 / 病人清單
- 以 `Location`（病床）+ `Encounter`（在院）組出病房 census 視圖
- 點入病人 → 基本資料 + 最近生命徵象趨勢（讀 `Observation` vital-signs）

### 4.4 今日待辦
- 聚合該病房的待執行項目：
  - 排程給藥：`MedicationRequest`（active）依 `dosageInstruction.timing` 展開為時段任務
  - 排程量測：以約定的 `ServiceRequest` 或 app 內規則產生（由你評估哪種做法對 MVP 務實）
- Polling 更新（30–60s），**不做** Subscription/push

### 4.5 生命徵象輸入（核心寫入路徑）
- TPR / 血壓 / SpO₂ / 疼痛分數輸入表單（iPad 針對快速輸入最佳化：數字鍵盤、上一床/下一床導航）
- 寫入符合 vital-signs profile 的 `Observation`（LOINC codes、TW Core 相容）
- 異常值即時視覺提示（僅提示，不做臨床決策建議——避免落入 SaMD 範圍）

### 4.6 給藥核對（barcode）
- 掃描藥品條碼 → 比對 `MedicationRequest`（five rights 的最小集：病人、藥品、劑量、途徑、時間）
- 確認後寫入 `MedicationAdministration`（performer = 登入的 Practitioner）
- 不符時的阻擋與 override 流程（override 需理由，記錄於 resource）

### 4.7 離線佇列與同步（MVP 的差異化核心）
- 所有寫入先落本地佇列，背景送出
- 斷網時完整可輸入；恢復連線自動 flush（transaction Bundle 批次）
- 樂觀鎖：`If-Match` + ETag；conflict 時的策略要在評估階段定義（提示使用者 vs 自動 rebase）
- 佇列項目狀態機：`pending → syncing → synced / failed(retryable) / failed(terminal)`，UI 需可見同步狀態
- App 被殺、裝置重開後佇列不得遺失

## 5. 明確不做（Non-goals）

- CarePlan / NANDA-NIC-NOC 護理計畫
- 交班（SBAR）
- 敘述性護理紀錄（DAR/SOAP）
- FHIR `Subscription` / push notification
- ~~多語系（僅 zh-Hant）~~ → **已實作**：base language 為 `en`，另附 `zh-Hant`。改動理由是對外（THAS 之外的市場、FHIR 社群）需要英文介面，而 FHIR／醫療領域的通用語言本來就是英文
- IAP 付費牆（僅預留 gating 介面）
- iPhone 最佳化、Apple Watch
- EHR launch（僅 standalone）

## 6. 非功能需求

- **安全**：token 僅存 Keychain；任意 URL 視為不受信任輸入；憑證釘選不做但 TLS 驗證不得關閉（內網開發例外走 ATS 白名單）
- **Session 安全（共用 iPad 場景）**：app 退到背景時遮罩畫面（避免 app switcher 洩漏 PHI）；閒置逾時後鎖定，需 Face ID / Touch ID / PIN 解鎖回到 session；逾時時間可設定，預設 5 分鐘
- **稽核**：每筆寫入同時產生 `AuditEvent`（若 server 不支援則本地留存，介面抽象化）
- **效能**：40 床病房 census 首屏 < 1s（暖快取）；單筆 Observation 寫入 UI 回饋 < 100ms（本地佇列先行）
- **測試**：離線同步狀態機必須有完整單元測試；SMART flow 以 mock authorization server 做整合測試
- **法規邊界**：不提供診斷/治療建議、不做劑量計算——維持在「醫療資訊紀錄工具」範圍，遠離 SaMD 分類

## 7. Demo 劇本（驗收基準）

> 登入（SMART standalone，輸入內網 Siming URL）→ 選病房 → 看今日待辦（3 筆排程給藥 + 排程量測）→ 掃碼給藥核對 1 筆 → 輸入 2 床生命徵象 → **開飛航模式** → 繼續輸入 2 床 → 關飛航模式 → 佇列自動同步，server 端 UI（Siming `/ui`）可見全部資料 → 切換 server profile 到 SMART sandbox，重新登入，證明同一 app 接不同 server。

此劇本全程通過 = MVP 完成。

## 8. Open Questions（評估階段要逐題回答）

1. **AppAuth-iOS vs 自寫 PKCE flow**：依賴成本 vs 實作風險，你的建議？
2. **SwiftData vs GRDB** 作為離線佇列：考量 Swift 6 concurrency、migration、背景寫入可靠性。
3. **排程量測的來源**：`ServiceRequest` 建模 vs app 內規則引擎，哪個對 MVP 務實？對日後接真 server 的遷移成本？
4. **Conflict resolution 預設策略**：護理情境下 last-write-wins 的風險是什麼？你建議的預設？
5. **`MedicationRequest.dosageInstruction.timing` 展開為任務**的邊界情況（PRN、range dose、tapering）MVP 該支援到哪？
6. **共用 FHIRModels 型別但 client/server 版本漂移**：如何鎖版本策略？
7. 你認為本 spec 還有什麼沒問出來、但會在第 3 週咬人的問題？

## 9. Milestone 骨架（由你細化）

- **M0** — 專案 scaffold、CI、FHIRModels/依賴接入、server profiles + discovery
- **M1** — SMART standalone login 全流程通（對 smart-launcher-v2 + 公開 sandbox 皆通過）
- **M2** — 病房 census + 病人視圖（唯讀）。**此 milestone 為可獨立發布的 v0.5「dashboard 版」**：完成條件包含可上架品質的 UI、對公開 sandbox 相容、session 安全到位。若後續寫入權限在生態端受阻，v0.5 即為獨立產品線（唯讀護理 dashboard）
- **M3** — 生命徵象輸入 + 線上直寫
- **M4** — 離線佇列 + 同步 + conflict 處理
- **M5** — 今日待辦 + 給藥核對
- **M6** — Demo 劇本全通、AuditEvent、打磨

---

*Spec version: 0.2 — 2026-09-03（M2=v0.5 dashboard 定位、MDM 設定、session 安全）*
