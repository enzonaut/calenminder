// Generates Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
// Run: swift scripts/generate-appicon.swift
// Design: Apple Calendar-style date tile - white card, red weekday word,
// large thin date numeral - plus a small task row (red check + dashes) at
// the bottom to mark it as Calenminder. The date is static (MONDAY 17);
// iOS does not allow third-party apps to render a live date on the icon.
import AppKit
import Foundation

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let red = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)      // Apple system red
let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let dashGray = NSColor(srgbRed: 0.82, green: 0.81, blue: 0.79, alpha: 1)

// Background: white with a whisper of vertical gradient.
let bg = NSGradient(
    starting: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    ending: NSColor(srgbRed: 0.965, green: 0.96, blue: 0.95, alpha: 1)
)!
bg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// AppKit origin is bottom-left; helper converts a top-origin center y.
func centerRect(for text: NSAttributedString, centerYTop: CGFloat) -> NSPoint {
    let bounds = text.size()
    return NSPoint(
        x: (CGFloat(size) - bounds.width) / 2,
        y: CGFloat(size) - centerYTop - bounds.height / 2
    )
}

// Weekday word, red, semibold, letterspaced - MONDAY, for the recycling task.
let weekdayStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 108, weight: .semibold),
    .foregroundColor: red,
    .kern: 14,
]
let weekday = NSAttributedString(string: "MONDAY", attributes: weekdayStyle)
weekday.draw(at: centerRect(for: weekday, centerYTop: 208))

// Large thin date numeral.
let numeralStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 512, weight: .thin),
    .foregroundColor: ink,
]
let numeral = NSAttributedString(string: "17", attributes: numeralStyle)
numeral.draw(at: centerRect(for: numeral, centerYTop: 520))

// Task row at the bottom: red checkmark, then two rounded dashes.
let rowCenterYTop: CGFloat = 862
let rowY = CGFloat(size) - rowCenterYTop

let check = NSBezierPath()
check.lineWidth = 26
check.lineCapStyle = .round
check.lineJoinStyle = .round
let checkOriginX: CGFloat = 242  // centers the 540pt check+dashes group
check.move(to: NSPoint(x: checkOriginX, y: rowY + 2))
check.line(to: NSPoint(x: checkOriginX + 40, y: rowY - 38))
check.line(to: NSPoint(x: checkOriginX + 112, y: rowY + 46))
red.setStroke()
check.stroke()

dashGray.setFill()
for (index, width) in [CGFloat(200), CGFloat(132)].enumerated() {
    let x = checkOriginX + 172 + CGFloat(index) * 236
    let dash = NSBezierPath(
        roundedRect: NSRect(x: x, y: rowY - 14, width: width, height: 30),
        xRadius: 15, yRadius: 15
    )
    dash.fill()
}

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let outURL = URL(fileURLWithPath: "Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outURL)
print("wrote \(outURL.path)")
