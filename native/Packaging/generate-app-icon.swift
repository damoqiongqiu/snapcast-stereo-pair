#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "native/Packaging/AppIcon.icns"
)
let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("StereoPairAppIcon-\(UUID().uuidString).iconset")

try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(size: Int) throws -> Data {
    let canvas = CGFloat(size)
    let scale = canvas / 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSGraphicsContext.current?.shouldAntialias = true
    NSGraphicsContext.current?.imageInterpolation = .high

    let bounds = NSRect(x: 64 * scale, y: 64 * scale, width: 896 * scale, height: 896 * scale)
    let background = NSBezierPath(
        roundedRect: bounds,
        xRadius: 208 * scale,
        yRadius: 208 * scale
    )
    NSGradient(colors: [
        color(0.055, 0.075, 0.105),
        color(0.10, 0.15, 0.20)
    ])?.draw(in: background, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    let glow = NSBezierPath(
        ovalIn: NSRect(
            x: 230 * scale,
            y: 600 * scale,
            width: 564 * scale,
            height: 340 * scale
        )
    )
    NSGradient(colors: [
        color(0.22, 0.70, 1.0, 0.18),
        color(0.22, 0.70, 1.0, 0.0)
    ])?.draw(in: glow, relativeCenterPosition: NSPoint(x: 0, y: 0.2))
    NSGraphicsContext.restoreGraphicsState()

    func drawSpeaker(x: CGFloat, colors: [NSColor]) {
        let panelRect = NSRect(
            x: x * scale,
            y: 252 * scale,
            width: 276 * scale,
            height: 520 * scale
        )
        let panel = NSBezierPath(
            roundedRect: panelRect,
            xRadius: 92 * scale,
            yRadius: 92 * scale
        )
        NSGradient(colors: colors)?.draw(in: panel, angle: -90)

        let cone = NSBezierPath(
            ovalIn: NSRect(
                x: (x + 58) * scale,
                y: 432 * scale,
                width: 160 * scale,
                height: 160 * scale
            )
        )
        color(0.96, 0.99, 1.0, 0.94).setFill()
        cone.fill()

        let driver = NSBezierPath(
            ovalIn: NSRect(
                x: (x + 106) * scale,
                y: 480 * scale,
                width: 64 * scale,
                height: 64 * scale
            )
        )
        color(0.04, 0.07, 0.10).setFill()
        driver.fill()
    }

    drawSpeaker(
        x: 174,
        colors: [color(0.25, 0.87, 1.0), color(0.15, 0.48, 0.94)]
    )
    drawSpeaker(
        x: 574,
        colors: [color(0.36, 0.95, 0.52), color(0.16, 0.65, 0.43)]
    )

    let bridge = NSBezierPath(
        roundedRect: NSRect(
            x: 440 * scale,
            y: 493 * scale,
            width: 144 * scale,
            height: 38 * scale
        ),
        xRadius: 19 * scale,
        yRadius: 19 * scale
    )
    color(0.96, 0.99, 1.0, 0.92).setFill()
    bridge.fill()

    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    try drawIcon(size: variant.pixels).write(
        to: iconsetURL.appendingPathComponent(variant.name)
    )
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetURL.path,
    "-o", outputURL.path
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}
