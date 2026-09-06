## Context

`Server/` 目前由三個部分拼成：smart-launcher-v2 跑在我們的 compose、Postgres 借自 Siming 自己的 compose、Siming 本身以 `swift run` 跑在 host。啟動需要兩段式操作，且開發過程中重啟 Siming 只能靠終止行程再重跑。

授權由 smart-launcher-v2 負責，而它是**協定模擬器**：正確重現 authorize/token/discovery 的形狀，但不驗證身分。Siming 這端 `SMART_ISSUER` 未設定，`SmartConfiguration.fromEnvironment` 回傳 nil，整個 bearer token 驗證被停用。兩者相加的結果是：**目前沒有任何一段程式碼會拒絕一個無效的 token**。

這使得 Tideng 的 401 處理、refresh 序列化、以及「回到登入頁」的路徑從未在真實條件下執行過。`docs/STATUS.md` 已把「無授權會被拒絕」列為待驗證。

跨 repo 的部分：Siming 的 `SmartConfiguration` 目前只模型化 resource server 那一半（issuer / audience / jwksURL / keys），沒有 authorization server 的端點欄位，因此它發出的 discovery 文件無法指向外部 IdP。

## Goals / Non-Goals

**Goals:**

- 登入需要真實帳密，且該流程與正式環境（診所自有 IdP）是同一條，不是 demo 專用路徑
- FHIR server 真正驗證 token，讓「無授權會被拒絕」這條路徑第一次可被執行與驗證
- 帳號與 `Practitioner` 的綁定在重灌資料後仍然成立
- `Server/` 目錄下一個 compose 指令即可備妥整個環境
- 位址與 issuer 由設定提供，使同一份 compose 可在不同位址執行

**Non-Goals:**

- 不部署到公開主機。正式環境由診所提供 FHIR server 與 IdP，`Server/` 不出貨；部署是業務決定
- 不在 Siming 內實作 authorization server
- 不做 SMART launch context（token response 夾帶 `patient` / `encounter`）。本 app 是 provider 端 standalone launch，不需要
- 不改變 app 既有的授權流程形狀（PKCE、`state`、`aud`、refresh 序列化皆維持）
- 不引入 IdP 的管理介面到 app 內。帳號生命週期屬於環境，不屬於產品

## Decisions

### 用 Keycloak 當授權伺服器

決定性的差別是 `fhirUser` claim。我們需要「把帳號的一個屬性變成 id_token 的自訂 claim」，Keycloak 以內建 protocol mapper 達成，設定即可、無需程式碼。

替代方案與否決理由：

- **Ory Hydra** — 它沒有使用者資料庫也沒有登入畫面，採用它等於要自己寫密碼表單，正是本案要避開的事
- **Authentik** — 可行（property mapping），但需要額外的 Redis 與 worker，且健康照護圈使用者少
- **Dex** — claim 客製能力不足以產生 `fhirUser`
- **Auth0 / Okta** — 由第三方持有醫療人員身分並按人頭計費，與「診所自有 IdP」的方向相反

次要理由：Keycloak 是開源選項中診所最可能already在跑的一個，且 SMART on FHIR 社群走過這條路，遇到問題查得到人。

### Siming 的授權端點以環境變數提供，不去抓 Keycloak 的 openid-configuration

Siming 需要在 discovery 文件中發布 `authorization_endpoint` 與 `token_endpoint`。可以在啟動時向 Keycloak 拉取 `openid-configuration` 自動推導，但那會在啟動路徑上加一個外部相依（Keycloak 未就緒時 Siming 起不來），而且該文件的欄位語意與 SMART 的並非一對一，多一層轉換就多一處會漂移。

採用明確的環境變數。代價是兩邊的位址要人工保持一致——這個代價由 compose 統一供給同一組變數來吸收。

### 授權端點欄位只在完整設定時才發布

Siming 同時服務兩種情境：純 resource server（前面另有 SMART 授權伺服器代理）與本案這種指向外部 IdP 的情境。只有在 authorize 與 token 兩個位址都提供時，才發布 `authorization_endpoint`、`token_endpoint`、`code_challenge_methods_supported`，並在 `capabilities` 附加 `launch-standalone` 與 `client-public`。

半套的宣告比不宣告危險：宣告了 `launch-standalone` 卻沒有 `authorization_endpoint`，client 會通過能力檢查然後在別的地方失敗。

### Siming 進 compose，seed 留在 host

Siming 已有可用的多階段 Dockerfile。收進 compose 的理由是 Keycloak 的 issuer 與服務位址——同一個 Docker network 上容器 DNS 直接可用，混合模式則需處理雙向的 `host.docker.internal` 指向，而那正是最容易做錯又最難查的地方。

原本不收的顧慮是寫死 clone 路徑，以 `${SIMING_PATH:-../../Siming}` 解決：平行 clone 者無需設定，路徑不同者在 `.env` 指定。

seed 留在 host：它依賴 `App/Packages/FHIRCore`，容器化需要整套 Swift toolchain 而換不到任何東西；它只需要以 HTTP 連得到 server。

### `Server/` 擁有自己的 Postgres

目前 Postgres 借自 Siming 的 compose，這是「兩段式啟動」的來源。`Server/` 的存在目的是讓環境跑得起來，那個目的不該要求先去別的 repo 做準備。代價是機器上會有兩個 Postgres 容器（Siming 自行開發時仍用它自己的），可以接受。

### Practitioner 改用 client-assigned id

以 PUT 指定資源 id（`Practitioner/practitioner-1` 等）建立，取代目前的 POST + server 分配 UUID。Keycloak 的帳號屬性必須指向一個穩定的參照，而目前每次重灌 id 都會變。

僅限 Practitioner：它是外部系統會按身分引用的資源。其餘資源維持 server 分配，因為改動它們沒有收益，而 id 的形狀是 server 的自由。

冪等改以 PUT 的語意達成（同一個 id 重送即覆寫），不再需要 conditional create 的比對。

### Keycloak realm 以匯入檔定義，不以介面手動設定

realm、client、client scope、protocol mapper 與帳號全部寫在一份可版控的匯入檔，容器啟動時匯入。手動設定無法版控、無法重現，且環境重建後會沉默地少掉某一項。

代價：日後從 Keycloak 介面調整的設定不會自動回寫到檔案。約定是**設定的來源是檔案**，介面上的調整必須回寫。

### `aud` 三處使用同一份不帶尾斜線的字面值

Siming 對 `aud` 的比對是**完全字串相等、大小寫敏感、不做任何 URL 正規化**（實作為 JWTKit 的 `verifyIntendedAudience`，等同 `contains`），因此 `http://siming:8080` 與 `http://siming:8080/` 是不同的值。它接受陣列，任一元素相等即通過；`SMART_AUDIENCE` 未設定時完全不檢查。

決定：**app 送出的 `aud` 參數、Keycloak 的 audience mapper、Siming 的 `SMART_AUDIENCE`，三者使用同一份字面值，且不帶尾斜線。** 該值由同一個環境變數供給，避免三處各自維護。

這條的代價是 app 端使用者輸入的 base URL 必須與該字面值一致——尾斜線的差異會表現為「登入成功但每個請求都 401」，是本案最難診斷的失敗模式，因此列為驗收項目而非註記。

### id_token 驗簽失敗只讓身分消失，不中斷 session

`fhirUser` 決定的是畫面上顯示的身分與 `Practitioner` 參照；真正的授權判斷在 FHIR server 對 access token 進行。因此驗簽失敗時正確的行為是「這個身分不可信、不使用」，而不是把使用者登出——後者會把一個顯示問題升級成無法工作。

這與既有的降級策略一致：拿不到 `PractitionerRole` 時職位行消失但姓名保留，拿不到姓名時退回 reference。

### 驗收要有牙齒：以變異確認

本案已經三次遇到同一個形狀——檢查通過了，但檢查的不是真正重要的那件事。最後一次是**為了抓沉默失敗而寫的斷言本身可以沉默地通過**（`SMART_AUDIENCE` 未設時「錯誤 audience 應得 401」必然成立）。

因此本案採用一個明確的步驟：**對關鍵驗收，逐條把它要保護的機制弄壞，確認該條驗收會失敗。** 不會失敗的驗收，就是在驗一個必然為真的東西。

成本是每條一次「弄壞 → 跑 → 還原」，相對於本案已經抓到的問題的代價，這個成本可以忽略。適用範圍不是全部 19 條，而是三條「保護沉默失敗」的驗收，它們列在對應任務的驗證欄位裡。

**這個方法的邊界要一併記住**：變異確認只能告訴你「這條驗收有牙齒」，不能告訴你「該寫的驗收都寫了」。它抓不到從未被寫下的那一條——而本案前幾個發現裡，有一半屬於後者。後者目前沒有系統性作法。

## Implementation Contract

#### 環境（`auth-environment`）

**行為**：在 `Server/` 執行一次 compose up 之後，Keycloak、Siming、Postgres 皆可連線，且不需要在其他目錄執行任何指令。app 端點擊登入會開啟 Keycloak 的登入頁，需輸入帳密；憑證錯誤時停留在登入頁且不發出 authorization code。

**設定形狀**：`Server/.env.example` 列出所有必要變數並附預設值，至少包含對外主機名、Keycloak realm 名稱、client id、以及 Siming 指向 Keycloak 的 issuer 與 jwks 位址。compose 以 `${VAR:-default}` 取用，committed 檔案中不出現寫死的主機名。

**帳號綁定**：realm 匯入檔為 seed 中的每位醫事人員建立一個帳號，帳號屬性存放其 `Practitioner` id，protocol mapper 將該屬性輸出為 `fhirUser`，值的形式為 `Practitioner/<id>`。

**失敗模式**：Siming 在 `SMART_ISSUER` 已設定但無法取得 jwks 時，必須讓失敗可見（啟動失敗或明確記錄），不得沉默地退回不驗證。

**驗收**：
- 不帶 Authorization header 的 FHIR 請求得到 401
- 以其他金鑰簽出的 token 得到 401
- 正確登入後的 token 可以取得資料
- 資料庫重建並重新 seed 後，同一組帳號仍解析到同一位 practitioner

**範圍界線**：realm 匯入檔、compose、`.env.example`、README 屬本案；Keycloak 的 realm 匯出／備份流程、帳號生命週期管理不屬本案。

#### 種子資料（`demo-data`）

**行為**：seed 以 PUT 建立 practitioner，資源 id 為 `practitioner-<seq>`，與 seq 一一對應且可從 seed 定義推導。重跑不產生重複，回報中 practitioner 一列的數字反映實際狀態。

**介面**：seed client 需要一個「以指定 id 寫入」的路徑，與既有的 conditional create 並存；其餘資源類型不受影響。

**驗收**：重建資料庫後連跑兩次 seed，practitioner 總數為 4 且 id 不變；`Practitioner/practitioner-1` 可直接讀取。

**範圍界線**：只有 practitioner 改為 client-assigned id。

#### 客戶端（`smart-authentication`）

**行為**：discovery 缺少 `authorization_endpoint`、`token_endpoint` 或 `code_challenge_methods_supported` 時，在開啟瀏覽器**之前**失敗，訊息指出是伺服器不支援。`capabilities` 缺 `launch-standalone` 或 `client-public` 時同樣在授權前擋下。

**id_token 驗證**：取得 token 後，以 discovery 提供的 jwks 位址取得公鑰驗證 `id_token` 簽章，並比對其 issuer 與 discovery 宣告的 issuer。任一不符時不從該 token 取出任何 claim，且不因此結束 session。缺少 `id_token` 時視為沒有身分，不視為登入失敗。

**失敗模式**：驗簽失敗、issuer 不符、jwks 取得失敗，三者的結果相同——身分為空、臨床資料照常載入。差異只記錄在 log，不呈現給使用者，因為使用者對此無可作為。

**驗收**：以 stub 注入的 token 覆蓋四種情況（簽章正確、簽章錯誤、issuer 不符、缺少 id_token），斷言身分有無與 session 是否存續；以及一則 discovery 欄位缺漏的測試，斷言在授權前就失敗。

**範圍界線**：只驗 `id_token`。access token 不在 client 端驗——那是 resource server 的職責，client 驗它既無意義也做不到（scope 之外的判斷需要 server 的資料）。

## Risks / Trade-offs

- **issuer 被寫進每一張 token** → 位址一律由設定提供；`.env.example` 以註解說明改動 issuer 會使既有 token 失效
- **`aud` 兩端不一致（尤其尾斜線）會表現為「token 有效但 401」** → 比對規則已確認為完全字串相等，見上方決策；三處由同一環境變數供給，並以一則刻意錯誤 audience 的 token 應得 401 作為驗收
- **Siming 的 image 可能安靜地少掉 terminology** — 它的 `packages/*.tgz` 是 gitignored、`scripts/` 在 `.dockerignore` 內，因此從乾淨 clone 建置會得到空的 packages 目錄。後果不是建置失敗：server 正常啟動、`/health` 回 200、每個 endpoint 都可連線，只有 CapabilityStatement 從 76,643 位元組塌成 11,488 → 驗收必須斷言回應長度，而不是「容器起得來」
- **compose 把未設的變數渲染成空字串，不是 unset** — 只檢查 `nil` 的守則擋不住 `VAR=""`，而容器化環境大量產生這種形狀。Siming 端已把空與純空白正規化為未設並在半套設定時啟動失敗；`SMART_ISSUER=""` 則刻意處理成啟動失敗而非關閉認證（正規化成「未設」會讓一個 typo 變成「FHIR 完全不需認證」，那是 fail open）→ 本案的變異確認必須同時涵蓋「整行刪掉」與「值為空字串」兩種形狀
- **防呆測試本身可能被沉默地滿足** — `SMART_AUDIENCE` 未設定時 Siming 完全不檢查 `aud`，於是「錯誤 audience 應得 401」這條斷言會在設定遺漏的環境下假性通過 → 該測試必須先斷言 `SMART_AUDIENCE` 非空。這是本案第二次遇到同一形狀：檢查通過了，但檢查的不是真正重要的那件事
- **Siming 的 image 每次都完整重建** — 它的 Dockerfile 在 `swift build` 之前 `COPY . .`，沒有依賴快取層，任何檔案變動都會重編全部依賴 → 日常開發不重建 image，只在 Siming 有變更時重建；若迴圈受影響再請 Siming 端拆出依賴層
- **Keycloak 啟動較慢，拖慢開發迴圈** → 它不隨程式碼變動重啟；日常只重啟 Siming
- **realm 設定在介面上被修改而未回寫檔案** → 以約定處理（來源是檔案），並在 README 明記
- **跨 repo 相依：Siming 未落地前本案無法端到端驗證** → 對方已在進行；本案的 client 端工作（discovery 檢查、id_token 驗簽）可先以 stub 完成並測試
- **移除 smart-launcher-v2 會失去一個對照組** — 它曾是驗證「不綁在單一 server 行為上」的第二個實作 → 公開 sandbox 仍在，且 Keycloak 本身就是第三個不同的授權伺服器，對照組不減反增

## Migration Plan

1. seed 改為 client-assigned id 並重灌，確認 practitioner id 穩定
2. Siming 端落地並發布可用的 discovery 文件（跨 repo）
3. compose 換成 Keycloak + Siming + Postgres，`.env.example` 就位
4. realm 匯入檔就位，帳號屬性指向步驟 1 的固定 id
5. Siming 啟用 `SMART_ISSUER`，驗證三種拒絕情境
6. app 端補 id_token 驗簽

回滾：本案的改動集中在 `Server/` 與 seed，回滾即回復先前的 compose 與 seed；app 端的 discovery 檢查與 id_token 驗簽對舊環境仍然成立（舊環境的 launcher 有發布必要欄位），因此不需要一併回滾。

## Open Questions

- **Keycloak 匯入檔中的初始密碼如何處理**。開發環境使用固定密碼並在 README 明記其為開發用；是否需要首次登入強制變更，待實作時依匯入檔的表達能力決定。
