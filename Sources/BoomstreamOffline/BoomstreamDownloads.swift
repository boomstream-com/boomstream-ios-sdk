import Foundation

public struct DownloadHandle: Equatable, Sendable {
    public let mediaCode: String

    public init(mediaCode: String) {
        self.mediaCode = mediaCode
    }
}

/// Публичный API офлайн-загрузок. `@MainActor` — UI-facing API, симметрично
/// `BoomstreamPlayerController`. Имплементация — `BoomstreamOfflineManager`.
@MainActor
public protocol BoomstreamDownloads: AnyObject, Sendable {
    func start(mediaCode: String, quality: DownloadQuality) async throws -> DownloadHandle
    func pause(mediaCode: String) async
    func resume(mediaCode: String) async
    func cancel(mediaCode: String) async
    func observe(mediaCode: String) -> AsyncStream<DownloadState>
    func observeAll() -> AsyncStream<[DownloadState]>
    func delete(mediaCode: String) async throws
    func stats() async -> StorageStats
    /// Удаляет загрузки с истёкшим `expiresAt` (TTL из server config).
    func purgeExpired() async
}
