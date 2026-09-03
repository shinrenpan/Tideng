# 本地開發環境

這個目錄放的是**怎麼把後端跑起來**，不是後端本身。
Siming 的原始碼在自己的 repo（<https://github.com/shinrenpan/Siming>），不複製進來——
兩份 source of truth 遲早會漂移。

## 起服務

```bash
# Docker daemon（本機用 colima）
colima start

cd Server
docker-compose up -d
docker-compose logs -f smart-launcher
```

launcher UI：<http://localhost:8090>

## 兩個階段

| | 後端 | Siming 需要就位嗎 | 目的 |
|---|---|---|---|
| **Phase A**（現在） | HAPI 公開 R4 server | 不需要 | 先把 SMART 登入流程寫通 |
| **Phase B** | Siming | 需要 | 換成自己的 server，驗證 client 零修改 |

切換方式：改 `docker-compose.yml` 的 `FHIR_SERVER_R4`，並把 `siming` / `postgres`
兩個服務取消註解。**iPad 端只換 base URL，程式碼不動**——這是 tech spec 的核心假設，
Phase B 就是在驗證它。

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

## 已知要先驗的事

launcher 的 patient / provider picker 會對後端打 `Patient?...`、`Practitioner?...` 搜尋。
Phase B 切到 Siming 時，**先確認這兩條查詢相容**再寫任何 client 程式碼——
這是 tech spec §6 的 S6 檢查項。
