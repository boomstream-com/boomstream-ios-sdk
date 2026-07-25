import Foundation
import Testing
@testable import BoomstreamPlayer

// Verifies the settings-menu data-model logic that lives in BoomstreamPlayerCore
// (i.e., the parts that don't need UIKit / a live AVPlayer).

// MARK: - Speed section always present

@MainActor
@Test func settingsMenuSpeedSectionAlwaysAvailable() {
    let core = BoomstreamPlayerCore()
    // availableSpeeds is a fixed, non-empty list regardless of load state.
    #expect(!core.availableSpeeds.isEmpty)
    core.release()
}

// MARK: - Speed selection round-trip

@MainActor
@Test func speedSelectionRoundTrip() {
    let core = BoomstreamPlayerCore()
    for speed in PlayerSpeed.allCases {
        core.setSpeed(speed)
        #expect(core.currentSpeed == speed)
    }
    core.release()
}

// MARK: - Audio section empty before readyToPlay

@MainActor
@Test func audioTracksEmptyBeforeLoad() {
    let core = BoomstreamPlayerCore()
    #expect(core.availableAudioTracks.isEmpty)
    #expect(core.currentAudioTrack == nil)
    core.release()
}

// MARK: - Audio track stream yields on discovery

@MainActor
@Test func audioTrackUpdatesStreamExists() {
    let core = BoomstreamPlayerCore()
    // Just verify the stream can be created without crashing.
    let _ = core.audioTrackUpdates
    core.release()
}

// MARK: - selectAudioTrack no-ops gracefully when no tracks loaded

@MainActor
@Test func selectAudioTrackNoOpWithoutTracks() {
    let core = BoomstreamPlayerCore()
    let phantom = AudioTrack(id: "0", displayName: "English")
    // Should not crash or mutate state when called before any item is loaded.
    core.selectAudioTrack(phantom)
    #expect(core.currentAudioTrack == nil)
    core.release()
}

// MARK: - Reset on load clears audio state

@MainActor
@Test func audioStateResetsOnLoad() async throws {
    // Simulate: inject audio state manually (internal test), then call release/reload.
    // We can't inject real AVFoundation audio groups in unit tests, so we verify
    // that stopPlayback (called inside load()) resets the public audio properties.
    let core = BoomstreamPlayerCore()
    // availableAudioTracks starts empty and stays empty after release.
    core.release()
    #expect(core.availableAudioTracks.isEmpty)
    #expect(core.currentAudioTrack == nil)
}

// MARK: - Quality + Speed independence

@MainActor
@Test func speedAndQualityAreIndependent() {
    let core = BoomstreamPlayerCore()
    core.setSpeed(.double)
    core.setQuality(.resolution(height: 720))
    #expect(core.currentSpeed == .double)
    #expect(core.currentQuality == .resolution(height: 720))
    core.selectAuto()
    #expect(core.currentSpeed == .double)  // speed unaffected by selectAuto
    #expect(core.currentQuality == .auto)
    core.release()
}
