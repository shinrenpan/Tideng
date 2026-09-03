## 1. 測試落腳處

- [ ] 1.1 [P] FHIRCore 具備可執行的測試 target，且 swift test 在該 package 內可跑出結果。驗證：在 App/Packages/FHIRCore 執行 swift test 回報通過的測試數而非「no tests」
- [ ] 1.2 [P] App target 具備 unit test target（命名 TidengTests），可測試 ViewModel。驗證：xcodebuild test 指定 -only-testing:TidengTests 通過一個確認 ViewModel 可被建構的測試

## 2. FHIR 層的查詢與判定

- [ ] 2.1 [P] FHIRClient 能組出五條新查詢：讀取單一 practitioner、依 practitioner 搜尋 role、今日就診（含 subject include）、進行中的用藥請求、近 24 小時帶參考範圍的生命徵象。生命徵象查詢帶上取樣邊界（24 小時時間窗、單次 500 筆上限），落實 design 決策「「超出參考值」必須在 client 端算，因此要有明確的取樣邊界」。驗證：FHIRSearchTests 針對每條查詢斷言送出的 path 與 query 參數，含時間窗與 count 上限（沿用既有 StubURLProtocol 模式）
- [ ] 2.2 [P] 參考範圍判定為純函式，只依 server 提供的 referenceRange 判斷數值是否落在範圍外，不使用任何內建常數。滿足 Requirement: Out-of-range determination uses only server-supplied ranges。驗證：表格驅動測試涵蓋值高於上界、低於下界、範圍內、只有下界、只有上界、無參考範圍、非數值型 value 共七種輸入
- [ ] 2.3 [P] HumanName 的顯示字串組合規則位於 FHIRCore，`clinical-dashboard` 與 `patient-list` 共用同一實作。支撐 Requirement: Patient rows present identity without interpretation 的姓名部分。驗證：測試涵蓋有 text、CJK family+given 無空格、西文 family+given 有空格、完全無姓名共四種輸入

## 3. 主畫面的狀態與資料

- [ ] 3.1 主畫面 State 能分別表達四個切片各自的計數與載入狀態，且計數值能區分「精確」與「至少」兩種語意。落實 design 決策「計數是下限而非精確值」。驗證：TidengTests 斷言注入單一切片的回應後，只有該切片的狀態改變、其餘維持 prepare；並斷言下限值與精確值在型別上可區分
- [ ] 3.2 側邊欄 header 能呈現登入者姓名與職位，取不到時依序降級為僅姓名、再降級為 raw reference。滿足 Requirement: Sidebar shows the signed-in practitioner。落實 design 決策「登入者身分需要兩支查詢，且必須容忍失敗」。驗證：TidengTests 分別注入「姓名+職位」「僅姓名」「讀取失敗」三種 apiResponse，斷言 state 的 header 欄位符合預期且不含空白佔位
- [ ] 3.3 四個計數各自獨立解析，任一失敗不影響其餘。滿足 Requirement: Slice counts resolve independently。落實 design 決策「計數獨立載入，首屏不等最慢的」。驗證：TidengTests 注入三成功一失敗的回應組合，斷言三個計數有值、失敗者標記為不可用、且四張卡片皆仍可點擊

## 4. 主畫面的呈現與導航

- [ ] 4.1 側邊欄呈現 header、大分類、footer 三段，且不出現任何標記為待實作的佔位項。滿足 Requirement: Sidebar presents top-level categories 與 Requirement: Sidebar footer identifies the connected server。驗證：模擬器截圖確認側邊欄只列出可用的大分類，footer 的 server host 與登出控制正常且登出後回到伺服器輸入畫面
- [ ] 4.2 內容區以 grid 呈現四張切片卡片，卡片在任何計數解析前即可見，各自顯示載入指示；下限值以明確標記呈現而非純數字。滿足 Requirement: Content area presents patient slices as cards。落實 design 決策「子分類是病人切片，不是資料類型」。驗證：模擬器實跑觀察卡片先出現、數字後到；並以 Preview 注入下限值確認標記存在
- [ ] 4.3 點選切片卡片在內容區 push 已套用該切片的病人清單，返回後回到 grid 且計數不重新查詢。滿足 Requirement: Selecting a card opens the corresponding patient list。落實 design 決策「導航用內容區內的 NavigationStack」。驗證：模擬器操作一次「今日就診」卡片的進入與返回，確認清單內容與返回後的計數皆符合

## 5. 病人清單接受切片

- [ ] 5.1 病人清單依傳入的切片識別碼決定查詢條件，且以 primitive 跨越 feature 邊界（不接收任何 Domain Model）。滿足 Requirement: Patient list queries by slice。落實 design 決策「切片以 primitive 跨越 feature 邊界」。驗證：TidengTests 對四個切片各斷言 ViewModel 發出的查詢條件正確，並斷言 HostController 的建構參數皆為 primitive
- [ ] 5.2 清單標題指明當前切片，關鍵字可同時比對姓名與病歷號且無結果時顯示搜尋無結果而非清空既有資料。滿足 Requirement: Patient list filters by keyword。驗證：TidengTests 斷言四個切片的標題各不相同、關鍵字分別命中姓名與病歷號；並以 Preview 確認無結果時的呈現
- [ ] 5.3 既有的四態呈現與病人列欄位在改為切片查詢後仍符合規格。滿足 Requirement: Patient list presents four states in the correct order 與 Requirement: Patient rows present identity without interpretation。驗證：TidengTests 涵蓋首次載入中、載入成功但無資料、已有內容時刷新失敗、首次載入失敗四種情境；並斷言部分精度生日（僅年、僅年月）與缺姓名、缺病歷號時的呈現

## 6. 文案與整體驗證

- [ ] 6.1 本 change 新增的所有使用者可見文案在 en 與 zh-Hant 皆到位，且無判讀性字眼（異常、疑似、需注意、建議）。滿足 Requirement: User-facing text states facts and never clinical judgement。驗證：xcstringstool sync 後 stale 數為 0、未翻譯數為 0；並人工複查新增條目的用字
- [ ] 6.2 完整流程在模擬器上以英文與繁中各跑一次並截圖，確認新版主畫面在兩種語言下皆正確。驗證：以 -AppleLanguages 分別啟動並截圖，比對兩份截圖的文案與版面
