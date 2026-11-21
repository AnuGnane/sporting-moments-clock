import CoreGraphics
import Testing
@testable import MomentsCore

@Suite("Sport backdrops")
struct SportBackdropTests {
    /// Every sport value in moments.json today, with the motif it should get.
    @Test(arguments: [
        ("Football", SportMotif.pitch),
        ("Athletics", .track),
        ("Swimming", .pool),
        ("Speed skating", .skatingOval),
        ("Tennis", .tennisCourt),
        ("Baseball", .diamond),
        ("Track cycling", .velodrome),
        ("Cricket", .cricketGround),
        ("Rowing", .rowingCourse),
        ("Motor racing", .racingCircuit),
        ("Alpine skiing", .contours),
        ("Horse racing", .racecourse),
        ("Boxing", .boxingRing),
        ("Golf", .golfGreen),
        ("Triathlon", .openWater),
        ("American football", .gridiron),
        ("Ice hockey", .rink),
        ("Rugby union", .rugbyPitch),
        ("Basketball", .basketballCourt),
        ("Ultrarunning", .routeProfile),
        ("Sailing", .openWater),
        ("Olympics", .dial),
        ("Cycling", .routeProfile),
        ("Snooker", .snookerTable),
        ("Climbing", .contours),
        ("Gymnastics", .dial),
        ("Darts", .dial),
        ("Squash", .dial),
        ("Open water swimming", .openWater),
    ])
    func sportMapsToMotif(sport: String, motif: SportMotif) {
        #expect(SportMotif(sport: sport) == motif)
    }

    @Test func unknownAndEmptySportsFallBackToTheDial() {
        #expect(SportMotif(sport: "Curling") == .dial)
        #expect(SportMotif(sport: "") == .dial)
        #expect(SportMotif(sport: "   ") == .dial)
    }

    @Test func matchingIgnoresCaseAndSpacing() {
        #expect(SportMotif(sport: "  FOOTBALL ") == .pitch)
        #expect(SportMotif(sport: "speed   skating") == .skatingOval)
        #expect(SportMotif(sport: "rugby league") == .rugbyPitch)
    }

    @Test func narrowerNamesWinOverBroaderOnes() {
        #expect(SportMotif(sport: "Table tennis") == .dial)
        #expect(SportMotif(sport: "Australian football") == .dial)
        #expect(SportMotif(sport: "American football") == .gridiron)
        #expect(SportMotif(sport: "Track cycling") == .velodrome)
        #expect(SportMotif(sport: "Road cycling") == .routeProfile)
        #expect(SportMotif(sport: "Open water swimming") == .openWater)
    }

    /// The big sports must never fall through to the generic dial, whatever the data holds.
    @Test func everySportWithFiveOrMoreMomentsHasItsOwnMotif() {
        var counts: [String: Int] = [:]
        for moment in Fixtures.bundledStore.moments { counts[moment.sport, default: 0] += 1 }
        let generic = counts.filter { $0.value >= 5 && $0.key != "Olympics" && SportMotif(sport: $0.key) == .dial }
        #expect(generic.isEmpty, "these sports draw only the dial: \(generic.keys.sorted())")
    }

    @Test func seedIsStableAcrossLaunches() {
        // FNV-1a 64: a fixed value, unlike Swift's per process Hasher.
        #expect(backdropSeed("M0001") == 0xc176_2368_14d6_d5eb)
        #expect(backdropSeed("M0001") == backdropSeed("M0001"))
        #expect(backdropSeed("M0001") != backdropSeed("M0002"))
    }

    @Test func variationIsDeterministicAndSmall() {
        let ids = Fixtures.bundledStore.moments.prefix(200).map(\.id)
        for id in ids {
            let a = BackdropVariation(seed: backdropSeed(id)), b = BackdropVariation(seed: backdropSeed(id))
            #expect(a == b)
            #expect(abs(a.dx) <= 0.025 && abs(a.dy) <= 0.02)
            #expect(a.zoom >= 0.95 && a.zoom <= 1.06)
        }
        #expect(Set(ids.map { BackdropVariation(seed: backdropSeed($0)).zoom }).count > 100, "cards vary")
    }

    @Test func tallCardsDrawTheMotifInALandscapeBand() {
        let wide = CGSize(width: 1920, height: 1080)
        #expect(SportBackdrop.drawingArea(in: wide) == CGRect(origin: .zero, size: wide))
        let fourThree = CGSize(width: 1600, height: 1200)
        #expect(SportBackdrop.drawingArea(in: fourThree) == CGRect(origin: .zero, size: fourThree))
        let tall = SportBackdrop.drawingArea(in: CGSize(width: 1080, height: 1920))
        #expect(tall.width == 1080 && tall.height == 900)
        #expect(tall.minY > 0 && tall.maxY < 1920)
    }
}

@Suite("Photo framing")
struct PhotoFramingTests {
    let card = CGSize(width: 1600, height: 900)

    @Test func landscapePhotosStayCentred() {
        let rect = PhotoFraming.rect(image: CGSize(width: 3000, height: 1500), filling: card)
        #expect(rect.size == CGSize(width: 1800, height: 900))
        #expect(rect.midX == card.width / 2 && rect.midY == card.height / 2)
    }

    @Test func squarePhotosStayCentred() {
        let rect = PhotoFraming.rect(image: CGSize(width: 2000, height: 2000), filling: card)
        #expect(rect.midX == card.width / 2 && rect.midY == card.height / 2)
    }

    @Test func portraitPhotosKeepTheirTopThirdInView() {
        // 2:3 on 16:9: the photo is 2400 tall on a 900 point card.
        let rect = PhotoFraming.rect(image: CGSize(width: 1000, height: 1500), filling: card)
        #expect(rect.size == CGSize(width: 1600, height: 2400))
        let visibleTop = -rect.minY / rect.height, visibleBottom = (card.height - rect.minY) / rect.height
        #expect(visibleTop <= 0.1, "the head end is in view")
        #expect(visibleBottom >= 1.0 / 3, "the top third is in view")
        // A centre crop would have started at 31% of the photo, below most heads.
        #expect(rect.midY > card.height / 2)
    }

    @Test(arguments: [CGSize(width: 1000, height: 1500), CGSize(width: 1902, height: 1920), CGSize(width: 900, height: 3000)])
    func portraitPhotosAlwaysCoverTheCard(image: CGSize) {
        for frame in [card, CGSize(width: 900, height: 1600), CGSize(width: 320, height: 200), CGSize(width: 3440, height: 1440)] {
            let rect = PhotoFraming.rect(image: image, filling: frame)
            #expect(rect.minX <= 0.001 && rect.minY <= 0.001)
            #expect(rect.maxX >= frame.width - 0.001 && rect.maxY >= frame.height - 0.001)
        }
    }

    @Test func tallPhotoOnAWideCardIsAPanelAtTheRightEdge() throws {
        let card = CGSize(width: 1600, height: 900)
        let panel = try #require(PhotoFraming.panel(image: CGSize(width: 1000, height: 1500), on: card))
        #expect(panel == CGRect(x: 1000, y: 0, width: 600, height: 900))
    }

    @Test func photosThatAreNotTallOrCardsThatAreNotWideFillTheCard() {
        let wide = CGSize(width: 1600, height: 900)
        #expect(PhotoFraming.panel(image: CGSize(width: 1500, height: 1000), on: wide) == nil)
        #expect(PhotoFraming.panel(image: CGSize(width: 1000, height: 1000), on: wide) == nil)
        #expect(PhotoFraming.panel(image: CGSize(width: 1000, height: 1500), on: CGSize(width: 900, height: 1600)) == nil)
        // Too wide to be a panel: more than six tenths of a 4:3 card.
        #expect(PhotoFraming.panel(image: CGSize(width: 1000, height: 1100), on: CGSize(width: 1200, height: 900)) == nil)
        #expect(PhotoFraming.panel(image: .zero, on: wide) == nil)
    }
}
