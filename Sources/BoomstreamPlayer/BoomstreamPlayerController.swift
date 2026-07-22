import Foundation

/// Единственная точка программного управления плеером. `@MainActor` даёт
/// compile-time гарантию main-thread контракта.
@MainActor
public protocol BoomstreamPlayerController: AnyObject {
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    /// - Parameter percent: 0...1 от известной длительности.
    func seek(toPercent percent: Double)
    func setVolume(_ volume: Float)
    func mute()
    func unmute()
    /// Плейлисты (`mediaData: array`).
    func next()
    func previous()
    /// Ориентацией владеет host-приложение; SDK меняет только layout-состояние.
    func setFullScreen(_ on: Bool)
    func toggleFullScreen()

    var currentPosition: TimeInterval { get }
    var duration: TimeInterval { get }
    var state: PlayerState { get }
    /// Каждый доступ возвращает независимый стрим (мультикаст).
    var states: AsyncStream<PlayerState> { get }
    var events: AsyncStream<PlayerEvent> { get }
    var progress: AsyncStream<PlaybackProgress> { get }

    // MARK: - Video quality API (Wave 1)

    /// Quality variants discovered from the HLS master manifest. Populated after `.readyToPlay`.
    /// Only primitives are exposed — no AVFoundation types (CSO constraint #1).
    var availableQualities: [VideoQuality] { get }
    /// The quality cap currently applied to the player engine (`.auto` until changed).
    var currentQuality: VideoQuality { get }
    /// The quality last requested by the host via `setQuality` / `selectAuto`.
    var preferredQuality: VideoQuality { get }
    /// Stream of available-quality updates (fires when variants are discovered or change).
    var qualityUpdates: AsyncStream<[VideoQuality]> { get }

    /// Apply a quality cap. Pass `.resolution(height:)` to restrict; see `availableQualities`.
    func setQuality(_ quality: VideoQuality)
    /// Remove the quality cap and return to adaptive streaming.
    func selectAuto()
}
