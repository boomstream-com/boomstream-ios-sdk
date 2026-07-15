import AVFoundation
import Foundation
import BoomstreamAPI

/// Офлайн-загрузки HLS на системном стеке `AVAssetDownloadURLSession`
/// (docs/SDK_ARCHITECTURE.md §6). Имплементирует `BoomstreamDownloads` и
/// `BoomstreamOfflineCache` (стык с плеером: `BoomstreamPlayerView(offlineCache:)`).
///
/// Background-сессия с фиксированным identifier: загрузки продолжаются после
/// сворачивания приложения; после перезапуска вызовите `restoreTransfers()`.
@MainActor
public final class BoomstreamOfflineManager: BoomstreamDownloads, BoomstreamOfflineCache {
    public static let defaultSessionIdentifier = "com.boomstream.sdk.offline"

    private let configClient: any BoomstreamConfigFetching
    private let store: DownloadRecordStore
    private var records: [String: DownloadRecord]
    private var activeTasks: [String: AVAssetDownloadTask] = [:]
    private var pendingLocations: [String: URL] = [:]
    private var currentStates: [String: DownloadState] = [:]
    private var lastPercent: [String: Double] = [:]
    private let stateBroadcast = Broadcast<DownloadState>()
    // Отдельный канал для observeAll(): оповещает и об удалениях (delete/cancel),
    // которые не выражаются одиночным DownloadState.
    private let catalogBroadcast = Broadcast<[DownloadState]>()
    private let delegateAdapter: OfflineSessionDelegate
    // nonisolated(unsafe): выставляется один раз в init, в deinit только invalidate.
    private nonisolated(unsafe) var session: AVAssetDownloadURLSession!

    /// - Parameters:
    ///   - configClient: клиент config-эндпоинта (резолв HLS URL + `ua_allow`-токен).
    ///   - sessionIdentifier: identifier background-сессии; должен быть стабильным между
    ///     запусками приложения.
    ///   - allowsCellularAccess: по умолчанию `false` — только Wi-Fi (аналог NETWORK_UNMETERED).
    ///   - storeDirectory: переопределение директории персистенции (тесты).
    public init(
        configClient: any BoomstreamConfigFetching,
        sessionIdentifier: String = BoomstreamOfflineManager.defaultSessionIdentifier,
        allowsCellularAccess: Bool = false,
        storeDirectory: URL? = nil
    ) {
        self.configClient = configClient
        self.store = DownloadRecordStore(directory: storeDirectory)
        self.records = store.load()
        self.delegateAdapter = OfflineSessionDelegate()

        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.allowsCellularAccess = allowsCellularAccess
        configuration.sessionSendsLaunchEvents = true
        // КРИТИЧНО: UA-токен должен быть session-level. AVAssetDownloadTask НЕ пробрасывает
        // AVURLAssetHTTPHeaderFieldsKey в запросы download-даемона (проверено эмпирически:
        // манифест скачивался в web-протокольном виде с [KEY]/[IV] вместо нативного) —
        // httpAdditionalHeaders применяются ко всем запросам сессии.
        configuration.httpAdditionalHeaders = [
            "User-Agent": BoomstreamSDKInfo.userAgent(token: configClient.userAgentToken)
        ]
        self.session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: delegateAdapter,
            delegateQueue: .main
        )
        delegateAdapter.manager = self

        for record in records.values where record.bookmark != nil {
            currentStates[record.mediaCode] = .completed(
                mediaCode: record.mediaCode,
                sizeBytes: record.sizeBytes ?? 0,
                expiresAt: record.expiresAt
            )
        }
    }

    deinit {
        // Разрывает retain-цикл session→delegate; уже запущенные background-таски доедут.
        session.finishTasksAndInvalidate()
    }

    // MARK: - BoomstreamDownloads

    public func start(mediaCode: String, quality: DownloadQuality) async throws -> DownloadHandle {
        if let record = records[mediaCode], record.bookmark != nil {
            emit(.completed(mediaCode: mediaCode, sizeBytes: record.sizeBytes ?? 0, expiresAt: record.expiresAt))
            return DownloadHandle(mediaCode: mediaCode)
        }
        if activeTasks[mediaCode] != nil {
            return DownloadHandle(mediaCode: mediaCode)
        }
        emit(.queued(mediaCode: mediaCode))

        let config: ConfigResponse
        do {
            config = try await configClient.fetchConfig(mediaCode: mediaCode, forceRefresh: false)
        } catch {
            let mapped = (error as? BoomstreamError) ?? .unknown(underlying: error)
            emit(.failed(mediaCode: mediaCode, error: mapped))
            throw mapped
        }

        guard case .authorised(let media) = config.media else {
            throw fail(mediaCode, reason: "media is unauthorised or a playlist — v1.0 downloads single VOD only")
        }
        guard !media.isLive else {
            throw fail(mediaCode, reason: "live broadcasts cannot be downloaded")
        }
        guard let url = media.links?.hlsURL else {
            throw fail(mediaCode, reason: "config has no HLS link")
        }
        // Preflight для шифрованного контента: имитируем запрос даемона (без ua_allow-UA)
        // и падаем с внятной ошибкой, если сервер отдаст web-протокольный манифест.
        if config.encrypt, await wouldDaemonReceiveWebClearKeyManifest(masterURL: url) {
            throw fail(
                mediaCode,
                reason: "encrypted download blocked: the system download daemon would receive the web "
                    + "clear-key manifest (URI=\"[KEY]\") and produce an unplayable asset — server-side "
                    + "native manifest with inline keys is required; streaming playback is unaffected"
            )
        }

        let userAgent = BoomstreamSDKInfo.userAgent(token: configClient.userAgentToken)
        let asset = AVURLAsset(url: url, options: BoomstreamAssetOptions.httpHeaderFields(userAgent: userAgent))
        // DownloadQuality: v1.0 только .auto; bitrate-hint через
        // AVAssetDownloadTaskMinimumRequiredMediaBitrateKey — задел на следующую версию.
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: media.title.isEmpty ? mediaCode : media.title,
            assetArtworkData: nil,
            options: nil
        ) else {
            throw fail(mediaCode, reason: "AVAssetDownloadTask unavailable in this environment")
        }

        task.taskDescription = mediaCode
        records[mediaCode] = DownloadRecord(mediaCode: mediaCode, title: media.title, bookmark: nil, expiresAt: nil, sizeBytes: nil)
        store.save(records)
        activeTasks[mediaCode] = task
        task.resume()
        return DownloadHandle(mediaCode: mediaCode)
    }

    public func pause(mediaCode: String) async {
        guard let task = activeTasks[mediaCode] else { return }
        task.suspend()
        emit(.paused(mediaCode: mediaCode, percent: lastPercent[mediaCode] ?? 0))
    }

    public func resume(mediaCode: String) async {
        guard let task = activeTasks[mediaCode] else { return }
        task.resume()
        emit(.inProgress(mediaCode: mediaCode, percent: lastPercent[mediaCode] ?? 0, bytesDownloaded: task.countOfBytesReceived))
    }

    public func cancel(mediaCode: String) async {
        guard let task = activeTasks.removeValue(forKey: mediaCode) else { return }
        task.cancel()
        // Финализация (удаление записи) — в didCompleteWithError(NSURLErrorCancelled).
    }

    public func observe(mediaCode: String) -> AsyncStream<DownloadState> {
        var captured: AsyncStream<DownloadState>.Continuation!
        let stream = AsyncStream<DownloadState>(bufferingPolicy: .bufferingNewest(8)) { captured = $0 }
        if let current = currentStates[mediaCode] {
            captured.yield(current)
        }
        let forward = Task { [stateBroadcast] in
            for await state in stateBroadcast.stream() where state.mediaCode == mediaCode {
                captured.yield(state)
            }
        }
        captured.onTermination = { _ in forward.cancel() }
        return stream
    }

    public func observeAll() -> AsyncStream<[DownloadState]> {
        var captured: AsyncStream<[DownloadState]>.Continuation!
        let stream = AsyncStream<[DownloadState]>(bufferingPolicy: .bufferingNewest(4)) { captured = $0 }
        captured.yield(Array(currentStates.values))
        let forward = Task { [catalogBroadcast] in
            for await snapshot in catalogBroadcast.stream() {
                captured.yield(snapshot)
            }
        }
        captured.onTermination = { _ in forward.cancel() }
        return stream
    }

    private func notifyCatalog() {
        catalogBroadcast.yield(Array(currentStates.values))
    }

    public func delete(mediaCode: String) async throws {
        if let task = activeTasks.removeValue(forKey: mediaCode) {
            task.cancel()
        }
        if let url = resolvedURL(for: mediaCode) {
            try? FileManager.default.removeItem(at: url)
        }
        records.removeValue(forKey: mediaCode)
        currentStates.removeValue(forKey: mediaCode)
        lastPercent.removeValue(forKey: mediaCode)
        store.save(records)
        notifyCatalog()
    }

    public func stats() async -> StorageStats {
        let completed = records.values.filter { $0.bookmark != nil }
        return StorageStats(
            downloadsCount: completed.count,
            totalSizeBytes: completed.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        )
    }

    public func purgeExpired() async {
        let now = Date()
        let expired = records.values.filter { record in
            guard let expiresAt = record.expiresAt else { return false }
            return expiresAt < now
        }
        for record in expired {
            try? await delete(mediaCode: record.mediaCode)
        }
    }

    /// Переподключение к background-таскам после перезапуска приложения.
    public func restoreTransfers() async {
        let tasks = await session.allTasks
        for task in tasks {
            guard let downloadTask = task as? AVAssetDownloadTask,
                  let mediaCode = downloadTask.taskDescription
            else { continue }
            activeTasks[mediaCode] = downloadTask
            emit(.inProgress(mediaCode: mediaCode, percent: lastPercent[mediaCode] ?? 0, bytesDownloaded: downloadTask.countOfBytesReceived))
        }
    }

    // MARK: - BoomstreamOfflineCache

    public func localAssetURL(mediaCode: String) -> URL? {
        resolvedURL(for: mediaCode)
    }

    // MARK: - Internal

    private func resolvedURL(for mediaCode: String) -> URL? {
        guard let bookmark = records[mediaCode]?.bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale, let fresh = try? url.bookmarkData() {
            records[mediaCode]?.bookmark = fresh
            store.save(records)
        }
        return url
    }

    private func emit(_ state: DownloadState) {
        currentStates[state.mediaCode] = state
        if case .inProgress(_, let percent, _) = state { lastPercent[state.mediaCode] = percent }
        if case .paused(_, let percent) = state { lastPercent[state.mediaCode] = percent }
        stateBroadcast.yield(state)
        notifyCatalog()
    }

    /// Имитирует поведение download-даемона: качает master + первый рендишен plain-сессией
    /// (дефолтный CFNetwork-style UA, без токена) и классифицирует ответ.
    /// Fail-open: при сетевой ошибке preflight возвращает false (не блокируем download —
    /// даемон сам отдаст ошибку, если что).
    private func wouldDaemonReceiveWebClearKeyManifest(masterURL: URL) async -> Bool {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (masterData, _) = try? await session.data(from: masterURL),
              let master = String(data: masterData, encoding: .utf8)
        else { return false }
        if ManifestInspector.isWebClearKeyProtocol(master) { return true }
        guard let variantURL = ManifestInspector.firstVariantURL(in: master, relativeTo: masterURL),
              let (variantData, _) = try? await session.data(from: variantURL),
              let variant = String(data: variantData, encoding: .utf8)
        else { return false }
        return ManifestInspector.isWebClearKeyProtocol(variant)
    }

    private func fail(_ mediaCode: String, reason: String) -> BoomstreamError {
        let error = BoomstreamError.offlineUnavailable(reason: reason)
        emit(.failed(mediaCode: mediaCode, error: error))
        return error
    }

    // MARK: - Delegate callbacks (main queue)

    fileprivate func handleProgress(task: AVAssetDownloadTask, loadedSeconds: Double, expectedSeconds: Double) {
        guard let mediaCode = task.taskDescription else { return }
        let percent = expectedSeconds > 0 ? min(loadedSeconds / expectedSeconds, 1) : 0
        emit(.inProgress(mediaCode: mediaCode, percent: percent, bytesDownloaded: task.countOfBytesReceived))
    }

    fileprivate func handleFinishedDownloading(task: AVAssetDownloadTask, location: URL) {
        guard let mediaCode = task.taskDescription else { return }
        pendingLocations[mediaCode] = location
    }

    fileprivate func handleCompletion(task: URLSessionTask, error: (any Error)?) {
        guard let mediaCode = task.taskDescription else { return }
        activeTasks.removeValue(forKey: mediaCode)
        let location = pendingLocations.removeValue(forKey: mediaCode)

        if let error {
            if let location {
                try? FileManager.default.removeItem(at: location)
            }
            if (error as NSError).code == NSURLErrorCancelled {
                records.removeValue(forKey: mediaCode)
                currentStates.removeValue(forKey: mediaCode)
                store.save(records)
                notifyCatalog()
            } else {
                emit(.failed(mediaCode: mediaCode, error: .network(underlying: error)))
            }
            return
        }

        guard let location, let bookmark = try? location.bookmarkData() else {
            emit(.failed(mediaCode: mediaCode, error: .offlineUnavailable(reason: "downloaded asset location is not persistable")))
            return
        }
        let size = Self.directorySize(location)
        records[mediaCode]?.bookmark = bookmark
        records[mediaCode]?.sizeBytes = size
        store.save(records)
        emit(.completed(mediaCode: mediaCode, sizeBytes: size, expiresAt: records[mediaCode]?.expiresAt))
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Адаптер делегата: отдельный NSObject, чтобы не создавать retain-цикл session→manager.
/// Колбэки приходят на main queue (`delegateQueue: .main`) → `assumeIsolated` корректен.
private final class OfflineSessionDelegate: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    weak var manager: BoomstreamOfflineManager?

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        // NSValue не Sendable — считаем секунды до хопа на MainActor.
        let loadedSeconds = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let expectedSeconds = timeRangeExpectedToLoad.duration.seconds
        MainActor.assumeIsolated {
            manager?.handleProgress(task: assetDownloadTask, loadedSeconds: loadedSeconds, expectedSeconds: expectedSeconds)
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            manager?.handleFinishedDownloading(task: assetDownloadTask, location: location)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        MainActor.assumeIsolated {
            manager?.handleCompletion(task: task, error: error)
        }
    }
}
