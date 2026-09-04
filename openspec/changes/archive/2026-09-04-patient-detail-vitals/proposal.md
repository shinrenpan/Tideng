## Why

到目前為止 app 只能列出病人和數出人數。點進任何一位病人都沒有反應——臨床上真正要看的東西，一樣也還沒做。

而 dashboard 的價值主張從來不是「有幾位病人」，是**看得出變化**。一個體溫 38.5 的數字本身說明不了什麼；38.5 是從 36.8 一路升上來的，還是從 39.2 退下來的，才是臨床判斷的依據。這件事只有趨勢圖做得到。

seed 資料已經備妥每位病人 48 小時的時序資料，前置條件到齊。

## What Changes

- 病人清單的每一列可點擊，進入該病人的詳情頁
- 新增病人詳情頁：基本資料（姓名、性別、年齡、病歷號）加上生命徵象區
- 生命徵象以 Swift Charts 繪製 48 小時趨勢圖，每種項目一張圖
- server 有提供參考範圍時，圖上以區間帶呈現該範圍——**呈現界限本身，不標記任何一點為異常**
- 觀測值在 client 端依時間排序後才繪製，不依賴 server 的 `_sort`
- 詳情頁在 iPad 上顯示於內容區，返回回到清單且清單狀態保留

## Non-Goals

- **不做寫入**。整個 app 維持唯讀，詳情頁不提供編輯或新增觀測值
- **不做用藥、檢驗、診斷、過敏等其他資料區塊**。這個 change 只做生命徵象；一次做完所有區塊會讓趨勢圖本身得不到該有的注意
- **不做跨病人的趨勢比較**。臨床動線是看一位病人的變化，不是比較兩個人
- **不標記任何觀測點為異常、不提示嚴重程度、不建議任何行動**。可以畫出 server 提供的參考範圍區間帶，讓使用者自己看到數值落在哪裡；不可以用顏色、圖示或文字宣告那個數值「不正常」。前者是呈現事實，後者是臨床判讀
- **不做時間範圍的切換**（7 天／30 天）。48 小時是 seed 資料的範圍，也是急性照護真正關心的窗口；要更長的區間等有人提出再說
- **不快取觀測值**。每次進入詳情頁重新查詢

## Capabilities

### New Capabilities

- `patient-detail`: 單一病人的詳情。呈現身分資料與生命徵象的時序變化，不做任何臨床判讀

### Modified Capabilities

- `patient-list`: 清單列從純展示變為可選取，並在選取時導向詳情

## Impact

- Affected specs: `patient-detail`, `patient-list`
- Affected code:
  - New:
    - App/Sources/Pages/PatientDetail/PatientDetailViewModel+Models.swift
    - App/Sources/Pages/PatientDetail/PatientDetailViewModel.swift
    - App/Sources/Pages/PatientDetail/PatientDetailView.swift
    - App/Sources/Pages/PatientDetail/PatientDetailHostController.swift
    - App/Sources/Pages/PatientDetail/PatientDetailMocks.swift
    - App/Tests/TidengTests/PatientDetailViewModelTests.swift
  - Modified:
    - App/Packages/FHIRClient/Sources/FHIRClient/FHIRSearch.swift
    - App/Packages/FHIRClient/Tests/FHIRClientTests/FHIRSearchTests.swift
    - App/Packages/FHIRCore/Sources/FHIRCore/Observation+Time.swift
    - App/Sources/Pages/PatientList/PatientListViewModel.swift
    - App/Sources/Pages/PatientList/PatientListView.swift
    - App/Sources/Pages/PatientList/PatientListHostController.swift
    - App/Sources/Pages/Main/MainView.swift
    - App/Resources/Localizable.xcstrings
  - Removed: (none)
