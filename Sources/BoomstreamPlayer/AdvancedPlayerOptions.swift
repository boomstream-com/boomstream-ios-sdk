import Foundation

/// Whitelisted-тюнинг плеера (docs/SDK_ARCHITECTURE.md §2, CSO constraint #1).
/// Сырой `AVPlayer` наружу не экспонируется — только эти параметры.
public struct AdvancedPlayerOptions: Equatable, Sendable {
    /// Секунды упреждающего буфера; 0 = системный автоматический выбор.
    public var preferredForwardBufferDuration: TimeInterval
    public var automaticallyWaitsToMinimizeStalling: Bool
    /// Бит/с; 0 = авто (адаптивный выбор рендишена).
    public var preferredPeakBitRate: Double
    /// When `true`, a gear button appears in the built-in controls overlay.
    /// Tapping it shows an action sheet listing `availableQualities` + Auto.
    /// Default is `false` (opt-in; existing overlay layout is unchanged).
    public var showQualitySelector: Bool

    public init(
        preferredForwardBufferDuration: TimeInterval = 0,
        automaticallyWaitsToMinimizeStalling: Bool = true,
        preferredPeakBitRate: Double = 0,
        showQualitySelector: Bool = false
    ) {
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
        self.preferredPeakBitRate = preferredPeakBitRate
        self.showQualitySelector = showQualitySelector
    }
}
