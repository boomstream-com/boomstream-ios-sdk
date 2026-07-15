import AVFoundation
import Foundation
import BoomstreamAPI

enum AssetFactory {
    static func assetOptions(userAgent: String) -> [String: any Sendable] {
        BoomstreamAssetOptions.httpHeaderFields(userAgent: userAgent)
    }

    static func makeAsset(url: URL, userAgent: String) -> AVURLAsset {
        // Для локальных (file://) ассетов заголовки игнорируются системой — безвредно.
        AVURLAsset(url: url, options: assetOptions(userAgent: userAgent))
    }
}
