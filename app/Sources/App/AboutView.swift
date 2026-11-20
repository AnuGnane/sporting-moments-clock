import AppKit
import SwiftUI

/// The app's name, version and copyright, read from Info.plist (set in project.yml).
enum AppInfo {
    static let tagline = "The time, told by famous sporting moments."

    /// "1.0 (1)".
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}

/// The About window: icon, name, version, one line on what it is, and the credits.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Sporting Moments Clock")
                .font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version)")
                .foregroundStyle(.secondary)
            Text(AppInfo.tagline)
                .padding(.top, 4)
            Button("Credits") { openWindow.bringForward(WindowID.credits) }
                .padding(.vertical, 6)
            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(width: 340)
    }
}
