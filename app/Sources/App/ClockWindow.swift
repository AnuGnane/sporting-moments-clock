import MomentsCore
import SwiftUI

/// The app's one window: the clock, with the demo bar fading in when the mouse moves.
struct ClockWindow: View {
    let model: ClockModel
    let demo: DemoController
    let deskClock: DeskClockMode

    @State private var isBarVisible = false
    @State private var isPointerOnBar = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showsWelcome = false

    /// Pass `-StartInDeskClockMode YES` (or set the default) to open straight into full screen.
    private var startsInDeskClockMode: Bool { UserDefaults.standard.bool(forKey: "StartInDeskClockMode") }

    var body: some View {
        ClockScreen(model: model)
            .overlay(alignment: .top) {
                DemoBar(demo: demo, deskClock: deskClock)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .opacity(isBarVisible ? 1 : 0)
                    .allowsHitTesting(isBarVisible)
                    .onHover { isPointerOnBar = $0 }
            }
            .onContinuousHover { phase in
                if case .active = phase { showBar() }
            }
            .onChange(of: model.demoDate) { showBar() }
            .onChange(of: demo.isPlaying) { showBar() }
            .background(DemoKeys(demo: demo))
            .onAppear {
                if startsInDeskClockMode {
                    DispatchQueue.main.async { deskClock.toggle() }
                } else {
                    showsWelcome = WelcomeView.shouldShow()
                }
            }
            .sheet(isPresented: $showsWelcome) { WelcomeView() }
            .onDisappear {
                // Closing the window ends the demo, so the menu bar shows the real time again
                // and a playing demo stops waking the app every few seconds.
                demo.backToNow()
                hideTask?.cancel()
            }
    }

    /// Shows the bar, then fades it (and, in desk clock mode, the pointer) after a few quiet seconds.
    private func showBar() {
        if !isBarVisible {
            withAnimation(.easeOut(duration: 0.2)) { isBarVisible = true }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if isPointerOnBar {
                showBar()
                return
            }
            withAnimation(.easeInOut(duration: 0.8)) { isBarVisible = false }
            if deskClock.isOn { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }
}

/// Demo controls: previous, play, next, a 24 hour coverage strip to scrub, back to now,
/// desk clock mode and settings.
struct DemoBar: View {
    let demo: DemoController
    let deskClock: DeskClockMode
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 14) {
                barButton("backward.end.fill", "Previous moment", key: "Left Arrow") { demo.step(forward: false) }
                barButton(demo.isPlaying ? "pause.fill" : "play.fill", demo.isPlaying ? "Pause" : "Play the day", key: "Space") {
                    demo.togglePlay()
                }
                barButton("forward.end.fill", "Next moment", key: "Right Arrow") { demo.step(forward: true) }
            }

            VStack(alignment: .leading, spacing: 4) {
                DayStrip(
                    minutesPerHour: demo.minutesCoveredPerHour,
                    minuteOfDay: demo.minuteOfDay,
                    onScrub: demo.scrub(toMinute:)
                )
                .frame(height: 26)
                HourTicks()
            }
            .frame(minWidth: 240)

            VStack(alignment: .trailing, spacing: 2) {
                Text(LocalDateTime.timeText(minuteOfDay: demo.minuteOfDay))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                Text(demo.isActive ? "DEMO" : "LIVE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(demo.isActive ? Palette.accent : Palette.secondary)
            }
            .frame(width: 54, alignment: .trailing)

            HStack(spacing: 14) {
                barButton("clock.arrow.circlepath", "Back to now", key: "N") { demo.backToNow() }
                    .disabled(!demo.isActive)
                    .opacity(demo.isActive ? 1 : 0.35)
                barButton(
                    deskClock.isOn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    deskClock.isOn ? "Leave desk clock mode" : "Desk clock mode",
                    key: deskClock.isOn ? nil : "full screen, display stays on"
                ) { deskClock.toggle() }
                barButton("gearshape.fill", "Settings") { openWindow.bringForward(WindowID.settings) }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 900)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }

    /// An icon button. `label` is what VoiceOver reads; the tooltip adds `key` in brackets.
    private func barButton(_ symbol: String, _ label: String, key: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key.map { "\(label) (\($0))" } ?? label)
        .accessibilityLabel(label)
    }
}

/// 24 bars, one per hour, as tall as the share of that hour's minutes that have a moment.
/// Click or drag anywhere on it to scrub.
private struct DayStrip: View {
    let minutesPerHour: [Int]
    let minuteOfDay: Int
    let onScrub: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(minutesPerHour.indices, id: \.self) { hour in
                        let share = CGFloat(minutesPerHour[hour]) / 60
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Palette.accent.opacity(0.35 + 0.65 * share))
                            .frame(height: max(2, height * share))
                            .frame(maxWidth: .infinity)
                    }
                }
                Capsule()
                    .fill(Palette.text)
                    .frame(width: 2, height: height + 6)
                    .offset(x: width * CGFloat(minuteOfDay) / 1440 - 1, y: 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onScrub(Int(value.location.x / max(width, 1) * 1440))
                }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Day strip")
        .accessibilityValue(LocalDateTime.timeText(minuteOfDay: minuteOfDay))
        .accessibilityAdjustableAction { direction in
            onScrub(minuteOfDay + (direction == .increment ? 15 : -15))
        }
    }
}

private struct HourTicks: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(Palette.secondary)
    }
}
