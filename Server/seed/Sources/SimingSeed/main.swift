import Foundation
import FHIRCore
import ModelsR4

// MARK: - 參數

let defaultBaseURL = "http://localhost:8080"
let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    SimingSeed — 灌入可 demo 的台灣診所示範資料

    用法：
      swift run SimingSeed [base-url]

      base-url  FHIR server 的位址，預設 \(defaultBaseURL)

    可重複執行：每個資源帶固定的 identifier，以 If-None-Exist 做 conditional create，
    重跑不會產生重複資料。
    """)
    exit(0)
}

let baseURLString = arguments.dropFirst().first { !$0.hasPrefix("-") } ?? defaultBaseURL
guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil else {
    FileHandle.standardError.write(Data("位址格式不正確：\(baseURLString)\n".utf8))
    exit(2)
}

let client = FHIRSeedClient(baseURL: baseURL)

print("目標 server：\(baseURL.absoluteString)")
guard await client.reachable() else {
    FileHandle.standardError.write(Data("""
    無法連線到 \(baseURL.absoluteString)
    請確認 server 已啟動（Siming: scripts/run-macOS.sh，或見 Server/README.md）
    
    """.utf8))
    exit(1)
}

// MARK: - 時間基準

let now = Date()
let hour: TimeInterval = 3600

// MARK: - Practitioner

var practitionerTally = SeedTally()
var practitionerIDs: [String] = []
/// seq → server 分配的 id。角色要掛回正確的人，不能靠陣列位置（有人建立失敗就會錯位）。
var practitionerIDBySeq: [Int: String] = [:]

for spec in SeedData.practitioners {
    let (resource, identifier) = ResourceBuilder.practitioner(spec)
    let outcome = try await client.post(
        resource,
        type: "Practitioner",
        identifierSystem: SeedData.identifierSystem,
        identifierValue: identifier
    )
    practitionerTally.record(outcome, identifier: identifier)
    if let id = outcome.id {
        practitionerIDs.append(id)
        practitionerIDBySeq[spec.seq] = id
    }
}

guard !practitionerIDs.isEmpty else {
    FileHandle.standardError.write(Data("沒有任何 Practitioner 建立成功，後續資源無法引用\n".utf8))
    exit(1)
}

// MARK: - PractitionerRole

var practitionerRoleTally = SeedTally()

for spec in SeedData.practitionerRoles {
    guard let practitionerID = practitionerIDBySeq[spec.seq] else { continue }
    let (resource, identifier) = ResourceBuilder.practitionerRole(
        practitionerID: practitionerID,
        spec: spec
    )
    let outcome = try await client.post(
        resource,
        type: "PractitionerRole",
        identifierSystem: SeedData.identifierSystem,
        identifierValue: identifier,
        // 這個 resource 的 identifier 在 Siming 上沒有索引，拿它當條件會比對到
        // 不相干的資源、然後靜默跳過。practitioner 有索引，而且語意也更對：
        // 這位醫事人員已經有角色就不要重建。
        condition: "practitioner=\(practitionerID)"
    )
    practitionerRoleTally.record(outcome, identifier: identifier)
}

/// 有處方權的醫事人員。護理師不在其中。
let prescriberIDs = SeedData.practitionerRoles
    .filter { SeedData.prescriberRoleCodes.contains($0.code) }
    .compactMap { practitionerIDBySeq[$0.seq] }

guard !prescriberIDs.isEmpty else {
    FileHandle.standardError.write(Data("沒有任何具處方權的醫事人員，MedicationRequest 無法指派 requester\n".utf8))
    exit(1)
}

// MARK: - Patient

var patientTally = SeedTally()
/// seq → server 分配的 id
var patientIDs: [Int: String] = [:]

for spec in SeedData.patients {
    let (resource, identifier) = ResourceBuilder.patient(spec)
    let outcome = try await client.post(
        resource,
        type: "Patient",
        identifierSystem: SeedData.identifierSystem,
        identifierValue: identifier
    )
    patientTally.record(outcome, identifier: identifier)
    if let id = outcome.id { patientIDs[spec.seq] = id }
}

// MARK: - Encounter（今日就診）

var encounterTally = SeedTally()

let startOfToday = Calendar.current.startOfDay(for: now)
let encounterSequences = SeedData.recentPatientSequences.sorted()

for (order, seq) in encounterSequences.enumerated() {
    guard let patientID = patientIDs[seq] else { continue }
    let practitionerID = practitionerIDs[seq % practitionerIDs.count]
    // 平均分布在「今天已經過去的時段」裡。
    //
    // 原本是 now 往前 1–6 小時，那會跨午夜：半夜灌資料時就診全部落到昨天，
    // 隔天 demo 看到「今日就診 0」而完全不知道為什麼。改成錨定在今天之內，
    // 灌資料的時刻再早也不會跨日；代價只是清晨灌的話就診會擠在一起，
    // 而那個時段本來就沒人在 demo。
    let elapsed = now.timeIntervalSince(startOfToday)
    let slot = elapsed / Double(encounterSequences.count + 1)
    let start = startOfToday.addingTimeInterval(slot * Double(order + 1))
    // 最後兩位病人還在診間，其餘看完離開了。小診所不會同時有 8 位病人在裡面，
    // 而且開放式 period 在 FHIR 裡代表「還沒結束」，會被時間查詢一直命中。
    let stillHere = SeedData.inProgressPatientSequences.contains(seq)
    let (resource, identifier) = ResourceBuilder.encounter(
        patientID: patientID,
        practitionerID: practitionerID,
        seq: seq,
        start: start,
        // 看診結束不能晚於現在——清晨灌資料時 20 分鐘會超過當下
        end: stillHere ? nil : min(start.addingTimeInterval(SeedData.consultationMinutes * 60), now)
    )
    let outcome = try await client.post(
        resource,
        type: "Encounter",
        identifierSystem: SeedData.identifierSystem,
        identifierValue: identifier
    )
    encounterTally.record(outcome, identifier: identifier)
}

// MARK: - Observation（生命徵象）

var observationTally = SeedTally()
var observationSeq = 0

for spec in SeedData.patients {
    guard let patientID = patientIDs[spec.seq] else { continue }

    // 走勢惡化的病人用 rising，其餘用 steady。每位病人都有跨越 48 小時的完整時序——
    // 少於這個範圍就看不出走勢，而走勢正是趨勢圖存在的理由。
    let isRising = SeedData.outOfRangeSequences.contains(spec.seq)

    // 初診病人只有最新那一次紀錄——診所本來就會有這種病人，
    // 順帶讓「單點也要畫得出來」這件事在真實資料上看得到。
    let timeline: [(index: Int, hoursAgo: Double)] =
        SeedData.firstVisitSequences.contains(spec.seq)
        ? [(SeedData.observationHoursAgo.count - 1, SeedData.observationHoursAgo[SeedData.observationHoursAgo.count - 1])]
        : SeedData.observationHoursAgo.enumerated().map { (index: $0.offset, hoursAgo: $0.element) }

    for (index, hoursAgo) in timeline {
        for vital in SeedData.vitals {
            observationSeq += 1

            // 走勢惡化的病人，四項生命徵象一律走 rising——血氧也不例外。
            // 血氧沒有參考範圍，所以它會是一條明顯下降、卻不帶任何判定的線；
            // 那正是「沒有依據就不判讀」要示範的東西。
            let trend = isRising ? vital.rising : vital.steady
            let value = trend[min(index, trend.count - 1)]

            let (resource, identifier) = ResourceBuilder.observation(
                patientID: patientID,
                vital: vital,
                value: value,
                recordedAt: now.addingTimeInterval(-hoursAgo * hour),
                seq: observationSeq
            )
            let outcome = try await client.post(
                resource,
                type: "Observation",
                identifierSystem: SeedData.identifierSystem,
                identifierValue: identifier
            )
            observationTally.record(outcome, identifier: identifier)
        }
    }
}

// MARK: - MedicationRequest（用藥中）

let medications = [
    "Amoxicillin 500mg 膠囊", "Metformin 500mg 錠", "Amlodipine 5mg 錠",
    "Atorvastatin 10mg 錠", "Losartan 50mg 錠", "Acetaminophen 500mg 錠",
    "Omeprazole 20mg 膠囊", "Aspirin 100mg 錠", "Levothyroxine 50mcg 錠",
    "Salbutamol 吸入劑"
]

var medicationTally = SeedTally()

for (index, medication) in medications.enumerated() {
    let seq = index + 1
    guard let patientID = patientIDs[seq] else { continue }
    // requester 只能是有處方權的人，不能沿用 Encounter 那條「所有人輪流」的路徑
    let practitionerID = prescriberIDs[seq % prescriberIDs.count]
    let (resource, identifier) = ResourceBuilder.medicationRequest(
        patientID: patientID,
        practitionerID: practitionerID,
        medication: medication,
        seq: seq,
        authoredOn: now.addingTimeInterval(-Double(seq) * 24 * hour)
    )
    let outcome = try await client.post(
        resource,
        type: "MedicationRequest",
        identifierSystem: SeedData.identifierSystem,
        identifierValue: identifier
    )
    medicationTally.record(outcome, identifier: identifier)
}

// MARK: - 結果

print("")
let results: [(String, SeedTally)] = [
    ("Practitioner", practitionerTally),
    ("PractitionerRole", practitionerRoleTally),
    ("Patient", patientTally),
    ("Encounter", encounterTally),
    ("Observation", observationTally),
    ("MedicationRequest", medicationTally)
]

for (name, tally) in results {
    print(String(format: "  %-18s 建立 %3d  已存在 %3d  失敗 %3d",
                 (name as NSString).utf8String!, tally.created, tally.existing, tally.rejected.count))
}

let failures = results.flatMap { $0.1.rejected }
if failures.isEmpty {
    print("\n完成。")
    exit(0)
} else {
    print("\n有 \(failures.count) 筆被拒絕：")
    for failure in failures.prefix(10) {
        print("  \(failure.identifier) → \(failure.detail)")
    }
    exit(1)
}
