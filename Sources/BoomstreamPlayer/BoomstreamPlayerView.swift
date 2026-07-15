#if canImport(UIKit)
import BoomstreamAPI
import SwiftUI

/// Мост к контроллеру для SwiftUI: view создаёт контроллер внутри себя,
/// прокси отдаёт его наружу после `makeUIView`.
///
/// ```swift
/// @StateObject private var player = BoomstreamPlayerProxy()
/// var body: some View {
///     BoomstreamPlayerView(mediaCode: "XXXXXXXX", proxy: player)
///     Button("Pause") { player.controller?.pause() }
/// }
/// ```
@MainActor
public final class BoomstreamPlayerProxy: ObservableObject {
    @Published public internal(set) var controller: (any BoomstreamPlayerController)?

    public init() {}
}

/// SwiftUI-плеер (primary UI, docs/SDK_ARCHITECTURE.md §2).
public struct BoomstreamPlayerView: UIViewRepresentable {
    private let mediaCode: String
    private let configClient: (any BoomstreamConfigFetching)?
    private let proxy: BoomstreamPlayerProxy?
    private let allowClearKeyDRMToken: String?
    private let advancedOptions: AdvancedPlayerOptions
    private let offlineCache: (any BoomstreamOfflineCache)?
    private let showsControls: Bool
    private let onState: (PlayerState) -> Void
    private let onFullScreenChanged: ((Bool) -> Void)?

    public init(
        mediaCode: String,
        configClient: (any BoomstreamConfigFetching)? = nil,
        proxy: BoomstreamPlayerProxy? = nil,
        allowClearKeyDRMToken: String? = nil,
        advancedOptions: AdvancedPlayerOptions = AdvancedPlayerOptions(),
        offlineCache: (any BoomstreamOfflineCache)? = nil,
        showsControls: Bool = true,
        onState: @escaping (PlayerState) -> Void = { _ in },
        onFullScreenChanged: ((Bool) -> Void)? = nil
    ) {
        self.mediaCode = mediaCode
        self.configClient = configClient
        self.proxy = proxy
        self.allowClearKeyDRMToken = allowClearKeyDRMToken
        self.advancedOptions = advancedOptions
        self.offlineCache = offlineCache
        self.showsControls = showsControls
        self.onState = onState
        self.onFullScreenChanged = onFullScreenChanged
    }

    public func makeUIView(context: Context) -> BoomstreamPlayerUIView {
        let view = BoomstreamPlayerUIView()
        view.onState = onState
        view.onFullScreenChanged = onFullScreenChanged
        view.isControlsEnabled = showsControls
        proxy?.controller = view.controller
        load(into: view)
        context.coordinator.loadedMediaCode = mediaCode
        return view
    }

    public func updateUIView(_ uiView: BoomstreamPlayerUIView, context: Context) {
        guard context.coordinator.loadedMediaCode != mediaCode else { return }
        context.coordinator.loadedMediaCode = mediaCode
        load(into: uiView)
    }

    public static func dismantleUIView(_ uiView: BoomstreamPlayerUIView, coordinator: Coordinator) {
        uiView.release()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    public final class Coordinator {
        var loadedMediaCode: String?
    }

    private func load(into view: BoomstreamPlayerUIView) {
        view.load(
            mediaCode: mediaCode,
            configClient: configClient,
            allowClearKeyDRMToken: allowClearKeyDRMToken,
            advancedOptions: advancedOptions,
            offlineCache: offlineCache
        )
    }
}
#endif
