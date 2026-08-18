import Foundation
import Testing
@testable import BoomstreamPlayer

/// Simulator-only AirPlay state-machine tests.
///
/// Verifies the public API surface and state transitions via `handleExternalPlaybackChange`,
/// an internal bridge accessible through `@testable import` that mirrors what the KVO
/// observer delivers when `AVPlayer.isExternalPlaybackActive` changes on device.
/// No real AirPlay router or Apple TV is required.

// MARK: - Initial state

@MainActor
@Test func airPlayInitialStateIsFalse() {
    let core = BoomstreamPlayerCore()
    #expect(core.isAirPlaying == false)
    core.release()
}

@MainActor
@Test func airPlayDeviceNameIsNilWithoutActiveRoute() {
    let core = BoomstreamPlayerCore()
    #expect(core.airPlayDeviceName == nil)
    core.release()
}

// MARK: - KVO simulation via @testable bridge

@MainActor
@Test func airPlayUpdatesYieldsTrueOnSimulatedKVOChange() async {
    let core = BoomstreamPlayerCore()
    let stream = core.airPlayUpdates

    core.handleExternalPlaybackChange(true)

    var iterator = stream.makeAsyncIterator()
    let value = await iterator.next()
    #expect(value == true)
    #expect(core.isAirPlaying == true)
    core.release()
}

@MainActor
@Test func airPlayUpdatesYieldsFalseWhenAirPlayEnds() async {
    let core = BoomstreamPlayerCore()
    let stream = core.airPlayUpdates

    core.handleExternalPlaybackChange(true)
    core.handleExternalPlaybackChange(false)

    var iterator = stream.makeAsyncIterator()
    let first = await iterator.next()
    let second = await iterator.next()
    #expect(first == true)
    #expect(second == false)
    #expect(core.isAirPlaying == false)
    #expect(core.airPlayDeviceName == nil)
    core.release()
}

@MainActor
@Test func airPlayDeviceNameClearedWhenAirPlayEnds() {
    let core = BoomstreamPlayerCore()
    core.handleExternalPlaybackChange(true)
    // Simulate end of AirPlay — device name must be cleared regardless of platform.
    core.handleExternalPlaybackChange(false)
    #expect(core.airPlayDeviceName == nil)
    #expect(core.isAirPlaying == false)
    core.release()
}

// MARK: - Teardown

@MainActor
@Test func airPlayObserverTeardownDoesNotCrash() {
    // Regression guard: releasing the core after AirPlay activity must not crash.
    let core = BoomstreamPlayerCore()
    let _ = core.airPlayUpdates
    core.handleExternalPlaybackChange(true)
    core.release()
    // stopPlayback() inside release() resets isAirPlaying to false.
    #expect(core.isAirPlaying == false)
}

@MainActor
@Test func airPlayKVODoesNotRetainCore() async {
    // Verify the KVO observer and Broadcast onTermination handler do not create a retain cycle.
    weak var weakCore: BoomstreamPlayerCore?
    autoreleasepool {
        let core = BoomstreamPlayerCore()
        weakCore = core
        let _ = core.airPlayUpdates
        core.handleExternalPlaybackChange(true)
        core.release()
    }
    await Task.yield()
    await Task.yield()
    #expect(weakCore == nil, "Core must be deallocated — no retain cycle via KVO observer or Broadcast continuation")
}
