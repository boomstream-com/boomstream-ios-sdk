import AVFoundation
import Foundation
import BoomstreamAPI

/// Ядро плеера: config-резолв → AVPlayer → маппинг в `PlayerState`/`PlayerEvent`.
/// Имплементирует `BoomstreamPlayerController`; сырой `AVPlayer` наружу не отдаётся
/// (CSO constraint #1) — view-обёртки цепляют его к `AVPlayerLayer` internal-доступом.
/// Телеметрии нет (CSO constraint #2).
@MainActor
public final class BoomstreamPlayerCore: BoomstreamPlayerController {
    // Internal: только для AVPlayerLayer в view-обёртках этого модуля.
    let player = AVPlayer()

    public private(set) var state: PlayerState = .idle {
        didSet {
            guard state != oldValue else { return }
            stateBroadcast.yield(state)
            onState?(state)
        }
    }

    /// Колбэк для view-обёрток (SwiftUI `onState:`).
    var onState: ((PlayerState) -> Void)?

    public private(set) var isFullScreen = false

    private let stateBroadcast = Broadcast<PlayerState>()
    private let eventBroadcast = Broadcast<PlayerEvent>()
    private let progressBroadcast = Broadcast<PlaybackProgress>()

    private var configClient: (any BoomstreamConfigFetching)?
    private var userAgent = BoomstreamSDKInfo.userAgent(token: nil)
    private var advancedOptions = AdvancedPlayerOptions()

    private var items: [PlayableItem] = []
    private var currentIndex = 0
    private var isPlaylistMode = false
    private var isLiveContent = false
    private var currentTitle: String?
    private var systemMessage: String?

    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var variantDiscoveryTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    // nonisolated(unsafe): мутация только на MainActor; чтение из deinit безопасно
    // (объект уничтожается, конкурентного доступа нет).
    private nonisolated(unsafe) var endObserverToken: (any NSObjectProtocol)?
    private nonisolated(unsafe) var timeObserverToken: Any?

    /// Интервал config-поллинга для офлайн-эфира; настраиваемый ради тестов.
    private let livePollInterval: TimeInterval

    // MARK: - Quality state

    public private(set) var availableQualities: [VideoQuality] = []
    public private(set) var currentQuality: VideoQuality = .auto
    public private(set) var preferredQuality: VideoQuality = .auto

    private let qualityBroadcast = Broadcast<[VideoQuality]>()
    public var qualityUpdates: AsyncStream<[VideoQuality]> { qualityBroadcast.stream() }

    /// Explicit quality override set by host via setQuality/selectAuto.
    /// nil = no override; AdvancedPlayerOptions.preferredPeakBitRate initial hint is preserved.
    private var qualityOverride: VideoQuality? = nil

    public init(livePollInterval: TimeInterval = 15) {
        self.livePollInterval = livePollInterval
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.handleTimeControlChange() }
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickProgress() }
        }
    }

    deinit {
        // player — immutable let; removeTimeObserver обязателен, иначе утечка.
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        loadTask?.cancel()
        pollTask?.cancel()
        variantDiscoveryTask?.cancel()
    }

    // MARK: - Loading

    public func load(
        mediaCode: String,
        configClient: any BoomstreamConfigFetching,
        allowClearKeyDRMToken: String? = nil,
        advancedOptions: AdvancedPlayerOptions = AdvancedPlayerOptions(),
        offlineCache: (any BoomstreamOfflineCache)? = nil
    ) {
        stopPlayback()
        self.configClient = configClient
        self.advancedOptions = advancedOptions
        // Per-call токен приоритетнее токена из BoomstreamOptions.
        let token = allowClearKeyDRMToken ?? configClient.userAgentToken
        userAgent = BoomstreamSDKInfo.userAgent(token: token)

        // Локальная копия имеет приоритет над сетью — офлайн-плейбек без config-запроса.
        if let localURL = offlineCache?.localAssetURL(mediaCode: mediaCode) {
            state = .loading
            items = [PlayableItem(title: nil, url: localURL)]
            isPlaylistMode = false
            isLiveContent = false
            systemMessage = nil
            playItem(at: 0)
            return
        }

        state = .loading
        loadTask = Task { [weak self] in
            await self?.resolveAndStart(mediaCode: mediaCode, forceRefresh: false, allowPolling: true)
        }
    }

    /// Полный teardown: остановить всё, вернуть `.idle`.
    public func release() {
        stopPlayback()
        configClient = nil
        state = .idle
    }

    private func stopPlayback() {
        loadTask?.cancel()
        loadTask = nil
        pollTask?.cancel()
        pollTask = nil
        variantDiscoveryTask?.cancel()
        variantDiscoveryTask = nil
        detachCurrentItemObservers()
        player.replaceCurrentItem(with: nil)
        items = []
        currentIndex = 0
        isPlaylistMode = false
        isLiveContent = false
        currentTitle = nil
        systemMessage = nil
        availableQualities = []
        currentQuality = .auto
        // preferredQuality and qualityOverride intentionally preserved across load() calls
    }

    private func resolveAndStart(mediaCode: String, forceRefresh: Bool, allowPolling: Bool) async {
        guard let configClient else { return }
        do {
            let config = try await configClient.fetchConfig(mediaCode: mediaCode, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            apply(plan: PlaybackPlan.make(from: config), mediaCode: mediaCode, allowPolling: allowPolling)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(message: (error as? BoomstreamError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func apply(plan: PlaybackPlan, mediaCode: String, allowPolling: Bool) {
        switch plan {
        case .posterOnly(let posterURL, let message, let shouldPoll):
            state = .posterOnly(posterURL: posterURL, message: message, isLiveOffline: shouldPoll)
            if shouldPoll, allowPolling {
                startLivePolling(mediaCode: mediaCode)
            }
        case .play(let playables, let isPlaylist, let isLive, let message):
            pollTask?.cancel()
            pollTask = nil
            state = .loading
            items = playables
            isPlaylistMode = isPlaylist
            isLiveContent = isLive
            systemMessage = message
            playItem(at: 0)
        }
    }

    /// Офлайн-эфир: перепрашиваем config c `forceRefresh`, пока эфир не опубликуют.
    private func startLivePolling(mediaCode: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self, livePollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(livePollInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.resolveAndStart(mediaCode: mediaCode, forceRefresh: true, allowPolling: false)
                guard case .posterOnly = self.state else { return }
            }
        }
    }

    // MARK: - Item playback

    private func playItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        detachCurrentItemObservers()
        currentIndex = index
        let playable = items[index]
        currentTitle = playable.title

        let asset = AssetFactory.makeAsset(url: playable.url, userAgent: userAgent)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = advancedOptions.preferredForwardBufferDuration
        player.automaticallyWaitsToMinimizeStalling = advancedOptions.automaticallyWaitsToMinimizeStalling
        // Apply initial hint from AdvancedPlayerOptions; setQuality/selectAuto override this at runtime.
        item.preferredPeakBitRate = advancedOptions.preferredPeakBitRate
        // Re-apply explicit override when host called setQuality/selectAuto; nil = keep hint above.
        if let override = qualityOverride {
            applyQualityToItem(item, quality: override)
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let errorText = observedItem.error?.localizedDescription
            Task { @MainActor [weak self] in self?.handleStatusChange(status, errorText: errorText) }
        }
        endObserverToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handlePlayedToEnd() }
        }

        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func detachCurrentItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
    }

    // MARK: - AVPlayer callbacks

    private func handleStatusChange(_ status: AVPlayerItem.Status, errorText: String?) {
        switch status {
        case .readyToPlay:
            state = .ready(
                title: currentTitle,
                isPlaylist: isPlaylistMode,
                playlistIndex: currentIndex,
                playlistSize: items.count,
                isLive: isLiveContent,
                systemMessage: systemMessage
            )
            eventBroadcast.yield(.loaded)
            discoverVariants()
        case .failed:
            state = .error(message: errorText ?? "Playback failed")
        default:
            break
        }
    }

    // MARK: - Variant discovery

    private func discoverVariants() {
        availableQualities = []   // clear stale values from previous playlist item
        guard let asset = player.currentItem?.asset as? AVURLAsset else { return }
        variantDiscoveryTask?.cancel()
        variantDiscoveryTask = Task { [weak self] in
            await self?.loadVariants(from: asset)
        }
    }

    private func loadVariants(from asset: AVURLAsset) async {
        // Preferred path: AVAssetVariant (iOS 15+ / macOS 12+) — no manifest download needed.
        if let variants = try? await asset.load(.variants), !variants.isEmpty {
            let qualities = variantsToQualities(variants)
            if !qualities.isEmpty {
                availableQualities = qualities
                qualityBroadcast.yield(qualities)
                return
            }
        }
        // Fallback: parse EXT-X-STREAM-INF from master manifest.
        guard let (data, _) = try? await URLSession.shared.data(from: asset.url),
              let text = String(data: data, encoding: .utf8)
        else { return }
        let qualities = HLSVariantParser.parse(master: text)
        guard !qualities.isEmpty, !Task.isCancelled else { return }
        availableQualities = qualities
        qualityBroadcast.yield(qualities)
    }

    private func variantsToQualities(_ variants: [AVAssetVariant]) -> [VideoQuality] {
        // Group by height, keep highest peakBitRate per height — all AVFoundation types stay internal.
        var byHeight: [Int: Double] = [:]
        for v in variants {
            guard let size = v.videoAttributes?.presentationSize else { continue }
            let h = Int(size.height)
            guard h > 0 else { continue }
            let bps = v.peakBitRate ?? 0
            if (byHeight[h] ?? 0) < bps { byHeight[h] = bps }
        }
        return byHeight.sorted { $0.key > $1.key }
            .map { .resolution(height: $0.key, peakBitRate: Int($0.value)) }
    }

    // MARK: - Quality application

    private func applyQualityToItem(_ item: AVPlayerItem, quality: VideoQuality) {
        switch quality {
        case .auto:
            item.preferredMaximumResolution = .zero   // removes resolution cap
            item.preferredPeakBitRate = 0             // removes bitrate cap
        case .resolution(let height, let peakBitRate, _):
            // Use a generous width (10000) so only height is the effective constraint.
            item.preferredMaximumResolution = CGSize(width: 10_000, height: CGFloat(height))
            item.preferredPeakBitRate = Double(peakBitRate ?? 0)
        }
    }

    // MARK: - BoomstreamPlayerController quality API

    public func setQuality(_ quality: VideoQuality) {
        preferredQuality = quality
        qualityOverride = quality
        currentQuality = quality
        if let item = player.currentItem {
            applyQualityToItem(item, quality: quality)
        }
    }

    public func selectAuto() {
        preferredQuality = .auto
        qualityOverride = .auto
        currentQuality = .auto
        if let item = player.currentItem {
            applyQualityToItem(item, quality: .auto)
        }
    }

    private func handleTimeControlChange() {
        guard case .ready = state else { return }
        switch player.timeControlStatus {
        case .playing:
            eventBroadcast.yield(.playing)
        case .paused:
            eventBroadcast.yield(.paused)
        default:
            break
        }
    }

    private func handlePlayedToEnd() {
        if isPlaylistMode, currentIndex + 1 < items.count {
            playItem(at: currentIndex + 1)
        } else {
            state = .ended
            eventBroadcast.yield(.ended)
        }
    }

    private func tickProgress() {
        guard case .ready = state else { return }
        let snapshot = progressSnapshot()
        progressBroadcast.yield(snapshot)
        eventBroadcast.yield(.progress(snapshot))
    }

    private func progressSnapshot() -> PlaybackProgress {
        let position = normalized(player.currentTime().seconds)
        let duration = normalized(player.currentItem?.duration.seconds ?? 0)
        let buffered = player.currentItem?.loadedTimeRanges
            .compactMap { ($0 as? CMTimeRange).map { range in normalized(range.end.seconds) } }
            .max() ?? 0
        return PlaybackProgress(position: position, duration: duration, bufferedPosition: buffered)
    }

    private func normalized(_ seconds: Double) -> TimeInterval {
        seconds.isFinite && seconds >= 0 ? seconds : 0
    }

    // MARK: - BoomstreamPlayerController

    public func play() { player.play() }
    public func pause() { player.pause() }

    public func seek(to seconds: TimeInterval) {
        player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        eventBroadcast.yield(.seeked(seconds))
    }

    public func seek(toPercent percent: Double) {
        let total = duration
        guard total > 0 else { return }
        seek(to: total * min(max(percent, 0), 1))
    }

    public func setVolume(_ volume: Float) { player.volume = min(max(volume, 0), 1) }
    public func mute() { player.isMuted = true }
    public func unmute() { player.isMuted = false }

    public func next() {
        guard isPlaylistMode, currentIndex + 1 < items.count else { return }
        playItem(at: currentIndex + 1)
    }

    public func previous() {
        guard isPlaylistMode, currentIndex > 0 else { return }
        playItem(at: currentIndex - 1)
    }

    public func setFullScreen(_ on: Bool) {
        guard isFullScreen != on else { return }
        isFullScreen = on
        eventBroadcast.yield(.fullScreenChanged(on))
    }

    public func toggleFullScreen() { setFullScreen(!isFullScreen) }

    public var currentPosition: TimeInterval { normalized(player.currentTime().seconds) }
    public var duration: TimeInterval { normalized(player.currentItem?.duration.seconds ?? 0) }

    public var states: AsyncStream<PlayerState> { stateBroadcast.stream() }
    public var events: AsyncStream<PlayerEvent> { eventBroadcast.stream() }
    public var progress: AsyncStream<PlaybackProgress> { progressBroadcast.stream() }
}
