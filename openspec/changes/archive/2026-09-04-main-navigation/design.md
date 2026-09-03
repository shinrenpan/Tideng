## Context

登入後的主畫面目前是單層：側邊欄項目直接對應內容區。三個項目中只有一個可用，另外兩個標著「待實作」。

本 change 把它改成兩層（側邊欄選大分類 → 內容區 grid 選切片 → 病人清單），並補上登入者身分。真正的難處不在版面，而在四張卡片的計數——FHIR 對其中兩個切片沒有直接可用的查詢，必須在 client 端計算，而這與「首屏要快」直接衝突。

現有約束：唯讀、iPad、Swift 6 strict concurrency、MVVMC。FHIRClient 對 auth 一無所知，透過 TokenProviding 取得憑證。

## Goals / Non-Goals

**Goals:**

- 兩層導航成立：側邊欄大分類 → 內容區切片 grid → 套用切片的病人清單
- 四張卡片各自帶計數，且首屏不被最貴的查詢拖住
- 登入者身分顯示於側邊欄 header，取不到時優雅降級
- 所有使用者可見文案維持「陳述事實、不做判讀」

**Non-Goals:**

- 不引入任何寫入路徑
- 不使用 app 內建的參考範圍常數
- 不做病人詳情頁與趨勢圖（下一個 change）
- 不做三欄 split view
- 不保證計數的絕對精確——見〈計數是下限而非精確值〉
- 不做計數的快取或背景更新，每次進入主畫面重新查詢

## Decisions

### 子分類是病人切片，不是資料類型

原先的方向是把「生命徵象」「檢驗報告」「用藥」並列為頂層入口。已否決。

理由：那是按資料類型分類，但臨床動線永遠是先有病人、再看該病人的資料。FHIR 的資料模型也如此——Observation 與 MedicationRequest 都以 patient 為必要查詢條件。「列出全院的體溫」沒有臨床意義，使用者點進去會走進死路。

改為四個切片後，每張卡片都是同一群病人的不同視角，終點一致（病人清單 → 未來的病人詳情），而且技術上是同一份查詢加不同條件，不是四個獨立功能。

### 計數獨立載入，首屏不等最慢的

四個計數各自是獨立的 request/response 對，各有自己的載入狀態欄位。內容區在任何計數解析之前就完整可見。

替代方案是等四個都回來再一起顯示——已否決。最貴的那個（超出參考值）需要撈回大量 Observation 並在 client 端比對，等它會讓首屏停在空白，而另外三個其實很快。

### 「超出參考值」必須在 client 端算，因此要有明確的取樣邊界

FHIR **沒有**針對 referenceRange 的 search parameter——無法用查詢直接問「哪些 observation 超出參考範圍」。referenceRange 是 Observation 內的欄位，只能撈回來逐筆比對。

因此本切片定義為**近 24 小時內、帶參考範圍、且數值落在範圍外的生命徵象所屬的病人**，並在卡片文案上標明時間窗。這不是技術妥協下的次佳選擇，而是更貼近臨床——醫師關心的本來就是最近的數值，不是三年前的。

取樣邊界：單次查詢上限 500 筆，最多跟隨 2 頁 next 連結。達到上限時計數標示為下限值（見下一節）。

### 一筆不合規的資料不得毀掉整批回應

**實作階段發現的問題。** FHIR R4 規定 `dateTime` 只要帶了時分秒就必須帶時區偏移，
而 FHIRModels 嚴格照規格解析。HAPI 公開 server 的資料有一批不合規（`2026-09-05T08:30:00`
沒有時區），於是 `JSONDecoder().decode(Bundle.self, ...)` 整份拋錯。

實測的比例：MedicationRequest 是 **1/307 筆**壞資料——一筆毀掉三百多筆好的；
Encounter 9/226；Observation 36/72。

對一個定位為「連得上任何 FHIR server」的 app，整批失敗不可接受。真實世界的 server
資料品質本來就參差，client 必須容忍。

作法：先嘗試整份解碼（絕大多數情況會成功，不付額外成本）；失敗時退回逐筆解碼，
跳過解不出來的 entry，並回報跳過的筆數。

跳過的筆數不是可以吞掉的資訊——它讓**從 entry 數出來的**計數失去精確性。因此有 entry
被跳過時，靠去重計數的三個切片一律降級為下限值。

但 `Bundle.total` 例外：那是 server 對自己資料的陳述，與本地解不解得開無關。server 說
307 筆、我們解不出其中一筆，總數仍然是 307。把它一併降級反而是把準確的數字報得比實際差。

不採用的替代方案：在解碼前改寫 JSON 補上時區。那是竄改來源資料，而且要補哪個時區
根本無從得知——猜錯會讓時間顯示錯誤，比跳過該筆更糟。

### 計數是下限而非精確值

三個切片（今日就診、超出參考值、用藥中）都必須撈回資源再依 patient reference 去重，因為 Bundle.total 給的是資源筆數不是病人數——一位病人可能有多次就診或多筆用藥。

而「全部病人」優先讀 Bundle.total；實測 HAPI 公開 server 不回傳 total，故必須有 fallback。

處理方式：拿得到精確值就顯示精確值；只拿得到下限（達到取樣上限、或 total 缺席且還有 next 連結）時，數字後綴一個標記表示「至少」。UI 不得把下限值呈現得像精確值。

### 登入者身分需要兩支查詢，且必須容忍失敗

id_token 的 fhirUser claim 只給 reference。姓名要讀 Practitioner，職位要搜尋 PractitionerRole。

兩支都可能失敗或回傳無用資料——公開 sandbox 上的 Practitioner 資料品質與病人資料一樣差。任一失敗都不得阻斷主畫面：姓名取不到就顯示 reference，職位取不到就不顯示那一行（不留空白佔位）。

姓名的組合規則與 `patient-list` 的病人姓名相同（server 給 text 就用 text；否則 CJK 直接相連、西文以空格分隔）。這是兩個 capability 共用的規則，但目前只有這兩處消費，尚未達到抽成獨立 domain capability 的門檻，故置於 FHIRCore 作為格式化工具而非 domain 邏輯。

### 切片以 primitive 跨越 feature 邊界

當前選取的切片由主畫面持有，以字串識別碼傳給病人清單的 HostController。病人清單不認識主畫面的 Domain Model，主畫面也不認識病人清單的。

### 導航用內容區內的 NavigationStack

點卡片後在內容區 push 病人清單，返回鈕回到 grid。三欄 split view 已否決——iPad 直向下三欄過擠。

## Implementation Contract

**行為**

- 登入完成後主畫面呈現：側邊欄（header 身分／大分類／footer 連線資訊與登出）、內容區（切片卡片 grid）
- 四張卡片在任何計數解析前即完整可見，各自顯示載入指示
- 每個計數獨立解析；任一失敗只影響該卡片，其餘照常顯示，失敗的卡片仍可點擊
- 點卡片在內容區 push 已套用切片條件的病人清單，標題指明當前切片；返回回到 grid 且計數不重新查詢

**介面與資料形狀**

- FHIRClient 新增五個具名查詢：讀取單一 practitioner、依 practitioner 搜尋 role、今日就診（帶 subject include）、進行中的用藥請求、近 24 小時帶參考範圍的生命徵象
- 主畫面的 State 為每個切片各持一個計數欄位與一個載入狀態欄位，不共用單一狀態
- 計數值需能表達「精確」與「至少」兩種語意，UI 依此決定是否加上下限標記
- 病人清單的 HostController 以字串切片識別碼 + base URL 建構，不接收任何 Domain Model

**失敗模式**

- 回應中有無法解碼的 entry → 跳過該筆、其餘照常呈現，並把該切片的計數降級為下限值；整批不得失敗
- practitioner 讀取失敗 → header 顯示 raw reference，不出現錯誤提示（身分顯示不是任務阻斷點）
- practitionerRole 搜尋失敗或無結果 → 省略職位行，不留空白
- 任一計數查詢失敗 → 該卡片顯示計數不可用，其餘不受影響
- observation 無 referenceRange → 不計入，且不視為錯誤
- 病人清單查詢失敗且清單已有內容 → 保留既有內容，不清空

**驗收準則**

- FHIRClient 五個新查詢各有測試，驗證送出的 path 與 query 參數（沿用既有的 URLProtocol stub 模式，測試檔為 App/Packages/FHIRClient/Tests/FHIRClientTests/FHIRSearchTests.swift）
- 超出參考值的判定為純函式並以表格驅動測試，涵蓋：值高於上界、低於下界、位於範圍內、只有下界、只有上界、無參考範圍、非數值型 value
- 姓名組合規則的測試涵蓋：有 text、CJK family+given、西文 family+given、完全無姓名
- 年齡推導的測試涵蓋：完整生日、僅年月、僅年、無生日、生日尚未到
- 模擬器實跑確認四張卡片先出現、計數後到，且單一失敗不影響其他卡片
- 中英文各截圖一次，確認新增文案兩種語言皆到位、且無判讀性字眼

**範圍邊界**

- 範圍內：主畫面（Main）、病人清單（PatientList）、FHIRClient 的查詢定義與其測試、FHIRCore 的參考範圍判定與姓名格式化、字串 catalog 的新增條目、兩個新的測試 target
- 範圍外：病人詳情、趨勢圖、任何寫入路徑、Siming 接入與 seed 資料、既有 SmartAuth 的行為

## Risks / Trade-offs

- **超出參考值在資料量大的 server 上會慢** → 以 24 小時時間窗與 500 筆／2 頁上限框住；卡片獨立載入使其不影響首屏
- **公開 sandbox 缺 referenceRange，該卡片恆為零，Demo 看不出價值** → Siming 的 seed 資料會帶 referenceRange（屬下一個 change）；在那之前此卡片為零是預期行為而非缺陷
- **去重後的計數與使用者對「有幾位病人」的直覺可能有落差**（例如今日就診 12 位，但實際 Encounter 有 15 筆） → 卡片語意固定為病人數，文案明說「位」
- **下限值可能被誤讀為精確值** → UI 對下限值加上明確標記，不以純數字呈現
- **Practitioner 資料品質差導致 header 長期顯示 raw reference** → 屬預期降級行為；Siming seed 會提供正確的 Practitioner 與 PractitionerRole

## Migration Plan

無資料遷移。本 change 不改變任何持久化資料的形狀，Keychain 中的憑證格式不變，使用者不需重新登入。

回退方式為還原本 change 的 commit；既有的登入流程與病人清單查詢不受影響。

## Open Questions

- 公開 server 上 Observation 帶 referenceRange 的實際覆蓋率未知。接上真實 server 後若覆蓋率過低，需重新評估是否改用其他來源（但不得改用 app 內建常數，該路徑已在 proposal 的 Non-Goals 排除）。
- 「今日」的判定目前以裝置時區的當地日期為準。跨時區使用（例如 server 在不同時區）時的正確行為尚未定義，待有實際案例再處理。
