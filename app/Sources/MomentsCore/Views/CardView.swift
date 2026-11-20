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
                TypeBackdrop(metrics: metrics)
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
private struct PhotoBackdrop: View {
    let photo: CGImage
    let metrics: CardMetrics

    var body: some View {
        Image(decorative: photo, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: metrics.size.width, height: metrics.size.height)
            .clipped()
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
}

/// The ground for type only cards: night blue with a faint lift behind the lockup.
private struct TypeBackdrop: View {
    let metrics: CardMetrics

    var body: some View {
        RadialGradient(
            colors: [Color(red: 0x17 / 255, green: 0x22 / 255, blue: 0x36 / 255), Palette.ground],
            center: UnitPoint(x: 0.2, y: 0.85),
            startRadius: 0,
            endRadius: metrics.unit * 0.75
        )
    }
}
