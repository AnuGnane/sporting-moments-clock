import SwiftUI

/// The whole screen: the current card, crossfading when it changes. The big clock on the
/// card is always the current time (or the demo time).
/// Shared by the app window and the screen saver.
public struct ClockScreen: View {
    let model: ClockModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ClockModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = CardMetrics(size: proxy.size)
            ZStack {
                Palette.ground

                // Crossfade between cards (a cut with Reduce Motion on). The clock text changes without animation.
                ZStack {
                    CardView(card: model.card, photo: model.photo, clock: clockText(model.displayDate, calendar: model.calendar),
                             showsEmptyMessage: model.isEmpty, metrics: metrics)
                        .id(model.card?.id)
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: model.card?.id)
            }
        }
        .ignoresSafeArea()
    }
}

/// Every size on the card is a fraction of one unit, so the design holds from the
/// System Settings thumbnail to a 6K display. The unit is the width, limited by the
/// height on very wide screens so the type never outgrows them.
struct CardMetrics {
    let size: CGSize
    var unit: CGFloat { min(size.width, size.height * 1.6) }

    var margin: CGFloat { unit * 0.05 }
    var time: CGFloat { unit * 0.13 }
    var headline: CGFloat { unit * 0.018 }
    var caption: CGFloat { unit * 0.035 }
    var small: CGFloat { unit * 0.0145 }
    var credit: CGFloat { unit * 0.0105 }
    var captionWidth: CGFloat { size.width * 0.62 }
}

/// "HH:mm" in the calendar's time zone, 24 hour whatever the locale says.
func clockText(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return LocalDateTime.timeText(minuteOfDay: parts.hour! * 60 + parts.minute!)
}
