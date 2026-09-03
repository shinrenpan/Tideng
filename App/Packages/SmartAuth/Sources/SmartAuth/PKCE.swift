import Foundation
import CryptoKit

/// PKCE（RFC 7636）的 verifier / challenge 組。
///
/// public client 沒有 client_secret，PKCE 是唯一能證明「拿 code 去換 token 的人，
/// 就是當初發起授權的那個 app」的機制。
public struct PKCE: Sendable, Equatable {

    public let verifier: String
    public let challenge: String
    public let method = "S256"

    public init() {
        self.verifier = Self.makeVerifier()
        self.challenge = Self.makeChallenge(from: verifier)
    }

    /// 測試用：以固定 verifier 建立，驗證 challenge 的推導是否正確。
    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.makeChallenge(from: verifier)
    }

    /// RFC 7636 允許 43–128 個 unreserved 字元。取上限：96 bytes 經 base64url 後正好 128 字元。
    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 96)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // CSPRNG 失敗代表系統層級異常，退回去用弱亂數產生授權憑證是不可接受的。
            fatalError("SecRandomCopyBytes 失敗：OSStatus \(status)")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {

    /// base64url（RFC 4648 §5）：`+/` 換成 `-_`，去掉 padding。
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
