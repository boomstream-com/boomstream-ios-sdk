import Foundation

/// Playback quality selection. Surfaces only primitives — no AVFoundation types (CSO constraint #1).
///
/// Equality and hashing are based on the discriminant only:
/// `.auto == .auto` and `.resolution(height: h) == .resolution(height: h)` regardless of
/// `peakBitRate` or `label` — two variants at the same height are the same quality slot.
public enum VideoQuality: Sendable {
    /// Let AVFoundation choose adaptively (default).
    case auto
    /// Cap to a specific vertical resolution (e.g. 1080, 720, 360).
    /// `label` is derived automatically ("1080p", "720p", …) when nil.
    case resolution(height: Int, peakBitRate: Int? = nil, label: String? = nil)

    /// Human-readable label for display (e.g. "1080p", "Auto").
    public var label: String {
        switch self {
        case .auto:
            return "Auto"
        case .resolution(let height, _, let customLabel):
            return customLabel ?? "\(height)p"
        }
    }

    /// Height in pixels; nil for `.auto`.
    public var height: Int? {
        guard case .resolution(let h, _, _) = self else { return nil }
        return h
    }
}

extension VideoQuality: CustomStringConvertible {
    public var description: String { label }
}

extension VideoQuality: Equatable {
    public static func == (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto): return true
        case (.resolution(let lh, _, _), .resolution(let rh, _, _)): return lh == rh
        default: return false
        }
    }
}

extension VideoQuality: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .auto: hasher.combine(0)
        case .resolution(let height, _, _): hasher.combine(1); hasher.combine(height)
        }
    }
}
