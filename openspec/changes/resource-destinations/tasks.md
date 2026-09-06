## 1. 種子資料

- [x] 1.1 seed 的處方帶四種 dosage 形態，每種至少一筆：一天三次無指定時間、需要時服用、多段遞減劑量、一天兩次帶明確時間。滿足 Requirement: Prescriptions carry dosage instructions in more than one shape。驗證：重建資料庫後連跑兩次 seed，斷言四者各自存在——無 `timeOfDay` 的 `timing.repeat`、`asNeeded`、長度大於一且劑量相異的 `dosageInstruction` 陣列、帶 `timeOfDay` 的 `timing.repeat`；並斷言既有性質不變——處方總數 10 且 requester 全為醫師，病人 20、就診 8、觀測值 308

## 2. 導航分流

- [x] 2.1 落實決策「終點頁由抵達的切片決定，而不是由病人決定」：清單的列被選取時，開啟的畫面由該清單所屬的切片決定，傳遞的仍只有 primitive。滿足 Requirement: List rows open the patient。驗證：TidengTests 對四個切片各斷言一次開啟的目的地，並斷言建構參數皆為 primitive
- [x] 2.2 切片識別字串無法對應到已知切片時導向病歷頁，不崩潰也不空白。落實 design 的失敗模式（Patient 是四者中對任何病人都成立的那一個）。驗證：TidengTests 以無效的切片字串建構清單，斷言選取後開啟病歷頁

## 3. 病歷頁（Patient）

- [x] 3.1 [P] 病歷頁顯示姓名、性別、生日與推算年齡，缺漏欄位整行省略而非填佔位字串。滿足 Requirement: The record view shows the patient resource itself。驗證：TidengTests 注入欄位齊全與無生日兩種 Patient，斷言後者不顯示生日也不顯示年齡
- [x] 3.2 [P] 落實決策「identifier 依型別分辨，無法辨識就不顯示」：病歷號只採用標記為 MR 的 identifier，身分證只採用國民身分證的 identifier system，兩者皆無時各自整行省略；辨識不出用途的 identifier 不顯示。滿足 Requirement: Identifiers are distinguished by what they are for 與 Requirement: The national identifier is shown when the server supplies it。驗證：TidengTests 注入只帶內部灌資料 key 的 Patient，斷言病歷號與身分證兩行皆不出現、且該 key 不以任何形式顯示

## 4. 就診頁（Encounter）

- [x] 4.1 就診頁列出該病人的就診，依開始時間新到舊，每筆顯示 status、class 與開始時間；無就診時明確說明而非空白框。滿足 Requirement: The encounter view shows this patient's visits。驗證：TidengTests 注入時間亂序的三筆就診，斷言呈現順序為開始時間新到舊；另注入空回應斷言顯示無內容而非失敗畫面
- [x] 4.2 落實決策「開放式 period 代表進行中，不用當下時間替代」：有 `period.end` 顯示結束時間；只有 `start` 顯示為進行中且不顯示結束時間；完全沒有 period 時兩者皆不顯示且不宣稱進行中。同時：顯示的是記錄的 `status`，不從 period 推導。滿足 Requirement: An encounter with no end is presented as still open 與 Requirement: The recorded status is shown, not inferred from the period。驗證：TidengTests 對三種 period 形態各斷言一次、斷言「進行中」那筆畫面上不出現任何當下時間；另注入 status 為 finished 但 period 無 end 的就診，斷言顯示的狀態是 finished
- [x] 4.4 participant 解析為 practitioner 姓名，解析不到時顯示 reference，且不影響該筆就診的呈現。滿足 Requirement: The participating practitioner is resolved when the server allows it。驗證：TidengTests 涵蓋解析成功與解析失敗兩種，斷言後者仍列出該筆就診

## 5. 用藥頁（MedicationRequest）

- [x] 5.1 用藥頁列出該病人的處方，每筆顯示藥品、status 與 requester；無處方時明確說明而非空白框。滿足 Requirement: The medication view shows this patient's prescriptions。驗證：TidengTests 注入兩筆處方斷言三個欄位皆呈現；另注入空回應斷言顯示無內容
- [x] 5.2 落實決策「時程照實呈現，絕不展開成具體時間」：有 `timeOfDay` 顯示那些時間；有 frequency／period 但無 `timeOfDay` 顯示次數與週期並明確表示未指定時間；`asNeeded` 顯示為需要時服用且不呈現時程；無法解讀的 timing 顯示為未指定而非留白。滿足 Requirement: Dosage instructions are reproduced, never expanded。驗證：TidengTests 對四種形態各注入一筆，**斷言無 `timeOfDay` 的那筆畫面文字不包含任何具體時間**
- [x] 5.3 每一段 `dosageInstruction` 都顯示且順序不變；完全沒有 `dosageInstruction` 時只顯示藥品、不顯示劑量行也不填補。滿足 Requirement: Every dosage instruction on a prescription is shown。驗證：TidengTests 注入三段遞減劑量的處方，斷言三段皆出現且順序與記錄一致；另注入無 dosageInstruction 的處方斷言只有藥品

## 6. 共通行為與文案

- [x] 6.1 三個新頁面各自具備載入中、成功有內容、成功無內容、失敗四種狀態，且已有內容時失敗不清空——與既有清單一致。驗證：TidengTests 對三個頁面各涵蓋四種情境，並各斷言一次「已有內容時收到失敗，內容仍在」
- [x] 6.2 三頁的查詢建構集中在既有的具名查詢集合，排序在 client 端完成，不依賴 server 的 `_sort`。落實決策「三頁共用一種「取這個病人的某類資源」的查詢形狀」。驗證：FHIRClientTests 對三個新查詢各斷言送出的 resourceType 與 patient 參數；TidengTests 注入亂序回應斷言排序由 client 完成
- [x] 6.3 三頁新增的所有使用者可見文案在 en 與 zh-Hant 皆到位，且不含判讀用語（異常、偏高、需注意、建議、應調整、疑似、逾期）。滿足 Requirement: The record view states facts and never characterises the patient、Requirement: The encounter view states facts and never characterises the visit、Requirement: The medication view offers no clinical judgement。驗證：xcstringstool sync 後 stale 為 0、未翻譯為 0，並逐條人工複查新增字串；特別檢查「未指定時間」的文案不含任何要求使用者採取行動的字眼

## 7. 整體驗證

- [ ] 7.1 完整流程在模擬器上跑一次：四張卡片分別點進去，確認抵達四個不同的畫面，且每個畫面顯示的是該 resource 家族的內容。驗證：四張截圖，各自可辨識出病歷／就診／用藥／趨勢圖
- [ ] 7.2 用藥頁對 seed 的四種 dosage 形態各截一張圖，確認「一天三次未指定時間」那筆畫面上沒有出現任何具體時間。驗證：截圖比對，並以搜尋確認畫面文字不含時鐘格式的字串
