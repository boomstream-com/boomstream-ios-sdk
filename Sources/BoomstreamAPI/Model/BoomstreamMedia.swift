/// Высокоуровневое представление config-ответа для player-sdk
/// (docs/SDK_ARCHITECTURE.md §2).
public enum BoomstreamMedia: Equatable, Sendable {
    /// Авторизованное одиночное медиа.
    case authorised(MediaData)
    /// Авторизованный плейлист.
    case playlist([MediaData])
    /// Неаутентифицированный доступ — только постеры (poster-only режим плеера).
    case unauthorised(posters: [Poster])
}
