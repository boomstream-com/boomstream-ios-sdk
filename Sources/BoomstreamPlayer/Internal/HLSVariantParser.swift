import Foundation

/// Parses `EXT-X-STREAM-INF` entries from an HLS master manifest into `VideoQuality` values.
///
/// Evidence (rule #16 — live Boomstream source, 2026-07-22):
///   GET https://play.boomstream.com/wZby7dI0/config → mediaData.links.hls (base64-decoded) →
///   GET https://cdnv.boomstream.com/adaptive/hash:.../PDHSp7yX/playlist.m3u8 — 5 variants:
///     #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1835322,RESOLUTION=720x960
///     #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1810308,RESOLUTION=720x960
///     #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=953903,RESOLUTION=480x640
///     #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=636246,RESOLUTION=360x480
///     #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=337388,RESOLUTION=240x320
///   Confirms multi-variant format: RESOLUTION=WIDTHxHEIGHT (height = second component), BANDWIDTH in bps.
enum HLSVariantParser {
    struct Variant {
        let height: Int
        let bandwidth: Int
        let codecs: String?
    }

    /// Returns unique variants sorted descending by height, then bandwidth.
    static func parse(master: String) -> [VideoQuality] {
        var results: [Variant] = []
        let lines = master.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }

        for (i, line) in lines.enumerated() {
            guard line.uppercased().hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            // Next non-empty, non-comment line is the variant URI — confirms this is a real variant entry
            let hasVariantURI = lines[(i + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix("#") }) != nil
            guard hasVariantURI else { continue }

            guard let height = parseAttribute("RESOLUTION", from: line).flatMap(parseHeight),
                  let bandwidth = parseAttribute("BANDWIDTH", from: line).flatMap({ Int($0) })
            else { continue }

            let codecs = parseAttribute("CODECS", from: line)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            results.append(Variant(height: height, bandwidth: bandwidth, codecs: codecs))
        }

        // Deduplicate by height, keeping highest bandwidth per height
        var byHeight: [Int: Variant] = [:]
        for v in results {
            if let existing = byHeight[v.height] {
                if v.bandwidth > existing.bandwidth { byHeight[v.height] = v }
            } else {
                byHeight[v.height] = v
            }
        }

        return byHeight.values
            .sorted { $0.height != $1.height ? $0.height > $1.height : $0.bandwidth > $1.bandwidth }
            .map { .resolution(height: $0.height, peakBitRate: $0.bandwidth) }
    }

    // MARK: - Attribute parsing

    private static func parseAttribute(_ key: String, from line: String) -> String? {
        // Matches KEY=VALUE or KEY="VALUE" in a comma-separated attribute list
        let pattern = "\(key)=([^\",][^,]*|\"[^\"]*\")"
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(line[range])
        let value = match.dropFirst(key.count + 1) // drop "KEY="
        return String(value)
    }

    private static func parseHeight(from resolution: String) -> Int? {
        // RESOLUTION=WxH  (e.g. "1920x1080")
        let parts = resolution.split(separator: "x")
        guard parts.count == 2, let h = Int(parts[1]) else { return nil }
        return h
    }
}
