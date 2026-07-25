#if canImport(UIKit)
import AVFoundation
import BoomstreamAPI
import UIKit

/// UIKit-обёртка плеера (back-compat для проектов без SwiftUI)
/// со встроенным overlay-контролов (тап по видео — показать/скрыть).
///
/// Требует ручного `release()` при уходе экрана (например, в `viewDidDisappear` /
/// `deinit` контроллера) — авто-release есть только у SwiftUI-обёртки, где
/// жизненный цикл детерминирован (`dismantleUIView`).
public final class BoomstreamPlayerUIView: UIView {
    public override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private let core = BoomstreamPlayerCore()
    private let posterView = UIImageView()
    private let messageLabel = UILabel()
    private let messageLabelContainer = UIView()
    private let loaderSpinner = UIActivityIndicatorView(style: .large)
    private let controls = PlayerControlsOverlay()
    private let liveBadge = LiveStatusBadge()
    private var stateTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var autoHideTask: Task<Void, Never>?
    private var posterFetchTask: Task<Void, Never>?
    private var isPlaying = false
    private var storedAdvancedOptions = AdvancedPlayerOptions()

    /// Colour overrides for controls, loader, and message overlay.
    /// All fields are optional — `nil` keeps default appearance (backward-compatible).
    public var style: BoomstreamPlayerStyle = BoomstreamPlayerStyle() {
        didSet { applyStyle() }
    }

    /// Программное управление. Сырой AVPlayer не экспонируется.
    public var controller: any BoomstreamPlayerController { core }
    public var states: AsyncStream<PlayerState> { core.states }
    /// Колбэк смены состояния (для SwiftUI-обёртки и UIKit-подписчиков без async).
    public var onState: ((PlayerState) -> Void)? {
        get { core.onState }
        set { core.onState = newValue }
    }
    /// Колбэк смены fullscreen — host скрывает свой chrome и растягивает view.
    public var onFullScreenChanged: ((Bool) -> Void)?
    /// Встроенные контролы (по умолчанию включены); выключайте, если рисуете свои.
    public var isControlsEnabled = true {
        didSet {
            if !isControlsEnabled { setControls(visible: false, animated: false) }
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        playerLayer.player = core.player
        playerLayer.videoGravity = .resizeAspect

        posterView.contentMode = .scaleAspectFit
        posterView.translatesAutoresizingMaskIntoConstraints = false
        posterView.isHidden = true
        addSubview(posterView)

        loaderSpinner.color = .white
        loaderSpinner.hidesWhenStopped = true
        loaderSpinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loaderSpinner)

        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabelContainer.translatesAutoresizingMaskIntoConstraints = false
        messageLabelContainer.isHidden = true
        messageLabelContainer.addSubview(messageLabel)
        addSubview(messageLabelContainer)

        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.alpha = 0
        controls.isHidden = true
        addSubview(controls)

        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        liveBadge.isHidden = true
        addSubview(liveBadge)

        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: topAnchor),
            posterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            posterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: trailingAnchor),

            loaderSpinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            loaderSpinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            messageLabelContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabelContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabelContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            messageLabelContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            messageLabel.topAnchor.constraint(equalTo: messageLabelContainer.topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: messageLabelContainer.bottomAnchor, constant: -8),
            messageLabel.leadingAnchor.constraint(equalTo: messageLabelContainer.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: messageLabelContainer.trailingAnchor, constant: -12),

            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            liveBadge.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
        ])

        wireControls()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        stateTask = Task { [weak self] in
            guard let stream = self?.core.states else { return }
            for await state in stream {
                self?.apply(state: state)
            }
        }
        eventsTask = Task { [weak self] in
            guard let stream = self?.core.events else { return }
            for await event in stream {
                self?.apply(event: event)
            }
        }
        progressTask = Task { [weak self] in
            guard let stream = self?.core.progress else { return }
            for await snapshot in stream {
                self?.controls.update(progress: snapshot)
            }
        }
        qualityTask = Task { [weak self] in
            guard let stream = self?.core.qualityUpdates else { return }
            for await qualities in stream {
                // Legacy mode only: settings-menu mode controls gear visibility via state transitions.
                guard self?.storedAdvancedOptions.showSettingsMenu == false else { continue }
                let visible = (self?.storedAdvancedOptions.showQualitySelector == true) && !qualities.isEmpty
                self?.controls.update(gearButtonVisible: visible)
            }
        }
    }

    private func wireControls() {
        controls.onPlayPause = { [weak self] in
            guard let self else { return }
            self.isPlaying ? self.core.pause() : self.core.play()
            self.scheduleAutoHide()
        }
        controls.onSeek = { [weak self] percent in
            self?.core.seek(toPercent: percent)
            self?.scheduleAutoHide()
        }
        controls.onPrevious = { [weak self] in
            self?.core.previous()
            self?.scheduleAutoHide()
        }
        controls.onNext = { [weak self] in
            self?.core.next()
            self?.scheduleAutoHide()
        }
        controls.onFullScreen = { [weak self] in
            self?.core.toggleFullScreen()
            self?.scheduleAutoHide()
        }
        controls.onGearTapped = { [weak self] sourceButton in
            guard let self else { return }
            if self.storedAdvancedOptions.showSettingsMenu {
                self.presentSettingsSheet(from: sourceButton)
            } else {
                self.presentQualitySheet(from: sourceButton)
            }
        }
    }

    // MARK: - Style application

    private func applyStyle() {
        loaderSpinner.color = style.loaderColor ?? .white
        messageLabel.textColor = style.messageTextColor ?? .white
        messageLabelContainer.backgroundColor = style.messageBackgroundColor
        messageLabelContainer.layer.cornerRadius = style.messageBackgroundColor != nil ? 8 : 0
        controls.applyStyle(style)
    }

    /// Update the locale used for settings menu strings without reloading media.
    /// Called from `BoomstreamPlayerView.updateUIView` when `advancedOptions.locale` changes.
    func updateLocale(_ locale: String) {
        storedAdvancedOptions.locale = locale
    }

    public func load(
        mediaCode: String,
        configClient: (any BoomstreamConfigFetching)? = nil,
        allowClearKeyDRMToken: String? = nil,
        advancedOptions: AdvancedPlayerOptions = AdvancedPlayerOptions(),
        offlineCache: (any BoomstreamOfflineCache)? = nil
    ) {
        storedAdvancedOptions = advancedOptions
        controls.update(gearButtonVisible: false)
        core.load(
            mediaCode: mediaCode,
            configClient: configClient ?? Boomstream.configClient,
            allowClearKeyDRMToken: allowClearKeyDRMToken,
            advancedOptions: advancedOptions,
            offlineCache: offlineCache
        )
    }

    /// Полная остановка воспроизведения и подписок. Обязателен при ручном UIKit-использовании.
    public func release() {
        for task in [stateTask, eventsTask, progressTask, qualityTask, autoHideTask, posterFetchTask] {
            task?.cancel()
        }
        stateTask = nil
        eventsTask = nil
        progressTask = nil
        qualityTask = nil
        autoHideTask = nil
        posterFetchTask = nil
        core.release()
    }

    // MARK: - State/event application

    private func apply(state: PlayerState) {
        switch state {
        case .loading:
            loaderSpinner.startAnimating()
            showMessage(nil)
            setControls(visible: false, animated: false)
            liveBadge.isHidden = true
        case .posterOnly(let posterURL, let message, let isLiveOffline):
            loaderSpinner.stopAnimating()
            showPoster(url: posterURL)
            showMessage(message)
            setControls(visible: false, animated: false)
            liveBadge.isHidden = !isLiveOffline
            if isLiveOffline { liveBadge.set(online: false) }
        case .error(let message):
            loaderSpinner.stopAnimating()
            posterView.isHidden = true
            showMessage(message)
            setControls(visible: false, animated: false)
            liveBadge.isHidden = true
        case .ready(_, let isPlaylist, let index, let size, let isLive, _):
            loaderSpinner.stopAnimating()
            posterView.isHidden = true
            showMessage(nil)
            controls.update(isPlaylist: isPlaylist, index: index, size: size)
            controls.update(isLive: isLive)
            if isLive { controls.setLive(online: true) }
            // corner-бейдж — только для офлайн-эфира на постере (контролы там скрыты);
            // в ready статус живёт в нижней панели контролов
            liveBadge.isHidden = true
            // Settings-menu mode: gear is always shown once the player is ready (Speed is always available).
            if storedAdvancedOptions.showSettingsMenu {
                controls.update(gearButtonVisible: true)
            }
            if isControlsEnabled {
                setControls(visible: true)
                scheduleAutoHide()
            }
        case .idle, .ended:
            loaderSpinner.stopAnimating()
            showMessage(nil)
            if case .ended = state {} else { liveBadge.isHidden = true }
            if case .ended = state {
                // финал: показать контролы для повторного plays
                controls.update(isPlaying: false)
                if isControlsEnabled { setControls(visible: true) }
            } else {
                setControls(visible: false, animated: false)
            }
        }
    }

    private func apply(event: PlayerEvent) {
        switch event {
        case .playing:
            isPlaying = true
            controls.update(isPlaying: true)
            scheduleAutoHide()
        case .paused:
            isPlaying = false
            controls.update(isPlaying: false)
            if isControlsEnabled, case .ready = core.state {
                setControls(visible: true)
            }
        case .ended:
            isPlaying = false
            controls.update(isPlaying: false)
        case .fullScreenChanged(let isFullScreen):
            controls.update(isFullScreen: isFullScreen)
            onFullScreenChanged?(isFullScreen)
        case .loaded, .progress, .seeked:
            break
        }
    }

    // MARK: - Controls visibility

    @objc private func handleTap() {
        guard isControlsEnabled, case .ready = core.state else { return }
        let makeVisible = controls.alpha < 0.5
        setControls(visible: makeVisible)
        if makeVisible { scheduleAutoHide() }
    }

    private func setControls(visible: Bool, animated: Bool = true) {
        autoHideTask?.cancel()
        if visible { controls.isHidden = false }
        let animations = { self.controls.alpha = visible ? 1 : 0 }
        let completion = { (_: Bool) in
            if !visible { self.controls.isHidden = true }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, let self, self.isPlaying, !self.controls.isScrubbing else { return }
            self.setControls(visible: false)
        }
    }

    // MARK: - Settings sheet (unified: Speed + Quality + Audio)

    private func presentSettingsSheet(from sourceButton: UIButton) {
        guard let vc = parentViewController else { return }
        let locale = storedAdvancedOptions.locale

        var sections: [SettingsSheetController.Section] = []

        // Speed section — always present
        let speedRows = core.availableSpeeds.map { speed in
            let label = speed == .normal
                ? BoomstreamMessages.resolve("settings_speed_normal", locale: locale)
                : speed.label
            return SettingsSheetController.Row(title: label, isSelected: speed == core.currentSpeed) { [weak self] in
                self?.core.setSpeed(speed)
            }
        }
        sections.append(SettingsSheetController.Section(
            title: BoomstreamMessages.resolve("settings_speed", locale: locale),
            items: speedRows
        ))

        // Quality section — only when variants have been discovered
        if !core.availableQualities.isEmpty {
            var qualityRows: [SettingsSheetController.Row] = [
                SettingsSheetController.Row(
                    title: BoomstreamMessages.resolve("settings_quality_auto", locale: locale),
                    isSelected: core.currentQuality == .auto
                ) { [weak self] in self?.core.selectAuto() }
            ]
            qualityRows += core.availableQualities.map { q in
                SettingsSheetController.Row(title: q.label, isSelected: q == core.currentQuality) { [weak self] in
                    self?.core.setQuality(q)
                }
            }
            sections.append(SettingsSheetController.Section(
                title: BoomstreamMessages.resolve("settings_quality", locale: locale),
                items: qualityRows
            ))
        }

        // Audio section — only when multiple tracks are available
        if core.availableAudioTracks.count > 1 {
            let audioRows = core.availableAudioTracks.map { track in
                SettingsSheetController.Row(
                    title: track.displayName,
                    isSelected: track == core.currentAudioTrack
                ) { [weak self] in self?.core.selectAudioTrack(track) }
            }
            sections.append(SettingsSheetController.Section(
                title: BoomstreamMessages.resolve("settings_audio", locale: locale),
                items: audioRows
            ))
        }

        // Subtitles section — only when real subtitle tracks are present (phantom CC filtered in Core)
        if !core.availableSubtitleTracks.isEmpty {
            var subtitleRows: [SettingsSheetController.Row] = [
                SettingsSheetController.Row(
                    title: BoomstreamMessages.resolve("subtitles_off", locale: locale),
                    isSelected: core.currentSubtitleTrack == nil
                ) { [weak self] in self?.core.selectNoSubtitles() }
            ]
            subtitleRows += core.availableSubtitleTracks.map { track in
                SettingsSheetController.Row(
                    title: track.displayName,
                    isSelected: track == core.currentSubtitleTrack
                ) { [weak self] in self?.core.selectSubtitleTrack(track) }
            }
            sections.append(SettingsSheetController.Section(
                title: BoomstreamMessages.resolve("subtitles_title", locale: locale),
                items: subtitleRows
            ))
        }

        let sheet = SettingsSheetController(
            title: BoomstreamMessages.resolve("settings_title", locale: locale),
            sections: sections
        )
        let nav = UINavigationController(rootViewController: sheet)
        if let sheetPC = nav.sheetPresentationController {
            sheetPC.detents = [.medium(), .large()]
            sheetPC.prefersGrabberVisible = true
            sheetPC.preferredCornerRadius = 16
        }
        vc.present(nav, animated: true)
    }

    // MARK: - Quality sheet (legacy: showQualitySelector)

    private func presentQualitySheet(from sourceButton: UIButton) {
        guard let vc = parentViewController else { return }
        let sheet = UIAlertController(title: "Video Quality", message: nil, preferredStyle: .actionSheet)

        let autoAction = UIAlertAction(title: VideoQuality.auto.label, style: .default) { [weak self] _ in
            self?.core.selectAuto()
        }
        if core.currentQuality == .auto { autoAction.setValue(true, forKey: "checked") }
        sheet.addAction(autoAction)

        for quality in core.availableQualities {
            let action = UIAlertAction(title: quality.label, style: .default) { [weak self] _ in
                self?.core.setQuality(quality)
            }
            if quality == core.currentQuality { action.setValue(true, forKey: "checked") }
            sheet.addAction(action)
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = controls
            popover.sourceRect = controls.convert(sourceButton.bounds, from: sourceButton)
        }
        vc.present(sheet, animated: true)
    }

    private var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    // MARK: - Poster / message

    private func showMessage(_ text: String?) {
        messageLabel.text = text
        messageLabelContainer.isHidden = (text == nil)
    }

    private func showPoster(url: URL?) {
        posterView.isHidden = false
        posterView.image = nil
        posterFetchTask?.cancel()
        guard let url else { return }
        posterFetchTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled
            else { return }
            self?.posterView.image = image
        }
    }
}

extension BoomstreamPlayerUIView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // кнопки/слайдер оверлея обрабатывают свои касания сами
        !(touch.view is UIControl)
    }
}
#endif
