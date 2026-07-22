# Boomstream iOS SDK

[![License](https://img.shields.io/badge/license-Apache%202.0-green)](LICENSE)
[![Platform](https://img.shields.io/badge/iOS-15.0%2B-orange)](#)
[![Swift](https://img.shields.io/badge/swift-6.0%2B-purple)](#)
[![SPM](https://img.shields.io/badge/SPM-compatible-blue)](#)

Нативный iOS SDK видеоплатформы [Boomstream](https://boomstream.com): воспроизведение HLS (VOD, live-трансляции, плейлисты, защищённый контент), клиент Boomstream API и офлайн-загрузки.

- **Zero third-party dependencies** — только системные фреймворки (AVFoundation, URLSession)
- iOS **15.0+**, Swift 6 (strict concurrency), Xcode 16+
- Дистрибуция — **Swift Package Manager**
- Лицензия — Apache 2.0

| Продукт | Назначение |
|---|---|
| `BoomstreamPlayer` | Плеер: SwiftUI-view и UIKit-обёртка, встроенные контролы, программное управление |
| `BoomstreamOffline` | Офлайн-загрузки HLS с фоновым продолжением |
| `BoomstreamAPI` | Клиент Boomstream API (листинги) и config-эндпоинта плеера |

## Quick start (5 минут до первого видео)

### 1. Установите SDK через Swift Package Manager

В Xcode: **File → Add Package Dependencies…** → вставьте URL:

```
https://github.com/boomstream-com/boomstream-ios-sdk.git
```

и добавьте нужные продукты (`BoomstreamPlayer`, при необходимости `BoomstreamOffline` и `BoomstreamAPI`) к своему таргету.

Либо в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/boomstream-com/boomstream-ios-sdk.git", from: "0.1.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "BoomstreamPlayer", package: "boomstream-ios-sdk"),
            .product(name: "BoomstreamOffline", package: "boomstream-ios-sdk"),
            .product(name: "BoomstreamAPI", package: "boomstream-ios-sdk"),
        ]
    )
]
```

### 2. Сконфигурируйте SDK

Один раз при старте приложения:

```swift
import BoomstreamAPI

@main
struct MyApp: App {
    init() {
        // API-ключ нужен только для листингов (Boomstream.api).
        // Плеер и офлайн-загрузки работают без него.
        Boomstream.configure(apiKey: appSecrets.boomstreamAPIKey)
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

### 3. Покажите плеер

```swift
import BoomstreamPlayer

struct PlayerScreen: View {
    var body: some View {
        BoomstreamPlayerView(mediaCode: "XXXXXXXX")
            .aspectRatio(16 / 9, contentMode: .fit)
    }
}
```

Плеер сам запросит конфигурацию медиа, выберет источник и начнёт воспроизведение.

## Модуль `BoomstreamPlayer`

### SwiftUI

```swift
@StateObject private var player = BoomstreamPlayerProxy()

var body: some View {
    BoomstreamPlayerView(
        mediaCode: "XXXXXXXX",
        proxy: player,                      // программное управление (опционально)
        onState: { state in /* PlayerState */ },
        onFullScreenChanged: { isFullScreen in /* скрыть свой chrome */ }
    )
    .aspectRatio(16 / 9, contentMode: .fit)

    Button("Пауза") { player.controller?.pause() }
}
```

### UIKit

```swift
let playerView = BoomstreamPlayerUIView()
view.addSubview(playerView)
playerView.load(mediaCode: "XXXXXXXX")
// обязательно при уходе с экрана:
playerView.release()
```

### Встроенные контролы

Тап по видео показывает overlay: play/pause, перемотка слайдером, кнопка fullscreen; для плейлистов — переключение треков (prev/next); для live-трансляций вместо таймлайна — цветной индикатор статуса эфира (зелёный — онлайн, серый — офлайн). Контролы скрываются автоматически через 3,5 с. Если рисуете собственный UI — отключите встроенный: `showsControls: false` (SwiftUI) или `isControlsEnabled = false` (UIKit).

### Программное управление и события

`BoomstreamPlayerController` (через `BoomstreamPlayerProxy` в SwiftUI или `playerView.controller` в UIKit):

```swift
controller.play(); controller.pause()
controller.seek(to: 30); controller.seek(toPercent: 0.5)
controller.setVolume(0.5); controller.mute(); controller.unmute()
controller.next(); controller.previous()          // плейлисты
controller.setFullScreen(true); controller.toggleFullScreen()
controller.currentPosition; controller.duration
```

Наблюдение — через `AsyncStream` (каждый доступ возвращает независимый стрим):

```swift
for await state in controller.states { ... }      // PlayerState
for await event in controller.events { ... }      // PlayerEvent
for await progress in controller.progress { ... } // PlaybackProgress (позиция/длительность/буфер)
```

Состояния: `idle`, `loading`, `ready(...)`, `posterOnly(...)` (нет доступа к медиа или эфир офлайн), `error(...)`, `ended`. События: `loaded`, `playing`, `paused`, `ended`, `progress`, `seeked`, `fullScreenChanged`.

### Выбор качества

`BoomstreamPlayerController` даёт доступ к вариантам качества из HLS-манифеста — можно
переключать программно или показать встроенную кнопку выбора в контролах плеера.

```swift
// Опционально: встроенная кнопка выбора качества в контролах плеера (по умолчанию выключена)
BoomstreamPlayerView(
    mediaCode: "XXXXXXXX",
    advancedOptions: AdvancedPlayerOptions(showQualitySelector: true)
)

// Программное переключение
controller.setQuality(.resolution(height: 720))  // ограничить воспроизведение (720p)
controller.selectAuto()                          // вернуть адаптивный выбор

// Список доступных вариантов (пустой до готовности плеера)
controller.availableQualities.forEach { print($0.label) }  // "1080p", "720p", …
controller.currentQuality                         // применённое качество (.auto по умолчанию)

// Наблюдение за обновлением списка вариантов
for await qualities in controller.qualityUpdates { ... }   // AsyncStream<[VideoQuality]>
```

Варианты качества берутся из HLS master-манифеста и появляются после готовности плеера
(до этого `availableQualities` — пустой список). Выбранное качество сохраняется при
переключении треков плейлиста; `.auto` снимает ограничение и возвращает адаптивный выбор.

### Защищённый контент

Для воспроизведения защищённых потоков передайте токен доступа проекта — SDK добавит его в User-Agent всех медиа-запросов (манифест, сегменты, ключи):

```swift
// глобально, при конфигурации:
Boomstream.configure(options: BoomstreamOptions(userAgentToken: appSecrets.accessToken))

// или на конкретное воспроизведение:
BoomstreamPlayerView(mediaCode: "XXXXXXXX", allowClearKeyDRMToken: appSecrets.accessToken)
```

Токен — секрет: не хардкодьте его в исходном коде.

### Live-трансляции

`isLive` приходит в `PlayerState.ready`. Пока эфир не запущен, плеер показывает постер (`posterOnly`) и сам опрашивает конфигурацию — воспроизведение начнётся автоматически после старта эфира. Если у трансляции есть записи, вместо постера воспроизводятся они.

### Тонкая настройка

```swift
BoomstreamPlayerView(
    mediaCode: "XXXXXXXX",
    advancedOptions: AdvancedPlayerOptions(
        preferredForwardBufferDuration: 10,          // сек упреждающего буфера (0 = авто)
        automaticallyWaitsToMinimizeStalling: true,
        preferredPeakBitRate: 0                      // бит/с (0 = адаптивный выбор)
    )
)
```

## Модуль `BoomstreamOffline`

### Инициализация

```swift
import BoomstreamOffline

let downloads = BoomstreamOfflineManager(configClient: Boomstream.configClient)
// после перезапуска приложения — переподключиться к фоновым загрузкам:
await downloads.restoreTransfers()
```

### Загрузка и управление

```swift
let handle = try await downloads.start(mediaCode: "XXXXXXXX", quality: .auto)

for await state in downloads.observe(mediaCode: "XXXXXXXX") {
    // queued / inProgress(percent, bytes) / paused / completed(size, expiresAt) / failed(error)
}
for await all in downloads.observeAll() { ... }    // весь каталог загрузок

await downloads.pause(mediaCode: "XXXXXXXX")
await downloads.resume(mediaCode: "XXXXXXXX")
await downloads.cancel(mediaCode: "XXXXXXXX")
try await downloads.delete(mediaCode: "XXXXXXXX")
let stats = await downloads.stats()                // количество и суммарный размер
await downloads.purgeExpired()                     // удалить загрузки с истёкшим сроком
```

По умолчанию загрузки идут только по Wi-Fi (`allowsCellularAccess: false`); загрузки продолжаются в фоне и после сворачивания приложения.

### Офлайн-воспроизведение

`BoomstreamOfflineManager` реализует `BoomstreamOfflineCache` — передайте его плееру, и скачанная копия будет играть без сети и без сетевого запроса конфигурации:

```swift
BoomstreamPlayerView(mediaCode: "XXXXXXXX", offlineCache: downloads)
```

### Ограничение

Загрузка **шифрованных** потоков в текущей версии недоступна: `start()` завершится типизированной ошибкой `BoomstreamError.offlineUnavailable` до начала скачивания. Онлайн-воспроизведение шифрованных потоков работает без ограничений.

## Модуль `BoomstreamAPI`

### Листинги (требуется API-ключ)

```swift
let videos = try await Boomstream.api.listFolder()          // видео папки (nil = корень)
let live = try await Boomstream.api.listLive()              // live-трансляции
let playlists = try await Boomstream.api.listPlaylists()    // плейлисты
```

### Config-эндпоинт

Низкоуровневый доступ к конфигурации медиа (то, чем пользуются плеер и загрузки; API-ключ не нужен):

```swift
let config = try await Boomstream.configClient.fetchConfig(mediaCode: "XXXXXXXX")
switch config.media {
case .authorised(let media):        // единичное видео: media.links?.hlsURL, постеры, live-поля
case .playlist(let items):          // плейлист
case .unauthorised(let posters):    // нет доступа — только постеры
}
```

### Ошибки

Все методы бросают типизированный `BoomstreamError`: `network`, `http(statusCode:body:)`, `apiError(message:)`, `unauthorised`, `mediaNotFound`, `drmFailure`, `offlineUnavailable`, `unknown`. Сетевые и 5xx-ошибки автоматически ретраятся (до 3 попыток с экспоненциальной задержкой).

## Configuration & secrets

- `Boomstream.configure(apiKey:options:)` вызывается один раз; повторный вызов с другой конфигурацией — programmer error.
- `BoomstreamOptions`: `userAgentToken` (токен доступа к защищённому контенту), `connectTimeout`/`resourceTimeout`, `apiBaseURL`/`configBaseURL`.
- **Никогда не хардкодьте API-ключ и токены** в исходном коде — передавайте их через xcconfig/CI-переменные (см. Example app). SDK не сохраняет ключи на диск; в `description` опций токен маскируется.

## Example app

```bash
cd Example
cp Config/Local.xcconfig.example Config/Local.xcconfig   # заполните значения
open BoomstreamExample.xcodeproj
```

Две вкладки: **«Медиа»** (плеер + листинги видео/трансляций/плейлистов из API + офлайн-загрузка выбранного медиа) и **«Player API»** (программное управление, прогресс, лог событий). Проект сгенерирован XcodeGen (`project.yml`); регенерация нужна только при его изменении.

Примечание: некоторые защищённые потоки не воспроизводятся на iOS Simulator — проверяйте на реальном устройстве.

## Сборка и тестирование

```bash
swift build          # сборка всех продуктов
swift test           # юнит-тесты
```

## Distribution

SDK распространяется только через Swift Package Manager; версии — git-теги SemVer (`v0.1.0`). CocoaPods не поддерживается и не планируется: CocoaPods trunk переходит в read-only режим ([анонс](https://blog.cocoapods.org/CocoaPods-Specs-Repo/)).

## Документация

- [Архитектура SDK](docs/SDK_ARCHITECTURE.md)

## License

Apache License 2.0 — см. [LICENSE](LICENSE).
