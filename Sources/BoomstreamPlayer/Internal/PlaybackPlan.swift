import Foundation
import BoomstreamAPI

struct PlayableItem: Equatable, Sendable {
    let title: String?
    let url: URL
}

/// Чистый резолв config → план воспроизведения. Вся ветвящаяся логика
/// (unauthorised/playlist/live-offline/records) здесь — тестируется без AVPlayer и сети.
enum PlaybackPlan: Equatable, Sendable {
    /// `shouldPoll` — live-трансляция офлайн: перепрашивать config c forceRefresh,
    /// пока оператор не опубликует эфир.
    case posterOnly(posterURL: URL?, message: String?, shouldPoll: Bool)
    case play(items: [PlayableItem], isPlaylist: Bool, isLive: Bool, systemMessage: String?)

    static func make(from config: ConfigResponse) -> PlaybackPlan {
        let configPoster = bestPoster(config.effectivePosters)
        switch config.media {
        case .unauthorised:
            return .posterOnly(posterURL: configPoster, message: restrictionMessage(config), shouldPoll: false)

        case .playlist(let list):
            let items = list.compactMap(playable(from:))
            guard !items.isEmpty else {
                return .posterOnly(posterURL: configPoster, message: restrictionMessage(config), shouldPoll: false)
            }
            return .play(items: items, isPlaylist: true, isLive: config.isLive, systemMessage: nil)

        case .authorised(let media):
            if media.isLiveOffline {
                // Эфир не опубликован: играем records как плейлист, иначе — постер + поллинг.
                let records = media.records.compactMap(playable(from:))
                if records.isEmpty {
                    let poster = bestPoster(media.posters.isEmpty ? config.effectivePosters : media.posters)
                    return .posterOnly(posterURL: poster, message: restrictionMessage(config), shouldPoll: true)
                }
                return .play(items: records, isPlaylist: records.count > 1, isLive: false, systemMessage: "live_offline_records")
            }
            guard let item = playable(from: media) else {
                return .posterOnly(posterURL: configPoster, message: restrictionMessage(config), shouldPoll: false)
            }
            return .play(items: [item], isPlaylist: false, isLive: media.isLive, systemMessage: nil)
        }
    }

    private static func playable(from media: MediaData) -> PlayableItem? {
        guard let url = media.links?.hlsURL else { return nil }
        return PlayableItem(title: media.title.isEmpty ? nil : media.title, url: url)
    }

    private static func bestPoster(_ posters: [Poster]) -> URL? {
        posters.max(by: { $0.width < $1.width })?.url
    }

    private static func restrictionMessage(_ config: ConfigResponse) -> String? {
        guard let restricted = config.accessRestricted else { return nil }
        return restricted.translate.isEmpty ? restricted.message : restricted.translate
    }
}
