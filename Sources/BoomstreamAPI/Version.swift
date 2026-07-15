public enum BoomstreamSDKInfo {
    /// Single source of truth: release-gate сверяет это значение с git-тегом (docs/SDK_ARCHITECTURE.md §10).
    public static let version = "0.1.0"

    /// База User-Agent строки; `ua_allow`-токен добавляется через `BoomstreamOptions.userAgentToken`.
    public static var userAgentBase: String { "Boomstream iOS SDK v\(version)" }

    /// UA-контракт: `"Boomstream iOS SDK v<ver> <token>"`; без токена — база.
    /// Единая точка композиции для api/player/offline модулей.
    public static func userAgent(token: String?) -> String {
        if let token { return "\(userAgentBase) \(token)" }
        return userAgentBase
    }
}
