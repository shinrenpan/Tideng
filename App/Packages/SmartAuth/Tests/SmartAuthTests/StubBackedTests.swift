import Testing

/// 所有共用 `StubURLProtocol` 靜態狀態的測試都掛在這個 suite 底下。
///
/// `.serialized` 標在單一 suite 上只序列化該 suite 內部——不同 suite 之間仍會並行，
/// 於是它們會互相覆寫 stub 的回應，症狀是測試各自拿到別人設定的 body 而詭異失敗。
/// 標在共同的 parent 上才會遞迴套用到所有子 suite。
@Suite(.serialized)
struct StubBackedTests {}
