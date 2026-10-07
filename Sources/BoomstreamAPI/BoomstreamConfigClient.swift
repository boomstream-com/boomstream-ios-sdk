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
        // x-platform позволяет медиасерверу выбирать платформенно-корректную доставку
        // (схемы шифрования/упаковки различаются между платформами). Только config-эндпоинт.
        self.http = BoomstreamHTTPClient(
            headers: ["User-Agent": userAgent, "x-platform": "ios"],
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

extension BoomstreamConfigClient: BoomstreamCastLinkFetching {
    /// `GET {configBaseURL}/api/cast/link?entity={mediaCode}` — on-demand cast-ссылка
    /// для зашифрованного медиа (сервер отвечает 200 с base64-ссылкой либо
    /// не-2xx с машиночитаемым `reason`). Заголовки те же, что у config
    /// (User-Agent с UA-токеном + x-platform) — авторизация эндпоинта на них.
    public func fetchCastLink(mediaCode: String) async throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/cast/link"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "entity", value: mediaCode)]
        guard let url = components?.url else {
            throw BoomstreamError.unknown(underlying: nil)
        }

        let (data, statusCode) = try await http.getRaw(url)
        let envelope = try? JSONDecoder().decode(CastLinkEnvelope.self, from: data)

        if (200...299).contains(statusCode) {
            guard let base64 = envelope?.data?.link,
                  let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                  let string = String(data: decoded, encoding: .utf8),
                  let linkURL = URL(string: string)
            else { throw BoomstreamError.unknown(underlying: nil) }
            return linkURL
        }

        if let raw = envelope?.data?.reason {
            throw BoomstreamCastLinkError(
                reason: CastLinkDenialReason(rawValue: raw) ?? .other,
                rawReason: raw
            )
        }
        throw BoomstreamHTTPClient.mapHTTPError(statusCode: statusCode, data: data, path: mediaCode)
    }
}

/// Wire-формат ответа cast-эндпоинта: `{"code":N,"data":{"link":...}}` или
/// `{"code":N,"data":{"reason":...}}`.
private struct CastLinkEnvelope: Decodable {
    struct Payload: Decodable {
        let link: String?
        let reason: String?
    }

    let data: Payload?
}

/// In-memory кэш успешных config-ответов по mediaCode.
///
/// Ответ с подписанными HLS-ссылками годен только до `exp` их конверта: протухшая
/// ссылка из кэша = гарантированный отказ сервера на манифесте/ключе. Такие записи
/// истекают за ``expiryMargin`` до `exp`; ответы без подписанных ссылок живут,
/// как и раньше, до пересоздания клиента.
private actor ConfigResponseCache {
    private struct Entry {
        let response: ConfigResponse
        let expiry: Date?
    }

    /// Страховочный зазор до фактического `exp`: выданная из кэша ссылка должна
    /// пережить старт воспроизведения (запрос манифестов и ключа).
    private static let expiryMargin: TimeInterval = 60

    private var storage: [String: Entry] = [:]

    func value(for mediaCode: String) -> ConfigResponse? {
        guard let entry = storage[mediaCode] else { return nil }
        if let expiry = entry.expiry, Date() >= expiry.addingTimeInterval(-Self.expiryMargin) {
            storage[mediaCode] = nil
            return nil
        }
        return entry.response
    }

    func store(_ response: ConfigResponse, for mediaCode: String) {
        storage[mediaCode] = Entry(response: response, expiry: response.earliestSignedLinkExpiry)
    }
}

extension ConfigResponse {
    /// Ближайший `exp` среди подписанных HLS-ссылок ответа, или `nil`, когда
    /// подписанных ссылок нет (бессрочное кэширование, прежнее поведение).
    var earliestSignedLinkExpiry: Date? {
        let items: [MediaData]
        switch mediaData {
        case .single(let media): items = [media]
        case .playlist(let list): items = list
        case nil: return nil
        }
        return items
            .compactMap { $0.links?.hlsURLString.flatMap(Self.signedLinkExp(from:)) }
            .min()
            .map(Date.init(timeIntervalSince1970:))
    }

    /// Достаёт `exp` из сегмента `data:<base64 JSON>` подписанной ссылки
    /// (`…/sign:<hmac>/data:<b64>/…`). Не подписанная или нечитаемая ссылка — `nil`.
    private static func signedLinkExp(from urlString: String) -> TimeInterval? {
        // Двоеточия в path-сегментах могут приходить и percent-encoded.
        let normalized = urlString.replacingOccurrences(of: "%3A", with: ":")
        guard normalized.contains("/sign:") else { return nil }
        for segment in normalized.split(separator: "/") where segment.hasPrefix("data:") {
            let base64 = String(segment.dropFirst("data:".count))
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let exp = json["exp"] as? NSNumber
            else { continue }
            return exp.doubleValue
        }
        return nil
    }
}
