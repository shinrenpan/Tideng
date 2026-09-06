import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

@MainActor
struct PatientRecordViewModelTests {

  private let identity = PatientRecordViewModel.PatientIdentity(id: "p1", name: "王志明")

  private func makeViewModel() throws -> PatientRecordViewModel {
    PatientRecordViewModel(client: try TestSupport.makeClient(), patient: identity)
  }

  /// 灌資料用的內部 key：**沒有 type**，所以不該被當成任何一種號碼顯示。
  private let seedingKey = #"{ "system": "urn:tideng:demo", "value": "patient-1" }"#

  private let medicalRecordNumber = """
  { "system": "urn:oid:2.16.886.101.20003.20001.1", "value": "A0000001",
    "type": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" }] } }
  """

  private let nationalIdentifier = """
  { "system": "http://www.moi.gov.tw", "value": "A100000001",
    "type": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "NNxxx" }] } }
  """

  private func patient(
    identifiers: [String], gender: String? = "male", birthDate: String? = "1958-03-12"
  ) throws -> FHIRBundleDecoder.Result {
    let fields = [
      gender.map { #""gender": "\#($0)""# },
      birthDate.map { #""birthDate": "\#($0)""# }
    ].compactMap { $0 }

    return TestSupport.response(try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [
      { "resource": { "resourceType": "Patient", "id": "p1",
          "name": [{ "family": "王", "given": ["志明"] }],
          "identifier": [\(identifiers.joined(separator: ","))]
          \(fields.isEmpty ? "" : "," + fields.joined(separator: ",")) } }
    ] }
    """))
  }

  // MARK: - 欄位齊全與缺漏

  @Test
  func `欄位齊全時姓名性別生日與年齡都呈現`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [seedingKey, medicalRecordNumber, nationalIdentifier])
    ))))

    let record = try #require(viewModel.state.record)
    #expect(record.name == "王志明")
    #expect(record.gender == .male)
    #expect(record.birthDate?.year == 1958)
    #expect(record.birthDate?.month == 3)
    #expect(record.birthDate?.day == 12)
    // 年齡由生日推導，不另存——固定基準日，否則斷言會隨執行日期漂移。
    let asOf = try #require(
      Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 6))
    )
    #expect(record.age(asOf: asOf) == 68)
  }

  @Test
  func `沒有生日時生日與年齡皆不顯示`() async throws {
    // 年齡是從生日推導的：沒有生日就沒有年齡可說，兩者必須同進退。
    // 這也是「缺漏欄位整行省略、不填佔位字串」的實作點。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [medicalRecordNumber], birthDate: nil)
    ))))

    let record = try #require(viewModel.state.record)
    #expect(record.birthDate == nil)
    #expect(record.age() == nil)
  }

  @Test
  func `resource 沒有 gender 欄位與 gender 記為 unknown 是兩件事`() async throws {
    // `.unknown` 是 FHIR 的合法值，意思是「記錄過，而記的是不詳」；
    // 欄位不存在則是「沒記」。合併兩者會讓畫面替記錄多說一句話。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [medicalRecordNumber], gender: nil)
    ))))
    #expect(try #require(viewModel.state.record).gender == nil)

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [medicalRecordNumber], gender: "unknown")
    ))))
    #expect(try #require(viewModel.state.record).gender == .unknown)
  }

  // MARK: - identifier 依型別分辨

  @Test
  func `只有內部 key 時病歷號與身分證兩行皆不出現`() async throws {
    // 這個 bug 發生過：病歷號欄位顯示的是 server 的內部識別碼。
    // 一個沒有標籤的號碼會讓讀的人自己假設它是他認得的那一個。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [seedingKey])
    ))))

    let record = try #require(viewModel.state.record)
    #expect(record.recordNumber == nil)
    #expect(record.nationalIdentifier == nil)
    // 那個 key 不得以任何形式出現在畫面資料裡。
    for child in Mirror(reflecting: record).children {
      #expect((child.value as? String) != "patient-1")
    }
  }

  @Test
  func `病歷號只採用標記為 MR 的那一個`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [seedingKey, medicalRecordNumber])
    ))))

    let record = try #require(viewModel.state.record)
    #expect(record.recordNumber == "A0000001")
    #expect(record.nationalIdentifier == nil)
  }

  @Test
  func `身分證號以 system 認定`() async throws {
    // 以 system 而不是 type coding 的 code 認定：TW Core 把它標成 `NNxxx`，
    // 真正說明是哪一國的是 code 上的 extension——比比對一個 URI 脆弱得多。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [seedingKey, nationalIdentifier])
    ))))

    let record = try #require(viewModel.state.record)
    #expect(record.nationalIdentifier == "A100000001")
    #expect(record.recordNumber == nil)
  }

  // MARK: - 四態

  @Test
  func `四種狀態各自到位`() async throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.api.loadRecord == .prepare)
    #expect(viewModel.state.record == nil)

    // 成功但 server 沒有這筆：不是失敗，是真的沒有。
    await viewModel.doAction(.apiResponse(.record(.success(TestSupport.response(
      try TestSupport.bundle(#"{ "resourceType": "Bundle", "type": "searchset", "entry": [] }"#)
    )))))
    #expect(viewModel.state.api.loadRecord == .success)
    #expect(viewModel.state.record == nil)

    // 成功且有內容
    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [medicalRecordNumber])
    ))))
    #expect(viewModel.state.api.loadRecord == .success)
    #expect(viewModel.state.record != nil)

    // 失敗
    await viewModel.doAction(.apiResponse(.record(.failure(.transport(message: "boom")))))
    if case .error = viewModel.state.api.loadRecord {} else {
      Issue.record("失敗應該進入 error 狀態")
    }
  }

  @Test
  func `已有內容時失敗不清空`() async throws {
    // 刷新失敗時，使用者眼前的資料要留著——不能換成錯誤畫面。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.record(.success(
      try patient(identifiers: [medicalRecordNumber])
    ))))
    await viewModel.doAction(.apiResponse(.record(.failure(.transport(message: "boom")))))

    #expect(viewModel.state.record?.recordNumber == "A0000001")
  }

  @Test
  func `首次出現只觸發一次載入`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.view(.isFirstAppear))
    #expect(viewModel.state.isFirstAppear == false)

    // 第二次被 guard 擋下：狀態停在第一次的結果，不會重新變回 loading。
    let after = viewModel.state.api.loadRecord
    await viewModel.doAction(.view(.isFirstAppear))
    #expect(viewModel.state.api.loadRecord == after)
  }
}
