import CoreGraphics
import Foundation
import Observation
import os

/// Drives one clock screen: ticks every minute, asks the picker for a card, and loads
/// the card's photo before showing it so the crossfade goes straight to the finished card.
@MainActor
@Observable
public final class ClockModel {
    /// The card on screen. Nil only when no moment matches anything (for example every layer off).
    public private(set) var card: Card?
    /// The decoded photo for `card`, nil for type only cards and for photos that could not be read.
    public private(set) var photo: CGImage?
    /// True once the picker has run and found no card at all. False while the first card's photo loads.
    public private(set) var isEmpty = false
    /// The real time. Updated every minute.
    public private(set) var now = Date()

    public var settings: ClockSettings {
        didSet {
            guard settings != oldValue else { return }
            refresh()
            onSettingsChange?(settings)
        }
    }

    /// Called after `settings` changes, for example to save them.
    @ObservationIgnored public var onSettingsChange: (@MainActor (ClockSettings) -> Void)?

    /// The minute the demo controls are showing. Nil means live.
    public var demoDate: Date? {
        didSet { if demoDate != oldValue { refresh() } }
    }

    /// The viewer's calendar and time zone. Follows the system setting.
    public var calendar = Calendar.autoupdatingCurrent

    /// The area, in pixels, that photos are decoded to fill. Nil means the largest screen,
    /// measured when each photo loads. The screen saver sets its own view's size, so the
    /// System Settings thumbnail decodes small.
    @ObservationIgnored public var photoPixelSize: CGSize?

    public let picker: MomentPicker

    /// The time the card is chosen for: the demo time, or now.
    public var displayDate: Date { demoDate ?? now }

    @ObservationIgnored private var ticker: MinuteTicker?
    @ObservationIgnored private var photoTask: Task<Void, Never>?
    /// The viewer's time zone when `card` was picked. A kept card is only right in that zone.
    @ObservationIgnored private var cardZone: String?

    private static let log = Logger(subsystem: AppIdentity.bundleID, category: "clock")

    public init(store: MomentStore, settings: ClockSettings) {
        self.picker = MomentPicker(store: store)
        self.settings = settings
    }

    public func start() {
        if ticker == nil {
            ticker = MinuteTicker { [weak self] in self?.tick() }
        }
        ticker?.start()
        now = Date()
        refresh()
    }

    /// Stops the minute timer and drops any photo still loading. The card stays as it is.
    public func stop() {
        ticker?.stop()
        photoTask?.cancel()
        photoTask = nil
    }

    /// A new minute (or a wake, or a clock change): keep the previous card when nothing
    /// matches (rule 6). After a time zone change the previous card's times belong to the old
    /// zone, so pick afresh instead.
    func tick() {
        now = Date()
        let previous = cardZone == calendar.timeZone.identifier ? card : nil
        show(picker.resolve(at: displayDate, calendar: calendar, settings: settings, previous: previous))
    }

    /// Settings or demo time changed: pick afresh, walking back if this minute is empty.
    public func refresh() {
        show(picker.resolve(at: displayDate, calendar: calendar, settings: settings, previous: nil))
    }

    private func show(_ next: Card?) {
        isEmpty = next == nil
        // The latest request wins, even when it is for the card already on screen.
        photoTask?.cancel()
        photoTask = nil
        guard next != card else { return }
        let zone = calendar.timeZone.identifier
        guard let url = next?.photo?.url else {
            present(next, photo: nil, zone: zone)
            return
        }
        let size = photoPixelSize ?? PhotoLoader.largestScreenPixelSize
        photoTask = Task {
            let image = await PhotoLoader.load(url, filling: size)
            guard !Task.isCancelled else { return }
            present(next, photo: image, zone: zone)
        }
    }

    private func present(_ next: Card?, photo: CGImage?, zone: String) {
        if card == nil, let next {
            Self.log.info("First card shown: \(next.moment.id, privacy: .public), photo: \(photo != nil, privacy: .public)")
        }
        if next?.photo != nil, photo == nil {
            Self.log.error("Could not read photo \(next?.photo?.url.lastPathComponent ?? "", privacy: .public); showing type only")
        }
        card = next
        self.photo = photo
        cardZone = zone
    }
}
