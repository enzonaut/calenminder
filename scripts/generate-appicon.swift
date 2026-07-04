// Generates Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
// Run: swift scripts/generate-appicon.swift
// Design: a calendar card (red header with binder rings, white body with a
// month grid) with a large red checkmark in front of it - a calendar with
// a check on it.
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

let redTop = NSColor(srgbRed: 1.00, green: 0.42, blue: 0.35, alpha: 1)
let redBottom = NSColor(srgbRed: 0.87, green: 0.18, blue: 0.14, alpha: 1)
let checkRed = NSColor(srgbRed: 0.91, green: 0.23, blue: 0.17, alpha: 1)
let cellGray = NSColor(srgbRed: 0.90, green: 0.89, blue: 0.87, alpha: 1)
let ringGray = NSColor(srgbRed: 0.62, green: 0.63, blue: 0.66, alpha: 1)

// Backdrop: soft neutral gradient.
NSGradient(
    starting: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1),
    ending: NSColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// AppKit origin is bottom-left; layout constants below use top-origin
// mental math converted inline (y = 1024 - topY - height).

// Calendar card with a soft shadow. Top-origin: x 132, y 172, w 760, h 724.
let cardRect = NSRect(x: 132, y: 1024 - 172 - 724, width: 760, height: 724)
let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 64, yRadius: 64)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.22)
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowBlurRadius = 42
shadow.set()
NSColor.white.setFill()
cardPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Red header: top 196pt of the card, rounded only at the card's top corners
// (clip to the card path, fill a rect).
NSGraphicsContext.current?.saveGraphicsState()
cardPath.addClip()
let headerRect = NSRect(x: cardRect.minX, y: cardRect.maxY - 196, width: cardRect.width, height: 196)
NSGradient(starting: redTop, ending: redBottom)!.draw(in: headerRect, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// Binder rings: two capsules straddling the card's top edge.
ringGray.setFill()
for ringX in [cardRect.minX + 190, cardRect.maxX - 190 - 44] {
    let ring = NSBezierPath(
        roundedRect: NSRect(x: ringX, y: cardRect.maxY - 58, width: 44, height: 148),
        xRadius: 22, yRadius: 22
    )
    ring.fill()
}

// Month grid on the card body: 4 columns x 3 rows.
let cell: CGFloat = 108, gap: CGFloat = 34
let gridW = 4 * cell + 3 * gap
let gridX = cardRect.minX + (cardRect.width - gridW) / 2
let bodyTop = cardRect.maxY - 196          // y of header bottom
let gridTopInset: CGFloat = 62
cellGray.setFill()
for row in 0..<3 {
    for col in 0..<4 {
        let x = gridX + CGFloat(col) * (cell + gap)
        let yTop = bodyTop - gridTopInset - CGFloat(row) * (cell + gap)
        let dayCell = NSBezierPath(
            roundedRect: NSRect(x: x, y: yTop - cell, width: cell, height: cell),
            xRadius: 22, yRadius: 22
        )
        dayCell.fill()
    }
}

// The big checkmark in front, bottom-right heavy: white halo stroke first,
// red stroke on top, both with its own drop shadow so it floats over the card.
func checkPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    p.move(to: NSPoint(x: 356, y: 1024 - 610))
    p.line(to: NSPoint(x: 540, y: 1024 - 796))
    p.line(to: NSPoint(x: 872, y: 1024 - 388))
    return p
}
NSGraphicsContext.current?.saveGraphicsState()
let checkShadow = NSShadow()
checkShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
checkShadow.shadowOffset = NSSize(width: 0, height: -14)
checkShadow.shadowBlurRadius = 30
checkShadow.set()
let halo = checkPath()
halo.lineWidth = 176
NSColor.white.setStroke()
halo.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

let check = checkPath()
check.lineWidth = 108
checkRed.setStroke()
check.stroke()

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let outURL = URL(fileURLWithPath: "Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outURL)
print("wrote \(outURL.path)")
