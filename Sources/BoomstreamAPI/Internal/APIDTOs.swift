import Foundation

// Wire-DTO Boomstream REST API (POST + JSON body, PascalCase-ключи envelope).

/// Тело запроса всех трёх листинг-эндпоинтов. Синтезированный Encodable
/// опускает nil `code`.
struct FolderAPIRequest: Encodable {
    var ver: String = "1.2"
    var code: String?
}

/// Envelope `POST api/media/folder`. Error shape: `{Status:"Failed", Message:"..."}`.
struct FolderAPIResponse: Decodable {
    let status: String?
    let message: String?
    let countTotal: Int
    let medias: [APIMediaItem]

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case countTotal
        case medias = "Medias"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        countTotal = c.decodeLenientInt(forKey: .countTotal) ?? 0
        medias = (try? c.decodeIfPresent([APIMediaItem].self, forKey: .medias)) ?? []
    }
}

/// Envelope `POST api/live/folder`.
struct LiveFolderAPIResponse: Decodable {
    let status: String?
    let message: String?
    let medias: [APILiveItem]

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case medias = "Medias"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        medias = (try? c.decodeIfPresent([APILiveItem].self, forKey: .medias)) ?? []
    }
}

/// Envelope `POST api/playlist/list`.
struct PlaylistListAPIResponse: Decodable {
    let status: String?
    let message: String?
    let items: [APIPlaylistItem]

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case items = "Items"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        items = (try? c.decodeIfPresent([APIPlaylistItem].self, forKey: .items)) ?? []
    }
}

struct APIMediaItem: Decodable {
    let code: String
    let title: String
    let duration: Int
    let mediaStatus: String?
    let poster: APIPoster?

    private enum CodingKeys: String, CodingKey {
        case code = "Code"
        case title = "Title"
        case duration = "Duration"
        case mediaStatus = "MediaStatus"
        case poster = "Poster"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        duration = c.decodeLenientInt(forKey: .duration) ?? 0
        mediaStatus = try? c.decodeIfPresent(String.self, forKey: .mediaStatus)
        poster = try? c.decodeIfPresent(APIPoster.self, forKey: .poster)
    }
}

struct APILiveItem: Decodable {
    let code: String
    let title: String
    let poster: APIPoster?

    private enum CodingKeys: String, CodingKey {
        case code = "Code"
        case title = "Title"
        case poster = "Poster"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        poster = try? c.decodeIfPresent(APIPoster.self, forKey: .poster)
    }
}

/// `Duration` — общая длительность плейлиста в миллисекундах, сериализована строкой.
struct APIPlaylistItem: Decodable {
    let code: String
    let name: String
    let durationMs: String
    let poster: APIPoster?

    private enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case durationMs = "Duration"
        case poster = "Poster"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        if let string = try? c.decodeIfPresent(String.self, forKey: .durationMs) {
            durationMs = string
        } else if let int = try? c.decodeIfPresent(Int.self, forKey: .durationMs) {
            durationMs = String(int)
        } else {
            durationMs = "0"
        }
        poster = try? c.decodeIfPresent(APIPoster.self, forKey: .poster)
    }
}

struct APIPoster: Decodable {
    let url: String?

    private enum CodingKeys: String, CodingKey {
        case url = "Url"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
    }
}
