# Changelog

Формат следует [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Проект придерживается [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — 2026-07-22

### Added

- **Выбор качества видео** (`BoomstreamPlayer`) — плеер отдаёт варианты качества, обнаруженные
  в HLS master-манифесте, для программного переключения. Новое в `BoomstreamPlayerController`:
  - `availableQualities: [VideoQuality]` — заполняется после готовности плеера, сортировка от
    большего разрешения к меньшему, сбрасывается на каждой смене медиа.
  - `currentQuality` / `preferredQuality: VideoQuality` — применённое и запрошенное качество
    (`.auto` по умолчанию).
  - `qualityUpdates: AsyncStream<[VideoQuality]>` — стрим обновлений списка вариантов.
  - `setQuality(_ quality: VideoQuality)` — ограничивает воспроизведение выбранным вариантом;
    переключение живое, без перезагрузки и потери позиции, сохраняется при смене трека плейлиста.
  - `selectAuto()` — снимает ограничение и возвращает адаптивный выбор.
- **`VideoQuality`** — публичный enum без AVFoundation-типов: `.auto` /
  `.resolution(height:peakBitRate:label:)` с UI-готовым `label` («1080p», «Auto»); покрыт
  reflection-тестом публичной поверхности.
- **`AdvancedPlayerOptions.showQualitySelector`** — opt-in флаг (по умолчанию `false`):
  кнопка выбора качества в встроенных контролах плеера (action sheet со списком вариантов + Auto).
  При `false` доступен только программный API. Демо — в Example, вкладка «Player API».

---

## [0.1.1] — 2026-07-16

### Fixed
- Example app: контейнер fullscreen-плеера корректно масштабируется при повороте устройства в открытом fullscreen.

### Changed
- README: бейджи License / Platform / Swift / SPM.

## [0.1.0] — 2026-07-16

Первый публичный релиз.

### Added
- `BoomstreamPlayer`: плеер на AVFoundation — SwiftUI-view (`BoomstreamPlayerView` + `BoomstreamPlayerProxy`) и UIKit-обёртка (`BoomstreamPlayerUIView`); программное управление через `BoomstreamPlayerController` (play/pause/seek/volume/next/previous/fullscreen) со стримами состояний, событий и прогресса; встроенные контролы (тап по видео, seek-слайдер, prev/next для плейлистов, fullscreen с индикацией состояния, автоскрытие); плейлисты с авто-переходом; live-трансляции (постер + автозапуск после публикации эфира, записи офлайн-эфира, цветной индикатор статуса вместо таймлайна); poster-режим для медиа без доступа; воспроизведение защищённых потоков по токену доступа; `AdvancedPlayerOptions`.
- `BoomstreamOffline`: офлайн-загрузки HLS на background `AVAssetDownloadURLSession` — start/pause/resume/cancel/delete, наблюдение через `AsyncStream` (`observe`/`observeAll`), `stats`/`purgeExpired`, восстановление загрузок после перезапуска (`restoreTransfers`), bookmark-персистенция; стык с плеером через `BoomstreamOfflineCache` (локальная копия играет без сети). Загрузка шифрованных потоков в текущей версии недоступна — типизированная ошибка до начала скачивания.
- `BoomstreamAPI`: `Boomstream.configure` + `BoomstreamOptions`; клиент config-эндпоинта (полиморфный `mediaData`, декодирование ссылок, live-поля, кэш + `forceRefresh`); клиент Boomstream API (`listFolder`/`listLive`/`listPlaylists`, Bearer-авторизация); типизированная `BoomstreamError`; retry сетевых и 5xx-ошибок.
- Example app (`Example/`): вкладка «Медиа» (плеер, листинги видео/трансляций/плейлистов, офлайн-загрузка выбранного медиа) и вкладка «Player API» (программное управление, прогресс, лог событий); авто-fullscreen по повороту устройства; секреты через gitignored `Local.xcconfig`.
