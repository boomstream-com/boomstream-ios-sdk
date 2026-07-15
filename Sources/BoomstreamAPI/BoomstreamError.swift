import Foundation

/// Корневая error-модель SDK.
public enum BoomstreamError: Error, Sendable {
    /// IO / timeout / DNS.
    case network(underlying: any Error)
    /// Non-2xx ответ Boomstream API.
    case http(statusCode: Int, body: String?)
    /// API вернул `{"Status":"Failed","Message":"..."}` — семантическая ошибка, не HTTP.
    case apiError(message: String)
    /// Config без `mediaData` — нет доступа к медиа.
    case unauthorised
    case mediaNotFound(mediaCode: String)
    case drmFailure(underlying: (any Error)?)
    case offlineUnavailable(reason: String)
    case unknown(underlying: (any Error)?)
}

extension BoomstreamError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .http(let statusCode, _):
            return "Boomstream API returned HTTP \(statusCode)"
        case .apiError(let message):
            return "Boomstream API error: \(message)"
        case .unauthorised:
            return "Media is not authorised for playback"
        case .mediaNotFound(let mediaCode):
            return "Media not found: \(mediaCode)"
        case .drmFailure:
            return "DRM failure"
        case .offlineUnavailable(let reason):
            return "Offline copy unavailable: \(reason)"
        case .unknown:
            return "Unknown Boomstream SDK error"
        }
    }
}