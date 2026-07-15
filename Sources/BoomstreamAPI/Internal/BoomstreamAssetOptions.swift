/// Options-словарь для `AVURLAsset` с UA-заголовком — единая точка для player/offline.
/// `AVURLAssetHTTPHeaderFieldsKey` — недокументированный, но индустриально-стандартный ключ;
/// доставляет UA во все три типа запросов (манифест/ключ/сегмент).
/// AVFoundation здесь не импортируется — таргет остаётся
/// Foundation-only, ключ — обычная строка.
package enum BoomstreamAssetOptions {
    package static func httpHeaderFields(userAgent: String) -> [String: any Sendable] {
        var options: [String: any Sendable] = [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
        ]
        if #available(iOS 16, macOS 13, *) {
            // Официальный ключ (AVURLAssetHTTPUserAgentKey, iOS 16+/macOS 13+);
            // на iOS 15 остаётся только header-fields fallback.
            options["AVURLAssetHTTPUserAgentKey"] = userAgent
        }
        return options
    }
}
