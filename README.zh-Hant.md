[English](README.md) · 繁體中文

# Tideng 提燈

基於 SMART on FHIR 標準的 iPad 客戶端。

![首頁](Screenshots/dashboard.png)

## 登入

三種登入方式：

1. **自己填 base URL** — 任何支援 SMART on FHIR 標準的伺服器都可以。
2. **Local Siming** — 本專案附的環境，Siming 當 FHIR 伺服器、Keycloak 當授權伺服器，
   帶示範資料。開發和 demo 用這個。
3. **SMART public sandbox** — 指向 `launch.smarthealthit.org`，公開的測試環境。

後兩者只是幫你把 base URL 填好，流程完全一樣。

![登入頁](Screenshots/signin.png)

## 目前實作的 FHIR resource

FHIR R4 定義了一百多個 resource，這裡只做臨床瀏覽用得到的。僅讀取。

- **`Patient`** — 病人清單與病歷
- **`Encounter`** — 就診狀態、時間與參與者
- **`MedicationRequest`** — 處方與給藥指示
- **`Observation`** — 生命徵象趨勢圖
- **`Practitioner`** / **`PractitionerRole`** — 登入者身分、就診參與者、處方開立者

## 跑起來

### App

需要 Xcode 26 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd App && xcodegen generate && open Tideng.xcodeproj
```

登入頁選 **SMART public sandbox** 就能跑，不用起本地伺服器。

### 本地 FHIR 伺服器（選用）

想看示範資料才需要這段。需要 Docker，以及 [Siming](https://github.com/shinrenpan/Siming)
的原始碼（FHIR 伺服器，docker-compose 會從原始碼建 image，所以不能只有 Docker）。

Siming 要放在 Tideng 隔壁：

```
your-folder/
├── Tideng/
└── Siming/
```

```bash
git clone https://github.com/shinrenpan/Siming.git

cd Tideng/Server && docker-compose up -d   # Keycloak + Siming + Postgres
cd seed && swift run SimingSeed            # 20 位病人、8 筆就診、308 筆觀測值、10 張處方
```

放別的地方也可以，設 `SIMING_PATH` 指過去。

在 app 裡點 **Local Siming**，或自己填 `http://localhost:8080`，帳號 `ho`、密碼 `tideng`。

示範資料都是產生的，帳號是虛構的醫事人員，沒有真實個資。

## 技術

### App

- **Swift 6**，strict concurrency
- **SwiftUI** + Swift Charts，iPad only
- **[MVVMC](https://github.com/shinrenpan/MVVMC)** — 自訂架構，一個 feature 一個目錄，
  M / V / VM / C 四層各自的職責與規範
- **FHIR R4** — [apple/FHIRModels](https://github.com/apple/FHIRModels) 鎖 `0.9.3`
- **SMART App Launch v2** — standalone、PKCE、`offline_access`、`id_token` RS256 驗簽
- **218 個測試** — app 112、FHIRCore 37、FHIRClient 25、SmartAuth 44

三個本地 SPM package 的依賴方向是單向的：`SmartAuth → FHIRClient`。
`FHIRClient` 只拿一個 `TokenProviding`，不碰 auth。

### Server

- **[Siming](https://github.com/shinrenpan/Siming)** — FHIR R4 伺服器，只驗證 token
- **Keycloak 26** — 授權伺服器，realm 設定寫在匯入檔裡
- **PostgreSQL 16**
- **docker-compose** — 三個 container，一個指令起完
- **seed** — Swift executable，共用 App 的 `FHIRCore` 產生示範資料

## 專案結構

```
App/        iPad app 與三個本地 package
Server/     本地開發環境（docker-compose）與示範資料 seed
openspec/   Claude Code + Spectra 的規格與改動記錄
```

用 [Spectra](https://github.com/kaochenlong/spectra-app) 做規格驅動開發（SDD）：
先寫提案和設計，通過後才實作，完成歸檔時把規格併進 `openspec/specs/`。
所以 `openspec/specs/` 是現況，`openspec/changes/archive/` 是每次改動當時的判斷。
