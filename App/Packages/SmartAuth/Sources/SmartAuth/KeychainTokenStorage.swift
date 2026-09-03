import Foundation
import Security

/// 把 `TokenSet` 存進 Keychain。
///
/// 以 server profile 的 id 當 account，換 server 時各自獨立、不會混用憑證。
public struct KeychainTokenStorage: TokenPersisting {

    private let service: String

    public init(service: String = "com.shinrenpan.Tideng.smart-tokens") {
        self.service = service
    }

    public func load(profileID: String) -> TokenSet? {
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    public func save(_ tokens: TokenSet, profileID: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }

        // 先刪再加，比 update/add 分支省事，也避免 attribute 殘留舊值。
        delete(profileID: profileID)

        var query = baseQuery(profileID: profileID)
        query[kSecValueData as String] = data
        // 裝置解鎖過一次後才可讀，且不同步到其他裝置與備份。
        // 共用 iPad 的場景下，憑證不該離開這台機器。
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(query as CFDictionary, nil)
    }

    public func delete(profileID: String) {
        SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
    }

    private func baseQuery(profileID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]
    }
}
