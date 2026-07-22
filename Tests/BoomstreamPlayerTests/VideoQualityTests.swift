import Foundation
import Testing
@testable import BoomstreamPlayer

// MARK: - VideoQuality model

@Test func videoQualityAutoLabel() {
    #expect(VideoQuality.auto.label == "Auto")
    #expect(VideoQuality.auto.description == "Auto")
    #expect(VideoQuality.auto.height == nil)
}

@Test func videoQualityResolutionDefaultLabel() {
    let q = VideoQuality.resolution(height: 1080)
    #expect(q.label == "1080p")
    #expect(q.height == 1080)
}

@Test func videoQualityResolutionCustomLabel() {
    let q = VideoQuality.resolution(height: 1080, peakBitRate: nil, label: "HD")
    #expect(q.label == "HD")
}

@Test func videoQualityEquatable() {
    #expect(VideoQuality.auto == .auto)
    #expect(VideoQuality.resolution(height: 720) == .resolution(height: 720))
    #expect(VideoQuality.resolution(height: 1080) != .resolution(height: 720))
    #expect(VideoQuality.resolution(height: 720) != .auto)
    // peakBitRate and label don't affect equality (same height = same quality slot)
    #expect(VideoQuality.resolution(height: 720, peakBitRate: 2_000_000) == .resolution(height: 720, peakBitRate: 1_000_000))
}

@Test func videoQualityHashable() {
    let set: Set<VideoQuality> = [.auto, .resolution(height: 720), .resolution(height: 1080), .auto]
    #expect(set.count == 3)
}

// MARK: - HLSVariantParser

private let sampleMaster = """
#EXTM3U
#EXT-X-VERSION:3

#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.42e01e,mp4a.40.2"
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
1080p/index.m3u8
"""

@Test func hlsParserExtractsVariants() {
    let qualities = HLSVariantParser.parse(master: sampleMaster)
    #expect(qualities.count == 3)
    let heights = qualities.compactMap(\.height).sorted(by: >)
    #expect(heights == [1080, 720, 360])
}

@Test func hlsParserSortsByHeightDescending() {
    let qualities = HLSVariantParser.parse(master: sampleMaster)
    let heights = qualities.compactMap(\.height)
    #expect(heights == heights.sorted(by: >))
}

@Test func hlsParserDeduplicatesByHeight() {
    let manifest = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
    720p-low/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
    720p-high/index.m3u8
    """
    let qualities = HLSVariantParser.parse(master: manifest)
    // Two streams with same height → one VideoQuality, highest bandwidth kept
    #expect(qualities.count == 1)
    if case .resolution(_, let bps, _) = qualities.first {
        #expect(bps == 2_500_000)
    }
}

@Test func hlsParserHandlesSingleRendition() {
    let manifest = """
    #EXTM3U
    #EXT-X-TARGETDURATION:10
    #EXTINF:10.0,
    segment0.ts
    """
    // No EXT-X-STREAM-INF lines → returns empty (single-rendition playlist, not master)
    let qualities = HLSVariantParser.parse(master: manifest)
    #expect(qualities.isEmpty)
}

@Test func hlsParserExtractsPeakBitRate() {
    let qualities = HLSVariantParser.parse(master: sampleMaster)
    let q1080 = qualities.first { $0.height == 1080 }
    if case .resolution(_, let bps, _) = q1080 {
        #expect(bps == 5_000_000)
    } else {
        Issue.record("Expected .resolution for 1080p")
    }
}

// MARK: - Core quality API (unit)

@MainActor
@Test func coreDefaultQualityIsAuto() {
    let core = BoomstreamPlayerCore()
    #expect(core.preferredQuality == .auto)
    #expect(core.currentQuality == .auto)
    #expect(core.availableQualities.isEmpty)
    core.release()
}

@MainActor
@Test func coreSetQualityUpdatesState() {
    let core = BoomstreamPlayerCore()
    core.setQuality(.resolution(height: 720))
    #expect(core.preferredQuality == .resolution(height: 720))
    #expect(core.currentQuality == .resolution(height: 720))
    core.selectAuto()
    #expect(core.preferredQuality == .auto)
    #expect(core.currentQuality == .auto)
    core.release()
}
