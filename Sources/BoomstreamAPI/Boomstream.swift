import Foundation

/// Точка входа SDK (docs/SDK_ARCHITECTURE.md §8).
///
/// ```swift
/// Boomstream.configure(apiKey: AppSecrets.boomstreamAPIKey)   // полный SDK
/// Boomstream.configure()                                       // player/offline-only
/// ```
///
/// API-ключ **опционален**: нужен только для листинг-API (`Boomstream.api`);
/// плеер и офлайн работают через публичный config-эндпоинт (`Boomstream.configClient`).
public enum Boomstream {
    /// Идемпотентен: повторный вызов с той же конфигурацией — no-op;
    /// с другой конфигурацией — programmer error (fail-fast).
    public static func configure(apiKey: String? = nil, options: BoomstreamOptions = BoomstreamOptions()) {
        BoomstreamRegistry.shared.configure(apiKey: apiKey, options: options)
    }

    public static var isConfigured: Bool { BoomstreamRegistry.shared.isConfigured }

    /// Клиент config-эндпоинта. Требует `configure()`.
    public static var configClient: BoomstreamConfigClient { BoomstreamRegistry.shared.requireConfigClient() }

    /// Клиент листинг-API. Требует `configure(apiKey:)` с непустым ключом.
    public static var api: BoomstreamAPIClient { BoomstreamRegistry.shared.requireAPIClient() }
}

/// Внутренний контейнер синглтонов. Без внешних DI-фреймворков — manual constructor injection.
final class BoomstreamRegistry: @unchecked Sendable {
    static let shared = BoomstreamRegistry()

    struct Configuration: Equatable {
        var apiKey: String?
        var options: BoomstreamOptions
    }

    private let lock = NSLock()
    private var configuration: Configuration?
    private var configClient: BoomstreamConfigClient?
    private var apiClient: BoomstreamAPIClient?

    var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return configuration != nil
    }

    func configure(apiKey: String?, options: BoomstreamOptions) {
        precondition(
            apiKey == nil || !apiKey!.trimmingCharacters(in: .whitespaces).isEmpty,
            "apiKey must be nil or non-blank (typical cause: build setting left unset)"
        )
        lock.lock()
        defer { lock.unlock() }
        let incoming = Configuration(apiKey: apiKey, options: options)
        if let existing = configuration {
            precondition(
                existing == incoming,
                "Boomstream.configure() called again with a different configuration; re-configuration is not supported"
            )
            return
        }
        configuration = incoming

        let userAgent = Self.effectiveUserAgent(options: options)
        configClient = BoomstreamConfigClient(
            baseURL: options.configBaseURL,
            userAgent: userAgent,
            userAgentToken: options.userAgentToken,
            connectTimeout: options.connectTimeout,
            resourceTimeout: options.resourceTimeout
        )
        apiClient = apiKey.map {
            BoomstreamAPIClient(
                baseURL: options.apiBaseURL,
                apiKey: $0,
                userAgent: userAgent,
                connectTimeout: options.connectTimeout,
                resourceTimeout: options.resourceTimeout
            )
        }
    }

    /// UA-контракт см. `BoomstreamSDKInfo.userAgent(token:)`.
    static func effectiveUserAgent(options: BoomstreamOptions) -> String {
        BoomstreamSDKInfo.userAgent(token: options.userAgentToken)
    }

    func requireConfigClient() -> BoomstreamConfigClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client = configClient else {
            preconditionFailure("Boomstream SDK not configured. Call Boomstream.configure() at app launch.")
        }
        return client
    }

    func requireAPIClient() -> BoomstreamAPIClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client = apiClient else {
            preconditionFailure(
                "Boomstream.api requires configure(apiKey:). Currently configured in player/offline-only mode."
            )
        }
        return client
    }

    var currentConfiguration: Configuration? {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }
}
