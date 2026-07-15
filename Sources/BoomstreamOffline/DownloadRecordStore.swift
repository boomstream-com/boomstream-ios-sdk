import Foundation

/// Запись о загрузке. Локация ассета хранится как **bookmark data**, не сырой путь —
/// контейнер приложения переезжает при backup/restore и обновлениях
/// (docs/SDK_ARCHITECTURE.md §6).
struct DownloadRecord: Codable, Equatable, Sendable {
    var mediaCode: String
    var title: String?
    var bookmark: Data?
    var expiresAt: Date?
    var sizeBytes: Int64?
}

/// Персистенция `mediaCode → DownloadRecord` в JSON-файле в Application Support.
/// Директория инжектируется ради тестов (temp dir).
final class DownloadRecordStore {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Boomstream", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("downloads.json")
    }

    func load() -> [String: DownloadRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([String: DownloadRecord].self, from: data)
        else { return [:] }
        return records
    }

    func save(_ records: [String: DownloadRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
