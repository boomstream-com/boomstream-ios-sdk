import Foundation
import BoomstreamAPI

/// Состояния загрузки.
public enum DownloadState: Sendable {
    case queued(mediaCode: String)
    case inProgress(mediaCode: String, percent: Double, bytesDownloaded: Int64)
    case paused(mediaCode: String, percent: Double)
    case completed(mediaCode: String, sizeBytes: Int64, expiresAt: Date?)
    case failed(mediaCode: String, error: BoomstreamError)

    public var mediaCode: String {
        switch self {
        case .queued(let mediaCode),
             .inProgress(let mediaCode, _, _),
             .paused(let mediaCode, _),
             .completed(let mediaCode, _, _),
             .failed(let mediaCode, _):
            return mediaCode
        }
    }
}
