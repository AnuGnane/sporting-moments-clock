// Installs the screen saver embedded in a built app into a folder, exactly as the app's
// Install button does (SaverInstaller), so make_release.sh can check that the installed
// copy's signature still verifies. Compiled with the core files it needs:
//
//     swiftc -parse-as-library dist/verify_install.swift app/Sources/MomentsCore/{SaverInstaller,SharedSettings,ClockSettings,AppIdentity}.swift
//     ./verify_install <SportingMomentsClock.app> <folder>

import Foundation

@main
struct VerifyInstall {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let app = Bundle(url: URL(filePath: arguments[1])) else {
            print("usage: verify_install <app> <folder>")
            exit(2)
        }
        let installer = SaverInstaller(source: SaverInstaller.embeddedSaver(in: app), directory: URL(filePath: arguments[2]))
        try installer.install()
        let status = installer.status()
        print("Installed \(installer.destination.path): \(status)")
        exit(status == .upToDate ? 0 : 1)
    }
}
