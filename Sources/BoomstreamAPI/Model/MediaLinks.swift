import Foundation

/// Ссылки воспроизведения. Все значения на wire — Base64-encoded, декодируются на доступе.
public struct MediaLinks: Equatable, Sendable, Decodable {
    /// Base64-encoded URL HLS-манифеста. Декодированное значение — `hlsURL` / `hlsURLString`.
    public let hls: String?

    public init(hls: String?) {
        self.hls = hls
    }

    /// Декодированный URL HLS-манифеста строкой, или `nil`.
    public var hlsURLString: String? {
        guard let hls,
              let data = Data(base64Encoded: hls, options: .ignoreUnknownCharacters),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    public var hlsURL: URL? {
        hlsURLString.flatMap(URL.init(string:))
    }
}
