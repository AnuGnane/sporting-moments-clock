import CoreText
import SwiftUI
import os

/// The four colours of the approved mockup.
public enum Palette {
    /// Night ground, #0c131f.
    public static let ground = Color(red: 0x0c / 255, green: 0x13 / 255, blue: 0x1f / 255)
    /// Text, #f3eee2.
    public static let text = Color(red: 0xf3 / 255, green: 0xee / 255, blue: 0xe2 / 255)
    /// Secondary text, #8f9bb0.
    public static let secondary = Color(red: 0x8f / 255, green: 0x9b / 255, blue: 0xb0 / 255)
    /// The one accent, #f4b740.
    public static let accent = Color(red: 0xf4 / 255, green: 0xb7 / 255, blue: 0x40 / 255)
}

/// Bundled fonts (SIL Open Font License, see Fonts/OFL-*.txt) with system fallbacks.
public enum Typography {
    private static let barlowSemiBold = "BarlowCondensed-SemiBold"
    private static let barlowMedium = "BarlowCondensed-Medium"
    private static let newsreader = "Newsreader16pt-Regular"
    private static let newsreaderItalic = "Newsreader16pt-Italic"

    private static let registered = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Registers the TTFs in `<bundle>/Contents/Resources/Fonts` for this process.
    /// Safe to call more than once (the saver host may create several views).
    /// Pass `Bundle(for:)` from the saver; `Bundle.main` there is legacyScreenSaver.
    public static func registerFonts(in bundle: Bundle) {
        let isNew = registered.withLock { $0.insert(bundle.bundlePath).inserted }
        guard isNew, let urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else { return }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered by another copy of the bundle is fine; anything else falls back to system fonts.
                let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                Logger(subsystem: AppIdentity.bundleID, category: "fonts")
                    .info("Font \(url.lastPathComponent, privacy: .public) not registered: \(message, privacy: .public)")
            }
        }
    }

    /// The huge time: Barlow Condensed SemiBold with tabular figures.
    public static func time(size: CGFloat) -> Font {
        custom(barlowSemiBold, size: size) ?? .system(size: size, weight: .semibold).width(.condensed)
    }

    /// Small condensed figures, used for the live clock.
    public static func figures(size: CGFloat) -> Font {
        custom(barlowMedium, size: size) ?? .system(size: size, weight: .medium).width(.condensed)
    }

    /// The caption: Newsreader, with its optical size axis set for the size it is drawn at.
    public static func caption(size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? newsreaderItalic : newsreader
        guard isAvailable(name) else {
            let serif = Font.system(size: size, design: .serif)
            return italic ? serif.italic() : serif
        }
        let opticalSize = min(max(size, 6), 72)
        let opszTag = 0x6F70737A  // 'opsz'
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: [opszTag: opticalSize],
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// Labels and small lines use the system font, as in the mockup.
    public static func small(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    private static func custom(_ name: String, size: CGFloat) -> Font? {
        isAvailable(name) ? Font.custom(name, fixedSize: size).monospacedDigit() : nil
    }

    private static func isAvailable(_ name: String) -> Bool {
        CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name
    }
}
