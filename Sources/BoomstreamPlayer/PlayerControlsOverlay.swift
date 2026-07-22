#if canImport(UIKit)
import UIKit

/// Встроенный overlay контролов плеера:
/// play/pause, prev/next (плейлисты), seek-слайдер с таймингами, fullscreen.
/// Управляется из `BoomstreamPlayerUIView`; сам ничего не знает про AVPlayer.
@MainActor
final class PlayerControlsOverlay: UIView {
    var onPlayPause: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onFullScreen: (() -> Void)?
    /// Called when the user taps the gear button; receives the button itself for iPad popover anchoring.
    var onQualityTapped: ((UIButton) -> Void)?
    /// percent 0…1
    var onSeek: ((Double) -> Void)?

    private(set) var isScrubbing = false

    private let dimView = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let fullScreenButton = UIButton(type: .system)
    // Internal: exposed for UIAlertController popover source on iPad.
    let qualityButton = UIButton(type: .system)
    private let slider = UISlider()
    private let positionLabel = UILabel()
    private let durationLabel = UILabel()
    private let liveIndicator = LiveStatusBadge()
    private let bottomSpacer = UIView()
    private var lastKnownDuration: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)

        let bigConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        let midConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        configure(playPauseButton, symbol: "play.fill", config: bigConfig) { [weak self] in self?.onPlayPause?() }
        configure(previousButton, symbol: "backward.end.fill", config: midConfig) { [weak self] in self?.onPrevious?() }
        configure(nextButton, symbol: "forward.end.fill", config: midConfig) { [weak self] in self?.onNext?() }
        configure(fullScreenButton, symbol: "arrow.up.left.and.arrow.down.right", config: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)) { [weak self] in self?.onFullScreen?() }
        let gearConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        qualityButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gearConfig), for: .normal)
        qualityButton.tintColor = .white
        qualityButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onQualityTapped?(self.qualityButton)
        }, for: .touchUpInside)
        qualityButton.isHidden = true
        previousButton.isHidden = true
        nextButton.isHidden = true

        let centerStack = UIStackView(arrangedSubviews: [previousButton, playPauseButton, nextButton])
        centerStack.axis = .horizontal
        centerStack.spacing = 40
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerStack)

        for label in [positionLabel, durationLabel] {
            label.textColor = .white
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.text = "0:00"
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.tintColor = .white
        slider.setThumbImage(thumbImage(radius: 6), for: .normal)
        slider.addAction(UIAction { [weak self] _ in self?.scrubChanged() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.isScrubbing = true }, for: .touchDown)
        for event in [UIControl.Event.touchUpInside, .touchUpOutside, .touchCancel] {
            slider.addAction(UIAction { [weak self] _ in self?.scrubEnded() }, for: event)
        }

        // Live-режим: слайдер/тайминги скрыты, слева — статус-индикатор, спейсер
        // держит fullscreen-кнопку прижатой вправо.
        liveIndicator.isHidden = true
        bottomSpacer.isHidden = true
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bottomStack = UIStackView(
            arrangedSubviews: [liveIndicator, positionLabel, slider, durationLabel, bottomSpacer, qualityButton, fullScreenButton]
        )
        bottomStack.axis = .horizontal
        bottomStack.spacing = 8
        bottomStack.alignment = .center
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomStack)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    private func configure(
        _ button: UIButton,
        symbol: String,
        config: UIImage.SymbolConfiguration,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func thumbImage(radius: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: radius * 2, height: radius * 2))
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
        }
    }

    private func scrubChanged() {
        guard isScrubbing, lastKnownDuration > 0 else { return }
        positionLabel.text = Self.timeString(Double(slider.value) * lastKnownDuration)
    }

    private func scrubEnded() {
        guard isScrubbing else { return }
        isScrubbing = false
        onSeek?(Double(slider.value))
    }

    // MARK: - Updates from player

    func update(progress: PlaybackProgress) {
        lastKnownDuration = progress.duration
        durationLabel.text = Self.timeString(progress.duration)
        guard !isScrubbing else { return }
        positionLabel.text = Self.timeString(progress.position)
        slider.value = Float(progress.fraction)
    }

    func update(isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        playPauseButton.setImage(
            UIImage(systemName: isPlaying ? "pause.fill" : "play.fill", withConfiguration: config),
            for: .normal
        )
    }

    /// Live: прогресс-бар и тайминги не имеют смысла — вместо них слева
    /// статус-индикатор эфира, fullscreen-кнопка остаётся справа.
    func update(isLive: Bool) {
        positionLabel.isHidden = isLive
        slider.isHidden = isLive
        durationLabel.isHidden = isLive
        liveIndicator.isHidden = !isLive
        bottomSpacer.isHidden = !isLive
    }

    func setLive(online: Bool) {
        liveIndicator.set(online: online)
    }

    func update(isFullScreen: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let symbol = isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullScreenButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
    }

    func update(isPlaylist: Bool, index: Int, size: Int) {
        let showsTrackButtons = isPlaylist && size > 1
        previousButton.isHidden = !showsTrackButtons
        nextButton.isHidden = !showsTrackButtons
        previousButton.isEnabled = index > 0
        nextButton.isEnabled = index < size - 1
    }

    /// Shows or hides the quality gear button. Hidden by default until qualities are discovered
    /// and `showQualitySelector` is enabled in `AdvancedPlayerOptions`.
    func update(qualityButtonVisible: Bool) {
        qualityButton.isHidden = !qualityButtonVisible
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(seconds.rounded()) : 0
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Постоянный индикатор статуса live-трансляции (язык-нейтральный «кружок с цветом»):
/// зелёный — эфир онлайн, серый — офлайн. Виден независимо от overlay-контролов.
@MainActor
final class LiveStatusBadge: UIView {
    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 11
        dot.layer.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])
        isAccessibilityElement = true
    }

    func set(online: Bool) {
        dot.backgroundColor = online ? .systemGreen : .systemGray
        accessibilityLabel = online ? "Live: online" : "Live: offline"
        dot.layer.removeAllAnimations()
        if online {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.layer.add(pulse, forKey: "pulse")
        }
    }
}
#endif
