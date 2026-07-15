import AVFoundation
import Foundation
import Testing
@testable import BoomstreamAPI
@testable import BoomstreamOffline

// Офлайн-цикл на реальных потоках. По умолчанию выключено (CI); локальный запуск:
//   BOOMSTREAM_IT=1 BOOMSTREAM_TEST_UA_KEY=<ua-key> swift test --filter OfflineIntegrationTests
// Полный download-цикл гоняется только на НЕшифрованном потоке (шифрованные теперь
// fail-fast по preflight-детекту): задайте BOOMSTREAM_IT_PLAIN_CODE=<code>.
private let environment = ProcessInfo.processInfo.environment
private let integrationEnabled = environment["BOOMSTREAM_IT"] == "1"
private let plainDownloadCode = environment["BOOMSTREAM_IT_PLAIN_CODE"]
private let encryptedCodes = (environment["BOOMSTREAM_IT_MEDIA_CODES"] ?? "wZby7dI0,ZXAJ4Ebw")
    .split(separator: ",").map(String.init)

@Suite(.serialized, .enabled(if: integrationEnabled))
@MainActor
struct OfflineIntegrationTests {

    private func makeClient() -> BoomstreamConfigClient {
        let token = environment["BOOMSTREAM_TEST_UA_KEY"]
        let base = environment["BOOMSTREAM_CONFIG_BASE"] ?? "https://play.boomstream.net/"
        return BoomstreamConfigClient(
            baseURL: URL(string: base)!,
            userAgent: BoomstreamSDKInfo.userAgent(token: token),
            userAgentToken: token,
            connectTimeout: 15,
            resourceTimeout: 60
        )
    }

    /// Preflight-детект: шифрованный поток, для которого даемон получил бы web-манифест,
    /// падает с типизированной ошибкой ДО скачивания сегментов.
    @Test(arguments: encryptedCodes)
    func encryptedDownloadFailsFastWithActionableError(mediaCode: String) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boomstream-offline-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = BoomstreamOfflineManager(
            configClient: makeClient(),
            sessionIdentifier: "boomstream-it-\(UUID().uuidString)",
            allowsCellularAccess: true,
            storeDirectory: dir
        )

        await #expect {
            _ = try await manager.start(mediaCode: mediaCode, quality: .auto)
        } throws: { error in
            guard case .offlineUnavailable(let reason) = error as? BoomstreamError else { return false }
            print("IT: fail-fast reason (\(mediaCode)): \(reason)")
            return reason.contains("native manifest")
        }
        // сегменты не качались — записи о загрузке нет
        let stats = await manager.stats()
        #expect(stats.downloadsCount == 0)
    }

    @Test(.enabled(if: plainDownloadCode != nil))
    func downloadsAndPlaysBackLocally() async throws {
        let downloadMediaCode = plainDownloadCode!
        let token = environment["BOOMSTREAM_TEST_UA_KEY"]
        let client = makeClient()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boomstream-offline-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = BoomstreamOfflineManager(
            configClient: client,
            sessionIdentifier: "boomstream-it-\(UUID().uuidString)",
            allowsCellularAccess: true,
            storeDirectory: dir
        )

        _ = try await manager.start(mediaCode: downloadMediaCode, quality: .auto)

        // ждём completed (поток 14 сек / ~3 МБ)
        let deadline = Date().addingTimeInterval(120)
        var completed = false
        observing: for await state in manager.observe(mediaCode: downloadMediaCode) {
            switch state {
            case .completed:
                completed = true
                break observing
            case .failed(_, let error):
                Issue.record("download failed: \(error)")
                return
            default:
                if Date() > deadline { break observing }
            }
        }
        #expect(completed, "download did not complete")

        let localURL = try #require(manager.localAssetURL(mediaCode: downloadMediaCode))
        print("IT: downloaded to \(localURL.path)")
        let stats = await manager.stats()
        #expect(stats.downloadsCount == 1)
        #expect(stats.totalSizeBytes > 100_000)

        // Локальный плейбек ШИФРОВАННОГО потока — задокументированное ограничение
        // (2026-07-15, macOS-хост): UA-токен не доходит до манифест-запросов
        // download-даемона (ни официальный AVURLAssetHTTPUserAgentKey, ни
        // AVURLAssetHTTPHeaderFieldsKey, ни session httpAdditionalHeaders) → манифест
        // сохраняется в web-протокольном виде (URI="[KEY]") и плейбек падает 403.
        // Follow-up: верификация на реальном iOS-устройстве + BE query-param токен.
        await withKnownIssue(
            "encrypted offline playback: UA token does not reach download-daemon manifest fetches",
            isIntermittent: true
        ) {
            let asset = AVURLAsset(
                url: localURL,
                options: BoomstreamAssetOptions.httpHeaderFields(userAgent: BoomstreamSDKInfo.userAgent(token: token))
            )
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.play()
            let playDeadline = Date().addingTimeInterval(20)
            while Date() < playDeadline, player.currentTime().seconds < 3, item.status != .failed {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            player.pause()
            #expect(item.status != .failed, "local playback failed: \(String(describing: item.error))")
            #expect(player.currentTime().seconds >= 3, "local playback did not progress")
        }

        // содержимое пакета (диагностика персистенции ключей AES-128)
        if let contents = FileManager.default.enumerator(at: localURL, includingPropertiesForKeys: nil) {
            for case let f as URL in contents.prefix(40) {
                print("IT: movpkg item: \(f.lastPathComponent)")
            }
        }

        try await manager.delete(mediaCode: downloadMediaCode)
        #expect(manager.localAssetURL(mediaCode: downloadMediaCode) == nil)
        #expect(FileManager.default.fileExists(atPath: localURL.path) == false)
    }
}
