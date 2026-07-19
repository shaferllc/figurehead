#!/usr/bin/env swift
// Generates AppIcon.icns: a deep-sea → teal gradient squircle with two
// stacked window cards — the promo-shot composite Figurehead exists to make.
// Usage: swift make-icon.swift  (run from the figurehead dir)

import AppKit
import Foundation

let here    = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Draws one window card: rounded rect + titlebar dots, rotated about its center.
func drawCard(in rect: NSRect, rotation: CGFloat, alpha: CGFloat,
              dots: Bool, shadow: Bool, px pf: CGFloat) {
    NSGraphicsContext.current?.saveGraphicsState()

    let t = NSAffineTransform()
    t.translateX(by: rect.midX, yBy: rect.midY)
    t.rotate(byDegrees: rotation)
    t.translateX(by: -rect.midX, yBy: -rect.midY)
    t.concat()

    if shadow {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.38)
        sh.shadowBlurRadius = pf * 0.035
        sh.shadowOffset = NSSize(width: 0, height: -pf * 0.02)
        sh.set()
    }

    let radius = rect.height * 0.16
    let card = roundedRect(rect, radius: radius)
    NSColor.white.withAlphaComponent(alpha).setFill()
    card.fill()

    if dots {
        // Reset shadow so interior details don't cast one.
        NSShadow().set()
        let dotR = rect.height * 0.045
        let dotY = rect.maxY - rect.height * 0.14
        let colors: [NSColor] = [
            NSColor(red: 1.00, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(red: 1.00, green: 0.75, blue: 0.28, alpha: 1),
            NSColor(red: 0.30, green: 0.82, blue: 0.36, alpha: 1),
        ]
        for (i, c) in colors.enumerated() {
            let dotX = rect.minX + rect.height * 0.14 + CGFloat(i) * dotR * 3.2
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: dotX - dotR, y: dotY - dotR,
                                        width: dotR * 2, height: dotR * 2)).fill()
        }
        // Faint content lines.
        NSColor(white: 0.75, alpha: 0.9).setFill()
        let lineH = rect.height * 0.045
        for row in 0..<3 {
            let w = rect.width * (row == 2 ? 0.38 : 0.62)
            let y = rect.maxY - rect.height * (0.34 + CGFloat(row) * 0.15)
            roundedRect(NSRect(x: rect.minX + rect.width * 0.10, y: y,
                               width: w, height: lineH),
                        radius: lineH / 2).fill()
        }
    }
    NSGraphicsContext.current?.restoreGraphicsState()
}

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: deep indigo → lagoon teal, the promo backdrop.
    let radius = pf * 0.225
    let squircle = roundedRect(NSRect(x: 0, y: 0, width: pf, height: pf), radius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.13, blue: 0.47, alpha: 1),
        NSColor(red: 0.10, green: 0.52, blue: 0.62, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -55)

    // Back card: dimmed, rotated — the staggered composite.
    drawCard(in: NSRect(x: pf * 0.14, y: pf * 0.26, width: pf * 0.52, height: pf * 0.40),
             rotation: 7, alpha: 0.55, dots: false, shadow: true, px: pf)

    // Front card: the hero window.
    drawCard(in: NSRect(x: pf * 0.30, y: pf * 0.18, width: pf * 0.56, height: pf * 0.44),
             rotation: -3, alpha: 1.0, dots: true, shadow: true, px: pf)

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path,
                  "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")
