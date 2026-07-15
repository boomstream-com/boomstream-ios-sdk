import Foundation
import Testing
import BoomstreamAPI
@testable import BoomstreamOffline

@Test func downloadStateExposesMediaCodeForEveryCase() {
    let states: [DownloadState] = [
        .queued(mediaCode: "abc"),
        .inProgress(mediaCode: "abc", percent: 0.5, bytesDownloaded: 1024),
        .paused(mediaCode: "abc", percent: 0.5),
        .completed(mediaCode: "abc", sizeBytes: 2048, expiresAt: nil),
        .failed(mediaCode: "abc", error: .offlineUnavailable(reason: "test")),
    ]
    for state in states {
        #expect(state.mediaCode == "abc")
    }
}

@Test func downloadHandleEquality() {
    #expect(DownloadHandle(mediaCode: "x") == DownloadHandle(mediaCode: "x"))
    #expect(DownloadHandle(mediaCode: "x") != DownloadHandle(mediaCode: "y"))
}
