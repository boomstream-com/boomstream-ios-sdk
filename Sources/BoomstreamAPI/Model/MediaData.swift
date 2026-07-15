import Foundation

/// Метаданные и стриминг-инфо одного медиа-итема (контракт config-эндпоинта).
///
/// Live-контракт:
/// - `isLive == true` — live-трансляция;
/// - `isPublish == true` — трансляция запущена оператором, можно играть;
/// - `isLiveOffline` — live, но не опубликована (показ постера или `records`).
public struct MediaData: Equatable, Sendable {
    public let title: String
    public let code: String
    public let duration: Int
    public let posters: [Poster]
    public let links: MediaLinks?
    public let mediaType: String
    public let width: Int?
    public let height: Int?
    public let ratio: String?
    public let isLive: Bool
    public let token: String?
    public let thumbnails: String?
    /// `true` когда трансляция опубликована (запущена) оператором.
    public let isPublish: Bool
    /// Encoder-source метаданные live-потока. На wire полиморфно: JSON `false` когда внешний
    /// RTMP/SRT-источник не настроен, URL-строка когда настроен. НЕ индикатор доступности —
    /// для offline-состояния использовать `isLiveOffline`.
    public let source: LiveSource?
    /// Записи live-трансляции, доступные когда трансляция офлайн. Формат элементов = `MediaData`.
    public let records: [MediaData]

    /// `true` для live-итема, который сейчас офлайн (не опубликован оператором).
    public var isLiveOffline: Bool { isLive && !isPublish }
}

/// Полиморфное значение поля `source` (bool | string на wire).
public enum LiveSource: Equatable, Sendable {
    case flag(Bool)
    case url(String)
}

extension MediaData: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, code, duration, posters, links, mediaType, width, height, ratio
        case isLive, token, thumbnails, isPublish, source, records
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        duration = c.decodeLenientInt(forKey: .duration) ?? 0
        posters = (try? c.decodeIfPresent([Poster].self, forKey: .posters)) ?? []
        links = try? c.decodeIfPresent(MediaLinks.self, forKey: .links)
        mediaType = (try? c.decodeIfPresent(String.self, forKey: .mediaType)) ?? "media"
        width = c.decodeLenientInt(forKey: .width)
        height = c.decodeLenientInt(forKey: .height)
        ratio = try? c.decodeIfPresent(String.self, forKey: .ratio)
        isLive = (try? c.decodeIfPresent(Bool.self, forKey: .isLive)) ?? false
        token = try? c.decodeIfPresent(String.self, forKey: .token)
        thumbnails = try? c.decodeIfPresent(String.self, forKey: .thumbnails)
        isPublish = (try? c.decodeIfPresent(Bool.self, forKey: .isPublish)) ?? false
        if let flag = try? c.decodeIfPresent(Bool.self, forKey: .source) {
            source = .flag(flag)
        } else if let url = try? c.decodeIfPresent(String.self, forKey: .source) {
            source = .url(url)
        } else {
            source = nil
        }
        records = (try? c.decodeIfPresent([MediaData].self, forKey: .records)) ?? []
    }
}
