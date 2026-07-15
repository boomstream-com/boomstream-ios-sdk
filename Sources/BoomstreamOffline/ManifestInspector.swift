import Foundation

/// Классификация HLS-манифестов для preflight-проверки перед download.
///
/// Контекст: download-даемон (`nsurlsessiond`) качает манифесты своим User-Agent —
/// токен доступа туда не доходит. Для шифрованных потоков сервер без токена отдаёт
/// web-протокольный манифест (`URI="[KEY]",IV=[IV]` + `#EXT-X-MEDIA-READY`), который
/// AVFoundation либо не может распарсить, либо сохраняет неиграбельным (403 на `[KEY]`
/// при плейбеке). Детект превращает это в типизированную ошибку до скачивания сегментов.
enum ManifestInspector {
    /// `true` когда манифест — web-протокольная (clear key) версия, неиграбельная нативно.
    static func isWebClearKeyProtocol(_ manifest: String) -> Bool {
        manifest.contains("#EXT-X-MEDIA-READY")
            || manifest.contains(#"URI="[KEY]""#)
            || manifest.contains("IV=[IV]")
    }

    /// URL первого рендишена из master-манифеста (первая не-комментарий строка).
    static func firstVariantURL(in master: String, relativeTo base: URL) -> URL? {
        for rawLine in master.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            return URL(string: line, relativeTo: base)?.absoluteURL
        }
        return nil
    }
}
