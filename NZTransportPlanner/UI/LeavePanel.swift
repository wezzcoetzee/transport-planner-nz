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
        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.setFrameTopLeftPoint(Self.anchor(width: host.fittingSize.width))
        p.orderFrontRegardless()
        NSAccessibility.post(element: p, notification: .announcementRequested,
                             userInfo: [.announcement: "Leave now. \(journey.notificationBody)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
            }
            JourneyLines(journey: j)
            HStack {
                // Neutral grey, not the system accent: green and orange are the only lamps.
                Button("Going") { model.going() }.keyboardShortcut(.defaultAction).tint(Color(white: 0.35)).fontWeight(.semibold)
                Button("Next") { model.skipRecommended() }.disabled(model.alternatives.isEmpty)
                    .help(model.alternatives.isEmpty ? "No later option today" : "Skip to the next option")
                Spacer()
                Button("Not today") { model.skipToday() }.buttonStyle(.borderless).foregroundStyle(.secondary)
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
