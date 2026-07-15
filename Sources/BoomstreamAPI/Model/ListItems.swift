/// Публичные итемы листинг-эндпоинтов.

/// Медиа-запись из `POST api/media/folder`.
public struct FolderMediaItem: Equatable, Sendable {
    public let code: String
    public let title: String
    public let duration: Int
    /// Абсолютный URL постера, или `nil`.
    public let poster: String?
    public let mediaStatus: String?

    public init(code: String, title: String = "", duration: Int = 0, poster: String? = nil, mediaStatus: String? = nil) {
        self.code = code
        self.title = title
        self.duration = duration
        self.poster = poster
        self.mediaStatus = mediaStatus
    }
}

/// Live-трансляция из `POST api/live/folder`.
public struct LiveMediaItem: Equatable, Sendable {
    public let code: String
    public let title: String
    public let poster: String?

    public init(code: String, title: String = "", poster: String? = nil) {
        self.code = code
        self.title = title
        self.poster = poster
    }
}

/// Плейлист из `POST api/playlist/list`.
/// `durationSeconds` конвертирован из миллисекундной строки API (`"244000"` → 244).
public struct PlaylistItem: Equatable, Sendable {
    public let code: String
    public let name: String
    public let durationSeconds: Int
    public let poster: String?

    public init(code: String, name: String = "", durationSeconds: Int = 0, poster: String? = nil) {
        self.code = code
        self.name = name
        self.durationSeconds = durationSeconds
        self.poster = poster
    }
}
