import AppKit
import SwiftUI

/// The "leave now" prompt: a small floating panel under the menu bar that stays until answered.
/// It does not take focus from the app being typed in, but it shows on every Space and over full-screen apps.
@MainActor
final class LeavePanel {
    private var panel: NSPanel?
    /// The journey the open panel is asking about.
    private(set) var journeyID: String?

    func show(model: AppModel) {
        guard let journey = model.recommended else { return }
        close()
        let host = NSHostingView(rootView: LeavePrompt(journey: journey, model: model))
        let p = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.setFrameTopLeftPoint(Self.anchor(width: host.fittingSize.width))
        p.orderFrontRegardless()
        NSAccessibility.post(
            element: p, notification: .announcementRequested,
            userInfo: [
                .announcement: "\(AppModel.spokenLeave(journey.leaveAt, now: .now)). \(journey.notificationBody)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        panel = p
        journeyID = journey.id
    }

    func close() {
        panel?.close()
        panel = nil
        journeyID = nil
    }

    /// Below the app's status item when it can be found, otherwise the top right of the main screen.
    private static func anchor(width: CGFloat) -> NSPoint {
        let gap: CGFloat = 6
        if let item = NSApp.windows.first(where: { $0.className.contains("StatusBarWindow") }), let screen = item.screen {
            let x = min(item.frame.midX - width / 2, screen.visibleFrame.maxX - width - gap)
            return NSPoint(x: max(x, screen.visibleFrame.minX + gap), y: item.frame.minY - gap)
        }
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: frame.maxX - width - gap, y: frame.maxY - gap)
    }
}

/// The answer the panel is asking for, filled so it stands out at a glance. AppKit draws default and prominent
/// buttons plain in a window without focus, and this panel never takes focus, so the fill is drawn here.
/// Neutral grey, not the system accent: green and orange are the only lamps.
private struct FilledAnswerStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))  // the small control size of Next beside it
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color(white: configuration.isPressed ? 0.28 : 0.35), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(isFocused ? 0.5 : 0)))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Borderless panels refuse key status by default, which would leave Return without a default button.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct LeavePrompt: View {
    /// The bus the panel opened for; realtime updates to the same trip replace it while the panel is up.
    let journey: Journey
    let model: AppModel

    var body: some View {
        let j = model.recommended?.id == journey.id ? model.recommended ?? journey : journey
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(j.countdownSchedule) { ctx in
                Text(MenuBarView.leaveText(j.leaveAt, now: ctx.date)).font(.title3.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(AppModel.spokenLeave(j.leaveAt, now: ctx.date))
            }
            JourneyLines(journey: j)
            HStack {
                Button("Going") { model.going() }.keyboardShortcut(.defaultAction).help("Leaving now (↩)")
                    .buttonStyle(FilledAnswerStyle())
                // Keys match the popover's; like Return they work once the panel has been clicked.
                Button("Next") { model.skipRecommended() }.disabled(model.alternatives.isEmpty)
                    .keyboardShortcut(.rightArrow, modifiers: []).help(model.nextHelp)
                Spacer()
                Button("Not today") { model.skipToday() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    .keyboardShortcut(.delete).help("No reminders until tomorrow (⌘⌫)")
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.black, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
        .preferredColorScheme(.dark)
    }
}
