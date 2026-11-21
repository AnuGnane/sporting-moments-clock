import SwiftUI

/// One moment: photo (when there is one) under a dark gradient, and the lower left
/// lockup of accent line, the current time, caption and date line. Designed to look finished as type alone.
struct CardView: View {
    let card: Card?
    let photo: CGImage?
    /// The current time (or the demo time), "HH:mm". Always the big figure on screen.
    let clock: String
    /// True once the picker has run and found nothing, for example with every layer off.
    let showsEmptyMessage: Bool
    let metrics: CardMetrics

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                PhotoBackdrop(photo: photo, metrics: metrics)
            } else {
                // No photo: the sport's own geometry, drawn once per card (the stopwatch dial before the first card).
                SportBackdrop(motif: card.map { SportMotif(sport: $0.moment.sport) } ?? .dial,
                              seed: backdropSeed(card?.moment.id ?? ""), size: metrics.size)
                    .equatable()
            }

            if let card {
                lockup(for: card)
            } else {
                emptyLockup
            }

            if let credit = card?.photo?.credit, photo != nil {
                Text(credit)
                    .font(Typography.small(size: metrics.credit))
                    .foregroundStyle(Palette.secondary.opacity(0.85))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: metrics.size.width * 0.3, alignment: .trailing)
                    .padding(.trailing, metrics.margin)
                    .padding(.bottom, metrics.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .clipped()
    }

    private func lockup(for card: Card) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // No accent line when it would only repeat the clock: the lockup starts with the time.
            if let headline = card.headline(clock: clock) {
                Text(headline.uppercased())
                    .font(Typography.small(size: metrics.headline, weight: .semibold))
                    .tracking(metrics.headline * 0.14)
                    .foregroundStyle(Palette.accent)
            }

            BigTime(text: clock, metrics: metrics)

            Text(card.caption)
                .font(Typography.caption(size: metrics.caption, italic: card.isQuotation))
                .foregroundStyle(Palette.text)
                .lineSpacing(metrics.caption * 0.12)
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: metrics.captionWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.caption * 0.15)

            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(Typography.small(size: metrics.small))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: metrics.captionWidth, alignment: .leading)
                    .padding(.top, metrics.small * 1.3)
            }
        }
        .shadow(color: Palette.ground.opacity(photo == nil ? 0 : 0.5), radius: metrics.unit * 0.006)
        .padding(.leading, metrics.margin)
        .padding(.bottom, metrics.margin)
        // One element for VoiceOver, with the accent line in sentence case rather than capitals.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([clock, card.headline(clock: clock), card.caption, card.detail]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". "))
    }

    /// No card yet (still loading), or nothing matches with these settings.
    private var emptyLockup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SPORTING MOMENTS CLOCK")
                .font(Typography.small(size: metrics.small, weight: .semibold))
                .tracking(metrics.small * 0.16)
                .foregroundStyle(Palette.accent)
            BigTime(text: clock, metrics: metrics)
            if showsEmptyMessage {
                Text("No moment matches these settings. Turn on a layer in Settings.")
                    .font(Typography.caption(size: metrics.caption * 0.7))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: metrics.captionWidth, alignment: .leading)
            }
        }
        .padding(.leading, metrics.margin)
        .padding(.bottom, metrics.margin)
        .accessibilityElement(children: .combine)
    }
}

/// The current time. Barlow Condensed has generous space above its figures, which the
/// negative padding takes back so the label sits close, as in the mockup.
private struct BigTime: View {
    let text: String
    let metrics: CardMetrics

    var body: some View {
        Text(text)
            .font(Typography.time(size: metrics.time))
            .foregroundStyle(Palette.text)
            .kerning(-metrics.time * 0.005)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, -metrics.time * 0.17)
            .padding(.bottom, -metrics.time * 0.12)
    }
}

/// Full bleed photo, aspect fill, under a gradient rising from the bottom so the type keeps its contrast.
/// Landscape photos fill the card, centred. A portrait photo on a wide card is shown whole as a
/// panel at the right edge; where that does not fit it fills the card, framed from near the top
/// (see `PhotoFraming`).
private struct PhotoBackdrop: View {
    let photo: CGImage
    let metrics: CardMetrics

    var body: some View {
        let image = CGSize(width: photo.width, height: photo.height)
        if let panel = PhotoFraming.panel(image: image, on: metrics.size) {
            sidePanel(panel)
        } else {
            fullBleed(PhotoFraming.rect(image: image, filling: metrics.size))
        }
    }

    private func fullBleed(_ frame: CGRect) -> some View {
        placed(frame)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Palette.ground.opacity(0.96), location: 0),
                        .init(color: Palette.ground.opacity(0.86), location: 0.3),
                        .init(color: Palette.ground.opacity(0.55), location: 0.55),
                        .init(color: Palette.ground.opacity(0.25), location: 0.8),
                        .init(color: Palette.ground.opacity(0.4), location: 1),
                    ],
                    startPoint: .bottom, endPoint: .top
                )
            }
    }

    /// A tall photo, usually a portrait of an athlete, shown whole at the right edge. Its left
    /// side fades into the ground so the lockup on the left stays on a calm surface.
    private func sidePanel(_ frame: CGRect) -> some View {
        let fadeEnd = (frame.minX + frame.width * 0.55) / metrics.size.width
        return ZStack {
            Palette.ground
            placed(frame)
            LinearGradient(
                stops: [
                    .init(color: Palette.ground, location: 0),
                    .init(color: Palette.ground, location: frame.minX / metrics.size.width),
                    .init(color: Palette.ground.opacity(0.0), location: fadeEnd),
                    .init(color: Palette.ground.opacity(0.15), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: Palette.ground.opacity(0.85), location: 0),
                    .init(color: Palette.ground.opacity(0.35), location: 0.3),
                    .init(color: Palette.ground.opacity(0.1), location: 0.6),
                    .init(color: Palette.ground.opacity(0.25), location: 1),
                ],
                startPoint: .bottom, endPoint: .top
            )
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
    }

    private func placed(_ frame: CGRect) -> some View {
        Image(decorative: photo, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.midX - metrics.size.width / 2, y: frame.midY - metrics.size.height / 2)
            .frame(width: metrics.size.width, height: metrics.size.height)
            .clipped()
    }
}

/// Where an aspect fill photo sits on the card. Landscape and square photos are centred, as
/// before. A portrait photo (taller than wide), usually an athlete, would lose the head to a
/// centre crop, so the point a quarter of the way down the photo goes to the middle of the
/// card instead, which keeps roughly the top third in view, never uncovering the card's edges.
enum PhotoFraming {
    /// The fraction of a portrait photo's height that is placed at the card's vertical middle.
    static let portraitFocus: CGFloat = 0.25

    /// A photo shown whole takes at most this share of the card's width as a side panel.
    static let panelMaxWidth: CGFloat = 0.6

    /// Where a tall photo sits when it is shown whole at the right edge of a wide card, or nil
    /// when the photo should fill the card. A portrait blown up to fill a wide screen shows
    /// little more than a face, behind the text; as a panel it keeps the whole figure.
    static func panel(image: CGSize, on card: CGSize) -> CGRect? {
        guard image.width > 0, image.height > image.width, card.width > card.height else { return nil }
        let width = card.height * image.width / image.height
        guard width <= card.width * panelMaxWidth else { return nil }
        return CGRect(x: card.width - width, y: 0, width: width, height: card.height)
    }

    /// The photo's rectangle in card coordinates. It always covers the whole card.
    static func rect(image: CGSize, filling card: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: card) }
        let scale = max(card.width / image.width, card.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        var y = (card.height - size.height) / 2
        if image.height > image.width {
            y = min(0, max(card.height - size.height, card.height / 2 - size.height * portraitFocus))
        }
        return CGRect(x: (card.width - size.width) / 2, y: y, width: size.width, height: size.height)
    }
}
