## Why

目前主畫面的側邊欄直接對應內容區，只有一層。這個結構撐不起接下來要加的功能，而且側邊欄現在只有一個可用項目加兩個「待實作」佔位，拿給診所看會像半成品。

更根本的問題是資訊架構的方向錯了：原先規劃把「生命徵象」「檢驗報告」「用藥」當成並列的頂層入口，但那是按資料類型分類。臨床的心智模型從來是先有病人、再看該病人的資料——FHIR 的資料模型也是如此（Observation、MedicationRequest 都以 patient 為必要查詢條件）。「列出全院的體溫」不是任何人會做的事。

## What Changes

- 主畫面改為兩層導航：側邊欄選大分類，右側 grid 是該分類底下的子分類入口
- 側邊欄新增 header，顯示登入者的姓名與職位；取不到時退回顯示 Practitioner reference
- 側邊欄中段為大分類，目前只有「病患」一項；移除「排程」「報表」兩個佔位項
- 側邊欄 footer 維持現況：server host、Practitioner reference、登出
- 右側 grid 的卡片是**同一群病人的不同切片**，不是資料類型：全部病人、今日就診、超出參考值、用藥中
- 每張卡片顯示該切片的病人數，四個計數各自非同步載入、各有獨立載入狀態
- 點卡片進入已套用該切片條件的病人清單，清單標題反映當前切片
- FHIRClient 新增五條查詢：Practitioner 讀取、PractitionerRole 搜尋、今日就診、用藥中、帶參考範圍的生命徵象
- 參考範圍判定與 HumanName 顯示規則移入 FHIRCore，兩個 feature 共用同一實作
- 補上兩個缺席的測試落腳處：FHIRCore 的測試 target，以及 App target 的 unit test target（ViewModel 測試目前無處可放）

## Non-Goals

- **不做寫入**。整個 app 維持唯讀，本 change 不引入任何 create/update 路徑
- **不使用 app 內建的參考範圍常數**。「超出參考值」只採用 server 在 Observation.referenceRange 提供的範圍，server 未提供就不標記。內建常數等同於由 app 定義何謂正常，那是臨床判讀。代價是 server 不給 referenceRange 時該卡片恆為零——接到真實 server、取得實際覆蓋率數據後再評估是否退讓
- **不做「排程」「報表」大分類**。等真的要實作時再加，列佔位項只會讓畫面顯得半成品
- **不做病人詳情頁與生命徵象趨勢圖**。那是下一個 change，本 change 的清單點擊行為維持現況（不導航）
- **不做三欄 split view**。iPad 直向下三欄過擠，已排除
- **不產生任何臨床判讀文案**。卡片名為「超出參考值」而非「異常」；不出現「疑似」「需注意」「建議」等字眼

## Capabilities

### New Capabilities

- `clinical-dashboard`: 登入後的主畫面。側邊欄呈現登入者身分與大分類，內容區以 grid 呈現病人切片入口與各自計數
- `patient-list`: 病人清單。依切片條件查詢並呈現病人，支援關鍵字過濾與四態呈現

### Modified Capabilities

(none)

## Impact

- Affected specs: `clinical-dashboard`, `patient-list`
- Affected code:
  - New:
    - App/Sources/Pages/Main/MainMocks.swift
    - App/Packages/FHIRClient/Tests/FHIRClientTests/FHIRSearchTests.swift
    - App/Packages/FHIRCore/Sources/FHIRCore/ReferenceRange.swift
    - App/Packages/FHIRCore/Sources/FHIRCore/HumanName+Display.swift
    - App/Packages/FHIRCore/Tests/FHIRCoreTests/ReferenceRangeTests.swift
    - App/Packages/FHIRCore/Tests/FHIRCoreTests/HumanNameDisplayTests.swift
    - App/Tests/TidengTests/MainViewModelTests.swift
    - App/Tests/TidengTests/PatientListViewModelTests.swift
  - Modified:
    - App/Packages/FHIRCore/Package.swift
    - App/project.yml
    - App/Sources/Pages/Main/MainViewModel+Models.swift
    - App/Sources/Pages/Main/MainViewModel.swift
    - App/Sources/Pages/Main/MainView.swift
    - App/Sources/Pages/Main/MainHostController.swift
    - App/Sources/Pages/PatientList/PatientListViewModel+Models.swift
    - App/Sources/Pages/PatientList/PatientListViewModel.swift
    - App/Sources/Pages/PatientList/PatientListView.swift
    - App/Sources/Pages/PatientList/PatientListMocks.swift
    - App/Packages/FHIRClient/Sources/FHIRClient/FHIRSearch.swift
    - App/Resources/Localizable.xcstrings
  - Removed: (none)
