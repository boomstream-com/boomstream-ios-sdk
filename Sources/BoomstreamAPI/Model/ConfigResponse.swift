import Foundation

/// Корневой ответ `https://play.boomstream.com/{mediaCode}/config`.
///
/// `mediaData` на wire полиморфен:
/// - **null** — неаутентифицированный доступ (только постеры/entity);
/// - **object** — одиночное медиа;
/// - **array** — плейлист.
public struct ConfigResponse: Equatable, Sendable {
    public let code: String
    public let language: String
    public let posters: [Poster]
    /// Типизированный `mediaData`; `nil` = unauthorised.
    public let mediaData: ConfigMediaData?
    public let entity: Entity?
    public let error: ServerError?
    public let isLive: Bool
    /// Wire-ключ `streaming_protocol`; по контракту всегда `"hls"`.
    public let streamingProtocol: String
    public let encrypt: Bool
    public let mediaType: String
    /// Fallback-ассеты сервера, когда per-media ассеты отсутствуют.
    public let defaults: ConfigDefaults?
    /// Не-nil когда сервер ограничивает доступ (PPV/подписка/preview-лимит).
    public let accessRestricted: AccessRestricted?

    /// `true` когда сервер идентифицировал контент как плейлист.
    /// Авторитетный источник — `mediaType` (не форма `mediaData`).
    public var isPlaylist: Bool { mediaType == "playlist" }

    /// Одиночное медиа, или `nil` для unauthorised/плейлиста.
    public var mediaDataSingle: MediaData? {
        if case .single(let media) = mediaData { return media }
        return nil
    }

    /// Элементы плейлиста, или `nil` для unauthorised/одиночного медиа.
    public var mediaDataPlaylist: [MediaData]? {
        if case .playlist(let items) = mediaData { return items }
        return nil
    }

    /// Эффективные постеры: `posters`, при пустых — `defaults.posters`.
    public var effectivePosters: [Poster] {
        posters.isEmpty ? (defaults?.posters ?? []) : posters
    }

    /// Удобный маппинг для player-sdk: авторизованное медиа / плейлист / poster-only.
    public var media: BoomstreamMedia {
        switch mediaData {
        case .playlist(let items):
            return .playlist(items)
        case .single(let media):
            return isPlaylist ? .playlist([media]) : .authorised(media)
        case nil:
            return .unauthorised(posters: effectivePosters)
        }
    }
}

/// Типизированное полиморфное поле `mediaData`.
public enum ConfigMediaData: Equatable, Sendable {
    case single(MediaData)
    case playlist([MediaData])
}

/// Fallback-ассеты из объекта `defaults` config-ответа.
public struct ConfigDefaults: Equatable, Sendable, Decodable {
    public let posters: [Poster]

    public init(posters: [Poster]) {
        self.posters = posters
    }

    private enum CodingKeys: String, CodingKey { case posters }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        posters = (try? c.decodeIfPresent([Poster].self, forKey: .posters)) ?? []
    }
}

/// Минимальный дескриптор сущности; присутствует и в unauthorised-ответах.
public struct Entity: Equatable, Sendable, Decodable {
    public let code: String
    public let title: String

    public init(code: String, title: String) {
        self.code = code
        self.title = title
    }

    private enum CodingKeys: String, CodingKey { case code, title }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
    }
}

/// Server-side error envelope; ненулевой `code` = ошибка.
public struct ServerError: Equatable, Sendable, Decodable {
    public let code: Int
    public let message: String
    public let translate: String

    public init(code: Int, message: String, translate: String) {
        self.code = code
        self.message = message
        self.translate = translate
    }

    private enum CodingKeys: String, CodingKey { case code, message, translate }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.decodeLenientInt(forKey: .code) ?? 0
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
        translate = (try? c.decodeIfPresent(String.self, forKey: .translate)) ?? ""
    }
}

/// Дескриптор ограничения доступа (`{message: "<локализационный ключ>", translate: "<текст сервера>"}`).
public struct AccessRestricted: Equatable, Sendable, Decodable {
    public let message: String
    public let translate: String

    public init(message: String, translate: String) {
        self.message = message
        self.translate = translate
    }

    private enum CodingKeys: String, CodingKey { case message, translate }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
        translate = (try? c.decodeIfPresent(String.self, forKey: .translate)) ?? ""
    }
}

extension ConfigResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case code, language, posters, mediaData, entity, error, isLive
        case streamingProtocol = "streaming_protocol"
        case encrypt, mediaType, defaults, accessRestricted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? "en"
        posters = (try? c.decodeIfPresent([Poster].self, forKey: .posters)) ?? []
        // Полиморфный mediaData: object → single, array → playlist, null/невалидный → nil
        // (терпимый декодинг: неожиданная форма не валит весь ответ).
        if let single = try? c.decodeIfPresent(MediaData.self, forKey: .mediaData) {
            mediaData = .single(single)
        } else if let items = try? c.decodeIfPresent([MediaData].self, forKey: .mediaData) {
            mediaData = .playlist(items)
        } else {
            mediaData = nil
        }
        entity = try? c.decodeIfPresent(Entity.self, forKey: .entity)
        error = try? c.decodeIfPresent(ServerError.self, forKey: .error)
        isLive = (try? c.decodeIfPresent(Bool.self, forKey: .isLive)) ?? false
        streamingProtocol = (try? c.decodeIfPresent(String.self, forKey: .streamingProtocol)) ?? "hls"
        encrypt = (try? c.decodeIfPresent(Bool.self, forKey: .encrypt)) ?? false
        mediaType = (try? c.decodeIfPresent(String.self, forKey: .mediaType)) ?? "media"
        defaults = try? c.decodeIfPresent(ConfigDefaults.self, forKey: .defaults)
        accessRestricted = try? c.decodeIfPresent(AccessRestricted.self, forKey: .accessRestricted)
    }
}
