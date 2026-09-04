# 本地開發環境

這個目錄放的是**怎麼把後端跑起來**，不是後端本身。
Siming 的原始碼在自己的 repo（<https://github.com/shinrenpan/Siming>），不複製進來——
兩份 source of truth 遲早會漂移。

## 兩段式啟動

Siming 與 launcher **各自獨立啟動**。不把 Siming 塞進這裡的 compose，是因為那需要寫死
它的 clone 路徑（`build: ../../Siming`），而那個假設換一台機器就失效。

### 1. 起 Siming

```bash
cd ~/Documents/github/Siming
docker-compose up -d db                       # Postgres

# demo 用獨立的資料庫，不動既有資料
docker-compose exec -T db psql -U siming -d postgres -c "CREATE DATABASE siming_demo;"
DATABASE_URL=postgres://siming:siming@localhost:5432/siming_demo swift run SimingServer
```

不設 `SMART_ISSUER` 時 Siming 完全不驗證 bearer token——Phase A 的信任邊界在 launcher，
這是刻意的。

> ⚠️ Siming 的 `scripts/run-macOS.sh` 用的是 `docker compose` 子命令。若你的環境只有獨立的
> `docker-compose`，照上面的指令手動走即可，不要去改那個 repo 的腳本。

### 2. 起 launcher

```bash
colima start          # 若尚未執行
cd Server
docker-compose up -d
```

launcher UI：<http://localhost:8090>

它的 `FHIR_SERVER_R4` 指向 `http://host.docker.internal:8080`（容器連回 host 的位址，
**macOS／Windows 適用，Linux 需另外設定**）。切回公開 server 只需改成
`https://hapi.fhir.org/baseR4` 再 `docker-compose up -d`。

### 3. 灌示範資料

```bash
cd Server/seed
swift run SimingSeed                          # 預設 http://localhost:8080
```

可重複執行：每個資源帶固定的 identifier，以 `If-None-Exist` 做 conditional create，
重跑只會回報「已存在」。

產生 20 位中文姓名的病人、4 位醫事人員（2 位醫師 + 2 位護理師，各帶 `PractitionerRole`）、
8 筆今日就診、308 筆生命徵象、10 筆用藥。處方只由醫師開立——護理師沒有處方權，
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

## iPad 要填哪個 URL

launcher 的 FHIR base URL **不是** `http://localhost:8090`，也不是 `/v/r4/fhir`。
路徑裡必須有 `sim/<base64>` 這一段，它裝的是 launch options：

```
http://localhost:8090/v/r4/sim/e30/fhir
                            ^^^ base64url("{}")，最小的 launch options
```

⚠️ **少了 sim 段時 discovery 仍然會成功**（`.well-known/smart-configuration` 照回），
但 authorize 會回 `Invalid launch options: SyntaxError: Unexpected end of JSON input`。
也就是說問題會一路潛伏到使用者按下登入才爆——查起來很費事，所以 app 內建的 preset
直接把正確格式寫死。

要自訂 launch context（指定醫師、病人、模擬錯誤）時，改開 <http://localhost:8090>
用 UI 產生，它會給一段更長的 base64。

| 跑在哪 | 用什麼位址 |
|---|---|
| iPad 模擬器 | `localhost` 直接可用 |
| 實體 iPad | 換成 Mac 的 LAN IP（`ipconfig getifaddr en0`），且兩者要同網段 |

實機還需要 ATS 例外才能走 HTTP —— 僅限 Debug configuration，Release build 不得包含。

## Siming 的能力缺口

實測結果記在 [`../docs/STATUS.md`](../docs/STATUS.md)。動工前值得知道的三項：

- **只支援 `transaction`，沒有 `batch`** — 唯讀期無影響，但牴觸 tech spec 的離線同步設計
- **`_summary=count` 與一般查詢走不同 SQL** — 同一個 query string，帶不帶 `_summary=count`
  會得到互相矛盾的答案。24 個 store 有 20 個漂移
- **`_count` 上限 100、`_sort` 只認五個欄位**（未知欄位靜默丟棄）

`PractitionerRole`、「搜尋回傳已刪除資源」、「`date` 帶時間被忽略」三項已由 Siming 端修復，
但還在 `fix/search-correctness` 分支上（⚠️ 尚未進 main，從 main clone 會回到有缺陷的版本）。

由此得到的通則：**凡是 UI 對使用者宣告了範圍，那個範圍就必須在 client 端守住。**
server 端的過濾對這個 app 是效能，不是正確性。
