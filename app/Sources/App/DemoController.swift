import Foundation
import MomentsCore
import Observation

/// The demo controls: scrub through the day, step between moments, play the day
/// quickly, and go back to now. Works by setting `ClockModel.demoDate`.
@MainActor
@Observable
final class DemoController {
    let model: ClockModel
    private(set) var isPlaying = false

    /// Seconds each moment stays up while playing: long enough to read, and to see the crossfade.
    private let playInterval: Duration = .seconds(2.5)
    @ObservationIgnored private var playTask: Task<Void, Never>?

    init(model: ClockModel) {
        self.model = model
    }

    /// Whether the clock is showing a demo time rather than now.
    var isActive: Bool { model.demoDate != nil }

    /// The displayed minute of the day, 0 to 1439.
    var minuteOfDay: Int {
        let parts = model.calendar.dateComponents([.hour, .minute], from: model.displayDate)
        return parts.hour! * 60 + parts.minute!
    }

    /// Which minutes have a moment, with the current settings and time zone.
    var coverage: [Bool] {
        model.picker.coverage(zone: model.calendar.timeZone, settings: model.settings)
    }

    /// Minutes covered in each hour, 00 to 23.
    var minutesCoveredPerHour: [Int] {
        let coverage = coverage
        return (0..<24).map { hour in coverage[hour * 60 ..< hour * 60 + 60].filter { $0 }.count }
    }

    func scrub(toMinute minute: Int) {
        let minute = min(max(minute, 0), 1439)
        let day = model.displayDate
        model.demoDate = model.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }

    /// Jumps to the next (or previous) minute that has a moment, wrapping round the day.
    func step(forward: Bool) {
        let coverage = coverage
        let start = minuteOfDay
        for offset in 1...1440 {
            let minute = (start + (forward ? offset : -offset) + 1440) % 1440
            if coverage[minute] {
                scrub(toMinute: minute)
                return
            }
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func backToNow() {
        pause()
        model.demoDate = nil
    }

    private func play() {
        isPlaying = true
        playTask = Task {
            while !Task.isCancelled {
                step(forward: true)
                try? await Task.sleep(for: playInterval)
            }
        }
    }

    private func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }
}
