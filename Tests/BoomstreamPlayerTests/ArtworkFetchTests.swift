import AVFoundation
import Foundation
import Testing
@testable import BoomstreamPlayer

// MARK: - artworkDataType magic-byte sniffing (pure, no I/O, parallel-safe)

@Test func artworkDataType_jpegMagicBytes_returnsJPEGDataType() {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) // JFIF header
    let result = BoomstreamPlayerCore.artworkDataType(from: jpeg)
    #expect(result == kCMMetadataBaseDataType_JPEG as String)
}

@Test func artworkDataType_pngMagicBytes_returnsNil() {
    // PNG: 89 50 4E 47 0D 0A 1A 0A — should NOT return JPEG; nil = AVFoundation probes.
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    #expect(BoomstreamPlayerCore.artworkDataType(from: png) == nil)
}

@Test func artworkDataType_webpBytes_returnsNil() {
    let webp = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
    #expect(BoomstreamPlayerCore.artworkDataType(from: webp) == nil)
}

@Test func artworkDataType_emptyData_returnsNilWithoutCrash() {
    #expect(BoomstreamPlayerCore.artworkDataType(from: Data()) == nil)
}

@Test func artworkDataType_twoByteData_returnsNilWithoutCrash() {
    #expect(BoomstreamPlayerCore.artworkDataType(from: Data([0xFF, 0xD8])) == nil)
}

// MARK: - fetchArtworkData HTTP status guard
//
// URLProtocol handler is static state — tests must be .serialized to avoid races.

/// URLProtocol mock for artwork fetch tests. Static handler protected by .serialized suite.
private final class ArtworkMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = ArtworkMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func artworkMockSession(status: Int, body: Data = Data()) -> URLSession {
    ArtworkMockURLProtocol.handler = { _ in (status, body) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ArtworkMockURLProtocol.self]
    return URLSession(configuration: config)
}

private let posterURL = URL(string: "https://cdn.example.com/poster.jpg")!

@Suite(.serialized)
struct FetchArtworkDataTests {
    @Test func http200_returnsData() async {
        let payload = Data([0xFF, 0xD8, 0xFF, 0x00])
        let session = artworkMockSession(status: 200, body: payload)
        let result = await BoomstreamPlayerCore.fetchArtworkData(from: posterURL, session: session)
        #expect(result == payload)
    }

    @Test func http404_returnsNil() async {
        let session = artworkMockSession(status: 404, body: Data("<html>Not Found</html>".utf8))
        let result = await BoomstreamPlayerCore.fetchArtworkData(from: posterURL, session: session)
        #expect(result == nil)
    }

    @Test func http301_returnsNil() async {
        let session = artworkMockSession(status: 301)
        let result = await BoomstreamPlayerCore.fetchArtworkData(from: posterURL, session: session)
        #expect(result == nil)
    }

    @Test func http500_returnsNil() async {
        let session = artworkMockSession(status: 500, body: Data("Internal Server Error".utf8))
        let result = await BoomstreamPlayerCore.fetchArtworkData(from: posterURL, session: session)
        #expect(result == nil)
    }
}
