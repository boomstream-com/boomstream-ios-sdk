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
}
