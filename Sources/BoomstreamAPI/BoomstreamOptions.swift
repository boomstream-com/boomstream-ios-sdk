import Foundation

/// Конфигурация SDK (docs/SDK_ARCHITECTURE.md §8).
public struct BoomstreamOptions: Equatable, Sendable {
    /// `ua_allow` / ClearKey-токен; добавляется к User-Agent запросов config и HLS.
    /// Секрет — никогда не логируется (см. `description`).
    public var userAgentToken: String?
    public var connectTimeout: TimeInterval
    public var resourceTimeout: TimeInterval
    public var apiBaseURL: URL
    public var configBaseURL: URL

    public init(
        userAgentToken: String? = nil,
        connectTimeout: TimeInterval = 15,
        resourceTimeout: TimeInterval = 30,
        apiBaseURL: URL = URL(string: "https://boomstream.com/")!,
        configBaseURL: URL = URL(string: "https://play.boomstream.com/")!
    ) {
        self.userAgentToken = userAgentToken
        self.connectTimeout = connectTimeout
        self.resourceTimeout = resourceTimeout
        self.apiBaseURL = apiBaseURL
        self.configBaseURL = configBaseURL
    }
}

extension BoomstreamOptions: CustomStringConvertible {
    public var description: String {
        // userAgentToken может содержать ua_allow/ClearKey-токен — маскируем всегда.
        let token = userAgentToken == nil ? "nil" : "***"
        return "BoomstreamOptions(userAgentToken: \(token), connectTimeout: \(connectTimeout), "
            + "resourceTimeout: \(resourceTimeout), apiBaseURL: \(apiBaseURL), configBaseURL: \(configBaseURL))"
    }
}
