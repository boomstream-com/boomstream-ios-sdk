import Foundation

/// Resolves built-in player UI strings by key and integrator-supplied locale.
/// Analogue of Android `BoomstreamMessages.resolve(key, locale)`.
/// Locale is set by the integrator via `AdvancedPlayerOptions.locale` — not derived from the system locale.
enum BoomstreamMessages {

    private static let table: [String: [String: String]] = [
        "settings_title":        ["en": "Settings",      "ru": "Настройки"],
        "settings_speed":        ["en": "Speed",         "ru": "Скорость"],
        "settings_audio":        ["en": "Audio",         "ru": "Аудио"],
        "settings_quality":      ["en": "Quality",       "ru": "Качество"],
        "settings_speed_normal": ["en": "Normal (1×)",   "ru": "Обычная (1×)"],
        "settings_quality_auto": ["en": "Auto",          "ru": "Авто"],
        "subtitles_title":         ["en": "Subtitles",     "ru": "Субтитры"],
        "subtitles_off":           ["en": "Off",           "ru": "Выкл"],
        "bsp_airplay_casting_to":  ["en": "Casting to",   "ru": "Трансляция на"],
        "bsp_airplay_casting_none": ["en": "Casting to TV", "ru": "Трансляция на ТВ"],
        "bsp_cast_not_allowed": [
            "en": "Casting is not available for this content",
            "ru": "Трансляция недоступна для этого контента",
        ],
    ]

    /// Returns the localized string for `key` in the given `locale` (ISO 639-1 code, e.g. "ru", "en").
    /// Only the first two characters are used, so "ru-RU" resolves as "ru".
    /// Falls back to "en" for unsupported locales; returns the key itself if the key is unknown.
    static func resolve(_ key: String, locale: String) -> String {
        let lang = String(locale.prefix(2)).lowercased()
        return table[key]?[lang] ?? table[key]?["en"] ?? key
    }
}
