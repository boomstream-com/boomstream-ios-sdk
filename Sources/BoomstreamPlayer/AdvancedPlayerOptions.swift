import Foundation

/// Whitelisted-тюнинг плеера (docs/SDK_ARCHITECTURE.md §2, CSO constraint #1).
/// Сырой `AVPlayer` наружу не экспонируется — только эти параметры.
public struct AdvancedPlayerOptions: Equatable, Sendable {
    /// Секунды упреждающего буфера; 0 = системный автоматический выбор.
    public var preferredForwardBufferDuration: TimeInterval
    public var automaticallyWaitsToMinimizeStalling: Bool
    /// Бит/с; 0 = авто (адаптивный выбор рендишена).
    public var preferredPeakBitRate: Double

    public init(
        preferredForwardBufferDuration: TimeInterval = 0,
        automaticallyWaitsToMinimizeStalling: Bool = true,
        preferredPeakBitRate: Double = 0
    ) {
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
        self.preferredPeakBitRate = preferredPeakBitRate
    }
}
