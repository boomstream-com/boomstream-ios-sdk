import Foundation

/// События плеера.
public enum PlayerEvent: Equatable, Sendable {
    case loaded
    case playing
    case paused
    case ended
    case progress(PlaybackProgress)
    case seeked(TimeInterval)
    case fullScreenChanged(Bool)
}
