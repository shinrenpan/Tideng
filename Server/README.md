# 本地開發環境

這個目錄不是「demo 用的後端」，是 **Tideng 在真實世界會遇到的環境的參考實作**。
目標是**像**，不是方便——凡是這裡有給、而真實環境不會給的東西，都是一個還沒爆的 bug。

Siming 的原始碼在自己的 repo（<https://github.com/shinrenpan/Siming>），不複製進來——
兩份 source of truth 遲早會漂移。這裡只放「怎麼把它跑起來」。

---

## 架構

三個容器，各自只做一件事。**Siming 只驗證 token，不簽發；Keycloak 只簽發，不碰臨床資料。**

```
                    ┌─────────────────────────────────────────┐
   iPad (模擬器)     │            Server/ 的 compose            │
        │           │                                         │
        │  ①        │   ┌───────────────┐                     │
        ├───────────┼──▶│    Siming     │  FHIR R4 資源伺服器   │
        │  discovery│   │  :8080        │  只驗 token，不簽發   │
        │           │   └───────┬───────┘                     │
        │           │           │ ④ 抓公鑰（容器 DNS）          │
        │  ②③       │           ▼                             │
        ├───────────┼──▶┌───────────────┐                     │
        │  帳密登入   │   │   Keycloak    │  授權伺服器           │
        │  換 token │   │  :8081        │  登入頁、簽發 token   │
        │           │   └───────┬───────┘                     │
        │           │           │                             │
        │           │   ┌───────▼───────┐                     │
        │           │   │   Postgres    │  Siming 的資料         │
        │           │   │  :5433        │  （Keycloak 用內嵌）   │
        │           │   └───────────────┘                     │
        └───────────┼─────────────────────────────────────────┘
           ⑤ 帶 token 取資料
```

| # | 步驟 | 誰對誰 |
|---|---|---|
| ① | `GET {siming}/.well-known/smart-configuration` | app → Siming。取得 authorize／token 端點（指向 Keycloak） |
| ② | 開系統瀏覽器，使用者**輸入帳密** | app → Keycloak。app 全程看不到密碼 |
| ③ | authorization code + PKCE → token | app → Keycloak |
| ④ | 抓公鑰驗簽 | Siming → Keycloak（**容器內部位址**） |
| ⑤ | `GET {siming}/Patient` + Bearer token | app → Siming。驗不過就 401 |

**seed 刻意留在 host**（`cd seed && swift run SimingSeed`）：它依賴 `App/Packages/FHIRCore`，
容器化要塞進整套 Swift toolchain 而換不到任何東西。

### 位址為什麼要分成三個變數

同一個「Keycloak 在哪裡」，在不同角色眼中是不同的位址。搞混的症狀都很難查：

| 變數 | 誰在用 | 必須是誰看得到的位址 | 填錯的症狀 |
|---|---|---|---|
| `SMART_ISSUER` | Siming 比對 token 的 `iss`；也是 app 瀏覽器要連的 | **對外** | 登入後每個請求 401 |
| `SMART_JWKS_URL` | Siming 自己抓公鑰 | **容器內** | Siming 啟動失敗（大聲，好查） |
| `SMART_AUDIENCE` | Siming 比對 token 的 `aud` | 必須與 app 送出的 `aud` **逐字元相同** | 登入成功但每個請求 401 |

⚠️ **`aud` 的比對是完全字串相等、大小寫敏感、不做 URL 正規化。**
`http://localhost:8080` 與 `http://localhost:8080/` 是兩個不同的值。多一個尾斜線，
症狀是「登入明明成功，但每一個請求都 401」——離原因非常遠。

⚠️ **`SMART_AUDIENCE` 沒設（或設成空字串）時，Siming 完全不檢查 `aud`。**
那是 fail open，而且沒有任何跡象。compose 會把未設的變數渲染成**空字串**而不是
「未設定」，所以不需要某一項時請**整行註解掉**，不要留 `VAR=`。

（Siming 發布在 `smart-configuration` 裡的 `jwks_uri` 是容器內部位址，client 連不到。
app 對此有處理：那個欄位只當提示，連不到就回頭問 issuer 自己的 OIDC discovery。）

---

## 起動

```bash
colima start                      # 若尚未執行
cp .env.example .env              # 全部有預設值，第一次不必改
docker-compose up -d              # 三個服務一起起來
./verify-image.sh                 # ⚠️ 不要略過，理由見下
cd seed && swift run SimingSeed   # 灌示範資料
```

> 這個環境只有獨立的 `docker-compose`，沒有 `docker compose` 子命令。
> Siming 的 `scripts/run-macOS.sh` 用的是後者，照這裡的指令走即可，不要去改那個 repo。

### 為什麼一定要跑 `verify-image.sh`

Siming 的 `packages/*.tgz`（FHIR 定義檔）是 gitignored。從乾淨 clone 或 CI 建置會得到
**空的 packages 目錄**，而後果不是建置失敗：

- server 正常啟動 ✓
- `/health` 回 200 ✓
- 每個 endpoint 都可連線 ✓
- **只有 terminology 是空的**，CapabilityStatement 從 76,643 位元組塌成 11,488

「容器起得來」這種檢查會讓壞掉的 image 通過。`verify-image.sh` 斷言的是回應長度。

### ⚠️ 重啟 Keycloak 之後要跟著重啟 Siming

Keycloak 用內嵌資料庫、不持久化，**每次重建容器都會重新產生簽章金鑰**。
Siming 的公鑰是啟動時抓一次，於是它手上的會是舊的：

```
Token verification failed        ← token 本身完全正確，只是簽它的金鑰換了
```

```bash
docker-compose restart siming    # 重啟 Keycloak 之後一定要做
```

已登入的 app session 也會一起失效，要重新登入。

### 灌資料需要一個機器帳號

Siming 啟用驗證之後，**seed 也是 client**——沒有 token 就一筆都寫不進去。
realm 裡有一個 `tideng-seed` service account，seed 會自己去換 token。

它刻意走 discovery 找授權伺服器，而不是把 Keycloak 的位址寫死：**seed 和 app 用同一套
方式找到授權伺服器**，否則它驗不到那條路徑，而那條路徑正是最容易設錯的。

用 service account 而不是某位醫事人員的帳密——資料載入工具不該持有人的密碼。

### 帳號

四位醫事人員，密碼一律 `tideng`（**開發用，正式部署必須換掉**）：

| 帳號 | 姓名 | 職位 | 綁定 |
|---|---|---|---|
| `ho` | 何宗霖 | 主治醫師 | `Practitioner/practitioner-1` |
| `chien` | 簡怡君 | 護理師 | `Practitioner/practitioner-2` |
| `chiu` | 邱承翰 | 主治醫師 | `Practitioner/practitioner-3` |
| `kang` | 康雅琳 | 護理師 | `Practitioner/practitioner-4` |

綁定靠 Keycloak 的使用者屬性 → `fhirUser` claim。**Practitioner 的 id 是 seed 指定的**
（不是 server 分配的 UUID），所以重灌資料不會讓綁定失效。

### Keycloak 的設定來源是檔案，不是介面

`keycloak/tideng-realm.json` 是唯一的來源。容器用內嵌資料庫、每次啟動重新匯入——
**從管理介面改的東西下次啟動就消失**。要改就改檔案。

⚠️ 檔名必須以 `-realm.json` 結尾。不符合時 Keycloak 會回報
`Import finished successfully` 然後**匯入零個 realm**，realm 根本不存在卻沒有任何錯誤。

⚠️ 匯入檔**不支援** `${env.X}` 替換（實測 Keycloak 26 當成字面值，然後以
`A redirect URI is not a valid URI` 拒絕啟動）。唯一跟主機有關的值是 audience，
用 `@SMART_AUDIENCE@` 佔位、由 compose 在啟動前替換。

---

## iPad 要填哪個 URL

直接填 Siming：**`http://localhost:8080`**。不再經過 smart-launcher-v2，也不需要
`sim/<base64>` 那一段——授權伺服器的位址由 Siming 在 discovery 裡告訴 app。

⚠️ **不要加尾斜線。** 這個字串會原樣成為 authorize 請求的 `aud` 參數，必須與
`SMART_AUDIENCE` 逐字元相同。

| 跑在哪 | 用什麼位址 |
|---|---|
| iPad 模擬器 | `localhost` 直接可用 |
| 實體 iPad | `.env` 的 `PUBLIC_HOST` 改成 Mac 的 LAN IP（`ipconfig getifaddr en0`），且兩者同網段 |

實機還需要 ATS 例外才能走 HTTP——僅限 Debug configuration，Release build 不得包含。

---

## 示範資料

```bash
cd seed && swift run SimingSeed    # 預設 http://localhost:8080
```

可重複執行。Practitioner 以指定 id 寫入（PUT），其餘資源帶固定 identifier 走
`If-None-Exist`，重跑只會回報「已存在」。

Practitioner 的 id 固定（`practitioner-1`…）而非 server 分配的 UUID——Keycloak 的帳號
綁的是 `Practitioner/<id>`，用 UUID 的話每次重灌綁定就失效。

產生 20 位中文姓名的病人、4 位醫事人員（2 醫師 + 2 護理師，各帶 `PractitionerRole`）、
8 筆今日就診、308 筆生命徵象、10 筆用藥。**處方只由醫師開立**——護理師沒有處方權，
輪流指派 `requester` 時若不看角色，資料在有臨床背景的人面前一眼就假。

生命徵象刻意做成三種形狀，各自要證明一件事：

- **跨 48 小時的時序**（42／30／9／3 小時前四個點）——少於這個跨度就看不出走勢，
  而走勢正是趨勢圖存在的理由：38.8 這個數字本身說明不了什麼，「從 37.0 一路升到
  38.8」才是要看的東西
- **3 位病人走惡化趨勢**，最新數值落在 server 提供的參考範圍外。血氧同樣下降
  （96 → 91）但**刻意不帶參考範圍**——同一頁上一個有依據可對照、一個沒有，後者
  用來證明 app 不會對沒有依據的數值做判斷
- **1 位初診病人**（潘冠宇）只有最近一次紀錄，每張圖只有一個點——診所本來就有這種
  病人，順帶讓「單一觀測值也要畫得出來」在真實資料上驗得到

就診紀錄 6 筆已結束（帶 `period.end`）、2 筆仍在診間。**不要讓它們全部開放式**：
沒有 `period.end` 的 period 在 FHIR 裡代表「進行中／結束時間未知」，會被
`date=ge<任何未來時間>` 命中，而且小診所不會同時有 8 位病人在診間裡。

時間一律錨定在**今天之內**平均分布，不是「`now` 往前 N 小時」——後者在半夜灌資料時
會整批跨到昨天，隔天 demo 看到「今日就診 0」而完全看不出原因。

**環境裡只有產生的資料**，沒有任何真實病人；四位醫事人員也是虛構的。

---

## 驗證它真的在擋

這幾條可以當場示範，比講架構有說服力：

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/Patient
#   401 —— 不帶 token

curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer nonsense" \
  http://localhost:8080/Patient
#   401 —— 亂編的 token
```

偽造得再像也一樣：`alg=none`、猜密鑰的 HS256、用自己金鑰正確簽的 RS256，
三種都試過，**即使 `iss`／`aud`／`scope`／`fhirUser` 全部填對，一律 401**。

`/metadata`、`/.well-known/smart-configuration`、`/health` 免驗證（正確——
client 要先讀得到它們才知道去哪裡登入）。

---

## Siming 的能力缺口

實測結果記在 [`../docs/STATUS.md`](../docs/STATUS.md)。動工前值得知道的：

- **只支援 `transaction`，沒有 `batch`** — 唯讀期無影響，但牴觸 tech spec 的離線同步設計
- **`_summary=count` 與一般查詢走不同 SQL** — 同一個 query string，帶不帶 `_summary=count`
  會得到互相矛盾的答案。24 個 store 有 20 個漂移
- **`_count` 上限 100、`_sort` 只認五個欄位**（未知欄位靜默丟棄）

`PractitionerRole`、「搜尋回傳已刪除資源」、「`date` 帶時間被忽略」三項已由 Siming 端
修復並發布為 **v1.1.1**，拉最新的 main 即可。

由此得到的通則：**凡是 UI 對使用者宣告了範圍，那個範圍就必須在 client 端守住。**
server 端的過濾對這個 app 是效能，不是正確性。
