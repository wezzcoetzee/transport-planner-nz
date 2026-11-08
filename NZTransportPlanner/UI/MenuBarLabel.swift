import AppKit
import SwiftUI

/// Kept deliberately static: dynamic views such as TimelineView inside a MenuBarExtra label trigger endless
/// status item updates. The model refreshes `menuTitle` on a timer instead.
///
/// Every state is drawn through one renderer so the symbol, spacing and type never shift between states. Calm is a
/// template image the status bar tints itself; orange and red are not templates, so they keep their color. The
/// image only changes when the title does, so nothing repaints between ticks.
struct MenuBarLabel: View {
    let model: AppModel
    /// The menu bar's own appearance; a light bar needs darker lamps to stay readable.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: Self.render(title: model.menuTitle, symbol: model.menuSymbol, tint: model.menuUrgency.tint(on: colorScheme)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.menuAccessibilityLabel)
    }

    private static func render(title: String, symbol: String, tint: Color?) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: symbol)
            if !title.isEmpty { Text(title).monospacedDigit() }
        }
        .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize)) // the status bar's own size
        .foregroundStyle(tint ?? .black)
        let renderer = ImageRenderer(content: content)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        image.isTemplate = tint == nil
        return image
    }
}

private extension AppModel.MenuUrgency {
    /// Colours from DESIGN.md's Menu Bar Label: delay-orange for soon, go-red for go, each with the system's
    /// darker light-appearance variant so a pale menu bar keeps them readable.
    func tint(on scheme: ColorScheme) -> Color? {
        let dark = scheme == .dark
        return switch self {
        case .calm: nil
        case .soon: dark ? Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255) : Color(red: 0xC9 / 255, green: 0x34 / 255, blue: 0)
        case .go: dark ? Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255) : Color(red: 0xD7 / 255, green: 0, blue: 0x15 / 255)
        }
    }
}
