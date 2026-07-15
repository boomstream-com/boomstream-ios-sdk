import BoomstreamAPI
import BoomstreamOffline
import BoomstreamPlayer
import SwiftUI

/// Unified-модель итема для всех трёх листингов.
struct ContentItem: Identifiable, Equatable {
    let code: String
    let title: String
    let poster: String?
    let duration: Int // секунды; 0 = неизвестно

    var id: String { code }
    var posterURL: URL? { poster.flatMap(URL.init(string:)) }
}

/// Общая view-model обеих вкладок: выбранный на «Медиа» mediaCode
/// управляет и вкладкой «Player API».
@MainActor
final class MainViewModel: ObservableObject {
    @Published private(set) var mediaList: [ContentItem] = []
    @Published private(set) var liveList: [ContentItem] = []
    @Published private(set) var playlistList: [ContentItem] = []
    @Published private(set) var listLoading = false
    @Published private(set) var listError: String?
    @Published private(set) var selectedMediaCode: String?
    @Published private(set) var downloadStates: [String: DownloadState] = [:]
    /// Fullscreen активного плеера — по нему прячется chrome (переключатель табов и т.д.).
    @Published private(set) var isFullScreen = false

    /// Кто включил fullscreen: поворот (auto) или кнопка (manual).
    /// Возврат в portrait выходит из fullscreen ТОЛЬКО при auto-входе.
    private enum FullScreenSource { case none, manual, auto }
    private var fullScreenSource: FullScreenSource = .none

    /// Контроллер плеера активной вкладки (неактивная уничтожается — живёт один).
    weak var activeController: (any BoomstreamPlayerController)?

    let apiKeyMissing = !AppEnvironment.hasAPIKey

    private var allItems: [ContentItem] { mediaList + liveList + playlistList }

    var mediaTitle: String? {
        guard let code = selectedMediaCode else { return nil }
        return allItems.first { $0.code == code }?.title
    }

    var mediaDescription: String? {
        guard let code = selectedMediaCode,
              let item = allItems.first(where: { $0.code == code }),
              item.duration > 0
        else { return nil }
        return "Длительность: \(timeString(seconds: Double(item.duration)))"
    }

    var selectedDownloadState: DownloadState? {
        selectedMediaCode.flatMap { downloadStates[$0] }
    }

    init() {
        // Fallback без ключа: листинги недоступны, но demo-код из xcconfig играет.
        if apiKeyMissing {
            if !AppEnvironment.demoMediaCode.isEmpty {
                selectedMediaCode = AppEnvironment.demoMediaCode
            }
        } else {
            Task { await loadAllMedia() }
        }
        Task { [weak self] in
            for await states in AppEnvironment.offline.observeAll() {
                guard let self else { return }
                self.downloadStates = Dictionary(uniqueKeysWithValues: states.map { ($0.mediaCode, $0) })
            }
        }
    }

    func selectMedia(_ code: String) {
        selectedMediaCode = code
        isFullScreen = false
        fullScreenSource = .none
    }

    /// Единая точка правды о fullscreen — событие плеера (кнопка оверлея,
    /// FullScr на вкладке Player API или наш же setFullScreen из handleOrientation).
    func handleFullScreenChanged(_ fullScreen: Bool) {
        isFullScreen = fullScreen
        if !fullScreen {
            fullScreenSource = .none
        } else if fullScreenSource != .auto {
            fullScreenSource = .manual
        }
    }

    /// Landscape → авто-fullscreen; portrait → выход, только если вход был авто.
    func handleOrientation(isLandscape: Bool) {
        if isLandscape {
            guard !isFullScreen else { return }
            fullScreenSource = .auto
            activeController?.setFullScreen(true)
        } else if isFullScreen, fullScreenSource == .auto {
            activeController?.setFullScreen(false)
        }
    }

    /// Параллельная загрузка трёх списков; видео управляют loading/error UI,
    /// live и плейлисты грузятся тихо.
    func loadAllMedia() async {
        listLoading = true
        listError = nil
        defer { listLoading = false }

        async let videosTask = Boomstream.api.listFolder()
        async let liveTask = Boomstream.api.listLive()
        async let playlistsTask = Boomstream.api.listPlaylists()

        do {
            mediaList = try await videosTask
                .map { ContentItem(code: $0.code, title: $0.title, poster: $0.poster, duration: $0.duration) }
                .filter { $0.poster != nil }
            if selectedMediaCode == nil {
                selectedMediaCode = mediaList.first?.code
            }
        } catch {
            listError = "Не удалось загрузить список медиа"
        }
        liveList = ((try? await liveTask) ?? [])
            .map { ContentItem(code: $0.code, title: $0.title, poster: $0.poster, duration: 0) }
        playlistList = ((try? await playlistsTask) ?? [])
            .map { ContentItem(code: $0.code, title: $0.name, poster: $0.poster, duration: $0.durationSeconds) }
    }

    func startDownload() {
        guard let code = selectedMediaCode else { return }
        Task { _ = try? await AppEnvironment.offline.start(mediaCode: code, quality: .auto) }
    }

    func cancelDownload() {
        guard let code = selectedMediaCode else { return }
        Task { await AppEnvironment.offline.cancel(mediaCode: code) }
    }

    func deleteDownload() {
        guard let code = selectedMediaCode else { return }
        Task { try? await AppEnvironment.offline.delete(mediaCode: code) }
    }
}

/// Форматирование `m:ss`.
func timeString(seconds: Double) -> String {
    let total = seconds.isFinite && seconds > 0 ? Int(seconds.rounded()) : 0
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// Пропорция экрана в текущей ориентации — для fullscreen-контейнера плеера.
@MainActor
func screenAspectRatio() -> CGFloat {
    let bounds = UIScreen.main.bounds
    guard bounds.height > 0 else { return 16 / 9 }
    return bounds.width / bounds.height
}
