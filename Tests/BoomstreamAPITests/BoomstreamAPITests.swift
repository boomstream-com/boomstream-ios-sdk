import Foundation
import Testing
@testable import BoomstreamAPI

@Test func versionFlowsIntoUserAgent() {
    #expect(!BoomstreamSDKInfo.version.isEmpty)
    #expect(BoomstreamSDKInfo.userAgentBase == "Boomstream iOS SDK v\(BoomstreamSDKInfo.version)")
}

@Test func optionsDescriptionMasksToken() {
    let options = BoomstreamOptions(userAgentToken: "super-secret-ua-allow-token")
    #expect(!options.description.contains("super-secret-ua-allow-token"))
    #expect(options.description.contains("***"))
    #expect(BoomstreamOptions().description.contains("userAgentToken: nil"))
}

@Test func optionsDefaultsMatchArchitectureDoc() {
    let options = BoomstreamOptions()
    #expect(options.connectTimeout == 15)
    #expect(options.resourceTimeout == 30)
    #expect(options.apiBaseURL.absoluteString == "https://boomstream.com/")
    #expect(options.configBaseURL.absoluteString == "https://play.boomstream.com/")
}

@Test func effectiveUserAgentComposition() {
    let withToken = BoomstreamRegistry.effectiveUserAgent(options: BoomstreamOptions(userAgentToken: "tok"))
    #expect(withToken == "Boomstream iOS SDK v\(BoomstreamSDKInfo.version) tok")
    let withoutToken = BoomstreamRegistry.effectiveUserAgent(options: BoomstreamOptions())
    #expect(withoutToken == BoomstreamSDKInfo.userAgentBase)
}

@Test func registryConfigureIsIdempotentForSameConfiguration() {
    let registry = BoomstreamRegistry()
    #expect(!registry.isConfigured)

    let options = BoomstreamOptions(userAgentToken: "t")
    registry.configure(apiKey: "key", options: options)
    registry.configure(apiKey: "key", options: options)

    #expect(registry.isConfigured)
    #expect(registry.currentConfiguration?.apiKey == "key")
}
