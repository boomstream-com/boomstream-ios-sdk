# Boomstream iOS SDK — архитектура

## Обзор

Один Swift Package (`BoomstreamSDK`) с тремя library-продуктами. Минимальная версия — iOS 15.0; язык — Swift 6 (strict concurrency, `swift-tools-version: 6.0`).

Принципы:

- **Zero third-party dependencies.** Только системные фреймворки: URLSession вместо сетевых библиотек, Codable вместо маперов, AVFoundation вместо сторонних движков, `AsyncStream` вместо реактивных фреймворков. SDK не приносит в проект потребителя конфликтов версий.
- **Движок воспроизведения не экспонируется.** Управление плеером — только через протокол `BoomstreamPlayerController` и whitelisted-настройки `AdvancedPlayerOptions`; прямого доступа к `AVPlayer` в публичном API нет.
- **SDK не собирает телеметрию.** Никаких аналитических маяков и сторонних сервисов; прогресс воспроизведения доступен приложению локально через стримы.
- **Строгая многопоточность.** Пакет собирается в Swift 6 language mode; UI-обращённые API (`BoomstreamPlayerController`, `BoomstreamDownloads`, view-обёртки) изолированы на `@MainActor` — вызов из фонового потока не компилируется. DTO и события — `Sendable` value types.

## Модули

```
Приложение ──► BoomstreamPlayer ──► BoomstreamAPI
        │
        └────► BoomstreamOffline ──► BoomstreamAPI
```

| Продукт | Содержимое | Зависимости |
|---|---|---|
| `BoomstreamAPI` | Конфигурация SDK, клиент config-эндпоинта, клиент Boomstream API, модели, error-модель | Foundation |
| `BoomstreamPlayer` | Ядро плеера на AVPlayer, SwiftUI/UIKit-обёртки, встроенные контролы | BoomstreamAPI, AVFoundation |
| `BoomstreamOffline` | Офлайн-загрузки HLS, персистенция, стык с плеером | BoomstreamAPI, AVFoundation |

Продукты подключаются независимо: приложению, которому нужен только REST-клиент, не нужны AVFoundation-таргеты; неиспользуемые продукты не попадают в бинарь (dead-code stripping). Версии всех продуктов выпускаются lockstep одним git-тегом.

## BoomstreamAPI

### Конфигурация

`Boomstream.configure(apiKey:options:)` вызывается один раз при старте приложения. API-ключ опционален: он нужен только листинг-методам (`Boomstream.api`); плеер и загрузки работают через публичный config-эндпоинт (`Boomstream.configClient`). Повторный вызов `configure` с другой конфигурацией — programmer error (fail-fast `precondition`).

`BoomstreamOptions`:

| Поле | Default | Назначение |
|---|---|---|
| `userAgentToken` | `nil` | Токен доступа к защищённому контенту; добавляется в User-Agent запросов |
| `connectTimeout` / `resourceTimeout` | 15 c / 30 c | Таймауты сетевых запросов |
| `apiBaseURL` | `https://boomstream.com/` | База Boomstream API |
| `configBaseURL` | `https://play.boomstream.com/` | База config-эндпоинта |

`userAgentToken` — секрет: в `description` опций он маскируется, SDK не пишет его на диск. User-Agent SDK: `"Boomstream iOS SDK v<версия> <токен>"`.

### Config-эндпоинт (`BoomstreamConfigClient`)

`GET {configBaseURL}/{mediaCode}/config`, без авторизации (только User-Agent). Ответ (`ConfigResponse`):

- `mediaData` полиморфен: `null` — доступа нет (только постеры), объект — одиночное медиа, массив — плейлист. Типизированный доступ — `config.media: BoomstreamMedia` (`.authorised` / `.playlist` / `.unauthorised`).
- Признак плейлиста — поле `mediaType` (авторитетный источник), не форма `mediaData`.
- Ссылки воспроизведения (`links.hls`) приходят Base64-encoded; декодированный URL — `MediaLinks.hlsURL`.
- Live-контракт: `isLive` — трансляция; `isPublish` — эфир запущен; `records` — записи для воспроизведения, когда эфир офлайн.
- `effectivePosters` — постеры медиа с fallback на `defaults`; `accessRestricted` — сообщение об ограничении доступа.

Декодирование терпимое: неизвестные ключи игнорируются, числа принимаются и строками — неожиданная форма одного поля не валит весь ответ.

Успешные ответы кэшируются в памяти по `mediaCode`; `forceRefresh: true` обходит кэш (используется поллингом офлайн-эфира). Ошибки не кэшируются.

### Boomstream API (`BoomstreamAPIClient`)

`POST` + JSON body, авторизация `Authorization: Bearer <apiKey>`:

| Метод | Эндпоинт | Результат |
|---|---|---|
| `listFolder(folderCode:)` | `api/media/folder` | `[FolderMediaItem]` |
| `listLive(folderCode:)` | `api/live/folder` | `[LiveMediaItem]` |
| `listPlaylists()` | `api/playlist/list` | `[PlaylistItem]` |

Семантическая ошибка API (`Status: "Failed"`) маппится в `BoomstreamError.apiError(message:)`.

### Сетевой слой и ошибки

Оба клиента работают через общий URLSession-слой: retry для 5xx и сетевых ошибок (экспоненциальная задержка, максимум 3 попытки), маппинг статусов — 401/403 → `.unauthorised`, 404 → `.mediaNotFound`. Публичные методы — `async throws BoomstreamError`; отмена — кооперативная, через structured concurrency вызывающего кода.

```swift
public enum BoomstreamError: Error, Sendable {
    case network(underlying: Error)
    case http(statusCode: Int, body: String?)
    case apiError(message: String)
    case unauthorised
    case mediaNotFound(mediaCode: String)
    case drmFailure(underlying: Error?)
    case offlineUnavailable(reason: String)
    case unknown(underlying: Error?)
}
```

## BoomstreamPlayer

### Пайплайн воспроизведения

1. `fetchConfig(mediaCode)` → `ConfigResponse`.
2. Чистая функция строит план воспроизведения: постер (нет доступа / эфир офлайн без записей), одиночное медиа, плейлист или записи офлайн-эфира.
3. `AVURLAsset` создаётся с User-Agent-заголовком (токен доступа уходит в запросы манифеста, сегментов и ключей) → `AVPlayerItem` → `AVPlayer`.
4. KVO и нотификации плеера маппятся в публичные состояния и события.

### Состояния, события, прогресс

```swift
enum PlayerState { case idle, loading,
    ready(title:isPlaylist:playlistIndex:playlistSize:isLive:systemMessage:),
    posterOnly(posterURL:message:isLiveOffline:), error(message:), ended }

enum PlayerEvent { case loaded, playing, paused, ended,
    progress(PlaybackProgress), seeked(TimeInterval), fullScreenChanged(Bool) }
```

`PlaybackProgress` — позиция/длительность/буфер + `fraction` (0…1, для live — 0). Наблюдение — мультикаст-`AsyncStream`: каждый доступ к `states`/`events`/`progress` возвращает независимый стрим, подписчиков может быть несколько.

### Контроллер

`BoomstreamPlayerController` (@MainActor): `play/pause`, `seek(to:)/seek(toPercent:)`, `setVolume/mute/unmute`, `next/previous` (плейлисты), `setFullScreen/toggleFullScreen`, `currentPosition/duration` + стримы. В SwiftUI контроллер доступен через `BoomstreamPlayerProxy` после монтирования view; в UIKit — свойство `controller` у `BoomstreamPlayerUIView`.

### View-обёртки

- **SwiftUI** — `BoomstreamPlayerView` (`UIViewRepresentable`): загрузка по `mediaCode`, авто-release при демонтаже, колбэки `onState` и `onFullScreenChanged`.
- **UIKit** — `BoomstreamPlayerUIView`: `load(mediaCode:...)` / `release()` (обязателен при уходе с экрана), `states`-стрим, постер и сообщение об ошибке поверх видео.

### Встроенные контролы

Overlay поверх видео: play/pause, prev/next (видимы только для плейлистов), seek-слайдер с таймингами, кнопка fullscreen (иконка отражает состояние). Тап по видео — показать/скрыть; автоскрытие через 3,5 с при воспроизведении; на паузе контролы остаются. Отключаются `showsControls: false` / `isControlsEnabled = false`.

### Live-трансляции

- Эфир офлайн → `posterOnly(isLiveOffline: true)` + фоновый поллинг config с `forceRefresh`; воспроизведение стартует автоматически после публикации эфира. Если у трансляции есть записи — воспроизводятся они.
- В контролах live-режима таймлайн заменён индикатором статуса эфира (зелёный пульсирующий — онлайн; серый — офлайн, поверх постера).

### Защищённый контент

Токен доступа (`userAgentToken` в опциях или per-call `allowClearKeyDRMToken`) добавляется в User-Agent всех медиа-запросов через options `AVURLAsset` — расшифровка потока для приложения прозрачна, дополнительный код не нужен.

### Тонкая настройка

`AdvancedPlayerOptions` — whitelisted-параметры: `preferredForwardBufferDuration`, `automaticallyWaitsToMinimizeStalling`, `preferredPeakBitRate`.

## BoomstreamOffline

### Механика

Системный стек `AVAssetDownloadURLSession` + `AVAssetDownloadTask`: фоновая загрузка с продолжением после сворачивания приложения, восстановление после перезапуска (`restoreTransfers()` переподключается к живым таскам background-сессии). По умолчанию — только Wi-Fi (`allowsCellularAccess: false`).

### API

`BoomstreamOfflineManager` (@MainActor, конформит `BoomstreamDownloads`): `start/pause/resume/cancel/delete`, `observe(mediaCode:)` и `observeAll()` (стримы `DownloadState`: `queued/inProgress/paused/completed/failed`), `stats()`, `purgeExpired()`.

### Персистенция

Локация скачанного ассета хранится как **bookmark data** (не сырой путь — контейнер приложения переезжает при backup/restore); реестр — JSON в Application Support. Протухший bookmark обновляется автоматически.

### Стык с плеером

`BoomstreamOfflineManager` реализует протокол `BoomstreamOfflineCache` (объявлен в `BoomstreamAPI`, чтобы player-таргет не зависел от offline-таргета). Плеер с параметром `offlineCache:` сначала проверяет локальную копию и играет её без сетевого запроса конфигурации.

### Ограничение: шифрованные потоки

Офлайн-загрузка шифрованных потоков в текущей версии недоступна. Перед созданием download-таска SDK выполняет preflight-проверку и, если поток не может быть корректно сохранён для офлайн-воспроизведения, завершает `start()` типизированной ошибкой `offlineUnavailable` — до скачивания сегментов, чтобы не оставлять на устройстве неиграбельные данные. Онлайн-воспроизведение шифрованных потоков работает без ограничений.

## Дистрибуция

- Только **Swift Package Manager**; версии — git-теги SemVer, все продукты выпускаются lockstep.
- CocoaPods не поддерживается и не планируется (CocoaPods trunk переходит в read-only режим).
- Публикуются исходники (source distribution) — бинарных артефактов и требований к подписи нет.

## Безопасность

- HTTPS enforced: базовые URL захардкожены `https://`; TLS-политика — системный ATS.
- API-ключ и токен доступа живут только в памяти процесса; на диск не пишутся, в логи не попадают (маскирование в `description`).
- Телеметрия отсутствует; сетевые запросы SDK ограничены доменами Boomstream, заданными в конфигурации.
