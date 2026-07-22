import Foundation
import Testing
import BoomstreamAPI
@testable import BoomstreamPlayer

/// Стаб config-клиента: отдаёт ответы по очереди (последний повторяется), пишет вызовы.
final class StubConfigClient: BoomstreamConfigFetching, @unchecked Sendable {
    let userAgentToken: String?
    private let lock = NSLock()
    private var queue: [Result<ConfigResponse, Error>]
    private(set) var calls: [(mediaCode: String, forceRefresh: Bool)] = []

    init(userAgentToken: String? = nil, responses: [Result<ConfigResponse, Error>]) {
        self.userAgentToken = userAgentToken
        self.queue = responses
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.count
    }

    var lastCall: (mediaCode: String, forceRefresh: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        return calls.last
    }

    func fetchConfig(mediaCode: String, forceRefresh: Bool) async throws -> ConfigResponse {
        try nextResponse(mediaCode: mediaCode, forceRefresh: forceRefresh).get()
    }

    private func nextResponse(mediaCode: String, forceRefresh: Bool) -> Result<ConfigResponse, Error> {
        lock.lock()
        defer { lock.unlock() }
        calls.append((mediaCode, forceRefresh))
        return queue.count > 1 ? queue.removeFirst() : queue[0]
    }
}

private func decodedConfig(_ json: String) throws -> ConfigResponse {
    try JSONDecoder().decode(ConfigResponse.self, from: Data(json.utf8))
}

@MainActor
private func waitFor(
    timeout: TimeInterval = 5,
    _ predicate: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return predicate()
}

@MainActor
@Test func unauthorisedLoadEndsInPosterOnly() async throws {
    let stub = StubConfigClient(responses: [.success(try decodedConfig("""
    {"mediaData": null, "accessRestricted": {"message": "access_restricted", "translate": "Denied"}}
    """))])
    let core = BoomstreamPlayerCore()

    core.load(mediaCode: "x", configClient: stub)

    let reached = await waitFor {
        if case .posterOnly(_, let message, let isLiveOffline) = core.state {
            return message == "Denied" && !isLiveOffline
        }
        return false
    }
    #expect(reached)
    core.release()
    #expect(core.state == .idle)
}

@MainActor
@Test func fetchFailureEndsInErrorState() async throws {
    let stub = StubConfigClient(responses: [.failure(BoomstreamError.mediaNotFound(mediaCode: "gone"))])
    let core = BoomstreamPlayerCore()

    core.load(mediaCode: "gone", configClient: stub)

    let reached = await waitFor {
        if case .error = core.state { return true }
        return false
    }
    #expect(reached)
    core.release()
}

@MainActor
@Test func liveOfflinePollsWithForceRefreshUntilPublished() async throws {
    let offline = try decodedConfig("""
    {"isLive": true, "mediaData": {"code": "l1", "isLive": true, "isPublish": false, "records": []}}
    """)
    let published = try decodedConfig("""
    {"isLive": true, "mediaData": {"title": "Live", "code": "l1", "isLive": true, "isPublish": true,
      "links": {"hls": "\(Data("https://example.invalid/live.m3u8".utf8).base64EncodedString())"}}}
    """)
    let stub = StubConfigClient(responses: [.success(offline), .success(published)])
    let core = BoomstreamPlayerCore(livePollInterval: 0.05)

    core.load(mediaCode: "l1", configClient: stub)

    // первый ответ → posterOnly, затем поллинг с forceRefresh достаёт published → уходим из posterOnly
    let leftPoster = await waitFor {
        if case .posterOnly = core.state { return false }
        return stub.callCount >= 2
    }
    #expect(leftPoster)
    #expect(stub.lastCall?.forceRefresh == true)
    core.release()
}

@MainActor
@Test func fullScreenTogglesAndEmitsEvent() async throws {
    let core = BoomstreamPlayerCore()
    let events = core.events

    core.setFullScreen(true)

    var iterator = events.makeAsyncIterator()
    let event = await iterator.next()
    #expect(event == .fullScreenChanged(true))
    #expect(core.isFullScreen)
    core.toggleFullScreen()
    #expect(!core.isFullScreen)
}

@MainActor
private final class StubOfflineCache: BoomstreamOfflineCache {
    let url: URL?
    init(url: URL?) { self.url = url }
    func localAssetURL(mediaCode: String) -> URL? { url }
}

@MainActor
@Test func offlineCacheHitSkipsConfigFetch() async throws {
    let stub = StubConfigClient(responses: [.failure(BoomstreamError.network(underlying: URLError(.notConnectedToInternet)))])
    let cache = StubOfflineCache(url: URL(fileURLWithPath: "/nonexistent/asset.movpkg"))
    let core = BoomstreamPlayerCore()

    core.load(mediaCode: "x", configClient: stub, offlineCache: cache)

    // локальная копия → сетевой config-резолв не выполняется вовсе
    let left = await waitFor {
        if case .loading = core.state { return false }
        return true
    }
    _ = left // итоговое состояние зависит от AVPlayer (файла нет → error) — важен только счётчик
    #expect(stub.callCount == 0)
    core.release()
}

// MARK: - B1 regression: AdvancedPlayerOptions.preferredPeakBitRate must survive when no explicit quality override is set

@MainActor
@Test func advancedOptionsPeakBitRatePreservedWithoutExplicitQualityOverride() async throws {
    // Before fix: qualityOverride was initialized to .auto, causing applyQualityToItem(_, .auto)
    // to set item.preferredPeakBitRate = 0 on every playItem(at:) — wiping the AdvancedPlayerOptions hint.
    // After fix: qualityOverride = nil initially; applyQualityToItem is skipped when nil.
    let hint: Double = 5_000_000
    let stub = StubConfigClient(responses: [.success(try decodedConfig("""
    {"mediaData": {"code": "q", "links": {"hls": "\(Data("https://example.invalid/vod.m3u8".utf8).base64EncodedString())"}}}
    """))])
    let core = BoomstreamPlayerCore()
    core.load(mediaCode: "q", configClient: stub, advancedOptions: AdvancedPlayerOptions(preferredPeakBitRate: hint))

    let reached = await waitFor(timeout: 3) { core.player.currentItem != nil }
    #expect(reached, "AVPlayerItem was not created within timeout")
    #expect(
        core.player.currentItem?.preferredPeakBitRate == hint,
        "AdvancedPlayerOptions.preferredPeakBitRate must not be zeroed before host calls setQuality/selectAuto"
    )
    core.release()
}

@Test func assetOptionsCarryUserAgentHeader() {
    let options = AssetFactory.assetOptions(userAgent: "UA test")
    let headers = options["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String]
    #expect(headers == ["User-Agent": "UA test"])
}

@Test func userAgentComposedFromToken() {
    #expect(BoomstreamSDKInfo.userAgent(token: "tok") == "\(BoomstreamSDKInfo.userAgentBase) tok")
    #expect(BoomstreamSDKInfo.userAgent(token: nil) == BoomstreamSDKInfo.userAgentBase)
}
