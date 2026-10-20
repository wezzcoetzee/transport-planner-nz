import AppKit

let size: CGFloat = 1024
let variant = CommandLine.arguments[1]
let out = CommandLine.arguments[2]

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS squircle: full-bleed rounded rect at ~22.4% radius inside the standard 10% margin
let inset = size * 0.1
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.224, yRadius: rect.width * 0.224)
NSColor.black.setFill(); path.fill()
ctx.saveGState(); path.addClip()

func symbol(_ name: String, pt: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: weight).applying(.init(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}
func draw(_ s: NSImage, centerX: CGFloat, centerY: CGFloat) {
    let sz = s.size
    s.draw(in: CGRect(x: centerX - sz.width / 2, y: centerY - sz.height / 2, width: sz.width, height: sz.height))
}
func text(_ str: String, pt: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, centerY: CGFloat) {
    let font = NSFont.monospacedDigitSystemFont(ofSize: pt, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: str, attributes: attrs)
    let sz = s.size()
    s.draw(at: CGPoint(x: centerX - sz.width / 2, y: centerY - sz.height / 2))
}
let green = NSColor(red: 0x30/255, green: 0xD1/255, blue: 0x58/255, alpha: 1)
let orange = NSColor(red: 1, green: 0x9F/255, blue: 0x0A/255, alpha: 1)
let cx = size / 2

switch variant {
case "board":
    // Departure board: bus glyph top, countdown below, one green lamp
    draw(symbol("bus.fill", pt: 300), centerX: cx, centerY: size * 0.63)
    text("12m", pt: 250, weight: .bold, color: .white, centerX: cx, centerY: size * 0.31)
    NSColor(calibratedWhite: 1, alpha: 1).set()
    let lamp = CGRect(x: size * 0.79 - 22, y: size * 0.79 - 22, width: 44, height: 44)
    green.setFill(); NSBezierPath(ovalIn: lamp).fill()
case "glyph":
    // Just the bus, large, with a small orange delay tick in the corner like the menu bar badge
    draw(symbol("bus.fill", pt: 520), centerX: cx, centerY: size * 0.5)
case "clock":
    // Countdown only, the product's one number
    text("12", pt: 520, weight: .heavy, color: .white, centerX: cx, centerY: size * 0.52)
    text("min", pt: 150, weight: .semibold, color: NSColor(white: 1, alpha: 0.55), centerX: cx, centerY: size * 0.24)
    draw(symbol("bus.fill", pt: 110), centerX: size * 0.78, centerY: size * 0.76)
default: fatalError("unknown variant")
}
ctx.restoreGState()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
