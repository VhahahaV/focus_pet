import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "scripts/dmg-assets/background.png"
let rootPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : FileManager.default.currentDirectoryPath
let outputURL = URL(fileURLWithPath: outputPath)
let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
let appIconURL = rootURL.appendingPathComponent("Sources/FocusPetMac/Resources/AppIcon.png")

let canvasSize = NSSize(width: 720, height: 460)
let image = NSImage(size: canvasSize)

struct Palette {
    static let ink = NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.26, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.38, green: 0.46, blue: 0.58, alpha: 1)
    static let softBlue = NSColor(calibratedRed: 0.24, green: 0.55, blue: 0.96, alpha: 1)
    static let warm = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.48, alpha: 1)
    static let mint = NSColor(calibratedRed: 0.25, green: 0.72, blue: 0.61, alpha: 1)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: width, height: height)
}

func drawText(
    _ text: String,
    in frame: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(in: frame, withAttributes: attributes)
}

func drawPill(_ frame: NSRect, text: String, tint: NSColor) {
    let path = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
    tint.withAlphaComponent(0.11).setFill()
    path.fill()
    tint.withAlphaComponent(0.28).setStroke()
    path.lineWidth = 1
    path.stroke()
    drawText(text, in: frame.insetBy(dx: 11, dy: 4), size: 10.5, weight: .semibold, color: tint)
}

func drawSoftPattern() {
    for row in 0..<7 {
        for col in 0..<10 {
            let x = CGFloat(col) * 82 + CGFloat(row % 2) * 36 + 14
            let y = CGFloat(row) * 58 + 28

            let diamond = NSBezierPath()
            diamond.move(to: NSPoint(x: x + 10, y: y + 20))
            diamond.line(to: NSPoint(x: x + 20, y: y + 10))
            diamond.line(to: NSPoint(x: x + 10, y: y))
            diamond.line(to: NSPoint(x: x, y: y + 10))
            diamond.close()
            NSColor.white.withAlphaComponent(0.17).setStroke()
            diamond.lineWidth = 1.2
            diamond.stroke()

            let dash = NSBezierPath(roundedRect: rect(x + 34, y + 7, 22, 4), xRadius: 2, yRadius: 2)
            NSColor.white.withAlphaComponent(0.15).setFill()
            dash.fill()
        }
    }
}

func drawRoundedImage(_ source: NSImage, frame: NSRect, radius: CGFloat, alpha: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    clip.addClip()
    source.draw(in: frame, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}

func drawCircleImage(_ source: NSImage, frame: NSRect, alpha: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(ovalIn: frame)
    clip.addClip()
    source.draw(in: frame, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}

func drawPawPrint(center: NSPoint, scale: CGFloat, tint: NSColor, alpha: CGFloat, rotation: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: rotation)
    transform.scale(by: scale)
    transform.concat()

    tint.withAlphaComponent(alpha).setFill()
    NSBezierPath(ovalIn: rect(-8, -7, 16, 13)).fill()
    NSBezierPath(ovalIn: rect(-18, 5, 8, 10)).fill()
    NSBezierPath(ovalIn: rect(-7, 11, 8, 11)).fill()
    NSBezierPath(ovalIn: rect(7, 9, 8, 11)).fill()
    NSBezierPath(ovalIn: rect(16, 1, 8, 10)).fill()

    NSGraphicsContext.restoreGraphicsState()
}

func drawCatWhiskerMarks(origin: NSPoint, tint: NSColor) {
    for offset in [CGFloat(-8), 0, 8] {
        let whisker = NSBezierPath()
        whisker.move(to: NSPoint(x: origin.x, y: origin.y + offset))
        whisker.curve(
            to: NSPoint(x: origin.x + 38, y: origin.y + offset + 3),
            controlPoint1: NSPoint(x: origin.x + 12, y: origin.y + offset + 5),
            controlPoint2: NSPoint(x: origin.x + 27, y: origin.y + offset - 2)
        )
        whisker.lineWidth = 2
        whisker.lineCapStyle = .round
        tint.withAlphaComponent(0.18).setStroke()
        whisker.stroke()
    }
}

func drawDropZone(center: NSPoint, accent: NSColor, side: String) {
    let haloFrame = rect(center.x - 78, center.y - 78, 156, 156)
    let halo = NSBezierPath(ovalIn: haloFrame)
    accent.withAlphaComponent(0.09).setFill()
    halo.fill()
    accent.withAlphaComponent(0.24).setStroke()
    halo.lineWidth = 2
    halo.stroke()

    let inner = NSBezierPath(ovalIn: haloFrame.insetBy(dx: 12, dy: 12))
    NSColor.white.withAlphaComponent(0.34).setStroke()
    inner.lineWidth = 1
    inner.stroke()

    let dotY = center.y - 92
    let dotFrame = side == "left" ? rect(center.x - 6, dotY, 12, 3) : rect(center.x - 6, dotY, 12, 3)
    let dot = NSBezierPath(roundedRect: dotFrame, xRadius: 1.5, yRadius: 1.5)
    accent.withAlphaComponent(0.36).setFill()
    dot.fill()
}

func drawArrow() {
    let shadow = NSBezierPath()
    shadow.move(to: NSPoint(x: 292, y: 223))
    shadow.curve(
        to: NSPoint(x: 432, y: 231),
        controlPoint1: NSPoint(x: 332, y: 237),
        controlPoint2: NSPoint(x: 390, y: 217)
    )
    shadow.lineWidth = 16
    shadow.lineCapStyle = .round
    Palette.softBlue.withAlphaComponent(0.07).setStroke()
    shadow.stroke()

    let path = NSBezierPath()
    path.move(to: NSPoint(x: 298, y: 226))
    path.curve(
        to: NSPoint(x: 426, y: 229),
        controlPoint1: NSPoint(x: 336, y: 236),
        controlPoint2: NSPoint(x: 386, y: 218)
    )
    path.lineWidth = 7
    path.lineCapStyle = .round
    Palette.softBlue.withAlphaComponent(0.64).setStroke()
    path.stroke()

    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: 308, y: 229))
    highlight.curve(
        to: NSPoint(x: 408, y: 230),
        controlPoint1: NSPoint(x: 340, y: 235),
        controlPoint2: NSPoint(x: 374, y: 223)
    )
    highlight.lineWidth = 2
    highlight.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.55).setStroke()
    highlight.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 420, y: 213))
    head.line(to: NSPoint(x: 438, y: 229))
    head.line(to: NSPoint(x: 419, y: 244))
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    Palette.softBlue.withAlphaComponent(0.80).setStroke()
    head.stroke()

    let headHighlight = NSBezierPath()
    headHighlight.move(to: NSPoint(x: 422, y: 218))
    headHighlight.line(to: NSPoint(x: 435, y: 229))
    headHighlight.line(to: NSPoint(x: 422, y: 240))
    headHighlight.lineWidth = 2
    headHighlight.lineCapStyle = .round
    headHighlight.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.42).setStroke()
    headHighlight.stroke()
}

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.97, green: 0.94, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.92, alpha: 1)
]) {
    gradient.draw(in: rect(0, 0, canvasSize.width, canvasSize.height), angle: 24)
}

drawSoftPattern()

let sweep = NSBezierPath()
sweep.move(to: NSPoint(x: 0, y: 375))
sweep.curve(to: NSPoint(x: 720, y: 312), controlPoint1: NSPoint(x: 210, y: 426), controlPoint2: NSPoint(x: 470, y: 338))
sweep.line(to: NSPoint(x: 720, y: 460))
sweep.line(to: NSPoint(x: 0, y: 460))
sweep.close()
NSColor.white.withAlphaComponent(0.20).setFill()
sweep.fill()

let panel = NSBezierPath(roundedRect: rect(48, 58, 624, 342), xRadius: 30, yRadius: 30)
NSColor.white.withAlphaComponent(0.67).setFill()
panel.fill()
NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.92, alpha: 0.20).setStroke()
panel.lineWidth = 1.5
panel.stroke()

if let appIcon = NSImage(contentsOf: appIconURL) {
    drawRoundedImage(appIcon, frame: rect(86, 306, 56, 56), radius: 15, alpha: 0.20)
    drawCircleImage(appIcon, frame: rect(628, 48, 86, 86), alpha: 0.10)
    drawCircleImage(appIcon, frame: rect(33, 68, 44, 44), alpha: 0.08)
    drawCatWhiskerMarks(origin: NSPoint(x: 604, y: 108), tint: Palette.softBlue)
}

drawText("Focus Pet", in: rect(0, 340, 720, 42), size: 30, weight: .bold, color: Palette.ink)

drawPawPrint(center: NSPoint(x: 158, y: 119), scale: 0.48, tint: Palette.softBlue, alpha: 0.12, rotation: -12)
drawPawPrint(center: NSPoint(x: 557, y: 331), scale: 0.42, tint: Palette.mint, alpha: 0.12, rotation: 15)
drawPawPrint(center: NSPoint(x: 618, y: 285), scale: 0.34, tint: Palette.warm, alpha: 0.12, rotation: -18)

drawDropZone(center: NSPoint(x: 210, y: 214), accent: Palette.softBlue, side: "left")
drawDropZone(center: NSPoint(x: 510, y: 214), accent: Palette.mint, side: "right")
drawArrow()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.94]) else {
    fatalError("Could not render DMG background")
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL)
