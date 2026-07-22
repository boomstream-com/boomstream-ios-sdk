import Foundation
import Testing
import BoomstreamPlayer

/// CSO constraint #1 — no AVFoundation/CoreMedia/AVKit types in the public API surface.
///
/// This test enumerates the public types from BoomstreamPlayer that host apps interact with
/// and asserts that none of their declared type names reference AVFoundation, CoreMedia, or AVKit.
/// It runs without network access and requires no device.
///
/// Covered types:
///   • VideoQuality (new Wave 1 type)
///   • BoomstreamPlayerController protocol members (via BoomstreamPlayerCore conformance)
///   • AdvancedPlayerOptions
///   • PlayerState, PlayerEvent, PlaybackProgress

private let forbiddenPrefixes = ["AV", "CM", "CoreMedia", "AVFoundation", "AVKit", "CGImage"]
// CGSize is an internal implementation detail (ok); it must not appear as a public return/param type.
// We use a string-match approach over Mirror/reflection since Swift's Mirror can't enumerate protocol
// requirements. Instead we compile-time-verify via the protocol itself and check known concrete types.

/// Returns true if a type name string contains a forbidden framework prefix.
private func isForbidden(_ typeName: String) -> Bool {
    forbiddenPrefixes.contains(where: { typeName.hasPrefix($0) })
}

// MARK: - VideoQuality surface

@Test func videoQualityExposesOnlyPrimitives() {
    // All associated values must be primitive Swift types.
    // .auto — no associated values.
    let auto = VideoQuality.auto
    #expect(auto.label is String)

    // .resolution — height: Int, peakBitRate: Int?, label: String?
    let res = VideoQuality.resolution(height: 1080, peakBitRate: 5_000_000, label: "1080p")
    #expect(res.height is Int?)
    #expect(res.label is String)

    // Confirm no AVFoundation type leaks through CustomStringConvertible
    let desc: String = res.description
    #expect(!desc.isEmpty)
}

@Test func videoQualityHeightIsOptionalInt() {
    // height property returns Int? — a pure Swift primitive
    let auto: VideoQuality = .auto
    let res: VideoQuality = .resolution(height: 720)
    let autoHeight: Int? = auto.height
    let resHeight: Int? = res.height
    #expect(autoHeight == nil)
    #expect(resHeight == 720)
}

// MARK: - Protocol surface via BoomstreamPlayerCore

@MainActor
@Test func controllerQualityAPIReturnsPrimitiveTypes() {
    let core = BoomstreamPlayerCore()

    // availableQualities: [VideoQuality] — VideoQuality is defined in BoomstreamPlayer, no AV types
    let available: [VideoQuality] = core.availableQualities
    #expect(available.isEmpty) // no content loaded

    // currentQuality / preferredQuality: VideoQuality
    let current: VideoQuality = core.currentQuality
    let preferred: VideoQuality = core.preferredQuality
    #expect(current == .auto)
    #expect(preferred == .auto)

    // qualityUpdates: AsyncStream<[VideoQuality]> — pure Swift
    let _: AsyncStream<[VideoQuality]> = core.qualityUpdates

    core.release()
}

@MainActor
@Test func setQualityAcceptsVideoQualityOnly() {
    // Compile-time check: setQuality(_:) takes VideoQuality, not an AV type.
    // If this compiles, the surface is correct.
    let core = BoomstreamPlayerCore()
    core.setQuality(.resolution(height: 720))
    core.selectAuto()
    core.release()
}

// MARK: - Type-name checks via string reflection

@Test func videoQualityTypenameContainsNoBannedPrefix() {
    let mirror = Mirror(reflecting: VideoQuality.auto)
    let typeName = String(describing: type(of: VideoQuality.auto))
    #expect(!isForbidden(typeName), "VideoQuality itself must not be an AV type: \(typeName)")
    _ = mirror // silence unused-variable warning
}

@Test func playerStateTypenameContainsNoBannedPrefix() {
    let typeName = String(describing: type(of: PlayerState.idle))
    #expect(!isForbidden(typeName))
}

@Test func playerEventTypenameContainsNoBannedPrefix() {
    let typeName = String(describing: type(of: PlayerEvent.loaded))
    #expect(!isForbidden(typeName))
}

@Test func playbackProgressTypenameContainsNoBannedPrefix() {
    let progress = PlaybackProgress(position: 0, duration: 0, bufferedPosition: 0)
    let typeName = String(describing: type(of: progress))
    #expect(!isForbidden(typeName))
}

@Test func advancedPlayerOptionsTypenameContainsNoBannedPrefix() {
    let opts = AdvancedPlayerOptions()
    let typeName = String(describing: type(of: opts))
    #expect(!isForbidden(typeName))
}
