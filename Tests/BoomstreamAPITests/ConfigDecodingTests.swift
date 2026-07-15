import Foundation
import Testing
@testable import BoomstreamAPI

private let hlsURLString = "https://example.com/master.m3u8"
private let hlsB64 = Data(hlsURLString.utf8).base64EncodedString()

private func decodeConfig(_ json: String) throws -> ConfigResponse {
    try JSONDecoder().decode(ConfigResponse.self, from: Data(json.utf8))
}

@Test func singleMediaConfigDecodes() throws {
    let json = """
    {
      "code": "abc123",
      "language": "ru",
      "posters": [{"width": 640, "height": 360, "link": "https://cdn.example.com/p.jpg"}],
      "mediaData": {
        "title": "Test video",
        "code": "abc123",
        "duration": 120,
        "links": {"hls": "\(hlsB64)"},
        "mediaType": "media"
      },
      "entity": {"code": "abc123", "title": "Test video"},
      "streaming_protocol": "hls",
      "encrypt": false,
      "mediaType": "media"
    }
    """
    let config = try decodeConfig(json)
    #expect(!config.isPlaylist)
    #expect(config.language == "ru")
    let media = try #require(config.mediaDataSingle)
    #expect(media.title == "Test video")
    #expect(media.duration == 120)
    #expect(media.links?.hlsURLString == hlsURLString)
    #expect(media.links?.hlsURL == URL(string: hlsURLString))
    #expect(config.media == .authorised(media))
    #expect(config.effectivePosters.count == 1)
}

@Test func playlistConfigDecodes() throws {
    let json = """
    {
      "code": "pl1",
      "mediaData": [
        {"title": "First", "code": "m1", "links": {"hls": "\(hlsB64)"}},
        {"title": "Second", "code": "m2"}
      ],
      "mediaType": "playlist"
    }
    """
    let config = try decodeConfig(json)
    #expect(config.isPlaylist)
    let items = try #require(config.mediaDataPlaylist)
    #expect(items.count == 2)
    #expect(items[0].code == "m1")
    #expect(config.mediaDataSingle == nil)
    #expect(config.media == .playlist(items))
}

@Test func unauthorisedConfigFallsBackToDefaultPosters() throws {
    let json = """
    {
      "code": "abc123",
      "mediaData": null,
      "posters": [],
      "defaults": {"posters": [{"width": 1280, "height": 0, "link": "https://cdn.example.com/default.jpg"}]},
      "accessRestricted": {"message": "access_restricted", "translate": "Доступ ограничен"},
      "entity": {"code": "abc123", "title": "Hidden"}
    }
    """
    let config = try decodeConfig(json)
    #expect(config.mediaData == nil)
    #expect(config.effectivePosters.first?.link == "https://cdn.example.com/default.jpg")
    #expect(config.media == .unauthorised(posters: config.effectivePosters))
    #expect(config.accessRestricted?.translate == "Доступ ограничен")
}

@Test func liveOfflineContractDecodes() throws {
    let json = """
    {
      "code": "live1",
      "isLive": true,
      "mediaData": {
        "title": "Broadcast",
        "code": "live1",
        "isLive": true,
        "isPublish": false,
        "source": false,
        "records": [{"title": "Recording 1", "code": "rec1", "links": {"hls": "\(hlsB64)"}}]
      }
    }
    """
    let config = try decodeConfig(json)
    let media = try #require(config.mediaDataSingle)
    #expect(media.isLiveOffline)
    #expect(media.source == .flag(false))
    #expect(media.records.count == 1)
    #expect(media.records[0].links?.hlsURLString == hlsURLString)
}

@Test func lenientIntAndUnknownKeysTolerated() throws {
    // Числа-в-строках и незнакомые ключи не должны валить декодинг.
    let json = """
    {
      "code": "abc123",
      "unknownField": {"nested": true},
      "mediaData": {"title": "t", "code": "abc123", "duration": "90", "width": "1920"}
    }
    """
    let config = try decodeConfig(json)
    let media = try #require(config.mediaDataSingle)
    #expect(media.duration == 90)
    #expect(media.width == 1920)
}

@Test func folderEnvelopeDecodesPascalCase() throws {
    let json = """
    {
      "countTotal": 46,
      "Folders": [{"code": "p76oybzr", "title": "folder"}],
      "Medias": [{"Code": "nKg3scvB", "Title": "Video", "Duration": 46, "MediaStatus": "VOD", "Poster": {"Url": "https://cdn.example.com/x.jpg"}}]
    }
    """
    let response = try JSONDecoder().decode(FolderAPIResponse.self, from: Data(json.utf8))
    #expect(response.status == nil)
    #expect(response.countTotal == 46)
    #expect(response.medias.count == 1)
    #expect(response.medias[0].code == "nKg3scvB")
    #expect(response.medias[0].poster?.url == "https://cdn.example.com/x.jpg")
}
