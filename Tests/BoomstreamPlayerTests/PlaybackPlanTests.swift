import Foundation
import Testing
import BoomstreamAPI
@testable import BoomstreamPlayer

private let hlsURLString = "https://example.com/master.m3u8"
private let hlsB64 = Data(hlsURLString.utf8).base64EncodedString()

private func config(_ json: String) throws -> ConfigResponse {
    try JSONDecoder().decode(ConfigResponse.self, from: Data(json.utf8))
}

@Test func unauthorisedConfigPlansPosterOnlyWithoutPolling() throws {
    let response = try config("""
    {
      "mediaData": null,
      "defaults": {"posters": [{"width": 640, "height": 0, "link": "https://cdn.example.com/small.jpg"},
                                {"width": 1280, "height": 0, "link": "https://cdn.example.com/big.jpg"}]},
      "accessRestricted": {"message": "access_restricted", "translate": "Доступ ограничен"}
    }
    """)
    let plan = PlaybackPlan.make(from: response)
    #expect(plan == .posterOnly(
        posterURL: URL(string: "https://cdn.example.com/big.jpg"),
        message: "Доступ ограничен",
        shouldPoll: false
    ))
}

@Test func singleVodPlansSingleItem() throws {
    let response = try config("""
    {"mediaData": {"title": "Movie", "code": "m1", "links": {"hls": "\(hlsB64)"}}}
    """)
    let plan = PlaybackPlan.make(from: response)
    #expect(plan == .play(
        items: [PlayableItem(title: "Movie", url: URL(string: hlsURLString)!)],
        isPlaylist: false,
        isLive: false,
        systemMessage: nil
    ))
}

@Test func playlistPlansAllPlayableItemsAndFiltersLinkless() throws {
    let response = try config("""
    {
      "mediaType": "playlist",
      "mediaData": [
        {"title": "A", "code": "a", "links": {"hls": "\(hlsB64)"}},
        {"title": "No link", "code": "b"},
        {"title": "C", "code": "c", "links": {"hls": "\(hlsB64)"}}
      ]
    }
    """)
    guard case .play(let items, let isPlaylist, _, _) = PlaybackPlan.make(from: response) else {
        Issue.record("expected .play")
        return
    }
    #expect(isPlaylist)
    #expect(items.map(\.title) == ["A", "C"])
}

@Test func liveOfflineWithRecordsPlansRecordsPlaylist() throws {
    let response = try config("""
    {
      "isLive": true,
      "mediaData": {
        "title": "Broadcast", "code": "l1", "isLive": true, "isPublish": false,
        "records": [
          {"title": "Rec 1", "code": "r1", "links": {"hls": "\(hlsB64)"}},
          {"title": "Rec 2", "code": "r2", "links": {"hls": "\(hlsB64)"}}
        ]
      }
    }
    """)
    guard case .play(let items, let isPlaylist, let isLive, let message) = PlaybackPlan.make(from: response) else {
        Issue.record("expected .play")
        return
    }
    #expect(items.count == 2)
    #expect(isPlaylist)
    #expect(!isLive)
    #expect(message == "live_offline_records")
}

@Test func liveOfflineWithoutRecordsPlansPollingPoster() throws {
    let response = try config("""
    {
      "isLive": true,
      "posters": [{"width": 640, "height": 360, "link": "https://cdn.example.com/live.jpg"}],
      "mediaData": {"title": "Broadcast", "code": "l1", "isLive": true, "isPublish": false, "records": []}
    }
    """)
    #expect(PlaybackPlan.make(from: response) == .posterOnly(
        posterURL: URL(string: "https://cdn.example.com/live.jpg"),
        message: nil,
        shouldPoll: true
    ))
}

@Test func publishedLivePlansLiveItem() throws {
    let response = try config("""
    {"isLive": true, "mediaData": {"title": "Live", "code": "l2", "isLive": true, "isPublish": true, "links": {"hls": "\(hlsB64)"}}}
    """)
    guard case .play(let items, _, let isLive, _) = PlaybackPlan.make(from: response) else {
        Issue.record("expected .play")
        return
    }
    #expect(items.count == 1)
    #expect(isLive)
}
