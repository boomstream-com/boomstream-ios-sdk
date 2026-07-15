import BoomstreamAPI
import BoomstreamOffline
import SwiftUI

@main
struct BoomstreamExampleApp: App {
    init() {
        AppEnvironment.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Конфигурация приложения. Значения приходят из Info.plist, куда подставляются
/// build-settings из `Config/Local.xcconfig` (gitignored) — ключи не хардкодятся.
@MainActor
enum AppEnvironment {
    static private(set) var hasAPIKey = false
    static private(set) var demoMediaCode = ""
    static private(set) var offline: BoomstreamOfflineManager!

    static func bootstrap() {
        let apiKey = infoValue("BoomstreamAPIKey")
        let options = BoomstreamOptions(
            userAgentToken: infoValue("BoomstreamUAToken"),
            configBaseURL: infoValue("BoomstreamConfigBase")
                .flatMap(URL.init(string:)) ?? URL(string: "https://play.boomstream.com/")!
        )
        Boomstream.configure(apiKey: apiKey, options: options)
        hasAPIKey = (apiKey != nil)
        demoMediaCode = infoValue("BoomstreamDemoMediaCode") ?? ""
        offline = BoomstreamOfflineManager(configClient: Boomstream.configClient)
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
