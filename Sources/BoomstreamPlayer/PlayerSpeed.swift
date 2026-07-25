import Foundation

/// Playback speed preset. Surfaces only primitives — no AVFoundation types (CSO constraint #1).
public enum PlayerSpeed: Float, CaseIterable, Sendable {
    case half        = 0.5
    case threeQuarters = 0.75
    case normal      = 1.0
    case oneQuarter  = 1.25
    case oneHalf     = 1.5
    case double      = 2.0

    public var label: String {
        switch self {
        case .half:         return "0.5×"
        case .threeQuarters: return "0.75×"
        case .normal:       return "Normal"
        case .oneQuarter:   return "1.25×"
        case .oneHalf:      return "1.5×"
        case .double:       return "2×"
        }
    }
}

extension PlayerSpeed: CustomStringConvertible {
    public var description: String { label }
}
