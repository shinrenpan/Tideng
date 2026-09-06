## Why

`Server/` 目前用 smart-launcher-v2 當授權伺服器，而它是**協定模擬器**：挑一個人就登入，不問密碼、不驗 token。這造成兩個問題。

對外：demo 時「按一下就進去」無法取信於診所，而且提問者是對的——一個看不到登入憑證的系統，本來就該解釋清楚憑證去了哪裡。

對內更嚴重：`docs/STATUS.md` 有一條掛著的待驗證項目「**無授權會被拒絕**」。因為 launcher 放行、Siming 的 `SMART_ISSUER` 也沒設（完全不驗 bearer token），這條反方向從來沒有跑過。也就是說 Tideng 的 401 處理與 refresh 流程，至今沒有對上任何一個真的會拒絕的驗證器。

`Server/` 的定位是「Tideng 在真實世界會遇到的環境」的參考實作，目標是**像**而不是方便。從這個定位看，模擬器一直是個佔位符——本案不是新增功能，是補回原本就缺的擬真度。

## What Changes

- **授權伺服器換成 Keycloak**，取代 smart-launcher-v2。登入頁由 Keycloak 提供，使用者在系統瀏覽器輸入帳密；Tideng 只拿得到 authorization code，**永遠不接觸密碼**。這條流程與正式環境（診所自己的 IdP）完全相同，不是 demo 專用的替代路徑。
- **`Server/` 全面容器化**：Keycloak、Siming、Postgres 皆進 compose。目前 Siming 與 seed 跑在 host、Postgres 借自 Siming 自己的 compose，啟動需要兩段式操作。改完之後 `Server/` 目錄下一個 compose 指令即可備妥整個環境。seed 維持在 host（它依賴 `App/Packages/FHIRCore`，容器化需要整套 Swift toolchain 而換不到任何東西）。
- **hostname 與 issuer 一律由環境變數提供**，不寫死 `localhost`。Keycloak 會把 issuer URL 寫進每一張簽發的 token，寫死之後若要改在別的位址執行，realm 設定與已簽發的 token 都會失效。
- **seed 改用 client-assigned id**（以 PUT 指定 `Practitioner/practitioner-N`）。目前 id 由 server 分配 UUID，每次重灌都會變，而 Keycloak 的帳號必須綁定一個穩定的 Practitioner 參照。
- **Siming 補上 authorization server 端點**（跨 repo）：它的 `.well-known/smart-configuration` 目前缺 `authorization_endpoint`、`token_endpoint`、`code_challenge_methods_supported`，且 `capabilities` 缺 `launch-standalone` 與 `client-public`。前三者在 Tideng 的設定模型中皆為非 optional，任一缺漏會讓 discovery 在解碼階段就失敗。
- **Siming 啟用 `SMART_ISSUER`**，第一次真正驗證 bearer token 的簽章與 issuer。這會關掉「無授權會被拒絕」那條待驗證項目。
- **Tideng 驗證 id_token 簽章**（透過 jwks_uri）。目前只解 payload 不驗簽，程式碼註解自述為 Phase B。接上真實 IdP 之後，未驗簽的 `fhirUser` 代表任何人都能偽造一個身分宣告。

## Capabilities

### New Capabilities

- `smart-authentication`: Tideng 對 SMART 授權伺服器的要求與驗證——discovery 必須具備哪些欄位、id_token 簽章如何驗證、驗證失敗時的行為。
- `auth-environment`: `Server/` 這個參考環境必須提供什麼——真實的帳密登入、可驗證的 token、帳號與 Practitioner 的綁定、以及一個指令即可備妥的啟動方式。

### Modified Capabilities

- `demo-data`: Practitioner 的識別改為 client-assigned 的穩定 id，讓外部系統（Keycloak）能長期綁定。

## Impact

- Affected specs: `smart-authentication`（新增）、`auth-environment`（新增）、`demo-data`（修改）
- Affected code:
  - New:
    - `Server/keycloak/realm-tideng.json`
    - `Server/.env.example`
    - `App/Packages/SmartAuth/Sources/SmartAuth/JWKS.swift`
    - `App/Packages/SmartAuth/Tests/SmartAuthTests/IDTokenVerificationTests.swift`
  - Modified:
    - `Server/docker-compose.yml`
    - `Server/README.md`
    - `Server/seed/Sources/SimingSeed/FHIRSeedClient.swift`
    - `Server/seed/Sources/SimingSeed/main.swift`
    - `Server/seed/Sources/SimingSeed/SeedData.swift`
    - `App/Packages/SmartAuth/Sources/SmartAuth/SmartConfiguration.swift`
    - `App/Packages/SmartAuth/Sources/SmartAuth/TokenResponse.swift`
    - `App/Packages/SmartAuth/Sources/SmartAuth/SmartAuthClient.swift`
    - `App/Sources/App/AppConfiguration.swift`
    - `docs/STATUS.md`
  - Removed:
    - smart-launcher-v2 服務（自 `Server/docker-compose.yml` 移除）
- Affected external repo: Siming（`~/Documents/github/Siming`）需補上 authorization server 端點並支援啟用 `SMART_ISSUER`。該 repo 的變更由其自己的 session 負責，本案只定義 Tideng 這端要求的合約與驗證方式。
