import Foundation
import Testing
@testable import BoomstreamPlayer

@Test func progressFractionIsClampedAndLiveSafe() {
    #expect(PlaybackProgress(position: 30, duration: 60, bufferedPosition: 45).fraction == 0.5)
    // live: duration неизвестна
    #expect(PlaybackProgress(position: 30, duration: 0, bufferedPosition: 0).fraction == 0)
    // за пределами длительности — клампится
    #expect(PlaybackProgress(position: 90, duration: 60, bufferedPosition: 90).fraction == 1)
    #expect(PlaybackProgress(position: -5, duration: 60, bufferedPosition: 0).fraction == 0)
}

@Test func advancedOptionsDefaultsDelegateToEngine() {
    let options = AdvancedPlayerOptions()
    #expect(options.preferredForwardBufferDuration == 0)
    #expect(options.automaticallyWaitsToMinimizeStalling)
    #expect(options.preferredPeakBitRate == 0)
}

@Test func playerStateEqualityCoversAssociatedValues() {
    let ready = PlayerState.ready(
        title: "t", isPlaylist: true, playlistIndex: 1, playlistSize: 3, isLive: false, systemMessage: nil
    )
    #expect(ready != .idle)
    #expect(
        PlayerState.posterOnly(posterURL: nil, message: "m", isLiveOffline: false)
            == .posterOnly(posterURL: nil, message: "m", isLiveOffline: false)
    )
    #expect(
        PlayerState.posterOnly(posterURL: nil, message: "m", isLiveOffline: true)
            != .posterOnly(posterURL: nil, message: "m", isLiveOffline: false)
    )
}
