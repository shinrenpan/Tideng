import Foundation
import Testing
@testable import SmartAuth

struct PKCETests {

    @Test("challenge 符合 RFC 7636 附錄 B 的官方測試向量")
    func matchesRFC7636TestVector() {
        // 直接用規格文件給的向量，證明的是「符合規格」而不是「跟我自己算的一致」。
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(pkce.method == "S256")
    }

    @Test("verifier 長度與字元集符合 RFC 7636")
    func verifierIsWellFormed() {
        let pkce = PKCE()
        // 規格允許 43–128 個字元，我們取上限。
        #expect(pkce.verifier.count == 128)

        // 只能是 unreserved 字元：A-Z a-z 0-9 - . _ ~
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))
    }

    @Test("每次產生的 verifier 都不同")
    func verifierIsRandom() {
        let values = Set((0..<50).map { _ in PKCE().verifier })
        #expect(values.count == 50)
    }

    @Test("base64url 不含 padding 與 +/ 字元")
    func base64URLIsClean() {
        let encoded = Data((0..<64).map { UInt8($0) }).base64URLEncodedString()
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
    }
}
