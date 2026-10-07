import Foundation
import Testing
@testable import BoomstreamAPI

/// URLProtocol-мок. Статический handler защищён `.serialized`-режимом сьюта —
/// все сетевые тесты живут в одном сьюте и не бегут параллельно.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset(handler: ((URLRequest) throws -> (Int, Data))?) {
        self.handler = handler
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.recordedRequests.append(request)
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func mockedConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return configuration
}

private func makeConfigClient(token: String? = "tok") -> BoomstreamConfigClient {
    BoomstreamConfigClient(
        baseURL: URL(string: "https://play.boomstream.com/")!,
        userAgent: BoomstreamRegistry.effectiveUserAgent(options: BoomstreamOptions(userAgentToken: token)),
        userAgentToken: token,
        connectTimeout: 5,
        resourceTimeout: 10,
        retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0),
        sessionConfiguration: mockedConfiguration()
    )
}

private func makeAPIClient() -> BoomstreamAPIClient {
    BoomstreamAPIClient(
        baseURL: URL(string: "https://boomstream.com/")!,
        apiKey: "test-key",
        userAgent: "Boomstream iOS SDK test",
        connectTimeout: 5,
        resourceTimeout: 10,
        retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0),
        sessionConfiguration: mockedConfiguration()
    )
}

/// Читает тело POST-запроса (URLProtocol отдаёт его стримом, не `httpBody`).
private func bodyData(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private let configFixture = Data("""
{"code": "abc123", "mediaData": {"title": "T", "code": "abc123"}, "mediaType": "media"}
""".utf8)

/// Config-ответ с подписанной HLS-ссылкой, у конверта которой задан `exp`.
private func signedConfigFixture(exp: TimeInterval) -> Data {
    let envelope = Data("""
    {"use_direct_links":"yes","is_encrypt":"yes","exp":\(Int(exp)),"intent":"stream","keys":"url"}
    """.utf8).base64EncodedString()
    let signedURL = "https://node.boomstream.com/adaptive/sign:abc/data:\(envelope)/abc123/playlist.m3u8"
    let hls = Data(signedURL.utf8).base64EncodedString()
    return Data("""
    {"code": "abc123", "mediaData": {"title": "T", "code": "abc123", "links": {"hls": "\(hls)"}}, "mediaType": "media"}
    """.utf8)
}

@Suite(.serialized)
struct NetworkClientTests {

    @Test func configClientSendsUserAgentAndCaches() async throws {
        MockURLProtocol.reset { request in
            #expect(request.url?.absoluteString == "https://play.boomstream.com/abc123/config")
            return (200, configFixture)
        }
        let client = makeConfigClient(token: "tok")

        let first = try await client.fetchConfig(mediaCode: "abc123")
        _ = try await client.fetchConfig(mediaCode: "abc123")

        #expect(first.mediaDataSingle?.title == "T")
        // второй вызов — из кэша, сеть один раз
        #expect(MockURLProtocol.recordedRequests.count == 1)
        let ua = MockURLProtocol.recordedRequests[0].value(forHTTPHeaderField: "User-Agent")
        #expect(ua == "Boomstream iOS SDK v\(BoomstreamSDKInfo.version) tok")
        // config-эндпоинт без авторизации
        #expect(MockURLProtocol.recordedRequests[0].value(forHTTPHeaderField: "Authorization") == nil)
        // медиасервер выбирает платформенную доставку по x-platform (паритет с Android)
        #expect(MockURLProtocol.recordedRequests[0].value(forHTTPHeaderField: "x-platform") == "ios")
    }

    @Test func forceRefreshBypassesCache() async throws {
        MockURLProtocol.reset { _ in (200, configFixture) }
        let client = makeConfigClient()

        _ = try await client.fetchConfig(mediaCode: "abc123")
        _ = try await client.fetchConfig(mediaCode: "abc123", forceRefresh: true)

        #expect(MockURLProtocol.recordedRequests.count == 2)
    }

    @Test func signedLinkNearExpiryEvictsConfigCache() async throws {
        // exp внутри страховочного зазора кэша → запись считается протухшей,
        // повторный fetch идёт в сеть (иначе плеер получит гарантированный отказ).
        MockURLProtocol.reset { _ in (200, signedConfigFixture(exp: Date().timeIntervalSince1970 + 30)) }
        let client = makeConfigClient()

        _ = try await client.fetchConfig(mediaCode: "abc123")
        _ = try await client.fetchConfig(mediaCode: "abc123")

        #expect(MockURLProtocol.recordedRequests.count == 2)
    }

    @Test func signedLinkFreshExpiryServedFromCache() async throws {
        MockURLProtocol.reset { _ in (200, signedConfigFixture(exp: Date().timeIntervalSince1970 + 3600)) }
        let client = makeConfigClient()

        _ = try await client.fetchConfig(mediaCode: "abc123")
        _ = try await client.fetchConfig(mediaCode: "abc123")

        #expect(MockURLProtocol.recordedRequests.count == 1)
    }

    @Test func castLinkSuccessDecodesBase64Link() async throws {
        let link = "https://node.boomstream.com/adaptive/sign:x/data:y/abc123/playlist.m3u8"
        let b64 = Data(link.utf8).base64EncodedString()
        MockURLProtocol.reset { request in
            #expect(request.url?.absoluteString == "https://play.boomstream.com/api/cast/link?entity=abc123")
            // Авторизация эндпоинта — те же заголовки, что у config.
            #expect(request.value(forHTTPHeaderField: "x-platform") == "ios")
            return (200, Data("{\"code\":200,\"data\":{\"link\":\"\(b64)\"}}".utf8))
        }
        let client = makeConfigClient(token: "tok")

        let url = try await client.fetchCastLink(mediaCode: "abc123")

        #expect(url.absoluteString == link)
    }

    @Test func castLinkDenialPreservesReason() async {
        MockURLProtocol.reset { _ in
            (403, Data("{\"code\":403,\"data\":{\"reason\":\"cast_not_allowed\"}}".utf8))
        }
        let client = makeConfigClient()

        await #expect(throws: BoomstreamCastLinkError(reason: .castNotAllowed, rawReason: "cast_not_allowed")) {
            _ = try await client.fetchCastLink(mediaCode: "abc123")
        }
    }

    @Test func castLinkUnknownReasonMapsToOther() async {
        MockURLProtocol.reset { _ in
            (423, Data("{\"code\":423,\"data\":{\"reason\":\"zero_balance\"}}".utf8))
        }
        let client = makeConfigClient()

        await #expect(throws: BoomstreamCastLinkError(reason: .other, rawReason: "zero_balance")) {
            _ = try await client.fetchCastLink(mediaCode: "abc123")
        }
    }

    @Test func config404MapsToMediaNotFound() async {
        MockURLProtocol.reset { _ in (404, Data()) }
        let client = makeConfigClient()

        await #expect {
            _ = try await client.fetchConfig(mediaCode: "missing")
        } throws: { error in
            if case .mediaNotFound(let mediaCode) = error as? BoomstreamError {
                return mediaCode == "missing"
            }
            return false
        }
    }

    @Test func retryOn500ThenSucceeds() async throws {
        MockURLProtocol.reset { _ in
            // первый запрос — 500, второй — успех
            MockURLProtocol.recordedRequests.count <= 1 ? (500, Data()) : (200, configFixture)
        }
        let client = makeConfigClient()

        let config = try await client.fetchConfig(mediaCode: "abc123")

        #expect(config.code == "abc123")
        #expect(MockURLProtocol.recordedRequests.count == 2)
    }

    @Test func apiClientSendsBearerAndModeTwoBody() async throws {
        MockURLProtocol.reset { request in
            #expect(request.url?.absoluteString == "https://boomstream.com/api/media/folder")
            #expect(request.httpMethod == "POST")
            return (200, Data("""
            {"countTotal": 1, "Medias": [{"Code": "m1", "Title": "V", "Duration": 46, "Poster": {"Url": "https://cdn.example.com/x.jpg"}}]}
            """.utf8))
        }
        let client = makeAPIClient()

        let items = try await client.listFolder(folderCode: "folder1")

        #expect(items == [FolderMediaItem(code: "m1", title: "V", duration: 46, poster: "https://cdn.example.com/x.jpg", mediaStatus: nil)])
        let request = MockURLProtocol.recordedRequests[0]
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode([String: String].self, from: bodyData(of: request))
        #expect(body == ["ver": "1.2", "code": "folder1"])
    }

    @Test func rootFolderRequestOmitsCode() async throws {
        MockURLProtocol.reset { _ in (200, Data(#"{"countTotal": 0, "Medias": []}"#.utf8)) }
        let client = makeAPIClient()

        _ = try await client.listFolder()

        let body = try JSONDecoder().decode([String: String].self, from: bodyData(of: MockURLProtocol.recordedRequests[0]))
        #expect(body == ["ver": "1.2"])
    }

    @Test func statusFailedThrowsApiError() async {
        MockURLProtocol.reset { _ in
            (200, Data(#"{"Status": "Failed", "Message": "Invalid API key"}"#.utf8))
        }
        let client = makeAPIClient()

        await #expect {
            _ = try await client.listLive()
        } throws: { error in
            if case .apiError(let message) = error as? BoomstreamError {
                return message == "Invalid API key"
            }
            return false
        }
    }

    @Test func playlistDurationMillisecondsStringMapsToSeconds() async throws {
        MockURLProtocol.reset { request in
            #expect(request.url?.absoluteString == "https://boomstream.com/api/playlist/list")
            return (200, Data("""
            {"Items": [{"Code": "uLmWi9IB", "Name": "Commercials", "Duration": "244000", "Poster": {"Url": "https://cdn.example.com/p.jpg"}}], "Status": "Success"}
            """.utf8))
        }
        let client = makeAPIClient()

        let items = try await client.listPlaylists()

        #expect(items == [PlaylistItem(code: "uLmWi9IB", name: "Commercials", durationSeconds: 244, poster: "https://cdn.example.com/p.jpg")])
    }

    @Test func api401MapsToUnauthorised() async {
        MockURLProtocol.reset { _ in (401, Data()) }
        let client = makeAPIClient()

        await #expect {
            _ = try await client.listFolder()
        } throws: { error in
            if case .unauthorised = error as? BoomstreamError { return true }
            return false
        }
    }
}
