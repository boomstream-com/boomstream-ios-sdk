import Foundation

/// A subtitle track available for selection. Surfaces only primitives — no AVFoundation types (CSO constraint #1).
public struct SubtitleTrack: Sendable, Equatable {
    /// Opaque identifier stable for the lifetime of one playback item.
    public let id: String
    /// Human-readable name for display (e.g. "English", "Français").
    public let displayName: String
}
