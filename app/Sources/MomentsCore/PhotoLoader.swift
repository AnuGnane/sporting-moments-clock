import AppKit
import ImageIO

/// Decodes bundled photos off the main thread, at no more than the screen needs.
///
/// ImageIO's thumbnail call decodes a JPEG straight to the smaller size, so the full
/// size bitmap never exists in memory.
enum PhotoLoader {
    static func load(_ url: URL, filling target: CGSize) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            decode(url, filling: target)
        }.value
    }

    /// The photo scaled to cover `target` pixels (aspect fill), never larger than the original.
    /// Nil when the file is missing or unreadable.
    static func decode(_ url: URL, filling target: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(of: source, filling: target),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The longest side the decoded photo needs for aspect fill. ImageIO does not enlarge,
    /// so a value above the original's size just means "full size".
    static func maxPixelSize(of source: CGImageSource, filling target: CGSize) -> CGFloat {
        let fallback = max(target.width, target.height)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return fallback }
        // EXIF orientations 5 to 8 are rotated a quarter turn, so width and height swap on screen.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        let scale = max(target.width / width, target.height / height)
        return (max(width, height) * scale).rounded(.up)
    }

    /// The largest screen's width and height in pixels: the clock window can go full screen on any of them.
    @MainActor
    static var largestScreenPixelSize: CGSize {
        let sizes = NSScreen.screens.map { CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor) }
        return CGSize(width: sizes.map(\.width).max() ?? 3840, height: sizes.map(\.height).max() ?? 2160)
    }
}
