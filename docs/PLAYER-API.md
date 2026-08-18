# Player API — справочник

Детальный справочник по `BoomstreamPlayerController` и связанным публичным типам.
Базовые примеры использования — в основном [README](../README.md).

---

## AirPlay (iOS) vs Google Cast (Android) — сравнение v1

| Возможность | iOS AirPlay v1 | Android Google Cast v1 |
|---|---|---|
| Включение | Автоматически (`allowsExternalPlayback = true`) | Требует `CastContext.initialize` + `CastButton` |
| Кнопка выбора приёмника | Интегратор размещает `AVRoutePickerView` | Интегратор размещает `MediaRouteButton` |
| Встроена ли кнопка в плеер | Нет | Нет |
| `isStreaming` / `isAirPlaying` | `controller.isAirPlaying: Bool` | `controller.isCasting: Bool` |
| Имя приёмника | `controller.airPlayDeviceName: String?` | `controller.castDeviceName: String?` |
| Поток изменений | `controller.airPlayUpdates: AsyncStream<Bool>` | `controller.castUpdates: Flow<Boolean>` |
| Overlay в плеере | «Casting to \<device\>» (авто, локализован) | «Casting to \<device\>» (авто, локализован) |
| `externalMetadata` (постер + название на экране ТВ) | ✅ (`AVMetadataItem`, `MPNowPlayingInfoCenter`) | ✅ (`MediaMetadata`) |
| Защищённый контент | ❌ v1 — только незащищённый | ❌ v1 — только незащищённый |
| Минимальная платформа | iOS 15.0+ | Android 5.0+ |

---

## Интеграция AirPlay — SwiftUI

```swift
import SwiftUI
import AVKit
import BoomstreamPlayer

struct PlayerWithAirPlay: View {
    @StateObject private var player = BoomstreamPlayerProxy()
    @State private var isAirPlaying = false
    @State private var airPlayDeviceName: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            BoomstreamPlayerView(mediaCode: "XXXXXXXX", proxy: player)
                .aspectRatio(16 / 9, contentMode: .fit)

            HStack {
                // Статус трансляции
                if isAirPlaying {
                    Label("Casting to \(airPlayDeviceName ?? "TV")", systemImage: "airplayvideo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Кнопка выбора приёмника — интегратор размещает сам
                AirPlayButton()
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal)
        }
        .task(id: player.controller != nil) {
            guard let ctrl = player.controller else { return }
            isAirPlaying = ctrl.isAirPlaying
            airPlayDeviceName = ctrl.airPlayDeviceName
            for await active in ctrl.airPlayUpdates {
                isAirPlaying = active
                airPlayDeviceName = ctrl.airPlayDeviceName
            }
        }
    }
}

/// AVRoutePickerView — системная кнопка выбора AirPlay-приёмника.
/// Разместите в своём layout; SDK не встраивает её автоматически.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
```

---

## Интеграция AirPlay — UIKit

```swift
import UIKit
import AVKit
import BoomstreamPlayer

final class PlayerViewController: UIViewController {
    private let playerView = BoomstreamPlayerUIView()
    private let routePicker = AVRoutePickerView()
    private var airPlayTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Плеер
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)

        // Кнопка выбора AirPlay-приёмника
        routePicker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(routePicker)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 9 / 16),

            routePicker.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 8),
            routePicker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            routePicker.widthAnchor.constraint(equalToConstant: 44),
            routePicker.heightAnchor.constraint(equalToConstant: 44),
        ])

        playerView.load(mediaCode: "XXXXXXXX")

        // Наблюдение за AirPlay-состоянием
        let ctrl = playerView.controller
        airPlayTask = Task { [weak self] in
            for await active in ctrl.airPlayUpdates {
                let device = ctrl.airPlayDeviceName
                self?.updateAirPlayStatus(active: active, device: device)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        airPlayTask?.cancel()
        playerView.release()
    }

    private func updateAirPlayStatus(active: Bool, device: String?) {
        // Обновите свой UI при изменении состояния AirPlay
    }
}
```

---

## `BoomstreamPlayerController` — AirPlay-члены протокола

| Член | Тип | Описание |
|---|---|---|
| `isAirPlaying` | `Bool` | `true` пока контент транслируется на AirPlay-приёмник |
| `airPlayDeviceName` | `String?` | Имя активного приёмника (`nil` когда не активно) |
| `airPlayUpdates` | `AsyncStream<Bool>` | Поток: `true` при начале, `false` при завершении трансляции |

Каждый доступ к `airPlayUpdates` возвращает независимый поток — несколько подписчиков работают без конфликтов.

---

## Ссылки

- [AVRoutePickerView — Apple Developer Documentation](https://developer.apple.com/documentation/avkit/avroutepickerview)
- [AVPlayer.allowsExternalPlayback — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avplayer/allowsexternalplayback)
- [MPNowPlayingInfoCenter — Apple Developer Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
