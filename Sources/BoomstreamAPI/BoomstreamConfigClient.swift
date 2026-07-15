import Foundation

/// Абстракция получения config — точка инъекции для player/offline модулей и их тестов.
public protocol BoomstreamConfigFetching: Sendable {
    func fetchConfig(mediaCode: String, forceRefresh: Bool) async throws -> ConfigResponse
    /// `ua_allow`-токен для media-запросов плеера (default `allowClearKeyDRMToken`).
    var userAgentToken: String? { get }
}

/// Клиент config-эндпоинта плеера: `GET {configBaseURL}/{mediaCode}/config`
/// (default: `https://play.boomstream.com/`). Без авторизации — только User-Agent.
///
/// Поведение аутентификации:
/// - авторизованный доступ → `ConfigResponse.mediaDataSingle`/`.mediaDataPlaylist` заполнены;
/// - неаутентифицированный → деградированный ответ с `mediaData == nil` и постерами;
///   SDK НЕ бросает `.unauthorised` в этом случае — проверяйте `mediaData`/`media`.
///
/// Экземпляр — через `Boomstream.configClient`.
public final class BoomstreamConfigClient: Sendable, BoomstreamConfigFetching {
    private let http: BoomstreamHTTPClient
    private let baseURL: URL
    private let cache = ConfigResponseCache()

    /// Токен из `BoomstreamOptions.userAgentToken` — player/offline-модули используют его
    /// как default `allowClearKeyDRMToken`. Не предназначен для чтения app-кодом.
    public let userAgentToken: String?

    init(
        baseURL: URL,
        userAgent: String,
        userAgentToken: String?,
        connectTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.baseURL = baseURL
        self.userAgentToken = userAgentToken
        self.http = BoomstreamHTTPClient(
            headers: ["User-Agent": userAgent],
            connectTimeout: connectTimeout,
            resourceTimeout: resourceTimeout,
            retryPolicy: retryPolicy,
            sessionConfiguration: sessionConfiguration
        )
    }

    /// Получает config для `mediaCode`.
    ///
    /// Успешные ответы кэшируются в памяти на время жизни клиента (пересоздание плеера
    /// не требует второго сетевого запроса). Ошибки не кэшируются.
    ///
    /// - Parameter forceRefresh: `true` — обойти кэш (live-polling, source-lost recovery).
    ///   Успешный ответ всё равно обновляет кэш.
    public func fetchConfig(mediaCode: String, forceRefresh: Bool = false) async throws -> ConfigResponse {
        if !forceRefresh, let cached = await cache.value(for: mediaCode) {
            return cached
        }
        let url = baseURL
            .appendingPathComponent(mediaCode)
            .appendingPathComponent("config")
        let response: ConfigResponse = try await http.get(url, errorPath: mediaCode)
        await cache.store(response, for: mediaCode)
        return response
    }
}

/// In-memory кэш успешных config-ответов по mediaCode.
private actor ConfigResponseCache {
    private var storage: [String: ConfigResponse] = [:]

    func value(for mediaCode: String) -> ConfigResponse? {
        storage[mediaCode]
    }

    func store(_ response: ConfigResponse, for mediaCode: String) {
        storage[mediaCode] = response
    }
}
