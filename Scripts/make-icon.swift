// Generates Lumen's app icon (1024x1024 PNG) with Core Graphics — no design
// assets needed. Usage: swift Scripts/make-icon.swift <output.png>
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("context")
}

// Squircle background.
let inset: CGFloat = 72
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Base diagonal gradient (deep slate -> near black).
let base = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.17, green: 0.18, blue: 0.29, alpha: 1),
    CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Warm "lumen" glow.
let glow = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 1.0, green: 0.56, blue: 0.24, alpha: 0.60),
    CGColor(red: 1.0, green: 0.34, blue: 0.30, alpha: 0.0),
] as CFArray, locations: [0, 1])!
let center = CGPoint(x: S * 0.5, y: S * 0.46)
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                       endCenter: center, endRadius: S * 0.44, options: [])
ctx.restoreGState()

// Glassy top highlight stroke.
ctx.saveGState()
ctx.addPath(squircle)
ctx.setLineWidth(3)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
ctx.strokePath()
ctx.restoreGState()

// Play triangle (rounded), optically centered.
let w: CGFloat = 280, h: CGFloat = 320
let cx = S * 0.5, cy = S * 0.5
let ox = cx - w * 0.30
let tri = CGMutablePath()
tri.move(to: CGPoint(x: ox, y: cy - h / 2))
tri.addLine(to: CGPoint(x: ox, y: cy + h / 2))
tri.addLine(to: CGPoint(x: ox + w, y: cy))
tri.closeSubpath()
ctx.saveGState()
ctx.setLineJoin(.round)
ctx.setLineWidth(48)            // rounds the corners via a thick stroke + fill
ctx.addPath(tri)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
ctx.drawPath(using: .fillStroke)
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(outURL.path)")
