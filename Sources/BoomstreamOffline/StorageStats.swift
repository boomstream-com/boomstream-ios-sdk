public struct StorageStats: Equatable, Sendable {
    public let downloadsCount: Int
    public let totalSizeBytes: Int64

    public init(downloadsCount: Int, totalSizeBytes: Int64) {
        self.downloadsCount = downloadsCount
        self.totalSizeBytes = totalSizeBytes
    }
}
