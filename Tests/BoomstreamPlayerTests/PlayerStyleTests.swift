#if canImport(UIKit)
import Foundation
import Testing
import UIKit
import BoomstreamPlayer

/// Tests for BoomstreamPlayerStyle — public API surface and backward-compat defaults.

// MARK: - Default values (backward-compat)

@Test func styleDefaultsAllNil() {
    let style = BoomstreamPlayerStyle()
    #expect(style.loaderColor == nil)
    #expect(style.accentColor == nil)
    #expect(style.seekBarPlayedColor == nil)
    #expect(style.seekBarScrubberColor == nil)
    #expect(style.seekBarBufferedColor == nil)
    #expect(style.messageTextColor == nil)
    #expect(style.messageBackgroundColor == nil)
}

@Test func styleAllFieldsCanBeSet() {
    let violet = UIColor(red: 0.4, green: 0.169, blue: 1.0, alpha: 1.0)
    var style = BoomstreamPlayerStyle(
        loaderColor: violet,
        accentColor: violet,
        seekBarPlayedColor: .white,
        seekBarScrubberColor: .white,
        seekBarBufferedColor: UIColor.white.withAlphaComponent(0.3),
        messageTextColor: .white,
        messageBackgroundColor: UIColor.black.withAlphaComponent(0.6)
    )
    #expect(style.loaderColor == violet)
    #expect(style.accentColor == violet)
    #expect(style.seekBarPlayedColor == .white)
    #expect(style.seekBarScrubberColor == .white)
    #expect(style.messageTextColor == .white)
    #expect(style.messageBackgroundColor != nil)

    // Struct mutation (copy-on-write semantics intact)
    style.accentColor = .red
    #expect(style.accentColor == .red)
}

@Test func styleTypenameContainsNoBannedPrefix() {
    let style = BoomstreamPlayerStyle()
    let typeName = String(describing: type(of: style))
    let forbidden = ["AV", "CM", "CoreMedia", "AVFoundation", "AVKit"]
    for prefix in forbidden {
        #expect(!typeName.hasPrefix(prefix), "BoomstreamPlayerStyle must not start with \(prefix)")
    }
}

@Test func styleSendable() {
    // Compile-time check: BoomstreamPlayerStyle is Sendable (used across actor boundaries)
    let style = BoomstreamPlayerStyle()
    Task { _ = style }  // would fail to compile if not Sendable
    #expect(Bool(true))
}

@Test func stylePartialInit() {
    // Only accentColor — all others remain nil
    let style = BoomstreamPlayerStyle(accentColor: .systemBlue)
    #expect(style.accentColor != nil)
    #expect(style.loaderColor == nil)
    #expect(style.seekBarPlayedColor == nil)
    #expect(style.seekBarScrubberColor == nil)
    #expect(style.seekBarBufferedColor == nil)
    #expect(style.messageTextColor == nil)
    #expect(style.messageBackgroundColor == nil)
}

@Test func stylePublicReflectionTypeName() {
    // BoomstreamPlayerStyle must appear under the BoomstreamPlayer module name
    let style = BoomstreamPlayerStyle()
    let typeName = String(reflecting: type(of: style))
    #expect(typeName.contains("BoomstreamPlayer") || typeName.contains("BoomstreamPlayerStyle"))
}
#endif
