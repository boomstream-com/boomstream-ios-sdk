import Foundation

/// An audio track available for selection. Surfaces only primitives — no AVFoundation types (CSO constraint #1).
public struct AudioTrack: Sendable, Equatable {
    /// Opaque identifier stable for the lifetime of one playback item.
    public let id: String
    /// Human-readable name for display (e.g. "English", "Français").
    public let displayName: String
}
