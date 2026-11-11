// Draws the Dock Morph app icon as a 1024x1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Note: CoreGraphics origin is bottom-left.

// MARK: Background tile (standard macOS icon shape: 824pt tile on a 1024 canvas)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = rounded(tile, 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x5B21B6))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let background = CGGradient(colorsSpace: space,
                            colors: [color(0xF472B6), color(0x8B5CF6), color(0x3730A3)] as CFArray,
                            locations: [0, 0.5, 1])!
ctx.drawLinearGradient(background,
                       start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.maxX, y: tile.minY),
                       options: [])
ctx.restoreGState()

// MARK: Two "ghost" docks behind, fading upward — the sets you can morph into
let slotColors: [[UInt32]] = [
    [0x34D399, 0xFBBF24, 0x60A5FA, 0xF87171],
    [0xFBBF24, 0x60A5FA, 0xF87171],
    [0x60A5FA, 0xF87171],
]

func drawDock(centerY: CGFloat, slots: [UInt32], slot: CGFloat, alpha: CGFloat, shadow: Bool) {
    let gap = slot * 0.22
    let pad = slot * 0.24
    let width = CGFloat(slots.count) * slot + CGFloat(slots.count - 1) * gap + pad * 2
    let height = slot + pad * 2
    let shelf = CGRect(x: 512 - width / 2, y: centerY - height / 2, width: width, height: height)

    ctx.saveGState()
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    }
    ctx.addPath(rounded(shelf, height * 0.3))
    ctx.setFillColor(color(0xFFFFFF, 0.9 * alpha))
    ctx.fillPath()
    ctx.restoreGState()

    for (index, hex) in slots.enumerated() {
        let x = shelf.minX + pad + CGFloat(index) * (slot + gap)
        let rect = CGRect(x: x, y: shelf.minY + pad, width: slot, height: slot)
        ctx.addPath(rounded(rect, slot * 0.24))
        ctx.setFillColor(color(hex, alpha))
        ctx.fillPath()
    }
}

drawDock(centerY: 690, slots: slotColors[2], slot: 92, alpha: 0.35, shadow: false)
drawDock(centerY: 540, slots: slotColors[1], slot: 108, alpha: 0.6, shadow: false)
drawDock(centerY: 350, slots: slotColors[0], slot: 124, alpha: 1, shadow: true)

// MARK: Write PNG
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("failed to write \(output.path)\n".data(using: .utf8)!)
    exit(1)
}
