import AVFoundation
#if os(iOS)
// AVPlayerItem.externalMetadata — AVKit-расширение; без импорта iOS-сборка не видит член.
import AVKit
#endif
import Foundation
import MediaPlayer
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
    private var audioDiscoveryTask: Task<Void, Never>?
    private var subtitleDiscoveryTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    /// Injectable URLSession for artwork download — overridable in tests via @testable import.
    var artworkSession: URLSession = .shared
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

    // MARK: - Speed state

    public private(set) var currentSpeed: PlayerSpeed = .normal
    public var availableSpeeds: [PlayerSpeed] { PlayerSpeed.allCases }

    // MARK: - Audio track state

    public private(set) var availableAudioTracks: [AudioTrack] = []
    public private(set) var currentAudioTrack: AudioTrack? = nil

    private let audioTrackBroadcast = Broadcast<[AudioTrack]>()
    public var audioTrackUpdates: AsyncStream<[AudioTrack]> { audioTrackBroadcast.stream() }

    // Internal AVFoundation references — never exposed publicly (CSO constraint #1).
    private var audioGroup: AVMediaSelectionGroup? = nil
    private var audioOptionMap: [String: AVMediaSelectionOption] = [:]

    // MARK: - Subtitle track state

    public private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    public private(set) var currentSubtitleTrack: SubtitleTrack? = nil

    private let subtitleTrackBroadcast = Broadcast<[SubtitleTrack]>()
    public var subtitleTrackUpdates: AsyncStream<[SubtitleTrack]> { subtitleTrackBroadcast.stream() }

    private var subtitleGroup: AVMediaSelectionGroup? = nil
    private var subtitleOptionMap: [String: AVMediaSelectionOption] = [:]

    // MARK: - AirPlay state

    public private(set) var isAirPlaying: Bool = false
    /// Human-readable name of the active AirPlay receiver; nil when not streaming.
    /// Sourced from AVAudioSession.routeChangeNotification — AVFoundation types stay internal.
    public private(set) var airPlayDeviceName: String? = nil

    private let airPlayBroadcast = Broadcast<Bool>()
    public var airPlayUpdates: AsyncStream<Bool> { airPlayBroadcast.stream() }

    // MARK: - Cast fallback

    /// Entity-код текущего `load()` — нужен эндпоинту cast-ссылки.
    private var currentMediaCode: String?
    /// Cast-ссылка текущего медиа; кэш на время одного `load()`.
    private var castFallbackURL: URL?
    /// `true` — плеер играет cast-ссылку вместо основной (AirPlay на приёмник,
    /// не осиливший платформенное шифрование). Internal для тестов.
    private(set) var isCastFallbackActive = false
    /// Имена AirPlay-маршрутов, которым потребовался fallback: повторный каст на
    /// тот же приёмник переключается сразу, без цикла ошибки. Живёт с контроллером.
    private var castRequiredRoutes: Set<String> = []
    private var castFallbackTask: Task<Void, Never>?
    /// Вотчдог handoff'а: веб-приёмник (LG/Samsung) не выдаёт ошибку item —
    /// плеер навсегда виснет в `.waitingToPlayAtSpecifiedRate` с причиной
    /// `.noItemToPlay` (подтверждено телеметрией: Mac играет сразу, LG стоит).
    private var castWatchdogTask: Task<Void, Never>?
    /// Позиция, восстанавливаемая после пересоздания item (fallback и возврат с него).
    private var pendingSeek: CMTime?

    private var externalPlaybackObservation: NSKeyValueObservation?
    // nonisolated(unsafe): мутация только на MainActor; чтение из deinit безопасно.
    private nonisolated(unsafe) var routeChangeObserverToken: (any NSObjectProtocol)?

    public init(livePollInterval: TimeInterval = 15) {
        self.livePollInterval = livePollInterval
        player.allowsExternalPlayback = true
        #if os(iOS) || os(tvOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        // Без категории .playback система оставляет дефолтный .soloAmbient: AirPlay-роут
        // работает как чистый аудио-выход и видео-handoff (isExternalPlaybackActive)
        // никогда не включается. Аналог управления audio focus в Android-SDK.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.handleTimeControlChange() }
        }
        externalPlaybackObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] p, _ in
            let active = p.isExternalPlaybackActive
            Task { @MainActor [weak self] in self?.handleExternalPlaybackChange(active) }
        }
        #if os(iOS)
        routeChangeObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleRouteChange() }
        }
        #endif
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
        if let token = routeChangeObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        externalPlaybackObservation?.invalidate()
        loadTask?.cancel()
        pollTask?.cancel()
        variantDiscoveryTask?.cancel()
        audioDiscoveryTask?.cancel()
        subtitleDiscoveryTask?.cancel()
        artworkTask?.cancel()
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
        currentMediaCode = mediaCode
        // Per-call токен приоритетнее токена из BoomstreamOptions.
        let token = allowClearKeyDRMToken ?? configClient.userAgentToken
        userAgent = BoomstreamSDKInfo.userAgent(token: token)

        // Локальная копия имеет приоритет над сетью — офлайн-плейбек без config-запроса.
        if let localURL = offlineCache?.localAssetURL(mediaCode: mediaCode) {
            state = .loading
            items = [PlayableItem(title: nil, url: localURL, posterURL: nil)]
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
        externalPlaybackObservation?.invalidate()
        externalPlaybackObservation = nil
        if let token = routeChangeObserverToken {
            NotificationCenter.default.removeObserver(token)
            routeChangeObserverToken = nil
        }
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
        audioDiscoveryTask?.cancel()
        audioDiscoveryTask = nil
        subtitleDiscoveryTask?.cancel()
        subtitleDiscoveryTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        castFallbackTask?.cancel()
        castFallbackTask = nil
        castWatchdogTask?.cancel()
        castWatchdogTask = nil
        castFallbackURL = nil
        isCastFallbackActive = false
        pendingSeek = nil
        currentMediaCode = nil
        // castRequiredRoutes намеренно переживает load() — память о приёмниках
        // действует всё время жизни контроллера.
        detachCurrentItemObservers()
        player.replaceCurrentItem(with: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        items = []
        currentIndex = 0
        isPlaylistMode = false
        isLiveContent = false
        currentTitle = nil
        systemMessage = nil
        availableQualities = []
        currentQuality = .auto
        availableAudioTracks = []
        currentAudioTrack = nil
        audioGroup = nil
        audioOptionMap = [:]
        availableSubtitleTracks = []
        currentSubtitleTrack = nil
        subtitleGroup = nil
        subtitleOptionMap = [:]
        if isAirPlaying { airPlayBroadcast.yield(false) }
        isAirPlaying = false
        airPlayDeviceName = nil
        // preferredQuality, qualityOverride, and currentSpeed intentionally preserved across load() calls
        // externalPlaybackObservation and routeChangeObserverToken are player-level; torn down in release().
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
        artworkTask?.cancel()
        artworkTask = nil
        currentIndex = index
        let playable = items[index]
        currentTitle = playable.title

        // Во время активного cast-fallback приёмник получает cast-ссылку
        // вместо основной; после завершения каста возвращаемся на playable.url.
        let url = (isCastFallbackActive ? castFallbackURL : nil) ?? playable.url
        let asset = AssetFactory.makeAsset(url: url, userAgent: userAgent)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = advancedOptions.preferredForwardBufferDuration
        player.automaticallyWaitsToMinimizeStalling = advancedOptions.automaticallyWaitsToMinimizeStalling
        // Apply initial hint from AdvancedPlayerOptions; setQuality/selectAuto override this at runtime.
        item.preferredPeakBitRate = advancedOptions.preferredPeakBitRate
        // Re-apply explicit override when host called setQuality/selectAuto; nil = keep hint above.
        if let override = qualityOverride {
            applyQualityToItem(item, quality: override)
        }

        #if os(iOS)
        item.externalMetadata = makeExternalMetadata(title: playable.title)
        #endif
        updateNowPlayingInfo(title: playable.title)
        startArtworkTask(posterURL: playable.posterURL, for: item)

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

    // MARK: - Metadata helpers

    #if os(iOS)
    private func makeExternalMetadata(title: String?) -> [AVMetadataItem] {
        guard let title else { return [] }
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        titleItem.extendedLanguageTag = "und"
        return [titleItem]
    }

    private func makeArtworkMetadataItem(from data: Data) -> AVMutableMetadataItem {
        let artItem = AVMutableMetadataItem()
        artItem.identifier = .commonIdentifierArtwork
        artItem.value = data as NSData
        if let dataType = BoomstreamPlayerCore.artworkDataType(from: data) {
            artItem.dataType = dataType
        }
        artItem.extendedLanguageTag = "und"
        return artItem
    }
    #endif

    /// Fetches artwork data, returning nil when the HTTP status ≠ 200 or on any network error.
    nonisolated static func fetchArtworkData(from url: URL, session: URLSession) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Sniffs magic bytes to determine the CoreMedia dataType for artwork metadata.
    /// Returns kCMMetadataBaseDataType_JPEG for JPEG; nil for all other formats
    /// (PNG, WebP, unknown) — AVFoundation probes untyped data itself.
    nonisolated static func artworkDataType(from data: Data) -> String? {
        guard data.count >= 3,
              data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF
        else { return nil }
        return kCMMetadataBaseDataType_JPEG as String
    }

    private func updateNowPlayingInfo(title: String?) {
        var info: [String: Any] = [:]
        if let title { info[MPMediaItemPropertyTitle] = title }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Downloads poster asynchronously and attaches it to `externalMetadata` and `nowPlayingInfo`.
    /// Cancelled on each `playItem(at:)` call and on `stopPlayback()`.
    private func startArtworkTask(posterURL: URL?, for item: AVPlayerItem) {
        guard let posterURL else { return }
        let session = artworkSession
        artworkTask = Task { [weak self, weak item] in
            guard let data = await BoomstreamPlayerCore.fetchArtworkData(from: posterURL, session: session),
                  !Task.isCancelled,
                  let self,
                  let item
            else { return }

            #if os(iOS)
            let artworkMeta = self.makeArtworkMetadataItem(from: data)
            var meta = item.externalMetadata.filter { $0.identifier != .commonIdentifierArtwork }
            meta.append(artworkMeta)
            item.externalMetadata = meta
            #endif

            #if canImport(UIKit)
            if let image = UIImage(data: data) {
                // @Sendable снимает наследование @MainActor-изоляции: MediaPlayer зовёт
                // этот handler на своей очереди при пуше Now Playing — иначе SIGTRAP на девайсе.
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
                var nowPlaying = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                nowPlaying[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
            }
            #endif
        }
    }

    // MARK: - AVPlayer callbacks

    private func handleStatusChange(_ status: AVPlayerItem.Status, errorText: String?) {
        switch status {
        case .readyToPlay:
            if let seek = pendingSeek {
                pendingSeek = nil
                player.seek(to: seek, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            }
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
            discoverAudioTracks()
            discoverSubtitleTracks()
        case .failed:
            #if DEBUG
            print("[BSP] item FAILED airPlaying=\(isAirPlaying) err=\(errorText ?? "-") shouldFallback=\(shouldAttemptCastFallback)")
            #endif
            // Ошибка item во время AirPlay — сигнатура приёмника, не осилившего
            // платформенное шифрование (веб-приёмники LG/Samsung останавливаются
            // на манифесте): пробуем cast-ссылку, прежде чем сдаваться.
            if shouldAttemptCastFallback {
                startCastFallback(originalError: errorText)
            } else {
                state = .error(message: errorText ?? "Playback failed")
            }
        default:
            break
        }
    }

    // MARK: - Cast fallback (logic)

    private var shouldAttemptCastFallback: Bool {
        isAirPlaying && !isCastFallbackActive && !isPlaylistMode && !isLiveContent
            && currentMediaCode != nil && configClient is BoomstreamCastLinkFetching
    }

    /// Детектор зависшего handoff'а: веб-приёмники (LG/Samsung) не играют
    /// платформенное шифрование, но и ошибки item не порождают — AVPlayer
    /// застревает в `.waitingToPlayAtSpecifiedRate` / `.noItemToPlay`
    /// (на успешном приёмнике статус — `.playing`, время идёт). Три секунды
    /// подряд в этом состоянии → переключаемся на cast-ссылку.
    private func startCastWatchdog() {
        castWatchdogTask?.cancel()
        guard shouldAttemptCastFallback else { return }
        castWatchdogTask = Task { [weak self] in
            var strikes = 0
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self,
                      self.isAirPlaying, !self.isCastFallbackActive
                else { return }
                let stuck = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                    && self.player.reasonForWaitingToPlay == .noItemToPlay
                strikes = stuck ? strikes + 1 : 0
                if strikes >= 3 {
                    #if DEBUG
                    print("[BSP] watchdog: receiver stuck (noItemToPlay ×3) → cast fallback")
                    #endif
                    self.startCastFallback(originalError: nil)
                    return
                }
            }
        }
    }

    private func startCastFallback(originalError: String?) {
        castWatchdogTask?.cancel()
        castWatchdogTask = nil
        guard let mediaCode = currentMediaCode,
              let fetcher = configClient as? BoomstreamCastLinkFetching
        else {
            state = .error(message: originalError ?? "Playback failed")
            return
        }
        state = .loading
        let resumeAt = player.currentTime()
        castFallbackTask?.cancel()
        castFallbackTask = Task { [weak self] in
            do {
                let url = try await fetcher.fetchCastLink(mediaCode: mediaCode)
                guard !Task.isCancelled, let self else { return }
                self.activateCastFallback(url: url, resumeAt: resumeAt)
            } catch {
                guard !Task.isCancelled, let self else { return }
                if let castError = error as? BoomstreamCastLinkError,
                   castError.reason == .castNotAllowed {
                    // Владелец проекта не разрешил каст защищённого — говорим прямо.
                    self.state = .error(message: BoomstreamMessages.resolve(
                        "bsp_cast_not_allowed", locale: self.advancedOptions.locale))
                } else {
                    // Fallback не состоялся — исходная ошибка воспроизведения честнее.
                    self.state = .error(message: originalError ?? "Playback failed")
                }
            }
        }
    }

    private func activateCastFallback(url: URL, resumeAt: CMTime) {
        castFallbackURL = url
        isCastFallbackActive = true
        if let route = airPlayDeviceName { castRequiredRoutes.insert(route) }
        if resumeAt.isValid, !resumeAt.isIndefinite, resumeAt.seconds > 0 { pendingSeek = resumeAt }
        playItem(at: currentIndex)
    }

    // MARK: - AirPlay callbacks

    // Internal (not private) so simulator tests can inject state via @testable import.
    func handleExternalPlaybackChange(_ active: Bool) {
        #if DEBUG
        print("[BSP] externalPlayback=\(active) route=\(airPlayDeviceName ?? "-") fallback=\(isCastFallbackActive)")
        #endif
        isAirPlaying = active
        airPlayBroadcast.yield(active)
        if active {
            startCastWatchdog()
        } else {
            castWatchdogTask?.cancel()
            castWatchdogTask = nil
            airPlayDeviceName = nil
            if isCastFallbackActive {
                // Каст закончился — возвращаемся на основную ссылку: локальное
                // воспроизведение снова с платформенным шифрованием (защита кадра).
                castFallbackTask?.cancel()
                castFallbackTask = nil
                isCastFallbackActive = false
                let resumeAt = player.currentTime()
                if resumeAt.isValid, !resumeAt.isIndefinite, resumeAt.seconds > 0 {
                    pendingSeek = resumeAt
                }
                playItem(at: currentIndex)
            }
        }
    }

    private func handleRouteChange() {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        airPlayDeviceName = outputs.first(where: { $0.portType == .airPlay })?.portName
        #if DEBUG
        print("[BSP] routeChange outputs=\(outputs.map { "\($0.portType.rawValue):\($0.portName)" }) airPlaying=\(isAirPlaying) extActive=\(player.isExternalPlaybackActive)")
        #endif
        // Повторный каст на приёмник, уже потребовавший fallback в этой сессии, —
        // переключаемся сразу, не дожидаясь цикла ошибки item.
        if let route = airPlayDeviceName, castRequiredRoutes.contains(route),
           shouldAttemptCastFallback {
            startCastFallback(originalError: nil)
        }
        #endif
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

    // MARK: - Audio track discovery

    private func discoverAudioTracks() {
        availableAudioTracks = []
        currentAudioTrack = nil
        audioGroup = nil
        audioOptionMap = [:]
        guard let item = player.currentItem else { return }
        audioDiscoveryTask?.cancel()
        audioDiscoveryTask = Task { [weak self] in
            await self?.loadAudioTracks(from: item)
        }
    }

    private func loadAudioTracks(from item: AVPlayerItem) async {
        // At readyToPlay, HLS assets have their media selection groups in memory —
        // the synchronous accessor does not trigger a network fetch at this point.
        guard !Task.isCancelled,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              group.options.count > 1
        else { return }

        var map: [String: AVMediaSelectionOption] = [:]
        var tracks: [AudioTrack] = []
        for (i, option) in group.options.enumerated() {
            let id = String(i)
            map[id] = option
            tracks.append(AudioTrack(id: id, displayName: option.displayName(with: Locale.current)))
        }
        guard !Task.isCancelled else { return }
        audioGroup = group
        audioOptionMap = map
        availableAudioTracks = tracks
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        if let selected,
           let entry = map.first(where: { $0.value == selected }) {
            currentAudioTrack = tracks.first(where: { $0.id == entry.key })
        }
        if currentAudioTrack == nil { currentAudioTrack = tracks.first }
        audioTrackBroadcast.yield(tracks)
    }

    // MARK: - Subtitle track discovery

    private func discoverSubtitleTracks() {
        availableSubtitleTracks = []
        currentSubtitleTrack = nil
        subtitleGroup = nil
        subtitleOptionMap = [:]
        guard let item = player.currentItem else { return }
        subtitleDiscoveryTask?.cancel()
        subtitleDiscoveryTask = Task { [weak self] in
            await self?.loadSubtitleTracks(from: item)
        }
    }

    private func loadSubtitleTracks(from item: AVPlayerItem) async {
        guard !Task.isCancelled,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else { return }

        var map: [String: AVMediaSelectionOption] = [:]
        var tracks: [SubtitleTrack] = []
        for (i, option) in group.options.enumerated() {
            guard BoomstreamPlayerCore.subtitleOptionPasses(
                mediaType: option.mediaType,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
                isAccessibility: option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility)
            ) else { continue }
            let id = String(i)
            map[id] = option
            tracks.append(SubtitleTrack(id: id, displayName: option.displayName(with: Locale.current)))
        }

        guard !Task.isCancelled, !tracks.isEmpty else { return }
        subtitleGroup = group
        subtitleOptionMap = map
        availableSubtitleTracks = tracks

        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        if let selected, let entry = map.first(where: { $0.value == selected }) {
            currentSubtitleTrack = tracks.first(where: { $0.id == entry.key })
        }
        subtitleTrackBroadcast.yield(tracks)
    }

    /// Filter predicate for real user-selectable subtitle options.
    /// Extracted as `nonisolated static` for unit testability — takes primitives, not AVFoundation objects.
    nonisolated static func subtitleOptionPasses(
        mediaType: AVMediaType,
        isForced: Bool,
        isAccessibility: Bool
    ) -> Bool {
        mediaType != .closedCaption
            && !isForced
            && !isAccessibility
    }

    // MARK: - BoomstreamPlayerController subtitle API

    public func selectSubtitleTrack(_ track: SubtitleTrack) {
        guard let group = subtitleGroup,
              let option = subtitleOptionMap[track.id],
              let item = player.currentItem
        else { return }
        item.select(option, in: group)
        currentSubtitleTrack = track
    }

    public func selectNoSubtitles() {
        guard let group = subtitleGroup,
              let item = player.currentItem
        else { return }
        item.select(nil, in: group)
        currentSubtitleTrack = nil
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

    // MARK: - BoomstreamPlayerController speed API

    public func setSpeed(_ speed: PlayerSpeed) {
        currentSpeed = speed
        // Apply immediately if currently playing; play() re-applies on next resume.
        if player.timeControlStatus == .playing {
            player.rate = speed.rawValue
        }
    }

    // MARK: - BoomstreamPlayerController audio API

    public func selectAudioTrack(_ track: AudioTrack) {
        guard let group = audioGroup,
              let option = audioOptionMap[track.id],
              let item = player.currentItem
        else { return }
        item.select(option, in: group)
        currentAudioTrack = track
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

    public func play() {
        player.play()
        // AVPlayer.play() resets rate to 1.0; re-apply non-normal speed immediately.
        if currentSpeed != .normal { player.rate = currentSpeed.rawValue }
    }

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
