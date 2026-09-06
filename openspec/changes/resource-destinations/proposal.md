## Why

這個 repo 的目的已經定調為**「iOS + FHIR 能力的證據」而不是產品**：公開原始碼、證明熟悉 iOS 與 FHIR、證明正確實作了 SMART 登入。

在那個目標下，判斷標準跟做產品時相反。做產品時該砍到只剩最強的一件事；做證據時，**涵蓋面就是說服力**——四個 FHIR resource 家族各做對一次，比一個畫面做得漂亮更能證明。

但廣度只有在每一個都做對時才算數。四個半成品的說服力低於兩個紮實的，所以這裡的重點不是「多做三頁」，是「每一頁都展示一個真的不好處理的地方」。

現況也確實有缺陷：四張切片卡片點進去都是同一份病人清單，清單再點進去都是同一個生命徵象詳情頁。使用者按了「超出參考值 3」，得到三個名字、性別、年齡、病歷號——**跟按「全部病人」拿到的那一列一模一樣，看不出來為什麼這幾個人在這裡**。

更根本的是，有兩張卡片的主角根本不是病人：「用藥中」的主角是藥，「超出參考值」的主角是數值。拿病人清單去回答「哪些數值動了」，形狀本來就不對。

## What Changes

- **病人清單依抵達的切片導向不同的終點頁。** 切片已經在清單的 state 裡，分流是既有結構的延伸，不是新機制。
- **新增「病歷」終點頁**（來自「全部病人」）：Patient resource 本身。展示 identifier 的分辨（病歷號與內部灌資料用的 key 是兩回事）、TW Core 的身分證欄位、性別、生日與推算年齡。缺漏欄位省略，不填佔位字串。
- **新增「就診狀態」終點頁**（來自「今日就診」）：Encounter。展示 status、period、class 與 participant 解析到 Practitioner。**開放式 period（只有 start 沒有 end）代表就診進行中**——這個語意在 demo-data 那輪已經理解過，現在讓它出現在畫面上。
- **新增「用藥」終點頁**（來自「用藥中」）：MedicationRequest。展示藥品的 CodeableConcept、`dosageInstruction` 與 `timing`、status 與 requester。**timing 照實呈現，不自行展開成具體時間點。**
- **「超出參考值」維持導向現有的生命徵象詳情頁**，不動。
- **seed 擴充 `dosageInstruction`**，塞四種刻意選過的形態。簡單的形態證明不了什麼——會被展示的是那些難的：
  - **q8h 但沒有 `timeOfDay`**（`frequency=3, period=1, periodUnit=d`）。最常見也最難：展開成哪三個時間點**不是 FHIR 資料能回答的**，那是機構的給藥常規。`NIS-TECH-SPEC.md` §5.4 記過這個坑。
  - **PRN**（`asNeededCodeableConcept`）：需要時服用，沒有固定時間。任何自動排時間表的實作都會在這裡做錯。
  - **tapering**：一筆處方帶多段 `dosageInstruction`，劑量遞減。序列很容易被壓平成一行。
  - **bid 帶明確 `timeOfDay`**：對照組。用來對比上面三個「資料沒說」的情況。

## Non-Goals

- 不新增第五張切片卡片。這個 change 是把既有四張走完，不是擴充目錄。
- 不做編輯模式與收費閘門。卡片目錄還不夠厚，而且買方未定，現在做等於把猜測固化進 UI。
- 不做 `MedicationAdministration` 或給藥核對。那是寫入路徑，本案維持唯讀。
- 不做給藥時間表的展開或提醒。那需要機構的給藥常規當輸入，而那個輸入不存在於 FHIR 資料裡。

## Capabilities

### New Capabilities

- `patient-record`: 「病歷」終點頁——Patient resource 的識別與人口學欄位如何呈現。
- `encounter-status`: 「就診狀態」終點頁——Encounter 的狀態、期間與參與者如何呈現，包含進行中的表示方式。
- `medication-list`: 「用藥」終點頁——MedicationRequest 的藥品、劑量與時程如何呈現，以及不得自行展開時程的界線。

### Modified Capabilities

- `patient-list`: 選取病人後開啟的終點頁，由抵達的切片決定，而不是永遠同一個。
- `demo-data`: 用藥資料必須帶有四種不同形態的 `dosageInstruction`，其中三種是資料本身沒有講清楚時間的情況。

## Impact

- Affected specs: `patient-record`（新增）、`encounter-status`（新增）、`medication-list`（新增）、`patient-list`（修改）、`demo-data`（修改）
- Affected code:
  - New:
    - `App/Sources/Pages/PatientRecord/PatientRecordViewModel.swift`
    - `App/Sources/Pages/PatientRecord/PatientRecordViewModel+Models.swift`
    - `App/Sources/Pages/PatientRecord/PatientRecordView.swift`
    - `App/Sources/Pages/EncounterStatus/EncounterStatusViewModel.swift`
    - `App/Sources/Pages/EncounterStatus/EncounterStatusViewModel+Models.swift`
    - `App/Sources/Pages/EncounterStatus/EncounterStatusView.swift`
    - `App/Sources/Pages/MedicationList/MedicationListViewModel.swift`
    - `App/Sources/Pages/MedicationList/MedicationListViewModel+Models.swift`
    - `App/Sources/Pages/MedicationList/MedicationListView.swift`
  - Modified:
    - `App/Sources/Pages/PatientList/PatientListView.swift`
    - `App/Sources/Pages/PatientList/PatientListViewModel.swift`
    - `App/Packages/FHIRClient/Sources/FHIRClient/FHIRSearch.swift`
    - `App/Packages/FHIRCore/Sources/FHIRCore/FHIRCore.swift`
    - `Server/seed/Sources/SimingSeed/ResourceBuilder.swift`
    - `Server/seed/Sources/SimingSeed/SeedData.swift`
    - `App/Resources/Localizable.xcstrings`
  - Removed: 無
