import AVFoundation
import Foundation
import Testing
@testable import BoomstreamPlayer

// MARK: - SubtitleTrack model

@Test func subtitleTrackEquatable() {
    let a = SubtitleTrack(id: "0", displayName: "English")
    let b = SubtitleTrack(id: "0", displayName: "English")
    let c = SubtitleTrack(id: "1", displayName: "Français")
    #expect(a == b)
    #expect(a != c)
}

// MARK: - Phantom filter unit tests (tests the predicate in isolation)

@Test func subtitleFilterPassesRealSubtitleTrack() {
    #expect(BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .subtitle,
        isForced: false,
        isAccessibility: false
    ))
}

@Test func subtitleFilterRejectsClosedCaption() {
    #expect(!BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .closedCaption,
        isForced: false,
        isAccessibility: false
    ))
}

@Test func subtitleFilterRejectsForcedSubtitles() {
    #expect(!BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .subtitle,
        isForced: true,
        isAccessibility: false
    ))
}

@Test func subtitleFilterRejectsAccessibilityTranscription() {
    #expect(!BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .subtitle,
        isForced: false,
        isAccessibility: true
    ))
}

@Test func subtitleFilterRejectsClosedCaptionEvenIfNotForcedOrAccessibility() {
    // CC is rejected regardless of other flags
    #expect(!BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .closedCaption,
        isForced: false,
        isAccessibility: false
    ))
    #expect(!BoomstreamPlayerCore.subtitleOptionPasses(
        mediaType: .closedCaption,
        isForced: true,
        isAccessibility: true
    ))
}

// MARK: - Core state before load

@MainActor
@Test func subtitleTracksEmptyBeforeLoad() {
    let core = BoomstreamPlayerCore()
    #expect(core.availableSubtitleTracks.isEmpty)
    #expect(core.currentSubtitleTrack == nil)
    core.release()
}

// MARK: - selectSubtitleTrack / selectNoSubtitles no-op without tracks

@MainActor
@Test func selectSubtitleTrackNoOpWithoutTracks() {
    let core = BoomstreamPlayerCore()
    let phantom = SubtitleTrack(id: "0", displayName: "English")
    core.selectSubtitleTrack(phantom)
    #expect(core.currentSubtitleTrack == nil)
    core.release()
}

@MainActor
@Test func selectNoSubtitlesNoOpWithoutTracks() {
    let core = BoomstreamPlayerCore()
    core.selectNoSubtitles()
    #expect(core.currentSubtitleTrack == nil)
    core.release()
}

// MARK: - State resets on release

@MainActor
@Test func subtitleStateResetsOnRelease() {
    let core = BoomstreamPlayerCore()
    core.release()
    #expect(core.availableSubtitleTracks.isEmpty)
    #expect(core.currentSubtitleTrack == nil)
}

// MARK: - Stream exists

@MainActor
@Test func subtitleTrackUpdatesStreamExists() {
    let core = BoomstreamPlayerCore()
    let _ = core.subtitleTrackUpdates
    core.release()
}

// MARK: - Independence from audio and quality state

@MainActor
@Test func subtitleStateIndependentFromAudioAndQuality() {
    let core = BoomstreamPlayerCore()
    core.setSpeed(.double)
    core.setQuality(.resolution(height: 720))
    // Subtitle state unaffected by speed/quality changes
    #expect(core.availableSubtitleTracks.isEmpty)
    #expect(core.currentSubtitleTrack == nil)
    core.release()
}
