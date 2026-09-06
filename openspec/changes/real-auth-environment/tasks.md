## 1. 種子資料的穩定識別

- [x] 1.1 落實決策「Practitioner 改用 client-assigned id」：seed client 具備以指定 id 寫入的路徑，與既有的 conditional create 並存，其餘資源型別行為不變。驗證：以該路徑對同一個 id 寫入兩次，第二次不產生新資源
- [x] 1.2 practitioner 以 `practitioner-<seq>` 為資源 id 建立，id 可從 seed 定義推導而不需查詢 server。滿足 Requirement: Practitioner identifiers are stable across reseeds。驗證：重建資料庫後連跑兩次 seed，`Practitioner/practitioner-1` 可直接讀取、practitioner 總數為 4 且 id 不變

## 2. 容器化的環境

- [x] 2.1 落實決策「Siming 進 compose，seed 留在 host」與「`Server/` 擁有自己的 Postgres」：compose 納入 Postgres 與 Siming（以 `${SIMING_PATH:-../../Siming}` 建置），移除 smart-launcher-v2，seed 維持在 host 執行。滿足 Requirement: The environment starts from one command in one directory。驗證：在所有服務皆未執行的機器上，於 `Server/` 執行一次 compose up 後三個服務皆可連線，過程中未於其他目錄執行任何指令
- [x] 2.2 建置出來的 Siming image 確實載入了 terminology，而不只是容器起得來。落實 design 風險「Siming 的 image 可能安靜地少掉 terminology」——它的 packages 是 gitignored，從乾淨 clone 建置會得到空目錄，而 server 仍會正常啟動、`/health` 仍回 200。驗證：對容器內的 server 取 CapabilityStatement，斷言回應長度數萬位元組等級而非一萬上下（實測有 packages 為 76,643 位元組、空 packages 為 11,488，差 6.7 倍，長度斷言即足夠靈敏）。落實決策「驗收要有牙齒：以變異確認」——把 build context 的 packages 移走重建一次，這條驗收必須變紅
- [x] 2.3 落實決策「用 Keycloak 當授權伺服器」與「Keycloak realm 以匯入檔定義，不以介面手動設定」：Keycloak 服務進 compose 並以匯入檔啟動。驗證：容器啟動後 realm 存在，且其內容與匯入檔一致（未經介面手動補設定）
- [x] 2.4 `Server/.env.example` 列出所有必要變數並附預設值；compose 一律以 `${VAR:-default}` 取用，committed 檔案中不出現寫死的主機名。滿足 Requirement: Addresses are configuration, not constants。驗證：以不同的主機名變數啟動，discovery、登入頁與 token 驗證三者皆使用該主機名，且未編輯任何 committed 檔案

## 3. Keycloak 的 realm 定義

- [x] 3.1 realm 匯入檔定義 public client：PKCE 要求 S256、redirect 為 app 的 callback scheme、不使用 client secret；並定義 SMART 需要的 client scope（`openid`、`fhirUser`、`user/*.read`、`offline_access`）。驗證：走完一次授權碼流程可取得 token，token response 的 scope 涵蓋這四項且有發出 refresh token；不帶 code_verifier 時被拒絕
- [x] 3.2 落實決策「`aud` 三處使用同一份不帶尾斜線的字面值」：Keycloak 的 audience mapper、app 送出的 `aud` 參數、Siming 的 `SMART_AUDIENCE` 由同一個環境變數供給。驗證：**先斷言 `SMART_AUDIENCE` 非空**，再確認正常登入的 token 可取得資料、且以刻意錯誤 audience（多一個尾斜線）簽發的 token 得到 401。順序不可顛倒——`SMART_AUDIENCE` 未設定（**或為空字串，compose 未設變數的渲染結果**）時 Siming 完全不檢查 aud，那條「應該 401」的斷言會假性通過，防呆本身被同一類沉默失敗吃掉。Siming 端已擋掉空字串，但那層擋得住「忘了設」、擋不住「設了但打錯字」，所以本條的非空斷言仍然必要。落實決策「驗收要有牙齒：以變異確認」——清空 `SMART_AUDIENCE` 跑一次，這條驗收必須變紅；若沒有變紅，代表「先斷言非空」那層擋法本身也是必然為真
- [x] 3.3 匯入檔為 seed 的四位醫事人員建立帳號，帳號屬性存放其 practitioner id，protocol mapper 將該屬性輸出為 `fhirUser`，值的形式為 `Practitioner/<id>`。滿足 Requirement: Accounts are bound to practitioners in the clinical data。驗證：兩個不同角色的帳號分別登入，各自解析到自己的 practitioner，側邊欄顯示的職位不同
- [x] 3.4 登入需要帳密，且錯誤的密碼不發出 authorization code。滿足 Requirement: The environment authenticates people, it does not simulate it。驗證：以存在的帳號搭配錯誤密碼提交，停留在登入頁且回呼網址未帶 code

## 4. FHIR server 真正拒絕

- [x] 4.1 Siming 啟用 `SMART_ISSUER` 指向 Keycloak 並以其 jwks 驗證 bearer token；`SMART_ISSUER` 已設定但取不到 jwks 時失敗可見，不得沉默退回不驗證。滿足 Requirement: The FHIR server rejects requests it cannot verify。驗證：不帶 Authorization header、以其他金鑰簽出的 token、issuer 不符的 token，三者皆得 401，正常 token 可取得資料；另以無法連線的 jwks 位址啟動，確認該情況可辨識且此時不會有請求被放行
- [x] 4.2 確認 Siming 發布的 discovery 文件符合本案的合約，涵蓋決策「Siming 的授權端點以環境變數提供，不去抓 Keycloak 的 openid-configuration」與「授權端點欄位只在完整設定時才發布」。驗證：設定完整時文件含 `authorization_endpoint`、`token_endpoint`、`code_challenge_methods_supported`、`grant_types_supported`、`token_endpoint_auth_methods_supported`，且 `capabilities` 為五項（`permission-v1`、`permission-patient`、`launch-standalone`、`client-public`、`context-standalone-patient`）；兩個端點皆未設定時上述欄位皆不出現、`capabilities` 只剩前兩項。落實決策「驗收要有牙齒：以變異確認」——**兩種變異都要跑**：(a) 從 compose 拿掉 `SMART_AUTHORIZE_URL` 整行，(b) 把它的值改成空字串 `""`。兩者 Siming 都必須啟動失敗。(b) 是容器化才會大量出現的形狀——compose／k8s 把未設變數渲染成空字串而不是 unset，而只檢查 nil 的守則擋不住它

## 5. 客戶端對伺服器的要求

- [x] 5.1 [P] discovery 缺少 `authorization_endpoint`、`token_endpoint`、`code_challenge_methods_supported` 任一者，或 `capabilities` 缺 `launch-standalone`／`client-public` 時，在開啟瀏覽器之前失敗，訊息指出是伺服器不支援且缺漏原因可區分。滿足 Requirement: Discovery rejects a server that cannot support the flow。驗證：SmartAuthTests 對五種缺漏各注入一份文件，斷言拋出且未進入授權
- [x] 5.2 [P] app 不呈現密碼欄位、不傳輸也不儲存密碼；持久化的資料中沒有任何欄位含有密碼。滿足 Requirement: The app never receives the user's credentials。驗證：SmartAuthTests 斷言 `TokenSet` 序列化後的欄位集合只含 token 相關項目；並以搜尋確認 app 端無密碼輸入元件

## 6. 身分宣告的驗證

- [x] 6.1 落實決策「id_token 驗簽失敗只讓身分消失，不中斷 session」：以 discovery 提供的 jwks 位址取得公鑰並快取，簽章與 issuer 皆通過時才取出 `fhirUser`；驗簽失敗、issuer 不符、jwks 取得失敗三者皆不產生身分且不結束 session。滿足 Requirement: The identity claim is verified before it is trusted。驗證：SmartAuthTests 以 stub 提供 jwks，涵蓋簽章正確、簽章錯誤、issuer 不符、缺少 id_token 四種情況，斷言身分有無與 session 是否存續，並斷言公鑰取得後重複驗證不再重新請求
- [x] 6.2 401 的處理維持既有形狀並在真實驗證器上成立：持有 refresh token 時刷新一次並重試，refresh 被拒或沒有 refresh token 時回到登入頁。滿足 Requirement: Rejection by the resource server is handled as rejection。驗證：模擬器上以 Keycloak 縮短的 token 壽命實測——擱置至過期後下拉刷新仍取得資料；再使 refresh 失敗，確認回到登入頁。**實測發現「登出 session」切不斷**——`offline_access` 發的是 offline token，設計上活過 session 登出；真正切得斷的是撤銷 consent 或停用帳號（兩者皆回 400 `invalid_grant`），而 app 對 400 的處理已有單元測試涵蓋

## 7. 文件與整體驗證

- [x] 7.1 `Server/README.md` 改寫為新的啟動方式（單一指令、`.env` 的角色、seed 仍在 host），並記錄 realm 設定的來源是匯入檔而非介面。驗證：依 README 在乾淨環境從零走一次，過程中不需要本文件以外的知識
- [x] 7.2 `docs/STATUS.md` 移除「無授權會被拒絕」的待驗證條目並記錄實測結果，同時更新環境描述；一併記錄環境只含產生的示範資料、帳號屬於虛構的醫事人員。滿足 Requirement: The environment holds no real patient data。驗證：文件中不再有已完成事項被列為待驗證，且環境內容的來源有明確陳述
- [x] 7.3 完整流程在模擬器上以英文與繁中各跑一次：輸入 base URL、Keycloak 登入、四張切片卡片、病人清單、詳情趨勢圖。驗證：兩種語言各截圖一次，確認登入頁出現、職位正確顯示、資料正確載入
