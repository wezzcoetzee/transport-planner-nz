import AppKit
import SwiftUI

/// Kept deliberately static: dynamic views such as TimelineView inside a MenuBarExtra label trigger endless
/// status item updates. The model refreshes `menuTitle` on a timer instead.
///
/// The status bar draws labels as monochrome templates, so the amber and red urgency states are rendered to
/// a non-template image. They only change when the title does, so nothing repaints between ticks.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let tint = model.menuUrgency.tint {
            Image(nsImage: Self.render(title: model.menuTitle, symbol: model.menuSymbol, tint: tint))
                .accessibilityLabel(model.menuUrgency == .go ? "Leave now" : "Leave in \(model.menuTitle)")
        } else if model.menuTitle.isEmpty {
            Image(systemName: model.menuSymbol)
        } else {
            Label(model.menuTitle, systemImage: model.menuSymbol).labelStyle(.titleAndIcon).monospacedDigit()
        }
    }

    private static func render(title: String, symbol: String, tint: Color) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: NSFont.systemFontSize))
        .foregroundStyle(tint)
        let renderer = ImageRenderer(content: content)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        image.isTemplate = false
        return image
    }
}

private extension AppModel.MenuUrgency {
    /// Colours from DESIGN.md: delay-orange for soon, system red for go.
    var tint: Color? {
        switch self {
        case .calm: nil
        case .soon: Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)
        case .go: Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
        }
    }
}
