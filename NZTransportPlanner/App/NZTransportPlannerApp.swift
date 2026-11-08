import SwiftUI
import UserNotifications

@main
struct NZTransportPlannerApp: App {
    private let model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Screenshots.isEnabled { Task { await Screenshots.render() }; return }
        #endif
        UNUserNotificationCenter.current().delegate = self
        AppModel.shared.askPermissionsOnce()
        // A new user would otherwise have to find a bus glyph in a crowded menu bar before setup can start.
        if !AppModel.shared.settings.isConfigured { openSettingsOnLaunch() }
    }

    private var launcher: NSWindow?

    /// `openSettings` only exists inside SwiftUI views, so a throwaway hosted view calls it once, then goes away.
    private func openSettingsOnLaunch() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsOpener { [weak self] in
            NSApp.activate()
            self?.launcher?.close()
            self?.launcher = nil
        })
        window.orderFront(nil)
        launcher = window
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let journeyID = response.notification.request.content.userInfo["journey"] as? String
        await AppModel.shared.handleNotificationAction(action, journeyID: journeyID)
    }
}

private struct SettingsOpener: View {
    let done: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View { Color.clear.onAppear { openSettings(); done() } }
}
