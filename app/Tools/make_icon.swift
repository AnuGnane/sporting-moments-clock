// Draws the app icon, the screen saver thumbnail and the menu bar glyph.
//
//     cd app && swift Tools/make_icon.swift
//
// Writes:
//   Sources/App/Assets.xcassets/AppIcon.appiconset    16 to 1024 px, 1x and 2x
//   Sources/App/Assets.xcassets/MenuBarIcon.imageset  template image, 18 pt
//   Sources/Saver/thumbnail.png, thumbnail@2x.png     System Settings thumbnail
//
// The artwork: two warm white digits in Barlow Condensed SemiBold over an amber bar, on
// the night blue ground of the card. The leading zero makes them read as clock hours
// (09, as in Bolt's 9.58 at 09:58) rather than a calendar date. The menu bar glyph is the
// same mark drawn as a line glyph: two zeros over the bar.

import AppKit
import CoreText
import SwiftUI

let app = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

// MARK: - Palette and type

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let groundTop = rgb(0x172236)
let groundBottom = rgb(0x0c131f)
let digitsColor = rgb(0xf3eee2)
let accent = rgb(0xf4b740)

let fontURL = app.appending(path: "Fonts/BarlowCondensed-SemiBold.ttf")
guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first else {
    fatalError("Cannot read \(fontURL.path)")
}

/// The digits on the icon.
let digits = "09"

// MARK: - Drawing

/// Draws the mark (digits over the accent bar) centred in `rect`, `height` tall from bar to top of digits.
func drawMark(in context: CGContext, center: CGPoint, digitHeight: CGFloat, minimumBar: CGFloat = 0) {
    // Cap height of Barlow is 0.7 em; size the font so the figures are `digitHeight` tall.
    let font = CTFontCreateWithFontDescriptor(descriptor, digitHeight / 0.7, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: digitsColor,
        .kern: digitHeight * 0.02,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: digits, attributes: attributes))
    let ink = CTLineGetImageBounds(line, context)

    let barHeight = max(digitHeight * 0.085, minimumBar)
    let gap = max(digitHeight * 0.12, barHeight * 0.9)
    let totalHeight = ink.height + gap + barHeight
    let bottom = center.y - totalHeight / 2

    // Bar: as wide as the digits' ink.
    let barRect = CGRect(x: center.x - ink.width / 2, y: bottom, width: ink.width, height: barHeight)
    context.setFillColor(accent)
    context.fill(barRect.integralIfLarge(digitHeight))

    // Digits: optically centred on their ink, not their advance.
    context.textPosition = CGPoint(x: center.x - ink.width / 2 - ink.minX, y: bottom + barHeight + gap - ink.minY)
    CTLineDraw(line, context)
}

extension CGRect {
    /// Snaps to whole pixels at small sizes, where a half covered pixel turns grey.
    func integralIfLarge(_ scale: CGFloat) -> CGRect { scale < 64 ? integral : self }
}

/// The icon: the macOS rounded square (824 of 1024, with a soft shadow) holding the mark.
func drawIcon(in context: CGContext, size: CGFloat) {
    let unit = size / 1024
    let square = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let path = RoundedRectangle(cornerRadius: 185 * unit, style: .continuous).path(in: square).cgPath

    context.saveGState()
    if size >= 64 {
        context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 20 * unit, color: CGColor(gray: 0, alpha: 0.35))
    }
    context.addPath(path)
    context.setFillColor(groundBottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [groundTop, groundBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: square.maxY), end: CGPoint(x: 0, y: square.minY), options: [])
    drawMark(in: context, center: CGPoint(x: size / 2, y: size / 2), digitHeight: 430 * unit, minimumBar: size <= 32 ? 1.5 : 0)
    context.restoreGState()
}

/// The thumbnail: the same mark on a full bleed ground.
func drawThumbnail(in context: CGContext, size: CGSize) {
    let gradient = CGGradient(colorsSpace: nil, colors: [groundTop, groundBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
    drawMark(in: context, center: CGPoint(x: size.width / 2, y: size.height / 2), digitHeight: size.height * 0.42)
}

/// The menu bar glyph, black on clear for a template image: two outlined zeros over the bar.
func drawMenuBarGlyph(in context: CGContext, size: CGFloat) {
    let pt = size / 18
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setLineWidth(1.5 * pt)
    for x in [3.25, 9.75] {
        let zero = CGRect(x: x * pt, y: 6.25 * pt, width: 5 * pt, height: 9.5 * pt)
        context.addPath(Capsule(style: .continuous).path(in: zero).cgPath)
    }
    context.strokePath()
    context.fill(CGRect(x: 2.5 * pt, y: 2 * pt, width: 13 * pt, height: 2 * pt))
}

// MARK: - Output

func png(width: Int, height: Int, to url: URL, draw: (CGContext) -> Void) {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldSmoothFonts(false)
    context.interpolationQuality = .high
    draw(context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
}

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

let files = FileManager.default
let assets = app.appending(path: "Sources/App/Assets.xcassets")
let iconSet = assets.appending(path: "AppIcon.appiconset")
let menuSet = assets.appending(path: "MenuBarIcon.imageset")
for folder in [iconSet, menuSet] {
    try? files.removeItem(at: folder)
    try! files.createDirectory(at: folder, withIntermediateDirectories: true)
}
writeJSON(["info": ["author": "xcode", "version": 1]], to: assets.appending(path: "Contents.json"))

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        png(width: pixels, height: pixels, to: iconSet.appending(path: name)) { drawIcon(in: $0, size: CGFloat(pixels)) }
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], to: iconSet.appending(path: "Contents.json"))

var glyphs: [[String: String]] = []
for scale in [1, 2] {
    let name = "menubar\(scale == 2 ? "@2x" : "").png"
    png(width: 18 * scale, height: 18 * scale, to: menuSet.appending(path: name)) { drawMenuBarGlyph(in: $0, size: CGFloat(18 * scale)) }
    glyphs.append(["idiom": "mac", "scale": "\(scale)x", "filename": name])
}
writeJSON(["images": glyphs, "info": ["author": "xcode", "version": 1], "properties": ["template-rendering-intent": "template"]],
          to: menuSet.appending(path: "Contents.json"))

for scale in [1, 2] {
    let name = "thumbnail\(scale == 2 ? "@2x" : "").png"
    png(width: 90 * scale, height: 58 * scale, to: app.appending(path: "Sources/Saver/\(name)")) {
        drawThumbnail(in: $0, size: CGSize(width: 90 * scale, height: 58 * scale))
    }
}
print("Wrote \(iconSet.path), \(menuSet.path) and the saver thumbnails")
