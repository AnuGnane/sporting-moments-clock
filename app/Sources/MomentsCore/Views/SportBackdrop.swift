import SwiftUI

// The ground for cards without a photo: a quiet drawing of the sport's own geometry
// (pitch markings, lane lines, court lines, contour lines) in tints between the night
// ground and the secondary text colour. Drawn once per card in a Canvas, with no bitmaps,
// and faded away from the lower left so the lockup keeps its contrast.

/// One graphic treatment per sport family. The card's `sport` string decides it.
enum SportMotif: String, CaseIterable, Sendable {
    /// Football: the penalty area, arc and centre circle, with mowing stripes.
    case pitch
    /// Athletics: eight lanes round the bend, staggered starts and the finish line.
    case track
    /// Swimming: lane ropes, floor lines and the backstroke flags line at the turning end.
    case pool
    /// Speed skating: the two lane oval with block markers and the crossing on the back straight.
    case skatingOval
    /// Tennis: the doubles court and net.
    case tennisCourt
    /// Baseball and softball: the infield, foul lines and mound.
    case diamond
    /// Track cycling: the banked oval with the blue band, measurement, sprinters' and stayers' lines.
    case velodrome
    /// Road cycling and ultrarunning: a stage elevation profile.
    case routeProfile
    /// Cricket: the pitch and creases, the fielding circle and the boundary rope.
    case cricketGround
    /// Rowing and paddling: buoyed lanes running to the finish line.
    case rowingCourse
    /// Motor racing: a corner with kerbs and the racing line.
    case racingCircuit
    /// Skiing, climbing and other mountain sports: contour lines.
    case contours
    /// Horse racing: the running rails, furlong markers and the winning post.
    case racecourse
    /// Boxing: the ropes and a corner post.
    case boxingRing
    /// Golf: the green with its slope lines, the cup and bunkers.
    case golfGreen
    /// American football: yard lines, hash marks and the end zone.
    case gridiron
    /// Ice hockey: the attacking zone with faceoff circles and the crease.
    case rink
    /// Rugby: try line, 22, the 10 metre and 5 metre lines and the posts.
    case rugbyPitch
    /// Basketball: the key, three point arc and rim.
    case basketballCourt
    /// Snooker and billiards: the table with baulk line, D and spots.
    case snookerTable
    /// Sailing, triathlon and open water swimming: swell lines and a buoyed course.
    case openWater
    /// Everything else: the dial of a stopwatch.
    case dial

    /// Ordered: the first rule whose keyword appears in the sport name wins, so
    /// "table tennis" is caught before "tennis" and "american football" before "football".
    private static let rules: [(keywords: [String], motif: SportMotif?)] = [
        (["table tennis", "beach volleyball", "australian football", "australian rules", "gaelic"], nil),
        (["american football", "gridiron", "canadian football"], .gridiron),
        (["rugby"], .rugbyPitch),
        (["ice hockey"], .rink),
        (["speed skating", "short track"], .skatingOval),
        (["track cycling", "velodrome", "keirin"], .velodrome),
        (["cycling", "ultrarunning", "ultramarathon", "ultra running", "trail running", "fell running",
          "mountain biking"], .routeProfile),
        (["open water", "triathlon", "sailing", "yachting", "windsurfing", "kitesurfing", "marathon swimming"], .openWater),
        (["horse racing", "horseracing", "racing (horse)", "steeplechase (horse)", "thoroughbred"], .racecourse),
        (["motor", "formula", "grand prix", "nascar", "indycar", "rally", "superbike", "motorcycle", "karting"], .racingCircuit),
        (["ski", "snowboard", "biathlon", "climbing", "mountaineering", "bobsleigh", "luge", "skeleton"], .contours),
        (["swimming", "diving", "water polo"], .pool),
        (["rowing", "canoe", "kayak", "regatta"], .rowingCourse),
        (["athletics", "track and field", "running", "sprint", "marathon", "decathlon", "heptathlon", "hurdles"], .track),
        (["football", "soccer"], .pitch),
        (["tennis"], .tennisCourt),
        (["cricket"], .cricketGround),
        (["baseball", "softball"], .diamond),
        (["basketball"], .basketballCourt),
        (["boxing", "kickboxing"], .boxingRing),
        (["golf"], .golfGreen),
        (["snooker", "billiards", "pool (cue sport)"], .snookerTable),
    ]

    /// The motif for a sport name from moments.json, ignoring case and spacing.
    /// Unknown sports get the stopwatch dial.
    init(sport: String) {
        let name = sport.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for rule in Self.rules where rule.keywords.contains(where: name.contains) {
            self = rule.motif ?? .dial
            return
        }
        self = .dial
    }
}

/// A stable seed from a moment id: FNV-1a, so it is the same in every process and on every
/// launch (Swift's own `Hasher` is randomised per process).
func backdropSeed(_ id: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

/// SplitMix64: a small deterministic generator, so a card draws the same way every time.
struct BackdropRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// Uniform in 0 ..< 1.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }

    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + (high - low) * unit()
    }
}

/// The small per card variation: the drawing shifts and scales a little, so two football
/// cards in a row do not look identical. Deterministic for a given seed.
struct BackdropVariation: Equatable {
    /// Shift as a fraction of the card's unit.
    let dx: CGFloat
    let dy: CGFloat
    /// Scale factor around 1.
    let zoom: CGFloat

    init(seed: UInt64) {
        var random = BackdropRandom(seed: seed)
        dx = random.range(-0.025, 0.025)
        dy = random.range(-0.02, 0.02)
        zoom = random.range(0.95, 1.06)
    }
}

/// The photo free ground: the lift gradient of the type only card, with the sport's motif
/// drawn over it. Equatable so the Canvas is redrawn only when the card or size changes,
/// not every minute when the clock text does.
struct SportBackdrop: View, Equatable {
    let motif: SportMotif
    let seed: UInt64
    let size: CGSize

    var body: some View {
        let unit = min(size.width, size.height * 1.6)
        ZStack {
            RadialGradient(
                colors: [Color(red: 0x17 / 255, green: 0x22 / 255, blue: 0x36 / 255), Palette.ground],
                center: UnitPoint(x: 0.2, y: 0.85),
                startRadius: 0,
                endRadius: unit * 0.75
            )
            Canvas(opaque: false) { context, size in
                context.drawLayer { layer in
                    var drawing = layer
                    let area = Self.drawingArea(in: size)
                    drawing.translateBy(x: 0, y: area.minY)
                    var painter = BackdropPainter(context: drawing, size: area.size, seed: seed)
                    painter.draw(motif)
                    Self.fadeBehindLockup(&layer, size: size)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// Where the motif is drawn. The motifs are composed for landscape cards; on a card much
    /// taller than wide (a display turned on its side) they are drawn in a band of landscape
    /// proportions above the lockup instead of being stretched to the full height.
    static func drawingArea(in size: CGSize) -> CGRect {
        let tallest = size.width / 1.2
        guard size.height > tallest else { return CGRect(origin: .zero, size: size) }
        return CGRect(x: 0, y: (size.height - tallest) * 0.3, width: size.width, height: tallest)
    }

    /// Keeps the lower left calm: the drawing fades to a trace around the lockup and along
    /// the bottom edge, as the photo cards darken towards the bottom.
    private static func fadeBehindLockup(_ layer: inout GraphicsContext, size: CGSize) {
        let unit = min(size.width, size.height * 1.6)
        let whole = Path(CGRect(origin: .zero, size: size))
        layer.blendMode = .destinationIn
        layer.fill(whole, with: .radialGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.16), location: 0),
                .init(color: .black.opacity(0.22), location: 0.42),
                .init(color: .black.opacity(0.7), location: 0.72),
                .init(color: .black, location: 1),
            ]),
            center: CGPoint(x: size.width * 0.22, y: size.height * 0.84),
            startRadius: 0, endRadius: unit * 0.82))
        layer.fill(whole, with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.4), location: 0),
                .init(color: .black, location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: size.height * 0.55)))
        layer.blendMode = .normal
    }
}

/// How bright a line is: tints between the ground and the secondary text colour, plus the
/// one restrained use of the accent.
enum Tone {
    /// Area fills: mowing stripes, the key, the end zone.
    case wash
    /// Secondary marks.
    case faint
    /// The main lines.
    case line
    /// The lines that carry the drawing.
    case strong
    /// At most one small element per motif.
    case accent

    var color: Color {
        switch self {
        case .wash: Palette.secondary.opacity(0.04)
        case .faint: Palette.secondary.opacity(0.13)
        case .line: Palette.secondary.opacity(0.21)
        case .strong: Palette.secondary.opacity(0.31)
        case .accent: Palette.accent.opacity(0.5)
        }
    }
}

/// Draws one motif. Plans are laid out in metres (yards for American football) and mapped to
/// the card with an affine transform, so the geometry is the sport's own at any size.
struct BackdropPainter {
    var context: GraphicsContext
    let size: CGSize
    let seed: UInt64
    var random: BackdropRandom
    let variation: BackdropVariation

    init(context: GraphicsContext, size: CGSize, seed: UInt64) {
        self.context = context
        self.size = size
        self.seed = seed
        self.random = BackdropRandom(seed: seed ^ 0x5bd1_e995)
        self.variation = BackdropVariation(seed: seed)
    }

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    /// The card's unit, as in `CardMetrics`.
    var unit: CGFloat { min(size.width, size.height * 1.6) }
    /// The base line weight.
    var hair: CGFloat { max(0.6, unit * 0.001) }
    var zoom: CGFloat { variation.zoom }

    /// A point on the card, nudged by this card's variation.
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x + variation.dx * unit, y: y + variation.dy * unit)
    }

    mutating func draw(_ motif: SportMotif) {
        switch motif {
        case .pitch: pitch()
        case .track: track()
        case .pool: pool()
        case .skatingOval: skatingOval()
        case .tennisCourt: tennisCourt()
        case .diamond: diamond()
        case .velodrome: velodrome()
        case .routeProfile: routeProfile()
        case .cricketGround: cricketGround()
        case .rowingCourse: rowingCourse()
        case .racingCircuit: racingCircuit()
        case .contours: contours()
        case .racecourse: racecourse()
        case .boxingRing: boxingRing()
        case .golfGreen: golfGreen()
        case .gridiron: gridiron()
        case .rink: rink()
        case .rugbyPitch: rugbyPitch()
        case .basketballCourt: basketballCourt()
        case .snookerTable: snookerTable()
        case .openWater: openWater()
        case .dial: dial()
        }
    }

    // MARK: Drawing helpers

    func stroke(_ path: Path, _ tone: Tone = .line, weight: CGFloat = 1, dash: [CGFloat] = [], round: Bool = false) {
        context.stroke(path, with: .color(tone.color), style: StrokeStyle(
            lineWidth: hair * weight, lineCap: round ? .round : .butt, lineJoin: .round, dash: dash))
    }

    func fill(_ path: Path, _ tone: Tone, eoFill: Bool = false) {
        context.fill(path, with: .color(tone.color), style: FillStyle(eoFill: eoFill))
    }

    func dot(_ center: CGPoint, radius: CGFloat, _ tone: Tone) {
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), tone)
    }

    /// A dotted line: dots of `weight` hairs every `spacing` points.
    func dotted(_ path: Path, _ tone: Tone, weight: CGFloat, spacing: CGFloat) {
        stroke(path, tone, weight: weight, dash: [0.001, spacing], round: true)
    }

    /// Local plan units to card points. Local x runs leftwards when `leftwards` is set, so a
    /// plan can be anchored on its right hand end.
    func plan(_ origin: CGPoint, scale: CGFloat, leftwards: Bool = false, angle: CGFloat = 0) -> CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y)
            .rotated(by: angle)
            .scaledBy(x: leftwards ? -scale : scale, y: scale)
    }

    static func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    static func segment(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        segment(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1))
    }

    /// Adds an arc as a polyline, from `start` to `end` radians (angles grow clockwise on
    /// screen). Sampled rather than `addArc` so the direction is never in doubt.
    static func addArc(_ path: inout Path, center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat,
                       connect: Bool = false) {
        let steps = max(12, Int(abs(end - start) / (.pi / 96)))
        for step in 0...steps {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if step == 0, !connect || path.isEmpty { path.move(to: point) } else { path.addLine(to: point) }
        }
    }

    static func arc(center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat) -> Path {
        var path = Path()
        addArc(&path, center: center, radius: radius, from: start, to: end)
        return path
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path(CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0)))
    }

    /// A running track or velodrome outline: two straights of `straight` and two bends of
    /// `radius`, centred on the origin.
    static func stadium(radius: CGFloat, straight: CGFloat) -> Path {
        var path = Path()
        let half = straight / 2
        addArc(&path, center: CGPoint(x: half, y: 0), radius: radius, from: -.pi / 2, to: .pi / 2)
        addArc(&path, center: CGPoint(x: -half, y: 0), radius: radius, from: .pi / 2, to: .pi * 1.5, connect: true)
        path.closeSubpath()
        return path
    }

    static func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

    /// `path` plus its mirror image across the halfway point of a field `length` long, so a
    /// plan is complete whichever part of it a wide or tall card shows.
    static func bothEnds(_ path: Path, length: CGFloat) -> Path {
        var both = path
        both.addPath(path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: length, ty: 0)))
        return both
    }

    /// A running track or skating oval with the right hand bend centred on the origin.
    static func oval(radius: CGFloat, straight: CGFloat) -> Path {
        stadium(radius: radius, straight: straight).applying(CGAffineTransform(translationX: -straight / 2, y: 0))
    }

    // MARK: Football

    /// A pitch with the goal line near the right edge and the touch line along the top:
    /// penalty area and arc, goal area, the halfway line and centre circle, corner arcs, over
    /// faint mowing stripes. Drawn whole, though most cards show only this end.
    func pitch() {
        typealias P = BackdropPainter
        let scale = unit * 0.0099 * zoom
        let t = plan(at(width - unit * 0.075, height * 0.04 + 34 * scale), scale: scale, leftwards: true)
        let length: CGFloat = 105

        var stripes = Path()
        for band in stride(from: CGFloat(0), to: length, by: 10.5) {
            stripes.addPath(P.rect(band, -34, band + 5.25, 34))
        }
        fill(stripes.applying(t), .wash)

        var end = Path()
        end.addPath(P.rect(0, -20.16, 16.5, 20.16))
        end.addPath(P.rect(0, -9.16, 5.5, 9.16))
        let arcEnd = acos(5.5 / 9.15)
        end.addPath(P.arc(center: CGPoint(x: 11, y: 0), radius: 9.15, from: -arcEnd, to: arcEnd))
        end.addPath(P.arc(center: CGPoint(x: 0, y: -34), radius: 1, from: 0, to: .pi / 2))
        end.addPath(P.arc(center: CGPoint(x: 0, y: 34), radius: 1, from: -.pi / 2, to: 0))
        var lines = P.bothEnds(end, length: length)
        lines.addPath(P.rect(0, -34, length, 34))
        lines.addPath(P.segment(length / 2, -34, length / 2, 34))
        lines.addPath(P.circle(CGPoint(x: length / 2, y: 0), 9.15))
        stroke(lines.applying(t), .line, weight: 1.35)

        stroke(P.bothEnds(P.rect(-2.0, -3.66, 0, 3.66), length: length).applying(t), .faint)
        dot(CGPoint(x: length / 2, y: 0).applying(t), radius: hair * 1.6, .line)
        dot(CGPoint(x: length - 11, y: 0).applying(t), radius: hair * 1.6, .line)
        dot(CGPoint(x: 11, y: 0).applying(t), radius: hair * 1.9, .accent)
    }

    // MARK: Athletics

    /// Eight lanes coming along the top, round the bend at the right and away at the bottom,
    /// wrapping the lockup. Staggered starts on the bend; the finish line in the accent.
    func track() {
        typealias P = BackdropPainter
        let scale = unit * 0.0088 * zoom
        let t = plan(at(width - unit * 0.43, height * 0.86), scale: scale)
        let straight: CGFloat = 84.39
        let radii = (0...8).map { 36.5 + 1.22 * CGFloat($0) }

        var lanes = Path()
        for radius in radii.dropFirst() { lanes.addPath(P.oval(radius: radius, straight: straight)) }
        stroke(lanes.applying(t), .line)
        stroke(P.oval(radius: radii[0], straight: straight).applying(t), .strong, weight: 1.6)

        // Staggered starts: one mark across each lane, further round the bend for the outer lanes.
        var starts = Path()
        for lane in 1...8 {
            let angle = P.degrees(-34 + CGFloat(lane - 1) * 7.5)
            let inner = radii[lane - 1] + 0.15, outer = radii[lane] - 0.15
            starts.addPath(P.segment(CGPoint(x: inner * cos(angle), y: inner * sin(angle)),
                                     CGPoint(x: outer * cos(angle), y: outer * sin(angle))))
        }
        stroke(starts.applying(t), .strong, weight: 1.4)

        // Relay take over marks on the top straight.
        var marks = Path()
        for x: CGFloat in [-30, -50] {
            for lane in 1...8 {
                let y = -(radii[lane - 1] + radii[lane]) / 2
                marks.addPath(P.segment(x, y - 0.25, x, y + 0.25))
            }
        }
        stroke(marks.applying(t), .faint, weight: 1.2)

        stroke(P.segment(0, -radii[0], 0, -radii[8]).applying(t), .accent, weight: 1.8)
    }

    // MARK: Speed skating

    /// The 400 metre oval: inner and outer lanes divided by rows of blocks, the warm up lane
    /// inside, and the crossing on the back straight (the top) where the skaters change lanes.
    func skatingOval() {
        typealias P = BackdropPainter
        let scale = unit * 0.0098 * zoom
        let t = plan(at(width - unit * 0.40, height * 0.84), scale: scale)
        let straight: CGFloat = 111.95
        let spacing = 2.4 * scale

        // The warm up lane's inner edge and the inner lane's edge: blocks on the ice.
        dotted(P.oval(radius: 22, straight: straight).applying(t), .line, weight: 2.4, spacing: spacing)
        dotted(P.oval(radius: 26, straight: straight).applying(t), .strong, weight: 2.6, spacing: spacing)

        // The divider between the lanes, open for the crossing.
        var divider = Path()
        divider.move(to: CGPoint(x: -12, y: -30))
        P.addArc(&divider, center: .zero, radius: 30, from: -.pi / 2, to: .pi / 2, connect: true)
        P.addArc(&divider, center: CGPoint(x: -straight, y: 0), radius: 30, from: .pi / 2, to: .pi * 1.5, connect: true)
        divider.addLine(to: CGPoint(x: -84, y: -30))
        dotted(divider.applying(t), .strong, weight: 2.6, spacing: spacing)

        var crossing = Path()
        crossing.addPath(P.segment(-12, -28, -84, -32))
        crossing.addPath(P.segment(-12, -32, -84, -28))
        stroke(crossing.applying(t), .faint, weight: 1.1, dash: [hair * 6, hair * 5])

        stroke(P.oval(radius: 34, straight: straight).applying(t), .line, weight: 1.3)
        stroke(P.oval(radius: 36.5, straight: straight).applying(t), .faint)
        // The finish on the home straight (the bottom), across both lanes.
        stroke(P.segment(-30, 26, -30, 34).applying(t), .strong, weight: 1.4)
    }

    // MARK: Swimming

    /// The turning end of a 50 metre pool, filling the top of the card with the near side
    /// wall just above the lockup: ropes of floats (busier in the last five metres), the T
    /// ends of the floor lines and the backstroke flags line.
    func pool() {
        typealias P = BackdropPainter
        let scale = unit * 0.019 * zoom
        // Local y runs from the near side wall (0) up the pool (negative), lanes of 2.5 metres.
        let t = plan(at(width - unit * 0.07, height * 0.58), scale: scale, leftwards: true)
        let float = max(1.5, 0.2 * scale)
        let lanes = 10

        let length: CGFloat = 50, breadth = -2.5 * CGFloat(lanes)
        var edges = Path()
        edges.addPath(P.segment(0, 0, 0, breadth))
        edges.addPath(P.segment(length, 0, length, breadth))
        edges.addPath(P.segment(0, 0, length, 0))
        edges.addPath(P.segment(0, breadth, length, breadth))
        stroke(edges.applying(t), .strong, weight: 1.6)

        var ropes = Path(), ropeEnds = Path()
        for rope in 1..<lanes {
            let y = -2.5 * CGFloat(rope)
            ropes.addPath(P.segment(5, y, length - 5, y))
            ropeEnds.addPath(P.bothEnds(P.segment(0, y, 5, y), length: length))
        }
        stroke(ropes.applying(t), .line, weight: 2.4, dash: [float, float * 0.5])
        stroke(ropeEnds.applying(t), .strong, weight: 2.4, dash: [float, float * 0.5])

        var floor = Path()
        for lane in 0..<lanes {
            let y = -1.25 - 2.5 * CGFloat(lane)
            floor.addPath(P.rect(2, y - 0.125, length - 2, y + 0.125))
            floor.addPath(P.bothEnds(P.rect(2, y - 0.5, 2.25, y + 0.5), length: length))
        }
        fill(floor.applying(t), .faint)

        stroke(P.bothEnds(P.segment(5, 0, 5, breadth), length: length).applying(t), .faint, weight: 1, dash: [hair * 4, hair * 4])
        stroke(P.bothEnds(P.segment(15, 0.25, 15, -0.6), length: length).applying(t), .strong, weight: 1.6)
    }

    // MARK: Tennis

    /// The doubles court standing upright at the right: the far baseline near the top, the
    /// net across the middle with its posts, and the near court running down into the fade.
    func tennisCourt() {
        typealias P = BackdropPainter
        let scale = unit * 0.028 * zoom
        let t = plan(at(width - unit * 0.22, height * 0.64), scale: scale)
        let halfLength: CGFloat = 11.885, doubles: CGFloat = 5.485, singles: CGFloat = 4.115

        fill(P.rect(-doubles, -halfLength, doubles, halfLength).applying(t), .wash)

        var lines = Path()
        lines.addPath(P.rect(-doubles, -halfLength, doubles, halfLength))
        lines.addPath(P.segment(-singles, -halfLength, -singles, halfLength))
        lines.addPath(P.segment(singles, -halfLength, singles, halfLength))
        lines.addPath(P.segment(-singles, -6.4, singles, -6.4))
        lines.addPath(P.segment(-singles, 6.4, singles, 6.4))
        lines.addPath(P.segment(0, -6.4, 0, 6.4))
        lines.addPath(P.segment(0, -halfLength, 0, -halfLength + 0.2))
        lines.addPath(P.segment(0, halfLength, 0, halfLength - 0.2))
        stroke(lines.applying(t), .line, weight: 1.2)

        stroke(P.segment(-doubles - 0.914, 0, doubles + 0.914, 0).applying(t), .strong, weight: 2)
        dot(CGPoint(x: -doubles - 0.914, y: 0).applying(t), radius: hair * 2.2, .strong)
        dot(CGPoint(x: doubles + 0.914, y: 0).applying(t), radius: hair * 2.2, .strong)
    }

    // MARK: Baseball

    /// The infield seen from above with home plate near the top right: foul lines, the base
    /// paths, the mound and the edge of the infield grass, with the outfield fence beyond.
    func diamond() {
        typealias P = BackdropPainter
        let scale = unit * 0.0084 * zoom
        let home = at(width - unit * 0.13, height * 0.09)
        let axis = P.degrees(126)
        let first = CGPoint(x: cos(axis - .pi / 4), y: sin(axis - .pi / 4))
        let third = CGPoint(x: cos(axis + .pi / 4), y: sin(axis + .pi / 4))
        func point(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: home.x + (first.x * a + third.x * b) * scale, y: home.y + (first.y * a + third.y * b) * scale)
        }
        func isFair(_ p: CGPoint) -> Bool {
            let v = CGPoint(x: (p.x - home.x) / scale, y: (p.y - home.y) / scale)
            return v.x * first.x + v.y * first.y >= 0 && v.x * third.x + v.y * third.y >= 0
        }
        func fairArc(center: CGPoint, radius: CGFloat) -> Path {
            var path = Path(), drawing = false
            for step in 0...720 {
                let angle = CGFloat(step) / 720 * 2 * .pi
                let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                if isFair(p) {
                    if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
                } else {
                    drawing = false
                }
            }
            return path
        }
        let base: CGFloat = 27.43

        var foul = Path()
        foul.addPath(P.segment(home, point(130, 0)))
        foul.addPath(P.segment(home, point(0, 130)))
        stroke(foul, .strong, weight: 1.3)

        var paths = Path()
        paths.move(to: point(base, 0))
        paths.addLine(to: point(base, base))
        paths.addLine(to: point(0, base))
        stroke(paths, .line, weight: 1.2)

        let mound = point(18.44 / sqrt(2), 18.44 / sqrt(2))
        stroke(P.circle(mound, 2.74 * scale), .line)
        stroke(fairArc(center: point(18.44 / sqrt(2) * 0.97, 18.44 / sqrt(2) * 0.97), radius: 29 * scale), .line, weight: 1.2)
        stroke(P.circle(home, 4 * scale), .faint)

        let bag = max(hair * 2.2, 0.38 * scale)
        for corner in [point(base, 0), point(base, base), point(0, base)] {
            fill(P.rect(corner.x - bag, corner.y - bag, corner.x + bag, corner.y + bag)
                .applying(CGAffineTransform(translationX: -corner.x, y: -corner.y)
                    .concatenating(CGAffineTransform(rotationAngle: axis - .pi / 4))
                    .concatenating(CGAffineTransform(translationX: corner.x, y: corner.y))), .strong)
        }
        dot(home, radius: bag * 1.1, .strong)

        var boxes = Path()
        for side: CGFloat in [-1, 1] {
            let corners = [(-0.9, 1.0), (-0.9, 2.2), (0.9, 2.2), (0.9, 1.0)].map { offset -> CGPoint in
                // Batter's boxes either side of the plate, across the axis.
                let along = CGFloat(offset.0), across = CGFloat(offset.1) * side
                let a = (along + across) / sqrt(2), b = (along - across) / sqrt(2)
                return point(a, b)
            }
            boxes.move(to: corners[0])
            for corner in corners.dropFirst() { boxes.addLine(to: corner) }
            boxes.closeSubpath()
        }
        stroke(boxes, .faint)
    }

    // MARK: Track cycling

    /// The 250 metre velodrome, tilted: the blue band on the inside, then the measurement,
    /// sprinters' (accent) and stayers' lines, the outer edge, and the pursuit lines.
    func velodrome() {
        typealias P = BackdropPainter
        let scale = unit * 0.0105 * zoom
        let t = plan(at(width * 0.70, height * 0.30), scale: scale, angle: P.degrees(-14))
        let straight: CGFloat = 40

        var band = P.stadium(radius: 20.9, straight: straight)
        band.addPath(P.stadium(radius: 20, straight: straight))
        fill(band.applying(t), .faint, eoFill: true)

        stroke(P.stadium(radius: 21.15, straight: straight).applying(t), .strong, weight: 1.3)
        stroke(P.stadium(radius: 22.0, straight: straight).applying(t), .accent, weight: 1.3)
        stroke(P.stadium(radius: 23.6, straight: straight).applying(t), .line, weight: 1.2)
        stroke(P.stadium(radius: 27.0, straight: straight).applying(t), .strong, weight: 1.4)
        stroke(P.stadium(radius: 27.6, straight: straight).applying(t), .faint)
        stroke(P.stadium(radius: 15, straight: straight).applying(t), .faint, dash: [hair * 3, hair * 6])

        var cross = Path()
        cross.addPath(P.segment(0, 20, 0, 27))
        cross.addPath(P.segment(0, -20, 0, -27))
        cross.addPath(P.segment(12, 20, 12, 27))
        stroke(cross.applying(t), .strong, weight: 1.5)
    }

    // MARK: Road cycling and ultrarunning

    /// A stage profile across the top of the card: the climbs, hatched down to the base line
    /// as in a race book, with faint height lines and the highest point in the accent.
    mutating func routeProfile() {
        let base = height * 0.46 + variation.dy * unit * 0.5
        let top = height * 0.09
        let summitFinish = random.unit() < 0.5
        var climbs: [(center: CGFloat, width: CGFloat, height: CGFloat)] = []
        for index in 0..<4 {
            climbs.append((center: 0.12 + CGFloat(index) * 0.22 + random.range(-0.05, 0.05),
                           width: random.range(0.035, 0.08), height: random.range(0.25, 0.7)))
        }
        if summitFinish { climbs.append((center: 0.9, width: 0.05, height: 1)) }
        let phase1 = random.range(0, 6), phase2 = random.range(0, 6)
        func elevation(_ x: CGFloat) -> CGFloat {
            var e = 0.1 + 0.04 * sin(x * 23 + phase1) + 0.025 * sin(x * 61 + phase2) + 0.012 * sin(x * 143 + phase1)
            for climb in climbs {
                let d = abs(x - climb.center) / climb.width
                e += climb.height * exp(-pow(d, 1.25) * 1.4)
            }
            return e
        }
        let samples = 320
        let values = (0...samples).map { elevation(CGFloat($0) / CGFloat(samples)) }
        let highest = values.max() ?? 1
        let x0 = -width * 0.02, x1 = width * 1.02
        let points = values.enumerated().map { index, value in
            CGPoint(x: x0 + (x1 - x0) * CGFloat(index) / CGFloat(samples),
                    y: base - (base - top) * (0.06 + 0.94 * value / highest))
        }

        var area = Path()
        area.move(to: CGPoint(x: x0, y: base))
        for point in points { area.addLine(to: point) }
        area.addLine(to: CGPoint(x: x1, y: base))
        area.closeSubpath()
        fill(area, .wash)

        // Hatching every "kilometre", down from the profile to the base line.
        var hatch = Path(), ticks = Path()
        let step = unit * 0.0115
        var x = x0 + step
        var count = 0
        while x < x1 {
            let index = min(samples, max(0, Int(((x - x0) / (x1 - x0) * CGFloat(samples)).rounded())))
            hatch.addPath(BackdropPainter.segment(x, points[index].y, x, base))
            if count % 5 == 4 { ticks.addPath(BackdropPainter.segment(x, base, x, base + unit * 0.008)) }
            x += step
            count += 1
        }
        stroke(hatch, .faint)
        stroke(ticks, .line)

        var levels = Path()
        for level in 1...3 {
            let y = base - (base - top) * CGFloat(level) / 3.6
            levels.addPath(BackdropPainter.segment(0, y, width, y))
        }
        stroke(levels, .faint, dash: [hair * 2, hair * 5])

        var profile = Path()
        profile.addLines(points)
        stroke(profile, .strong, weight: 1.7)
        stroke(BackdropPainter.segment(0, base, width, base), .line, weight: 1.2)

        if let peak = values.firstIndex(of: highest) {
            dot(points[peak], radius: hair * 2.4, .accent)
        }
    }

    // MARK: Cricket

    /// The middle of the ground from above: the pitch running up and down with its creases
    /// and stumps, the fielding circle of discs round it, and the boundary rope beyond.
    func cricketGround() {
        typealias P = BackdropPainter
        let scale = unit * 0.0068 * zoom
        let t = plan(at(width * 0.74, height * 0.44), scale: scale)
        let boundary: CGFloat = 70

        stroke(P.circle(.zero, boundary).applying(t), .line, weight: 2.6)

        // The fielding circle: two semicircles of 30 yards round the stumps, joined by straights.
        var ring = Path()
        P.addArc(&ring, center: CGPoint(x: 0, y: -10.06), radius: 27.43, from: .pi, to: 2 * .pi)
        P.addArc(&ring, center: CGPoint(x: 0, y: 10.06), radius: 27.43, from: 0, to: .pi, connect: true)
        ring.closeSubpath()
        dotted(ring.applying(t), .strong, weight: 3, spacing: 2.6 * scale)

        let strip = P.rect(-1.525, -12.5, 1.525, 12.5).applying(t)
        fill(strip, .faint)
        stroke(strip, .line)
        var creases = Path()
        for end: CGFloat in [-1, 1] {
            let stumps = 10.06 * end, popping = (10.06 - 1.22) * end
            creases.addPath(P.segment(-1.32, stumps, 1.32, stumps))
            creases.addPath(P.segment(-2.6, popping, 2.6, popping))
            creases.addPath(P.segment(-1.32, popping, -1.32, stumps + 1.22 * end))
            creases.addPath(P.segment(1.32, popping, 1.32, stumps + 1.22 * end))
        }
        stroke(creases.applying(t), .strong, weight: 1.1)
        for end: CGFloat in [-1, 1] {
            dot(CGPoint(x: 0, y: 10.06 * end).applying(t), radius: max(hair * 1.6, 0.2 * scale), .strong)
        }
    }

    // MARK: Rowing

    /// Seven buoyed lanes running to the finish line near the right edge: a buoy every ten
    /// metres, brighter over the last 250, then the finish line and the lane boards beyond it.
    func rowingCourse() {
        typealias P = BackdropPainter
        let metre = unit * 0.0042 * zoom
        let finish = width - unit * 0.12 + variation.dx * unit
        let laneGap = unit * 0.04
        let top = height * 0.08 + variation.dy * unit
        let lines = 8

        var buoys = Path(), lastStretch = Path()
        for row in 0..<lines {
            let y = top + CGFloat(row) * laneGap
            var count = 1
            var x = finish - metre * 10
            while x > -metre * 10 {
                let radius = max(1, hair * (count <= 25 ? 1.6 : 1.3))
                if count <= 25 {
                    lastStretch.addPath(P.circle(CGPoint(x: x, y: y), radius))
                } else {
                    buoys.addPath(P.circle(CGPoint(x: x, y: y), radius))
                }
                x -= metre * 10
                count += 1
            }
        }
        var cables = Path()
        for row in 0..<lines {
            let y = top + CGFloat(row) * laneGap
            cables.addPath(P.segment(-metre * 10, y, finish, y))
        }
        stroke(cables, .faint, weight: 0.8)
        fill(buoys, .line)
        fill(lastStretch, .strong)

        let bottom = top + CGFloat(lines - 1) * laneGap
        stroke(P.segment(finish, top - laneGap * 0.7, finish, bottom + laneGap * 0.7), .strong, weight: 1.8)
        var boards = Path()
        for lane in 0..<(lines - 1) {
            let y = top + (CGFloat(lane) + 0.5) * laneGap
            boards.addPath(P.segment(finish + laneGap * 0.45, y, finish + laneGap * 0.85, y))
        }
        stroke(boards, .line, weight: 2.4)
        let quarter = finish - metre * 250
        stroke(P.segment(quarter, top - laneGap * 0.4, quarter, bottom + laneGap * 0.4), .faint, dash: [hair * 3, hair * 4])
    }

    // MARK: Motor racing

    /// A corner: track edges, kerbs striped at the apex and on the exit, the gravel trap
    /// line outside, and the racing line in the accent from turn in to apex to exit.
    func racingCircuit() {
        typealias P = BackdropPainter
        let w = width, h = height
        let a = at(-0.06 * w, 0.18 * h), b = at(0.46 * w, 0.18 * h)
        let c1 = at(0.94 * w, 0.18 * h), c2 = at(0.90 * w, 0.56 * h), e = at(0.70 * w, 1.12 * h)
        let ribbon = Ribbon(start: a, straightTo: b, curve: (c1, c2, e))
        let half = unit * 0.042 * zoom

        // Gravel trap edge round the outside of the corner.
        stroke(ribbon.offsetPath(-half - unit * 0.07, from: 0.3, to: 0.92), .faint, dash: [hair * 2, hair * 4], round: true)
        stroke(ribbon.offsetPath(-half, from: 0, to: 1), .strong, weight: 1.4)
        stroke(ribbon.offsetPath(half, from: 0, to: 1), .strong, weight: 1.4)

        let apex = ribbon.apex
        let kerb = unit * 0.013
        ribbon.kerb(painter: self, side: 1, edge: half, depth: kerb, from: apex - 0.12, to: apex + 0.1, stripe: unit * 0.016)
        ribbon.kerb(painter: self, side: -1, edge: half, depth: kerb, from: apex + 0.18, to: apex + 0.34, stripe: unit * 0.016)

        let turnIn = apex - 0.22, exit = apex + 0.28
        let racing = ribbon.path { s in
            let outside: CGFloat = -0.72, inside: CGFloat = 0.78
            let lateral: CGFloat
            if s < turnIn || s > exit {
                lateral = outside
            } else if s < apex {
                lateral = outside + (inside - outside) * (1 - cos((s - turnIn) / (apex - turnIn) * .pi)) / 2
            } else {
                lateral = inside + (outside - inside) * (1 - cos((s - apex) / (exit - apex) * .pi)) / 2
            }
            return lateral * half
        }
        stroke(racing, .accent, weight: 1.3, dash: [hair * 5, hair * 3.5])
    }

    // MARK: Mountains

    /// Contour lines of a deterministic mountain, the summit in the upper right, with every
    /// fifth line heavier as on a map and the summit marked in the accent.
    mutating func contours() {
        let peaks: [(x: CGFloat, y: CGFloat, height: CGFloat, spread: CGFloat)] = [
            (width * random.range(0.74, 0.84), height * random.range(0.12, 0.22), 1.0, unit * 0.24),
            (width * random.range(0.50, 0.60), height * random.range(0.0, 0.10), random.range(0.5, 0.7), unit * 0.14),
            (width * random.range(0.92, 1.02), height * random.range(0.50, 0.62), random.range(0.4, 0.55), unit * 0.18),
            (width * random.range(0.62, 0.70), height * random.range(0.36, 0.46), random.range(0.18, 0.3), unit * 0.08),
        ].map { (x: $0.0 + variation.dx * unit, y: $0.1 + variation.dy * unit, height: $0.2, spread: $0.3) }
        let phases = (0..<4).map { _ in random.range(0, 2 * .pi) }
        let u = unit
        func field(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            var value: CGFloat = 0
            for peak in peaks {
                let dx = (x - peak.x) / peak.spread, dy = (y - peak.y) / peak.spread
                value += peak.height * exp(-(dx * dx + dy * dy))
            }
            value += 0.05 * sin(x / u * 7 + phases[0]) * cos(y / u * 6 + phases[1])
            value += 0.025 * sin(x / u * 15 + phases[2]) * sin(y / u * 13 + phases[3])
            return value
        }

        let cell = unit / 150
        let columns = Int(width / cell) + 2, rows = Int(height / cell) + 2
        var grid = [CGFloat](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                grid[row * columns + column] = field(CGFloat(column) * cell, CGFloat(row) * cell)
            }
        }
        let levels = stride(from: CGFloat(0.06), through: 1.3, by: 0.052).map { $0 }
        var normal = Path(), index = Path()
        for (number, level) in levels.enumerated() {
            var path = Path()
            Contours.trace(grid: grid, columns: columns, rows: rows, cell: cell, level: level, into: &path)
            if number % 5 == 4 { index.addPath(path) } else { normal.addPath(path) }
        }
        stroke(normal, .line, weight: 1.0, round: true)
        stroke(index, .strong, weight: 1.5, round: true)

        // The summit: the highest grid point.
        if let top = grid.indices.max(by: { grid[$0] < grid[$1] }) {
            let point = CGPoint(x: CGFloat(top % columns) * cell, y: CGFloat(top / columns) * cell)
            if point.x < width && point.y < height {
                dot(point, radius: hair * 2.2, .accent)
            }
        }
    }

    // MARK: Horse racing

    /// The home straight along the top, bending away at the right: inner rail with its
    /// posts, outer rail, a dolled out rail, furlong markers and the winning post in the accent.
    func racecourse() {
        typealias P = BackdropPainter
        let w = width, h = height
        let a = at(-0.06 * w, 0.30 * h), b = at(0.58 * w, 0.30 * h)
        let c1 = at(0.92 * w, 0.30 * h), c2 = at(1.0 * w, 0.10 * h), e = at(0.90 * w, -0.16 * h)
        let ribbon = Ribbon(start: a, straightTo: b, curve: (c1, c2, e))
        let half = unit * 0.06 * zoom

        // A left handed course: the inner rail is on the left of the direction of running.
        stroke(ribbon.offsetPath(-half, from: 0, to: 1), .strong, weight: 1.6)
        dotted(ribbon.offsetPath(-half, from: 0, to: 1), .strong, weight: 2.4, spacing: unit * 0.022)
        stroke(ribbon.offsetPath(half, from: 0, to: 1), .line, weight: 1.3)
        stroke(ribbon.offsetPath(-half * 0.55, from: 0.25, to: 1), .faint, dash: [hair * 6, hair * 5])

        var furlongs = Path()
        for s in stride(from: CGFloat(0.3), through: 0.95, by: 0.16) {
            let (point, normal) = ribbon.frame(at: s)
            let inner = CGPoint(x: point.x - normal.x * half, y: point.y - normal.y * half)
            furlongs.addPath(P.segment(inner, CGPoint(x: inner.x - normal.x * unit * 0.022, y: inner.y - normal.y * unit * 0.022)))
        }
        stroke(furlongs, .strong, weight: 2)

        let (post, normal) = ribbon.frame(at: 0.16)
        stroke(P.segment(CGPoint(x: post.x - normal.x * half, y: post.y - normal.y * half),
                         CGPoint(x: post.x + normal.x * half, y: post.y + normal.y * half)), .accent, weight: 1.4)
        dot(CGPoint(x: post.x - normal.x * half, y: post.y - normal.y * half), radius: hair * 2.6, .accent)
    }

    // MARK: Boxing

    /// Four ropes sagging between posts across the top of the card, the near corner post on
    /// the right with its pad (accent), and the ropes of the next side running away from it.
    func boxingRing() {
        typealias P = BackdropPainter
        let post = at(width - unit * 0.16, 0)
        let top = height * 0.13 + variation.dy * unit
        let gap = unit * 0.052 * zoom
        let farPost = -width * 0.42
        let ropes = (0..<4).map { top + CGFloat($0) * gap }

        var near = Path()
        for (index, y) in ropes.enumerated() {
            let sag = unit * (0.016 + 0.002 * CGFloat(index))
            near.move(to: CGPoint(x: farPost, y: y))
            near.addQuadCurve(to: CGPoint(x: post.x, y: y), control: CGPoint(x: (farPost + post.x) / 2, y: y + sag * 2))
        }
        stroke(near, .line, weight: 3.2, round: true)

        // The adjoining side recedes up and to the right.
        var side = Path()
        for (index, y) in ropes.enumerated() {
            side.move(to: CGPoint(x: post.x, y: y))
            side.addQuadCurve(to: CGPoint(x: width + unit * 0.05, y: y - unit * 0.05 - CGFloat(index) * gap * 0.25),
                              control: CGPoint(x: post.x + unit * 0.12, y: y - unit * 0.01))
        }
        stroke(side, .faint, weight: 2.4, round: true)

        // Rope ties, holding the ropes together between the posts.
        var ties = Path()
        for fraction: CGFloat in [0.62, 0.82] {
            let x = farPost + (post.x - farPost) * fraction
            let curve = 4 * fraction * (1 - fraction)
            ties.move(to: CGPoint(x: x, y: ropes[0] + unit * 0.016 * curve))
            ties.addLine(to: CGPoint(x: x, y: ropes[3] + unit * 0.022 * curve))
        }
        stroke(ties, .faint, weight: 1.4)

        let floor = ropes[3] + gap * 1.3
        stroke(P.segment(post.x, top - gap * 0.7, post.x, floor), .line, weight: 4.5)
        let pad = unit * 0.011
        let padShape = Path(roundedRect: CGRect(x: post.x - pad, y: top - gap * 0.45, width: pad * 2,
                                                height: ropes[3] - top + gap * 0.9), cornerRadius: pad * 0.6)
        fill(padShape, .wash)
        stroke(padShape, .accent, weight: 1.3)
        stroke(P.segment(width * 0.5, floor, width, floor), .faint, weight: 1.2)
    }

    // MARK: Golf

    /// The green from above: its edge and fringe, slope lines rising to one side, mowing
    /// stripes, two bunkers, and the cup in the accent.
    mutating func golfGreen() {
        let centre = at(width - unit * 0.30, height * 0.30)
        let rx = unit * 0.24 * zoom, ry = unit * 0.155 * zoom
        let tilt = random.range(-0.25, 0.1)
        var harmonics: [(CGFloat, CGFloat)] = []
        for _ in 2...4 { harmonics.append((random.range(0.025, 0.06), random.range(0, 2 * .pi))) }
        func blob(_ centre: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ tilt: CGFloat, _ harmonics: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            for step in 0...180 {
                let angle = CGFloat(step) / 180 * 2 * .pi
                var r: CGFloat = 1
                for (index, harmonic) in harmonics.enumerated() {
                    r += harmonic.0 * sin(CGFloat(index + 2) * angle + harmonic.1)
                }
                let x = rx * r * cos(angle), y = ry * r * sin(angle)
                let point = CGPoint(x: centre.x + x * cos(tilt) - y * sin(tilt), y: centre.y + x * sin(tilt) + y * cos(tilt))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }

        let green = blob(centre, rx, ry, tilt, harmonics)
        context.drawLayer { layer in
            layer.clip(to: green)
            var stripes = Path()
            let band = unit * 0.028
            var x = centre.x - rx * 2.5
            while x < centre.x + rx * 2.5 {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: centre.y - ry * 2))
                stripe.addLine(to: CGPoint(x: x + band, y: centre.y - ry * 2))
                stripe.addLine(to: CGPoint(x: x + band + ry * 1.2, y: centre.y + ry * 2))
                stripe.addLine(to: CGPoint(x: x + ry * 1.2, y: centre.y + ry * 2))
                stripe.closeSubpath()
                stripes.addPath(stripe)
                x += band * 2
            }
            layer.fill(stripes, with: .color(Tone.wash.color))
        }
        stroke(blob(centre, rx * 1.08, ry * 1.1, tilt, harmonics), .faint, weight: 1, dash: [hair * 3, hair * 3])
        stroke(green, .strong, weight: 1.4)

        // Slope lines: rings that shrink towards a high point on the green's far side.
        let high = CGPoint(x: centre.x + rx * 0.35, y: centre.y - ry * 0.3)
        var slope = Path()
        for ring in 1...4 {
            let f = 1 - CGFloat(ring) * 0.2
            let c = CGPoint(x: high.x + (centre.x - high.x) * f, y: high.y + (centre.y - high.y) * f)
            slope.addPath(blob(c, rx * f * 0.95, ry * f * 0.95, tilt, harmonics))
        }
        stroke(slope, .faint, weight: 1)

        let bunker = blob(CGPoint(x: centre.x + rx * 0.62, y: centre.y + ry * 1.45), unit * 0.085, unit * 0.04,
                          tilt - 0.35, [(0.08, 1.2), (0.05, 0.4), (0.03, 2.2)])
        fill(bunker, .wash)
        stroke(bunker, .line, weight: 1.2)
        let second = blob(CGPoint(x: centre.x - rx * 1.25, y: centre.y - ry * 0.55), unit * 0.05, unit * 0.03,
                          tilt + 0.5, [(0.07, 0.3), (0.06, 1.9), (0.02, 0.8)])
        fill(second, .wash)
        stroke(second, .line, weight: 1.2)

        let cup = CGPoint(x: centre.x - rx * 0.28, y: centre.y + ry * 0.18)
        stroke(BackdropPainter.circle(cup, unit * 0.0055), .accent, weight: 1.4)
    }

    // MARK: American football

    /// Yard lines every five yards, hash marks every yard, the goal line and end zone at the
    /// right, the posts on the end line, and the first down line in the accent.
    func gridiron() {
        typealias P = BackdropPainter
        let scale = unit * 0.0205 * zoom
        let t = plan(at(width - unit * 0.235, height * 0.30), scale: scale, leftwards: true)
        let half: CGFloat = 26.67

        fill(P.rect(-10, -half, 0, half).applying(t), .wash)
        var lines = Path()
        for yard in stride(from: 5, through: 70, by: 5) {
            lines.addPath(P.segment(CGFloat(yard), -half, CGFloat(yard), half))
        }
        lines.addPath(P.segment(-10, -half, -10, half))
        stroke(lines.applying(t), .line, weight: 1.2)
        stroke(P.segment(0, -half, 0, half).applying(t), .strong, weight: 2.2)

        var hashes = Path()
        for yard in 1...70 where yard % 5 != 0 {
            let x = CGFloat(yard)
            for y: CGFloat in [-3.08, 3.08] {
                hashes.addPath(P.segment(x, y - 0.33, x, y + 0.33))
            }
            hashes.addPath(P.segment(x, -half + 0.33, x, -half + 1))
            hashes.addPath(P.segment(x, half - 1, x, half - 0.33))
        }
        stroke(hashes.applying(t), .line, weight: 1.1)
        stroke(P.segment(2, -0.33, 2, 0.33).applying(t), .line, weight: 1.1)

        stroke(P.segment(-10, -3.08, -10, 3.08).applying(t), .strong, weight: 2.4)
        dot(CGPoint(x: -10, y: -3.08).applying(t), radius: hair * 2, .strong)
        dot(CGPoint(x: -10, y: 3.08).applying(t), radius: hair * 2, .strong)

        // The first down line sits between yard lines, clear of the caption's column.
        let target = width * 0.735
        let origin = CGPoint(x: 0, y: 0).applying(t).x
        let yards = ((origin - target) / scale).rounded() + 0.5
        stroke(P.segment(yards, -half, yards, half).applying(t), .accent, weight: 1.6)
    }

    // MARK: Ice hockey

    /// The rink with one end near the right edge: rounded boards, goal line, crease and net,
    /// the end zone faceoff circles with their hash marks, the blue line, and the centre line
    /// and circle. Drawn whole, though most cards show only this end.
    func rink() {
        typealias P = BackdropPainter
        let scale = unit * 0.0185 * zoom
        let t = plan(at(width - unit * 0.05, height * 0.47), scale: scale, leftwards: true)
        let length: CGFloat = 60.96, half: CGFloat = 12.95, corner: CGFloat = 8.53

        stroke(Path(roundedRect: CGRect(x: 0, y: -half, width: length, height: half * 2), cornerRadius: corner)
            .applying(t), .strong, weight: 1.8)

        let goalLine: CGFloat = 3.35
        let reach = half - corner + sqrt(corner * corner - (corner - goalLine) * (corner - goalLine))
        stroke(P.bothEnds(P.segment(goalLine, -reach, goalLine, reach), length: length).applying(t), .line, weight: 1.2)
        stroke(P.bothEnds(P.segment(22.86, -half, 22.86, half), length: length).applying(t), .line, weight: 3.6)
        stroke(P.segment(length / 2, -half, length / 2, half).applying(t), .line, weight: 3.6, dash: [hair * 10, hair * 2.5])

        var circles = Path(), hashes = Path(), spots: [CGPoint] = []
        for y: CGFloat in [-6.71, 6.71] {
            let centre = CGPoint(x: goalLine + 6.1, y: y)
            circles.addPath(P.circle(centre, 4.57))
            for side: CGFloat in [-1, 1] {
                for along: CGFloat in [-0.9, 0.9] {
                    hashes.addPath(P.segment(centre.x + along, centre.y + side * 4.57, centre.x + along, centre.y + side * 5.2))
                }
            }
            for x in [centre.x, 24.38] { spots += [CGPoint(x: x, y: y), CGPoint(x: length - x, y: y)] }
        }
        circles = P.bothEnds(circles, length: length)
        circles.addPath(P.circle(CGPoint(x: length / 2, y: 0), 4.57))
        stroke(circles.applying(t), .line, weight: 1.2)
        stroke(P.bothEnds(hashes, length: length).applying(t), .line, weight: 1.2)
        for point in spots + [CGPoint(x: length / 2, y: 0)] {
            dot(point.applying(t), radius: max(hair * 1.6, 0.3 * scale), .line)
        }

        var crease = Path()
        crease.move(to: CGPoint(x: goalLine, y: -1.22))
        crease.addLine(to: CGPoint(x: goalLine + 1.37, y: -1.22))
        P.addArc(&crease, center: CGPoint(x: goalLine, y: 0), radius: 1.83, from: -P.degrees(41.8), to: P.degrees(41.8), connect: true)
        crease.addLine(to: CGPoint(x: goalLine, y: 1.22))
        crease.closeSubpath()
        crease = P.bothEnds(crease, length: length)
        fill(crease.applying(t), .wash)
        stroke(crease.applying(t), .line)

        var net = Path()
        net.move(to: CGPoint(x: goalLine, y: -0.915))
        net.addQuadCurve(to: CGPoint(x: goalLine, y: 0.915), control: CGPoint(x: goalLine - 1.6, y: 0))
        net.addPath(P.segment(goalLine, -3.35, 0, -4.27))
        net.addPath(P.segment(goalLine, 3.35, 0, 4.27))
        stroke(P.bothEnds(net, length: length).applying(t), .faint, weight: 1.2)
    }

    // MARK: Rugby

    /// The pitch with one try line near the right edge and the touch line near the top: the
    /// posts, in goal, the 22, the dashed 10 and 5 metre lines, halfway, and the 5 and 15
    /// metre dashes along the touch line. Drawn whole, though most cards show only this end.
    func rugbyPitch() {
        typealias P = BackdropPainter
        let scale = unit * 0.0095 * zoom
        let t = plan(at(width - unit * 0.14, height * 0.66), scale: scale, leftwards: true)
        let length: CGFloat = 100, touch: CGFloat = 35

        var end = Path()
        end.addPath(P.segment(0, -touch, 0, touch))
        end.addPath(P.segment(22, -touch, 22, touch))
        var solid = P.bothEnds(end, length: length)
        solid.addPath(P.segment(-10, -touch, length + 10, -touch))
        solid.addPath(P.segment(-10, touch, length + 10, touch))
        solid.addPath(P.segment(length / 2, -touch, length / 2, touch))
        stroke(solid.applying(t), .line, weight: 1.2)
        stroke(P.bothEnds(P.segment(-10, -touch, -10, touch), length: length).applying(t), .faint, weight: 1.2)

        stroke(P.bothEnds(P.segment(40, -touch, 40, touch), length: length).applying(t), .line, weight: 1.2,
               dash: [scale * 2, scale * 2.5])
        stroke(P.bothEnds(P.segment(5, -touch, 5, touch), length: length).applying(t), .line, weight: 1.2,
               dash: [scale * 2, scale * 2.5])

        var long = Path()
        for y in [-touch + 5, -touch + 15, touch - 15, touch - 5] {
            long.addPath(P.segment(0, y, length, y))
        }
        stroke(long.applying(t), .faint, weight: 1.2, dash: [scale * 1, scale * 4])

        stroke(P.bothEnds(P.segment(0, -2.8, 0, 2.8), length: length).applying(t), .strong, weight: 2.2)
        for point in [CGPoint(x: 0, y: -2.8), CGPoint(x: 0, y: 2.8), CGPoint(x: length, y: -2.8), CGPoint(x: length, y: 2.8)] {
            dot(point.applying(t), radius: hair * 2.4, .strong)
        }
    }

    // MARK: Basketball

    /// The court with one basket near the right edge: the key, free throw circle, three point
    /// line, restricted area, backboard, the halfway line and centre circle; the near rim in the
    /// accent. Drawn whole, though most cards show only this end.
    func basketballCourt() {
        typealias P = BackdropPainter
        let scale = unit * 0.031 * zoom
        let t = plan(at(width - unit * 0.065, height * 0.47), scale: scale, leftwards: true)
        let length: CGFloat = 28, half: CGFloat = 7.5, rim = CGPoint(x: 1.575, y: 0)

        fill(P.bothEnds(P.rect(0, -2.45, 5.8, 2.45), length: length).applying(t), .wash)
        var end = Path()
        end.addPath(P.rect(0, -2.45, 5.8, 2.45))
        end.addPath(P.arc(center: CGPoint(x: 5.8, y: 0), radius: 1.8, from: -.pi / 2, to: .pi / 2))
        let corner = asin(6.6 / 6.75)
        end.move(to: CGPoint(x: 0, y: -6.6))
        end.addLine(to: CGPoint(x: rim.x + 6.75 * cos(corner), y: -6.6))
        P.addArc(&end, center: rim, radius: 6.75, from: -corner, to: corner, connect: true)
        end.addLine(to: CGPoint(x: 0, y: 6.6))
        end.move(to: CGPoint(x: 1.2, y: -1.25))
        end.addLine(to: CGPoint(x: rim.x, y: -1.25))
        P.addArc(&end, center: rim, radius: 1.25, from: -.pi / 2, to: .pi / 2, connect: true)
        end.addLine(to: CGPoint(x: 1.2, y: 1.25))
        for x: CGFloat in [1.75, 2.85, 3.7, 4.55] {
            end.addPath(P.segment(x, -2.45, x, -2.6))
            end.addPath(P.segment(x, 2.45, x, 2.6))
        }
        var lines = P.bothEnds(end, length: length)
        lines.addPath(P.rect(0, -half, length, half))
        lines.addPath(P.segment(length / 2, -half, length / 2, half))
        lines.addPath(P.circle(CGPoint(x: length / 2, y: 0), 1.8))
        stroke(lines.applying(t), .line, weight: 1.2)
        stroke(P.bothEnds(P.arc(center: CGPoint(x: 5.8, y: 0), radius: 1.8, from: .pi / 2, to: .pi * 1.5), length: length)
            .applying(t), .faint, dash: [hair * 4, hair * 4])

        stroke(P.bothEnds(P.segment(1.2, -0.9, 1.2, 0.9), length: length).applying(t), .strong, weight: 2)
        stroke(P.circle(CGPoint(x: length - rim.x, y: 0), 0.23).applying(t), .line, weight: 1.5)
        stroke(P.circle(rim, 0.23).applying(t), .accent, weight: 1.5)
    }

    // MARK: Snooker

    /// The table from above, baulk end on the left: cushions and rail, six pockets, the baulk
    /// line and D, and the spots.
    func snookerTable() {
        typealias P = BackdropPainter
        let scale = unit * 0.17 * zoom
        let length: CGFloat = 3.569, half: CGFloat = 0.889
        let t = plan(at(width - unit * 0.08 - length * scale, height * 0.33), scale: scale)

        fill(P.rect(0, -half, length, half).applying(t), .wash)
        stroke(P.rect(0, -half, length, half).applying(t), .strong, weight: 1.3)
        stroke(Path(roundedRect: CGRect(x: -0.11, y: -half - 0.11, width: length + 0.22, height: half * 2 + 0.22),
                    cornerRadius: 0.09).applying(t), .line, weight: 1.2)

        var pockets = Path()
        for x in [0, length / 2, length] {
            for y in [-half, half] {
                pockets.addPath(P.circle(CGPoint(x: x, y: y), 0.05))
            }
        }
        fill(pockets.applying(t), .line)

        var baulk = Path()
        baulk.addPath(P.segment(0.737, -half, 0.737, half))
        baulk.addPath(P.arc(center: CGPoint(x: 0.737, y: 0), radius: 0.292, from: .pi / 2, to: .pi * 1.5))
        stroke(baulk.applying(t), .line, weight: 1.2)

        let spots: [CGPoint] = [CGPoint(x: 0.737, y: -0.292), CGPoint(x: 0.737, y: 0), CGPoint(x: 0.737, y: 0.292),
                                CGPoint(x: length / 2, y: 0), CGPoint(x: (length / 2 + length) / 2, y: 0),
                                CGPoint(x: length - 0.324, y: 0)]
        for spot in spots { dot(spot.applying(t), radius: hair * 1.7, .strong) }
    }

    // MARK: Water

    /// Swell lines over the top of the card and a course of three buoys joined by a dashed
    /// line, the first mark in the accent.
    mutating func openWater() {
        let phase1 = random.range(0, 2 * .pi), phase2 = random.range(0, 2 * .pi)
        var swell = Path(), heavy = Path()
        let spacing = unit * 0.03
        var row = 0
        var y = height * 0.03 + variation.dy * unit
        while y < height * 0.8 {
            var line = Path()
            var x: CGFloat = 0
            while x <= width {
                let wave = unit * 0.006 * sin(x / (unit * 0.07) + phase1 + CGFloat(row) * 0.45)
                    + unit * 0.003 * sin(x / (unit * 0.025) + phase2 - CGFloat(row) * 0.3)
                let point = CGPoint(x: x, y: y + wave)
                if x == 0 { line.move(to: point) } else { line.addLine(to: point) }
                x += unit * 0.004
            }
            if row % 4 == 3 { heavy.addPath(line) } else { swell.addPath(line) }
            y += spacing
            row += 1
        }
        stroke(swell, .faint)
        stroke(heavy, .line, weight: 1.2)

        let marks = [at(width * 0.60, height * 0.15), at(width * 0.88, height * 0.27), at(width * 0.80, height * 0.56)]
        var course = Path()
        course.move(to: at(width * 0.30, height * 0.06))
        for mark in marks { course.addLine(to: mark) }
        course.addLine(to: at(width * 0.52, height * 0.50))
        stroke(course, .strong, weight: 1.2, dash: [hair * 5, hair * 4])
        let radius = unit * 0.009
        for (index, mark) in marks.enumerated() {
            fill(BackdropPainter.circle(mark, radius * 1.6), .wash)
            if index == 0 {
                stroke(BackdropPainter.circle(mark, radius), .accent, weight: 1.6)
            } else {
                stroke(BackdropPainter.circle(mark, radius), .strong, weight: 1.5)
            }
        }
    }

    // MARK: Generic

    /// The dial of a stopwatch, centred off the top right corner: fifths of a second, the
    /// sixty second marks, the twelve long marks, and one mark in the accent.
    func dial() {
        typealias P = BackdropPainter
        let centre = at(width - unit * 0.06, height * 0.02)
        let radius = unit * 0.46 * zoom

        stroke(P.circle(centre, radius), .line, weight: 1.3)
        stroke(P.circle(centre, radius * 0.86), .faint)
        stroke(P.circle(centre, radius * 0.62), .faint, dash: [hair * 2, hair * 5])
        stroke(P.circle(centre, radius * 1.08), .faint)

        var fine = Path(), seconds = Path(), long = Path()
        for tick in 0..<300 {
            let angle = CGFloat(tick) / 300 * 2 * .pi - .pi / 2
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            func point(_ r: CGFloat) -> CGPoint { CGPoint(x: centre.x + direction.x * r, y: centre.y + direction.y * r) }
            if tick % 25 == 0 {
                long.addPath(P.segment(point(radius * 0.88), point(radius)))
            } else if tick % 5 == 0 {
                seconds.addPath(P.segment(point(radius * 0.92), point(radius)))
            } else {
                fine.addPath(P.segment(point(radius * 0.965), point(radius)))
            }
        }
        stroke(fine, .faint)
        stroke(seconds, .line, weight: 1.2)
        stroke(long, .strong, weight: 1.8)

        // One second mark in the accent, somewhere on the visible lower left quarter of the dial.
        let tick = 30 + CGFloat(seed % 14)
        let angle = tick / 60 * 2 * .pi - .pi / 2
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        stroke(P.segment(CGPoint(x: centre.x + direction.x * radius * 0.92, y: centre.y + direction.y * radius * 0.92),
                         CGPoint(x: centre.x + direction.x * radius, y: centre.y + direction.y * radius)), .accent, weight: 1.8)
    }
}

/// A road or racecourse: a straight followed by one cubic bend, sampled into points with
/// normals so edges, kerbs and lines can be offset from the centre line.
struct Ribbon {
    let points: [CGPoint]
    /// Unit normals to the right of the direction of travel (y grows downwards).
    let normals: [CGPoint]

    init(start: CGPoint, straightTo bendStart: CGPoint,
         curve: (CGPoint, CGPoint, CGPoint), samples: Int = 400) {
        var points: [CGPoint] = []
        let straightSamples = samples / 4
        for i in 0..<straightSamples {
            let s = CGFloat(i) / CGFloat(straightSamples)
            points.append(CGPoint(x: start.x + (bendStart.x - start.x) * s, y: start.y + (bendStart.y - start.y) * s))
        }
        let bendSamples = samples - straightSamples
        for i in 0...bendSamples {
            let s = CGFloat(i) / CGFloat(bendSamples), r = 1 - s
            let a = r * r * r, b = 3 * r * r * s, c = 3 * r * s * s, d = s * s * s
            points.append(CGPoint(x: a * bendStart.x + b * curve.0.x + c * curve.1.x + d * curve.2.x,
                                  y: a * bendStart.y + b * curve.0.y + c * curve.1.y + d * curve.2.y))
        }
        self.points = points
        normals = points.indices.map { i in
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(0.0001, sqrt(dx * dx + dy * dy))
            return CGPoint(x: -dy / length, y: dx / length)
        }
    }

    private func index(_ s: CGFloat) -> Int {
        min(points.count - 1, max(0, Int((s * CGFloat(points.count - 1)).rounded())))
    }

    /// The point and right hand normal at `s`, 0 to 1 along the ribbon.
    func frame(at s: CGFloat) -> (CGPoint, CGPoint) {
        let i = index(s)
        return (points[i], normals[i])
    }

    /// Where the bend turns hardest, 0 to 1 along the ribbon.
    var apex: CGFloat {
        var best = 0, bestTurn: CGFloat = 0
        for i in 2..<(points.count - 2) {
            let a = normals[i - 2], b = normals[i + 2]
            let turn = abs(a.x * b.y - a.y * b.x)
            if turn > bestTurn { bestTurn = turn; best = i }
        }
        return CGFloat(best) / CGFloat(points.count - 1)
    }

    /// A line offset to the right of the centre line by `offset(s)` points.
    func path(offset: (CGFloat) -> CGFloat) -> Path {
        var path = Path()
        for i in points.indices {
            let s = CGFloat(i) / CGFloat(points.count - 1)
            let o = offset(s)
            let point = CGPoint(x: points[i].x + normals[i].x * o, y: points[i].y + normals[i].y * o)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    func offsetPath(_ offset: CGFloat, from start: CGFloat, to end: CGFloat) -> Path {
        var path = Path()
        let first = index(start), last = index(end)
        guard first < last else { return path }
        for i in first...last {
            let point = CGPoint(x: points[i].x + normals[i].x * offset, y: points[i].y + normals[i].y * offset)
            if i == first { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Kerb blocks outside the track edge on one side (1 right, -1 left), alternating tone.
    func kerb(painter: BackdropPainter, side: CGFloat, edge: CGFloat, depth: CGFloat,
              from start: CGFloat, to end: CGFloat, stripe: CGFloat) {
        var light = Path(), dark = Path()
        let first = index(start), last = index(end)
        guard first < last else { return }
        var blockStart = first, travelled: CGFloat = 0, isLight = true
        for i in (first + 1)...last {
            let dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y
            travelled += sqrt(dx * dx + dy * dy)
            if travelled >= stripe || i == last {
                var block = Path()
                let inner = edge * side, outer = (edge + depth) * side
                func point(_ j: Int, _ o: CGFloat) -> CGPoint {
                    CGPoint(x: points[j].x + normals[j].x * o, y: points[j].y + normals[j].y * o)
                }
                block.move(to: point(blockStart, inner))
                for j in blockStart...i { block.addLine(to: point(j, inner)) }
                for j in stride(from: i, through: blockStart, by: -1) { block.addLine(to: point(j, outer)) }
                block.closeSubpath()
                if isLight { light.addPath(block) } else { dark.addPath(block) }
                isLight.toggle()
                blockStart = i
                travelled = 0
            }
        }
        painter.fill(light, .strong)
        painter.fill(dark, .faint)
    }
}

/// Marching squares: the contour of a sampled field at one level, as line segments.
enum Contours {
    static func trace(grid: [CGFloat], columns: Int, rows: Int, cell: CGFloat, level: CGFloat, into path: inout Path) {
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let a = grid[row * columns + column]            // top left
                let b = grid[row * columns + column + 1]        // top right
                let c = grid[(row + 1) * columns + column + 1]  // bottom right
                let d = grid[(row + 1) * columns + column]      // bottom left
                var index = 0
                if a > level { index |= 8 }
                if b > level { index |= 4 }
                if c > level { index |= 2 }
                if d > level { index |= 1 }
                if index == 0 || index == 15 { continue }
                let x = CGFloat(column) * cell, y = CGFloat(row) * cell
                func lerp(_ p: CGFloat, _ q: CGFloat) -> CGFloat { (level - p) / (q - p) }
                let top = CGPoint(x: x + cell * lerp(a, b), y: y)
                let right = CGPoint(x: x + cell, y: y + cell * lerp(b, c))
                let bottom = CGPoint(x: x + cell * lerp(d, c), y: y + cell)
                let left = CGPoint(x: x, y: y + cell * lerp(a, d))
                func segment(_ p: CGPoint, _ q: CGPoint) { path.move(to: p); path.addLine(to: q) }
                switch index {
                case 1, 14: segment(left, bottom)
                case 2, 13: segment(bottom, right)
                case 3, 12: segment(left, right)
                case 4, 11: segment(top, right)
                case 5: segment(left, top); segment(bottom, right)
                case 6, 9: segment(top, bottom)
                case 7, 8: segment(left, top)
                case 10: segment(left, bottom); segment(top, right)
                default: break
                }
            }
        }
    }
}
