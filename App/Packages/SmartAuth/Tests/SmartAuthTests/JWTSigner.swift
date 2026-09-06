import Foundation
import Security

/// 測試用的 RS256 簽章器：現場產一把 RSA 金鑰，發布對應的 JWKS，並簽出 JWT。
///
/// 用真的金鑰而不是預錄的字串，才測得到真的驗簽——預錄的簽章只要換一個
/// 實作就對不上，那時分不出是實作錯了還是 fixture 過期了。
struct JWTSigner {

  let kid = "test-key"
  private let privateKey: SecKey
  private let publicKey: SecKey

  init() throws {
    var error: Unmanaged<CFError>?
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: 2048,
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error!.takeRetainedValue() as Error
    }
    privateKey = key
    publicKey = SecKeyCopyPublicKey(key)!
  }

  /// server 會發布的 JWKS。
  var jwksJSON: Data {
    var error: Unmanaged<CFError>?
    let der = SecKeyCopyExternalRepresentation(publicKey, &error)! as Data
    let (modulus, exponent) = Self.splitPKCS1(der)
    let jwk: [String: Any] = [
      "keys": [[
        "kty": "RSA", "alg": "RS256", "use": "sig", "kid": kid,
        "n": Self.base64URL(modulus), "e": Self.base64URL(exponent),
      ]]
    ]
    return try! JSONSerialization.data(withJSONObject: jwk)
  }

  func sign(claims: [String: Any], kid overrideKID: String? = nil) throws -> String {
    let header = ["alg": "RS256", "typ": "JWT", "kid": overrideKID ?? kid]
    let headerPart = Self.base64URL(try JSONSerialization.data(withJSONObject: header))
    let payloadPart = Self.base64URL(try JSONSerialization.data(withJSONObject: claims))
    let signingInput = Data("\(headerPart).\(payloadPart)".utf8)

    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      privateKey, .rsaSignatureMessagePKCS1v15SHA256, signingInput as CFData, &error
    ) else {
      throw error!.takeRetainedValue() as Error
    }
    return "\(headerPart).\(payloadPart).\(Self.base64URL(signature as Data))"
  }

  // MARK: -

  /// 從 PKCS#1 的 RSAPublicKey DER 取出 modulus 與 exponent。
  ///
  /// 結構是 `SEQUENCE { INTEGER n, INTEGER e }`，兩個 INTEGER 前面可能有一個
  /// 為了表示正數而加的 0x00，取值時要去掉。
  private static func splitPKCS1(_ der: Data) -> (Data, Data) {
    var index = der.startIndex
    func readLength() -> Int {
      let first = der[index]; index += 1
      if first < 0x80 { return Int(first) }
      let count = Int(first & 0x7F)
      var value = 0
      for _ in 0..<count { value = value << 8 | Int(der[index]); index += 1 }
      return value
    }
    func readInteger() -> Data {
      index += 1                      // 0x02 INTEGER
      let length = readLength()
      var bytes = der[index..<(index + length)]
      index += length
      if bytes.first == 0x00 { bytes = bytes.dropFirst() }
      return Data(bytes)
    }
    index += 1                        // 0x30 SEQUENCE
    _ = readLength()
    return (readInteger(), readInteger())
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
