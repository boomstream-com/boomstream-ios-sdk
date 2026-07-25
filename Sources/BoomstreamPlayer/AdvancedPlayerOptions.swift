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
    /// Tapping it shows a unified settings sheet with Speed, Quality, and Audio sections.
    /// Supersedes `showQualitySelector` when both are `true`.
    /// Default is `false` (opt-in; existing overlay layout is unchanged).
    public var showSettingsMenu: Bool

    /// Legacy opt-in: gear button shows a quality-only action sheet.
    /// Ignored when `showSettingsMenu` is `true`.
    /// Default is `false`.
    public var showQualitySelector: Bool

    /// Language code for built-in UI strings shown in the settings menu (e.g. `"ru"`, `"en"`).
    /// Only the first two characters are used, so `"ru-RU"` resolves as `"ru"`.
    /// Supported: `"en"`, `"ru"`. Unsupported locales fall back to `"en"`.
    /// Locale is set by the integrator — not derived from the system locale.
    /// Default is `"en"`.
    public var locale: String

    public init(
        preferredForwardBufferDuration: TimeInterval = 0,
        automaticallyWaitsToMinimizeStalling: Bool = true,
        preferredPeakBitRate: Double = 0,
        showSettingsMenu: Bool = false,
        showQualitySelector: Bool = false,
        locale: String = "en"
    ) {
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
        self.preferredPeakBitRate = preferredPeakBitRate
        self.showSettingsMenu = showSettingsMenu
        self.showQualitySelector = showQualitySelector
        self.locale = locale
    }
}
