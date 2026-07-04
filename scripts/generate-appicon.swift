// Generates Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
// Run: swift scripts/generate-appicon.swift
// Design: flat desk-calendar - red header band, off-white body with a month
// grid, one day filled red with a white checkmark (the "task done" nod).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

// Convert a top-left-origin rect to CoreGraphics' bottom-left origin.
func rect(x: CGFloat, yTop: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(size) - yTop - h, width: w, height: h)
}

// Body.
ctx.setFillColor(rgb(250, 249, 246))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Header band with a vertical gradient.
let headerHeight: CGFloat = 300
let headerRect = rect(x: 0, yTop: 0, w: 1024, h: headerHeight)
ctx.saveGState()
ctx.clip(to: headerRect)
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(255, 106, 90), rgb(222, 47, 35)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: 0, y: CGFloat(size) - headerHeight),
    options: []
)
ctx.restoreGState()

// Weekday tick marks in the header (abstract, no text).
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
let tickW: CGFloat = 88, tickH: CGFloat = 26, tickGap: CGFloat = 40
let ticksTotal = 4 * tickW + 3 * tickGap
var tickX = (CGFloat(size) - ticksTotal) / 2
for _ in 0..<4 {
    let path = CGPath(roundedRect: rect(x: tickX, yTop: 137, w: tickW, h: tickH), cornerWidth: 13, cornerHeight: 13, transform: nil)
    ctx.addPath(path)
    ctx.fillPath()
    tickX += tickW + tickGap
}

// Month grid: 4 columns x 3 rows of rounded day cells.
let cell: CGFloat = 152, gap: CGFloat = 40
let gridW = 4 * cell + 3 * gap
let gridH = 3 * cell + 2 * gap
let startX = (CGFloat(size) - gridW) / 2
let startY = headerHeight + (CGFloat(size) - headerHeight - gridH) / 2
let accentCol = 3, accentRow = 2

for row in 0..<3 {
    for col in 0..<4 {
        let cellRect = rect(
            x: startX + CGFloat(col) * (cell + gap),
            yTop: startY + CGFloat(row) * (cell + gap),
            w: cell, h: cell
        )
        let path = CGPath(roundedRect: cellRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.addPath(path)
        if row == accentRow && col == accentCol {
            ctx.setFillColor(rgb(232, 58, 44))
        } else {
            ctx.setFillColor(rgb(232, 230, 225))
        }
        ctx.fillPath()
    }
}

// White checkmark inside the accent cell.
let accentRect = rect(
    x: startX + CGFloat(accentCol) * (cell + gap),
    yTop: startY + CGFloat(accentRow) * (cell + gap),
    w: cell, h: cell
)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(24)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: accentRect.minX + 0.26 * cell, y: accentRect.minY + 0.48 * cell))
ctx.addLine(to: CGPoint(x: accentRect.minX + 0.44 * cell, y: accentRect.minY + 0.30 * cell))
ctx.addLine(to: CGPoint(x: accentRect.minX + 0.76 * cell, y: accentRect.minY + 0.68 * cell))
ctx.strokePath()

// Write the PNG.
let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: "Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("failed to write PNG") }
print("wrote \(outURL.path)")
