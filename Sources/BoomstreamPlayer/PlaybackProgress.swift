import Foundation

public struct PlaybackProgress: Equatable, Sendable {
    public let position: TimeInterval
    public let duration: TimeInterval
    public let bufferedPosition: TimeInterval

    public init(position: TimeInterval, duration: TimeInterval, bufferedPosition: TimeInterval) {
        self.position = position
        self.duration = duration
        self.bufferedPosition = bufferedPosition
    }

    /// Прогресс 0...1; 0 когда длительность неизвестна (live).
    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
