import Foundation

/// 提供 access token 給 `FHIRClient`。
///
/// 定義在 client 這一側、由 auth 模組去實作，是為了讓 `FHIRClient` 對 SMART 流程一無所知——
/// 它可以完全脫離 auth 單獨測試，換掉登入方式也不必動 client。
public protocol TokenProviding: Sendable {
    /// 回傳當下可用的 access token；不需驗證的 server 回 `nil`。
    func validToken() async throws -> String?
}

/// 不帶驗證。用於公開 FHIR endpoint 與測試。
public struct NoAuthentication: TokenProviding {
    public init() {}
    public func validToken() async throws -> String? { nil }
}
