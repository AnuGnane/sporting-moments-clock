import AppKit
import MomentsCore
import SwiftUI

/// The saver's Options sheet. Settings live in the Sporting Moments Clock app: the saver
/// runs in a sandboxed host that can read the app's settings but not write them.
@MainActor
enum ConfigureSheet {
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let content = ConfigureSheetView(appURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppIdentity.bundleID)) {
            [weak window] in
            guard let window else { return }
            if let parent = window.sheetParent {
                parent.endSheet(window)
            } else {
                window.close()
            }
        }
        window.contentViewController = NSHostingController(rootView: content)
        return window
    }
}

private struct ConfigureSheetView: View {
    let appURL: URL?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sporting Moments Clock")
                .font(.headline)
            Text("Settings for this screen saver are in the Sporting Moments Clock app: its menu bar icon and its Settings window.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if let appURL {
                    Button("Open Sporting Moments Clock") {
                        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                        close()
                    }
                }
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
