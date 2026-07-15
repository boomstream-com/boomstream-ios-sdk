import Foundation

/// Постер/превью в конкретном разрешении (wire-контракт: `{width, height, link}`).
public struct Poster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Абсолютный URL изображения.
    public let link: String

    public init(width: Int, height: Int, link: String) {
        self.width = width
        self.height = height
        self.link = link
    }

    public var url: URL? { URL(string: link) }
}

extension Poster: Decodable {
    private enum CodingKeys: String, CodingKey {
        case width, height, link
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // height у defaults-постеров обычно 0; сервер может опускать поля — терпимый декодинг
        self.width = container.decodeLenientInt(forKey: .width) ?? 0
        self.height = container.decodeLenientInt(forKey: .height) ?? 0
        self.link = (try? container.decodeIfPresent(String.self, forKey: .link)) ?? ""
    }
}

extension KeyedDecodingContainer {
    /// Терпимый декодинг: принимает и число, и число-в-строке (`"5"` → 5).
    func decodeLenientInt(forKey key: Key) -> Int? {
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return int }
        if let string = try? decodeIfPresent(String.self, forKey: key) { return Int(string) }
        if let double = try? decodeIfPresent(Double.self, forKey: key) { return Int(double) }
        return nil
    }
}
