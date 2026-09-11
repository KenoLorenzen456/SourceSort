// Draws the 1024 px app icon: a folder with a down arrow and sorting lines.
// Usage: swift Scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// Background tile, inset like Apple's icon grid (824 px on a 1024 canvas).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(40, 110, 230, 1))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(78, 160, 255, 1), rgb(28, 88, 214, 1)] as CFArray, locations: [0, 1])!,
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Folder: back panel with tab, then a lighter front panel.
let back = CGMutablePath()
back.move(to: CGPoint(x: 230, y: 250))
back.addLine(to: CGPoint(x: 230, y: 700))
back.addArc(tangent1End: CGPoint(x: 230, y: 730), tangent2End: CGPoint(x: 260, y: 730), radius: 30)
back.addLine(to: CGPoint(x: 420, y: 730))
back.addLine(to: CGPoint(x: 470, y: 680))
back.addLine(to: CGPoint(x: 764, y: 680))
back.addArc(tangent1End: CGPoint(x: 794, y: 680), tangent2End: CGPoint(x: 794, y: 650), radius: 30)
back.addLine(to: CGPoint(x: 794, y: 250))
back.closeSubpath()
ctx.addPath(back)
ctx.setFillColor(rgb(205, 228, 255, 1))
ctx.fillPath()

let front = CGPath(roundedRect: CGRect(x: 230, y: 250, width: 564, height: 390), cornerWidth: 34, cornerHeight: 34, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0, 30, 90, 0.25))
ctx.addPath(front)
ctx.setFillColor(rgb(255, 255, 255, 1))
ctx.fillPath()
ctx.restoreGState()

// Down arrow on the left of the front panel.
let blue = rgb(30, 100, 225, 1)
ctx.setFillColor(blue)
let arrow = CGMutablePath()
arrow.addRoundedRect(in: CGRect(x: 338, y: 390, width: 52, height: 180), cornerWidth: 26, cornerHeight: 26)
arrow.move(to: CGPoint(x: 280, y: 420))
arrow.addLine(to: CGPoint(x: 364, y: 310))
arrow.addLine(to: CGPoint(x: 448, y: 420))
arrow.closeSubpath()
ctx.addPath(arrow)
ctx.fillPath()

// Sorting lines, shortest at the bottom.
for (i, width) in [260.0, 200.0, 140.0].enumerated() {
    let y = 520 - CGFloat(i) * 90
    ctx.addPath(CGPath(roundedRect: CGRect(x: 500, y: y, width: width, height: 40), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(i == 0 ? blue : rgb(30, 100, 225, 0.55))
    ctx.fillPath()
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
