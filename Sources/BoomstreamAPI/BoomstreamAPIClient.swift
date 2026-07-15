import Foundation

/// Type-safe клиент Boomstream API (`{apiBaseURL}api/...`, default `https://boomstream.com/`).
///
/// Контракт: Mode 2 (POST + JSON body), аутентификация `Authorization: Bearer` —
/// добавляется прозрачно, ключ передаётся один раз в `Boomstream.configure`.
/// Экземпляр — через `Boomstream.api`.
public final class BoomstreamAPIClient: Sendable {
    private let http: BoomstreamHTTPClient
    private let baseURL: URL

    init(
        baseURL: URL,
        apiKey: String,
        userAgent: String,
        connectTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.baseURL = baseURL
        self.http = BoomstreamHTTPClient(
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "User-Agent": userAgent,
            ],
            connectTimeout: connectTimeout,
            resourceTimeout: resourceTimeout,
            retryPolicy: retryPolicy,
            sessionConfiguration: sessionConfiguration
        )
    }

    /// Медиа из папки видеотеки: `POST api/media/folder`. `folderCode == nil` — корень.
    /// Возвращаются только медиа-записи (без подпапок).
    public func listFolder(folderCode: String? = nil) async throws -> [FolderMediaItem] {
        let response: FolderAPIResponse = try await http.postJSON(
            baseURL.appendingPathComponent("api/media/folder"),
            body: FolderAPIRequest(code: folderCode),
            errorPath: "api/media/folder"
        )
        if response.status == "Failed" {
            throw BoomstreamError.apiError(message: response.message ?? "API error")
        }
        return response.medias.map {
            FolderMediaItem(
                code: $0.code,
                title: $0.title,
                duration: $0.duration,
                poster: $0.poster?.url,
                mediaStatus: $0.mediaStatus
            )
        }
    }

    /// Live-трансляции: `POST api/live/folder`. `folderCode == nil` — корень.
    public func listLive(folderCode: String? = nil) async throws -> [LiveMediaItem] {
        let response: LiveFolderAPIResponse = try await http.postJSON(
            baseURL.appendingPathComponent("api/live/folder"),
            body: FolderAPIRequest(code: folderCode),
            errorPath: "api/live/folder"
        )
        if response.status == "Failed" {
            throw BoomstreamError.apiError(message: response.message ?? "API error")
        }
        return response.medias.map {
            LiveMediaItem(code: $0.code, title: $0.title, poster: $0.poster?.url)
        }
    }

    /// Плейлисты аккаунта: `POST api/playlist/list`.
    public func listPlaylists() async throws -> [PlaylistItem] {
        let response: PlaylistListAPIResponse = try await http.postJSON(
            baseURL.appendingPathComponent("api/playlist/list"),
            body: FolderAPIRequest(),
            errorPath: "api/playlist/list"
        )
        if response.status == "Failed" {
            throw BoomstreamError.apiError(message: response.message ?? "API error")
        }
        return response.items.map {
            PlaylistItem(
                code: $0.code,
                name: $0.name,
                durationSeconds: Int($0.durationMs).map { $0 / 1000 } ?? 0,
                poster: $0.poster?.url
            )
        }
    }
}
