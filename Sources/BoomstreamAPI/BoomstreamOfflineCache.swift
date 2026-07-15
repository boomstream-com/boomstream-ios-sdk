import Foundation

/// Стык player ↔ offline: плеер спрашивает локальную копию перед сетевым config-резолвом.
/// Имплементируется `BoomstreamOfflineManager` (offline-sdk); протокол живёт в api-таргете,
/// чтобы player не зависел от offline.
public protocol BoomstreamOfflineCache: AnyObject, Sendable {
    /// URL скачанного ассета для `mediaCode`, или `nil` когда локальной копии нет.
    @MainActor func localAssetURL(mediaCode: String) -> URL?
}
