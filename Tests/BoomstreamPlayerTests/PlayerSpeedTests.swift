import Foundation
import Testing
@testable import BoomstreamPlayer

// MARK: - PlayerSpeed model

@Test func playerSpeedLabels() {
    #expect(PlayerSpeed.half.label == "0.5×")
    #expect(PlayerSpeed.threeQuarters.label == "0.75×")
    #expect(PlayerSpeed.normal.label == "Normal")
    #expect(PlayerSpeed.oneQuarter.label == "1.25×")
    #expect(PlayerSpeed.oneHalf.label == "1.5×")
    #expect(PlayerSpeed.double.label == "2×")
}

@Test func playerSpeedRawValues() {
    #expect(PlayerSpeed.half.rawValue == 0.5)
    #expect(PlayerSpeed.normal.rawValue == 1.0)
    #expect(PlayerSpeed.double.rawValue == 2.0)
}

@Test func playerSpeedDescriptionMatchesLabel() {
    for speed in PlayerSpeed.allCases {
        #expect(speed.description == speed.label)
    }
}

@Test func playerSpeedAllCasesCount() {
    #expect(PlayerSpeed.allCases.count == 6)
}

// MARK: - Core speed API

@MainActor
@Test func coreDefaultSpeedIsNormal() {
    let core = BoomstreamPlayerCore()
    #expect(core.currentSpeed == .normal)
    #expect(core.availableSpeeds == PlayerSpeed.allCases)
    core.release()
}

@MainActor
@Test func coreSetSpeedUpdatesCurrentSpeed() {
    let core = BoomstreamPlayerCore()
    core.setSpeed(.double)
    #expect(core.currentSpeed == .double)
    core.setSpeed(.half)
    #expect(core.currentSpeed == .half)
    core.setSpeed(.normal)
    #expect(core.currentSpeed == .normal)
    core.release()
}

@MainActor
@Test func coreSpeedPersistedAcrossStopPlayback() async throws {
    let core = BoomstreamPlayerCore()
    core.setSpeed(.oneHalf)
    #expect(core.currentSpeed == .oneHalf)
    // stopPlayback is called inside load(); speed is intentionally preserved.
    // We can't call load() without a config client, so verify via public state only.
    core.release()
    // After release, speed remains — it is not part of idle reset.
    #expect(core.currentSpeed == .oneHalf)
}

// MARK: - AudioTrack model

@Test func audioTrackEquality() {
    let a = AudioTrack(id: "0", displayName: "English")
    let b = AudioTrack(id: "0", displayName: "English")
    let c = AudioTrack(id: "1", displayName: "Français")
    #expect(a == b)
    #expect(a != c)
}

// MARK: - Core audio API

@MainActor
@Test func coreDefaultAudioState() {
    let core = BoomstreamPlayerCore()
    #expect(core.availableAudioTracks.isEmpty)
    #expect(core.currentAudioTrack == nil)
    core.release()
}

// MARK: - AdvancedPlayerOptions

@Test func advancedOptionsDefaultsPreserved() {
    let opts = AdvancedPlayerOptions()
    #expect(opts.showSettingsMenu == false)
    #expect(opts.showQualitySelector == false)
}

@Test func advancedOptionsSettingsMenuFlag() {
    let opts = AdvancedPlayerOptions(showSettingsMenu: true)
    #expect(opts.showSettingsMenu == true)
    #expect(opts.showQualitySelector == false)
}

@Test func advancedOptionsLegacyQualitySelectorPreserved() {
    let opts = AdvancedPlayerOptions(showQualitySelector: true)
    #expect(opts.showSettingsMenu == false)
    #expect(opts.showQualitySelector == true)
}

@Test func advancedOptionsEquatableRoundtrip() {
    let a = AdvancedPlayerOptions(showSettingsMenu: true, showQualitySelector: false)
    let b = AdvancedPlayerOptions(showSettingsMenu: true, showQualitySelector: false)
    #expect(a == b)
    let c = AdvancedPlayerOptions(showSettingsMenu: false, showQualitySelector: true)
    #expect(a != c)
}
