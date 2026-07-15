import Foundation
import Testing
@testable import BoomstreamAPI
@testable import BoomstreamPlayer

// Интеграция с реальными потоками Boomstream. По умолчанию выключено (CI);
// локальный запуск:
//   BOOMSTREAM_IT=1 BOOMSTREAM_TEST_UA_KEY=<ua-key> swift test --filter PlayerIntegrationTests
// Опционально: BOOMSTREAM_CONFIG_BASE (default https://play.boomstream.net/),
// BOOMSTREAM_IT_MEDIA_CODES (default "wZby7dI0,ZXAJ4Ebw" — защищённые тестовые потоки).
private let environment = ProcessInfo.processInfo.environment
private let integrationEnabled = environment["BOOMSTREAM_IT"] == "1"
private let mediaCodes = (environment["BOOMSTREAM_IT_MEDIA_CODES"] ?? "wZby7dI0,ZXAJ4Ebw")
    .split(separator: ",").map(String.init)

@Suite(.serialized, .enabled(if: integrationEnabled))
@MainActor
struct PlayerIntegrationTests {

    private func makeConfigClient() -> BoomstreamConfigClient {
        let token = environment["BOOMSTREAM_TEST_UA_KEY"]
        let base = environment["BOOMSTREAM_CONFIG_BASE"] ?? "https://play.boomstream.net/"
        return BoomstreamConfigClient(
            baseURL: URL(string: base)!,
            userAgent: BoomstreamSDKInfo.userAgent(token: token),
            userAgentToken: token,
            connectTimeout: 15,
            resourceTimeout: 30
        )
    }

    @Test(arguments: mediaCodes)
    func playsStreamNatively(mediaCode: String) async throws {
        let core = BoomstreamPlayerCore()
        core.load(mediaCode: mediaCode, configClient: makeConfigClient())
        core.mute()

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if case .ready = core.state { break }
            if case .error(let message) = core.state {
                Issue.record("player error for \(mediaCode): \(message)")
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard case .ready = core.state else {
            Issue.record("\(mediaCode) not ready in 30s, state=\(core.state)")
            return
        }

        let playbackDeadline = Date().addingTimeInterval(30)
        while Date() < playbackDeadline, core.currentPosition < 3 {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        #expect(core.currentPosition >= 3, "\(mediaCode): playback did not progress past 3s")
        core.release()
    }
}
