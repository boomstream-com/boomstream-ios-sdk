import Foundation
import Testing
@testable import BoomstreamPlayer

// MARK: - English keys

@Test func messagesEnglishAllKeys() {
    #expect(BoomstreamMessages.resolve("settings_title",        locale: "en") == "Settings")
    #expect(BoomstreamMessages.resolve("settings_speed",        locale: "en") == "Speed")
    #expect(BoomstreamMessages.resolve("settings_audio",        locale: "en") == "Audio")
    #expect(BoomstreamMessages.resolve("settings_quality",      locale: "en") == "Quality")
    #expect(BoomstreamMessages.resolve("settings_speed_normal", locale: "en") == "Normal (1×)")
    #expect(BoomstreamMessages.resolve("settings_quality_auto", locale: "en") == "Auto")
    #expect(BoomstreamMessages.resolve("subtitles_title",       locale: "en") == "Subtitles")
    #expect(BoomstreamMessages.resolve("subtitles_off",         locale: "en") == "Off")
}

// MARK: - Russian keys

@Test func messagesRussianAllKeys() {
    #expect(BoomstreamMessages.resolve("settings_title",        locale: "ru") == "Настройки")
    #expect(BoomstreamMessages.resolve("settings_speed",        locale: "ru") == "Скорость")
    #expect(BoomstreamMessages.resolve("settings_audio",        locale: "ru") == "Аудио")
    #expect(BoomstreamMessages.resolve("settings_quality",      locale: "ru") == "Качество")
    #expect(BoomstreamMessages.resolve("settings_speed_normal", locale: "ru") == "Обычная (1×)")
    #expect(BoomstreamMessages.resolve("settings_quality_auto", locale: "ru") == "Авто")
    #expect(BoomstreamMessages.resolve("subtitles_title",       locale: "ru") == "Субтитры")
    #expect(BoomstreamMessages.resolve("subtitles_off",         locale: "ru") == "Выкл")
}

// MARK: - Fallback to English for unsupported locale

@Test func messagesFallbackToEnglishForUnsupportedLocale() {
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "de") == "Speed")
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "fr") == "Speed")
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "xx") == "Speed")
    #expect(BoomstreamMessages.resolve("settings_quality_auto", locale: "ja") == "Auto")
}

// MARK: - Unknown key returns the key itself

@Test func messagesUnknownKeyReturnsKey() {
    #expect(BoomstreamMessages.resolve("unknown_key",          locale: "en") == "unknown_key")
    #expect(BoomstreamMessages.resolve("missing_translation",  locale: "ru") == "missing_translation")
}

// MARK: - Locale subtag normalization ("ru-RU" → "ru", "en-US" → "en")

@Test func messagesLocaleSubtagNormalized() {
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "ru-RU") == "Скорость")
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "en-US") == "Speed")
    #expect(BoomstreamMessages.resolve("settings_speed", locale: "en-GB") == "Speed")
}

// MARK: - AdvancedPlayerOptions.locale default

@Test func advancedOptionsLocaleDefaultsToEnglish() {
    let opts = AdvancedPlayerOptions()
    #expect(opts.locale == "en")
}

@Test func advancedOptionsLocaleRoundtrip() {
    let opts = AdvancedPlayerOptions(locale: "ru")
    #expect(opts.locale == "ru")
}
