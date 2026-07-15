# Changelog

## [0.1.0] — 2026-07-16

Первый публичный релиз.

### Added
- `BoomstreamPlayer`: плеер на AVFoundation — SwiftUI-view (`BoomstreamPlayerView` + `BoomstreamPlayerProxy`) и UIKit-обёртка (`BoomstreamPlayerUIView`); программное управление через `BoomstreamPlayerController` (play/pause/seek/volume/next/previous/fullscreen) со стримами состояний, событий и прогресса; встроенные контролы (тап по видео, seek-слайдер, prev/next для плейлистов, fullscreen с индикацией состояния, автоскрытие); плейлисты с авто-переходом; live-трансляции (постер + автозапуск после публикации эфира, записи офлайн-эфира, цветной индикатор статуса вместо таймлайна); poster-режим для медиа без доступа; воспроизведение защищённых потоков по токену доступа; `AdvancedPlayerOptions`.
- `BoomstreamOffline`: офлайн-загрузки HLS на background `AVAssetDownloadURLSession` — start/pause/resume/cancel/delete, наблюдение через `AsyncStream` (`observe`/`observeAll`), `stats`/`purgeExpired`, восстановление загрузок после перезапуска (`restoreTransfers`), bookmark-персистенция; стык с плеером через `BoomstreamOfflineCache` (локальная копия играет без сети). Загрузка шифрованных потоков в текущей версии недоступна — типизированная ошибка до начала скачивания.
- `BoomstreamAPI`: `Boomstream.configure` + `BoomstreamOptions`; клиент config-эндпоинта (полиморфный `mediaData`, декодирование ссылок, live-поля, кэш + `forceRefresh`); клиент Boomstream API (`listFolder`/`listLive`/`listPlaylists`, Bearer-авторизация); типизированная `BoomstreamError`; retry сетевых и 5xx-ошибок.
- Example app (`Example/`): вкладка «Медиа» (плеер, листинги видео/трансляций/плейлистов, офлайн-загрузка выбранного медиа) и вкладка «Player API» (программное управление, прогресс, лог событий); авто-fullscreen по повороту устройства; секреты через gitignored `Local.xcconfig`.
