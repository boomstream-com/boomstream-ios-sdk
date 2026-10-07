import Foundation

/// Машиночитаемая причина отказа эндпоинта cast-ссылки.
public enum CastLinkDenialReason: String, Sendable, Equatable {
    /// Шифрование включено, но владелец проекта не разрешил каст защищённого контента.
    case castNotAllowed = "cast_not_allowed"
    /// Запрос не распознан как доверенный нативный клиент (нет платформы или UA-токена).
    case clientNotTrusted = "client_not_trusted"
    /// Контент не зашифрован — каст-ссылка не нужна, кастуйте обычной.
    case notNeeded = "not_needed"
    /// Медиа не найдено или каст для него невозможен (live, материал и т.п.).
    case notFound = "not_found"
    /// Доступ закрыт теми же правилами, что и у config (PPV/подписка/лимиты).
    case accessDenied = "access_denied"
    /// Прочие ответы сервера (баланс, блокировки) — как пришли.
    case other = "other"
}

/// Ошибка получения cast-ссылки с сохранённой причиной отказа.
public struct BoomstreamCastLinkError: Error, Sendable, Equatable {
    public let reason: CastLinkDenialReason
    /// Сырой `reason` сервера — для `other` и диагностики.
    public let rawReason: String

    public init(reason: CastLinkDenialReason, rawReason: String) {
        self.reason = reason
        self.rawReason = rawReason
    }
}

/// Получение cast-ссылки (совместимой с внешними приёмниками) для зашифрованного
/// медиа. Отдельный протокол, а не расширение `BoomstreamConfigFetching`, — чтобы
/// не ломать существующие конформансы интеграторов; плеер обнаруживает поддержку
/// через `as?`.
public protocol BoomstreamCastLinkFetching: Sendable {
    /// Возвращает подписанную cast-ссылку для медиа `mediaCode` (entity-код,
    /// тот же, что у `fetchConfig`). Бросает ``BoomstreamCastLinkError`` при
    /// машиночитаемом отказе сервера, `BoomstreamError` при сетевых проблемах.
    func fetchCastLink(mediaCode: String) async throws -> URL
}
