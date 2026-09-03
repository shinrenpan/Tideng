import Foundation

// MARK: - State

extension MainViewModel {

  struct State: Equatable, Sendable {
    var menuItems: [MenuItem] = MenuItem.allCases
    var selection: MenuItem = .patients
    /// 顯示在側邊欄底部，讓使用者知道自己連到哪裡。
    var serverHost: String = ""
    /// 從 id_token 的 fhirUser claim 來，形如 `Practitioner/123`。
    var practitionerReference: String?
  }

  /// 側邊欄項目。
  ///
  /// 純 UI 狀態——伺服器不知道它存在，也不會出現在任何 API 合約裡。
  enum MenuItem: String, Identifiable, CaseIterable, Sendable {
    case patients
    case tasks
    case vitals

    var id: String { rawValue }

    /// PoC 只有病人清單能用，其餘先佔位。
    var isAvailable: Bool { self == .patients }
  }
}
