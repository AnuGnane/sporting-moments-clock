import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MomentsCore

/// Writes a plain JPEG of the given pixel size.
func writeJPEG(width: Int, height: Int, to url: URL) throws {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite("Clock model")
@MainActor
struct ClockModelTests {
    let london = Fixtures.calendar("Europe/London")
    let credit = "Photo: Someone · CC BY 2.0 · Wikimedia Commons"

    /// Waits for photo loading to finish (decoding a small JPEG takes a few milliseconds).
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    @Test func theLatestRequestWinsEvenWhenItIsTheCardOnScreen() async throws {
        let folder = try TemporaryFolder()
        try writeJPEG(width: 64, height: 40, to: folder.url.appending(path: "B.jpg"))
        let a = Fixtures.moment("A", at: "2000-01-01T12:00")
        let b = Fixtures.moment("B", at: "2000-01-01T12:01", image: MomentImage(file: "B.jpg", credit: credit))
        let model = ClockModel(store: MomentStore(moments: [a, b], imagesDirectory: folder.url), settings: ClockSettings())
        model.calendar = london

        model.demoDate = Fixtures.date(2026, 11, 20, 12, 0, in: london)
        #expect(model.card?.moment.id == "A")
        // Ask for B (its photo starts loading), then straight back to A, which is still on screen.
        model.demoDate = Fixtures.date(2026, 11, 20, 12, 1, in: london)
        model.demoDate = Fixtures.date(2026, 11, 20, 12, 0, in: london)
        try await settle()
        #expect(model.card?.moment.id == "A")
        #expect(model.photo == nil)
    }

    @Test func aPhotoCardShowsWithItsPhoto() async throws {
        let folder = try TemporaryFolder()
        try writeJPEG(width: 64, height: 40, to: folder.url.appending(path: "B.jpg"))
        let b = Fixtures.moment("B", at: "2000-01-01T12:01", image: MomentImage(file: "B.jpg", credit: credit))
        let model = ClockModel(store: MomentStore(moments: [b], imagesDirectory: folder.url), settings: ClockSettings())
        model.calendar = london
        model.demoDate = Fixtures.date(2026, 11, 20, 12, 1, in: london)
        try await settle()
        #expect(model.card?.moment.id == "B")
        #expect(model.photo?.width == 64)
    }

    @Test func anUnreadablePhotoGivesATypeOnlyCard() async throws {
        let folder = try TemporaryFolder()
        try Data("not a jpeg".utf8).write(to: folder.url.appending(path: "B.jpg"))
        let b = Fixtures.moment("B", at: "2000-01-01T12:01", image: MomentImage(file: "B.jpg", credit: credit))
        let model = ClockModel(store: MomentStore(moments: [b], imagesDirectory: folder.url), settings: ClockSettings())
        model.calendar = london
        model.demoDate = Fixtures.date(2026, 11, 20, 12, 1, in: london)
        try await settle()
        #expect(model.card?.moment.id == "B")
        #expect(model.photo == nil)  // so the view draws the type backdrop and no credit
    }

    @Test func stoppingDropsAPhotoStillLoading() async throws {
        let folder = try TemporaryFolder()
        try writeJPEG(width: 64, height: 40, to: folder.url.appending(path: "B.jpg"))
        let b = Fixtures.moment("B", at: "2000-01-01T12:01", image: MomentImage(file: "B.jpg", credit: credit))
        let model = ClockModel(store: MomentStore(moments: [b], imagesDirectory: folder.url), settings: ClockSettings())
        model.calendar = london
        model.demoDate = Fixtures.date(2026, 11, 20, 12, 1, in: london)
        model.stop()
        try await settle()
        #expect(model.card == nil)
    }

    /// In viewer mode a kept card's time is a minute in the old zone. After the Mac's time zone
    /// changes, the clock picks again for the new zone instead of keeping it.
    @Test func aTimeZoneChangePicksAfresh() throws {
        // 12:00 UTC on 1 July 2000: 13:00 in London (summer time), 21:00 in Tokyo.
        let moment = Fixtures.moment("M1", at: "2000-07-01T13:00", zone: "Europe/London")
        let model = ClockModel(store: MomentStore(moments: [moment]), settings: ClockSettings(timeMode: .viewer))
        model.calendar = london
        // 13:00 in London in November is 13:00 UTC: 22:00 in Tokyo, where nothing matches.
        model.demoDate = Fixtures.date(2026, 11, 20, 13, 0, in: london)
        #expect(model.card?.time == "13:00")

        model.calendar = Fixtures.calendar("Asia/Tokyo")
        model.tick()
        // Walked back to 21:00 Tokyo time rather than keeping "13:00", a London minute.
        let card = try #require(model.card)
        #expect(card.time == "21:00")
        #expect(card.headline(clock: "22:00") == "Around 21:00 your time · 13:00 in London")
    }

    @Test func aKeptCardStaysWhenTheZoneIsUnchanged() {
        let moment = Fixtures.moment("M1", at: "2000-07-01T13:00", zone: "Europe/London")
        let model = ClockModel(store: MomentStore(moments: [moment]), settings: ClockSettings())
        model.calendar = london
        model.demoDate = Fixtures.date(2026, 11, 20, 13, 0, in: london)
        let shown = model.card
        model.tick()
        #expect(model.card == shown)
    }
}

@Suite("Photo decoding")
struct PhotoLoaderTests {
    @Test func decodesJustLargeEnoughToFillTheTarget() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "wide.jpg")
        try writeJPEG(width: 2000, height: 1000, to: url)
        // A square 400 px target: the height limits, so 800 x 400 covers it.
        let small = try #require(PhotoLoader.decode(url, filling: CGSize(width: 400, height: 400)))
        #expect(small.width == 800 && small.height == 400)
        // A thumbnail sized target decodes a thumbnail sized image.
        let thumbnail = try #require(PhotoLoader.decode(url, filling: CGSize(width: 300, height: 188)))
        #expect(thumbnail.width <= 400)
        // Never enlarged beyond the original.
        let large = try #require(PhotoLoader.decode(url, filling: CGSize(width: 6000, height: 4000)))
        #expect(large.width == 2000 && large.height == 1000)
    }

    @Test func aPortraitPhotoCoversALandscapeScreen() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "tall.jpg")
        try writeJPEG(width: 1000, height: 2000, to: url)
        let image = try #require(PhotoLoader.decode(url, filling: CGSize(width: 800, height: 500)))
        #expect(image.width == 800 && image.height == 1600)
    }

    @Test func missingOrBrokenFilesGiveNil() throws {
        let folder = try TemporaryFolder()
        #expect(PhotoLoader.decode(folder.url.appending(path: "missing.jpg"), filling: CGSize(width: 100, height: 100)) == nil)
        let broken = folder.url.appending(path: "broken.jpg")
        try Data("not a jpeg".utf8).write(to: broken)
        #expect(PhotoLoader.decode(broken, filling: CGSize(width: 100, height: 100)) == nil)
    }
}
