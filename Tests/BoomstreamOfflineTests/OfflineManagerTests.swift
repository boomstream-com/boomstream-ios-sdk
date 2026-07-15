import Foundation
import Testing
import BoomstreamAPI
@testable import BoomstreamOffline

// MARK: - Stubs

final class StubConfig: BoomstreamConfigFetching, @unchecked Sendable {
    let userAgentToken: String?
    private let result: Result<ConfigResponse, Error>

    init(userAgentToken: String? = nil, _ result: Result<ConfigResponse, Error>) {
        self.userAgentToken = userAgentToken
        self.result = result
    }

    func fetchConfig(mediaCode: String, forceRefresh: Bool) async throws -> ConfigResponse {
        try result.get()
    }
}

private func decodedConfig(_ json: String) throws -> ConfigResponse {
    try JSONDecoder().decode(ConfigResponse.self, from: Data(json.utf8))
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("boomstream-offline-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - DownloadRecordStore

@Test func recordStoreRoundTripsBookmarks() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    // реальный файл, чтобы bookmark резолвился
    let assetFile = dir.appendingPathComponent("asset.movpkg")
    try Data("stub".utf8).write(to: assetFile)
    let bookmark = try assetFile.bookmarkData()

    let store = DownloadRecordStore(directory: dir)
    store.save(["abc": DownloadRecord(mediaCode: "abc", title: "T", bookmark: bookmark, expiresAt: nil, sizeBytes: 4)])

    let reloaded = DownloadRecordStore(directory: dir).load()
    #expect(reloaded["abc"]?.title == "T")
    #expect(reloaded["abc"]?.sizeBytes == 4)

    var stale = false
    let resolved = try URL(resolvingBookmarkData: try #require(reloaded["abc"]?.bookmark), bookmarkDataIsStale: &stale)
    #expect(resolved.lastPathComponent == "asset.movpkg")
}

@Test func recordStoreLoadsEmptyWhenMissing() {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(DownloadRecordStore(directory: dir).load().isEmpty)
}

// MARK: - Manager rejection paths (без сети и без создания download-таска)

@MainActor
@Test func startRejectsUnauthorisedMedia() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manager = BoomstreamOfflineManager(
        configClient: StubConfig(.success(try decodedConfig(#"{"mediaData": null}"#))),
        sessionIdentifier: "test-\(UUID().uuidString)",
        storeDirectory: dir
    )

    await #expect(throws: BoomstreamError.self) {
        _ = try await manager.start(mediaCode: "x", quality: .auto)
    }
    let stats = await manager.stats()
    #expect(stats.downloadsCount == 0)
}

@MainActor
@Test func startRejectsLiveBroadcast() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let live = try decodedConfig("""
    {"isLive": true, "mediaData": {"code": "l1", "isLive": true, "isPublish": true,
     "links": {"hls": "\(Data("https://example.com/live.m3u8".utf8).base64EncodedString())"}}}
    """)
    let manager = BoomstreamOfflineManager(
        configClient: StubConfig(.success(live)),
        sessionIdentifier: "test-\(UUID().uuidString)",
        storeDirectory: dir
    )

    await #expect {
        _ = try await manager.start(mediaCode: "l1", quality: .auto)
    } throws: { error in
        if case .offlineUnavailable(let reason) = error as? BoomstreamError {
            return reason.contains("live")
        }
        return false
    }
}

// MARK: - ManifestInspector

@Test func webClearKeyManifestIsDetected() {
    let webChunklist = """
    #EXTM3U
    #EXT-X-VERSION:5
    #EXT-X-MEDIA-READY:11222966130e2438
    #EXT-X-KEY:METHOD=AES-128,URI="[KEY]",IV=[IV]
    #EXTINF:5.672,
    https://m16.example.com/media-1.ts
    """
    #expect(ManifestInspector.isWebClearKeyProtocol(webChunklist))
}

@Test func nativeManifestIsNotDetected() {
    let nativeChunklist = """
    #EXTM3U
    #EXT-X-VERSION:5
    #EXT-X-KEY:METHOD=AES-128,URI="https://m16.example.com/key.bin",IV=0x314365754C336E55485634746A7A5274
    #EXTINF:5.672,
    https://m16.example.com/media-1.ts
    """
    #expect(!ManifestInspector.isWebClearKeyProtocol(nativeChunklist))
    let plainManifest = "#EXTM3U\n#EXTINF:4.0,\nhttps://example.com/seg0.ts\n"
    #expect(!ManifestInspector.isWebClearKeyProtocol(plainManifest))
}

@Test func firstVariantURLResolvesRelativeAndAbsolute() throws {
    let base = try #require(URL(string: "https://bs.example.com/adaptive/code/playlist.m3u8"))
    let master = """
    #EXTM3U
    #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1835322
    https://m16.example.com/vod/chunklist.m3u8
    """
    #expect(ManifestInspector.firstVariantURL(in: master, relativeTo: base)?.host == "m16.example.com")

    let relativeMaster = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunk.m3u8\n"
    #expect(
        ManifestInspector.firstVariantURL(in: relativeMaster, relativeTo: base)?.absoluteString
            == "https://bs.example.com/adaptive/code/chunk.m3u8"
    )
    #expect(ManifestInspector.firstVariantURL(in: "#EXTM3U\n", relativeTo: base) == nil)
}

@MainActor
@Test func localAssetURLNilWithoutDownload() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manager = BoomstreamOfflineManager(
        configClient: StubConfig(.success(try decodedConfig(#"{"mediaData": null}"#))),
        sessionIdentifier: "test-\(UUID().uuidString)",
        storeDirectory: dir
    )
    #expect(manager.localAssetURL(mediaCode: "nope") == nil)
}
