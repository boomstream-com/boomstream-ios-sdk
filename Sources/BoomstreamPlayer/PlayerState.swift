import Foundation

/// Состояния плеера.
public enum PlayerState: Equatable, Sendable {
    case idle
    case loading
    case ready(
        title: String?,
        isPlaylist: Bool,
        playlistIndex: Int,
        playlistSize: Int,
        isLive: Bool,
        systemMessage: String?
    )
    /// Постер вместо плеера: неавторизованный доступ (`mediaData: null`) либо
    /// live-трансляция офлайн (`isLiveOffline == true`, идёт поллинг config).
    case posterOnly(posterURL: URL?, message: String?, isLiveOffline: Bool)
    case error(message: String)
    case ended
}
