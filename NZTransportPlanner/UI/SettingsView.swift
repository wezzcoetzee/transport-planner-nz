import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Tab { case commute, route, data }

    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            page(.commute).tabItem { Label("Commute", systemImage: "bus") }.tag(Tab.commute)
            page(.route).tabItem { Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(Tab.route)
            page(.data).tabItem { Label("Data", systemImage: "externaldrive") }.tag(Tab.data)
        }
        .frame(width: 520) // each page sets its own height, so the window fits the tab like native Settings
        .preferredColorScheme(.dark)
        .background(.black)
    }

    /// Commute fits without scrolling even with its warnings showing; Data is short.
    @ViewBuilder func page(_ tab: Tab) -> some View {
        switch tab {
        case .commute: CommuteSettings(model: model).frame(height: 620)
        case .route: RouteSettings(model: model).frame(height: 620)
        case .data: DataSettings(model: model).frame(height: 380)
        }
    }
}

private struct CommuteSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Places") {
                PlaceSearchField(title: "Office", place: $model.settings.office, autofocus: true)
                PlaceSearchField(title: "Home", place: $model.settings.home, autofocus: model.settings.office != nil)
            }
            Section("When to leave") {
                DatePicker("Ideal time", selection: leaveTime, displayedComponents: .hourAndMinute)
                Stepper(value: $model.settings.earliestLeaveOffsetMinutes, in: 0...90, step: 5) {
                    offsetLabel("Earliest", minutes: -model.settings.earliestLeaveOffsetMinutes)
                }
                Stepper(value: $model.settings.latestLeaveOffsetMinutes, in: 0...120, step: 5) {
                    offsetLabel("Latest", minutes: model.settings.latestLeaveOffsetMinutes)
                }
                WeekdayPicker(selection: $model.settings.activeWeekdays)
                if model.settings.activeWeekdays.isEmpty {
                    Text("No days selected, so there is no commute to plan").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Reminders") {
                LeadPicker(leads: $model.settings.reminderLeadMinutes)
                if model.settings.reminderLeadMinutes.isEmpty {
                    Text("No reminders. Only the menu bar counts down").font(.caption).foregroundStyle(.orange)
                } else if !model.settings.reminderLeadMinutes.contains(0) {
                    Text("Without Now, nothing pops up at the leave time").font(.caption).foregroundStyle(.secondary)
                }
                // Permissions are asked once both places are set; until then these would warn about nothing.
                if model.settings.isConfigured {
                    NotificationHint()
                    LocationHint(model: model)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                    .onAppear { model.refreshLoginItemState() }
                if model.loginItemRefused {
                    HStack {
                        Text("macOS did not allow it. Check Login Items").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open") { SMAppService.openSystemSettingsLoginItems() }.remedyButtonStyle()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// "Earliest  16:40  20 min before": the clock time is what the user checks; the offset is what the stepper moves.
    private func offsetLabel(_ title: String, minutes: Int) -> some View {
        ValueLabel(title: title,
                   value: leaveTime.wrappedValue.addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened),
                   detail: minutes == 0 ? "the ideal time" : "\(abs(minutes)) min \(minutes < 0 ? "before" : "after")")
    }

    private var leaveTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(model.settings.preferredLeaveMinutes * 60)) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.settings.preferredLeaveMinutes = (c.hour ?? 17) * 60 + (c.minute ?? 0)
            })
    }
}

/// A stepper label that reads like stock settings: the noun on the left, the value trailing, optional dimmed detail.
private struct ValueLabel: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
        .monospacedDigit()
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    /// Foundation weekday numbers in Monday-first order; names come from the calendar so they follow the locale.
    private let days = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack {
            Text("Days")
            Spacer()
            ForEach(days, id: \.self) { day in
                Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { selection.contains(day) }, set: { on in if on { selection.insert(day) } else { selection.remove(day) } }))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .accessibilityHint(Calendar.current.weekdaySymbols[day - 1])
            }
        }
    }
}

/// Says why reminders would not reach the user. Shown in Settings and the popover, since Settings is rarely opened.
/// The app cannot change the alert style itself, so anything past the first prompt points at System Settings.
struct NotificationHint: View {
    @State private var problem: String?

    var body: some View {
        Group {
            if let problem {
                HStack {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Fix") { Task { await fix() } }.remedyButtonStyle()
                        .accessibilityLabel("Fix notifications")
                }
            }
        }
        .task {
            #if DEBUG
            guard !Screenshots.isEnabled else { return }
            #endif
            problem = await LeaveNotifier.problem()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { problem = await LeaveNotifier.problem() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationPermissionAnswered)) { _ in
            Task { problem = await LeaveNotifier.problem() }
        }
    }

    private func fix() async {
        let allowed = (try? await LeaveNotifier.requestPermission()) ?? false
        problem = await LeaveNotifier.problem()
        if !allowed || problem != nil { NSWorkspace.shared.open(Self.settingsURL) }
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!
}

/// Reminders only fire at the office; this speaks up only when location changes that.
private struct LocationHint: View {
    let model: AppModel

    var body: some View {
        if let text {
            HStack {
                Text(text).font(.caption).foregroundStyle(model.locationDenied ? .orange : .secondary)
                Spacer()
                if model.locationDenied {
                    Button("Fix") { NSWorkspace.shared.open(Self.settingsURL) }.remedyButtonStyle()
                        .accessibilityLabel("Fix location access")
                }
            }
        }
    }

    private var text: String? {
        switch model.presence {
        case .atOffice: nil
        case .away: "Away from the office. Reminders paused"
        case .unknown where model.locationDenied: "Location is off. Reminders fire anywhere"
        case .unknown where model.location != nil: "Location too vague to tell. Reminders fire anywhere"
        case .unknown: nil // still looking; reminders behave as if at the office meanwhile
        }
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices")!
}

private struct LeadPicker: View {
    @Binding var leads: [Int]
    /// Common leads, plus any saved one outside them so it can still be switched off.
    private var options: [Int] { Array(Set([20, 15, 10, 5, 0] + leads)).sorted(by: >) }

    var body: some View {
        HStack {
            Text("Remind")
            Spacer()
            ForEach(options, id: \.self) { m in
                Toggle(m == 0 ? "Now" : "\(m) min", isOn: Binding(
                    get: { leads.contains(m) },
                    set: { on in leads = on ? (leads + [m]).sorted(by: >) : leads.filter { $0 != m } }))
                .toggleStyle(.button)
                .controlSize(.small)
                .accessibilityHint(m == 0 ? "At the leave time" : "\(m) minutes before the leave time")
            }
        }
        .help("Minutes before the leave time. Now also pops up a panel under the menu bar")
    }
}

private struct RouteSettings: View {
    @Bindable var model: AppModel
    /// nil until loaded, so "No stops within" never flashes while the lists are still coming.
    @State private var officeStops: [(stop: Stop, distance: Double)]?
    @State private var homeStops: [(stop: Stop, distance: Double)]?

    var body: some View {
        Form {
            Section("Getting there") {
                Picker("Transfers", selection: $model.settings.maxTransfers) { Text("Direct only").tag(0); Text("Up to one").tag(1) }
                Stepper(value: bufferMinutes, in: 0...10) {
                    ValueLabel(title: "At the stop", value: "\(bufferMinutes.wrappedValue) min", detail: "before departure")
                }
                Stepper(value: $model.settings.stopSearchRadiusMeters, in: 200...1500, step: 100) {
                    ValueLabel(title: "Stops within", value: "\(Int(model.settings.stopSearchRadiusMeters)) m")
                }
                Stepper(value: walkKmh, in: 3...7) {
                    ValueLabel(title: "Walking pace", value: "\(walkKmh.wrappedValue) km/h")
                }
            }
            if !model.hasTimetable, model.settings.office != nil || model.settings.home != nil {
                // One status for both lists, with its fix beside it.
                Section {
                    LabeledContent("Timetable") {
                        HStack {
                            Text(model.timetableStatus).foregroundStyle(model.importFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            Button(model.downloadActionTitle) { Task { await model.refreshFeedIfStale(force: true) } }
                                .remedyButtonStyle().disabled(model.isImporting)
                        }
                    }
                }
            }
            stopList("Near the office", place: model.settings.office, missing: "Set Office on the Commute tab", officeStops)
            stopList("Near home", place: model.settings.home, missing: "Set Home on the Commute tab", homeStops)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task(id: StopQuery(office: model.settings.office, home: model.settings.home,
                            radius: model.settings.stopSearchRadiusMeters, hasTimetable: model.hasTimetable, feed: model.feedVersion)) {
            officeStops = if let o = model.settings.office { await model.candidateStops(for: o) } else { [] }
            homeStops = if let h = model.settings.home { await model.candidateStops(for: h) } else { [] }
        }
    }

    /// The planner works in seconds; the setting is whole minutes so the label always matches what is stored.
    private var bufferMinutes: Binding<Int> {
        Binding(get: { Int((Double(model.settings.boardingBufferSeconds) / 60).rounded()) },
                set: { model.settings.boardingBufferSeconds = $0 * 60 })
    }

    /// Stored in m/s for the planner, shown and stepped in whole km/h, the unit people know their pace in.
    private var walkKmh: Binding<Int> {
        Binding(get: { Int((model.settings.walkMetersPerSecond * 3.6).rounded()) },
                set: { model.settings.walkMetersPerSecond = Double($0) / 3.6 })
    }

    private func walkMinutes(_ straightLine: Double) -> Int {
        max(1, Int((straightLine * AppModel.walkDetour / model.settings.walkMetersPerSecond / 60).rounded(.up)))
    }

    /// Reloads the lists when a place, the radius or the timetable changes.
    private struct StopQuery: Equatable {
        let office: Place?, home: Place?, radius: Double, hasTimetable: Bool, feed: String?
    }

    private func stopList(_ title: String, place: Place?, missing: String, _ loaded: [(stop: Stop, distance: Double)]?) -> some View {
        let stops = loaded ?? []
        return Section(title) {
            stopRows(place: place, missing: missing, loaded: loaded, stops)
        }
    }

    @ViewBuilder private func stopRows(place: Place?, missing: String, loaded: [(stop: Stop, distance: Double)]?, _ stops: [(stop: Stop, distance: Double)]) -> some View {
            if place == nil {
                Text(missing).foregroundStyle(.secondary)
            } else if !model.hasTimetable {
                Text("Stops appear once the timetable is in").foregroundStyle(.secondary)
            } else if loaded != nil, stops.isEmpty {
                Text("No stops within \(Int(model.settings.stopSearchRadiusMeters)) m").monospacedDigit().foregroundStyle(.secondary)
            }
            ForEach(stops, id: \.stop.id) { entry in
                Toggle(isOn: Binding(
                    get: { !model.settings.excludedStopIDs.contains(entry.stop.id) },
                    set: { on in if on { model.settings.excludedStopIDs.remove(entry.stop.id) } else { model.settings.excludedStopIDs.insert(entry.stop.id) } })) {
                    HStack {
                        Text(entry.stop.name)
                        Text(entry.stop.code).foregroundStyle(.secondary)
                        Spacer()
                        // The same walk the popover shows: street distance at the chosen pace, not a straight line.
                        Text("\(walkMinutes(entry.distance)) min walk").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
    }
}

private struct DataSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Auckland Transport timetable") {
                LabeledContent("Status") {
                    HStack {
                        Text(model.timetableStatus).foregroundStyle(model.importFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        // Offered only when it would fix something; new timetables arrive by themselves.
                        if model.importFailed || !model.hasTimetable {
                            Button(model.downloadActionTitle) { Task { await model.refreshFeedIfStale(force: true) } }
                                .remedyButtonStyle().disabled(model.isImporting)
                        }
                    }
                }
                .help(model.feedVersion.map { "Timetable version \($0)" } ?? "")
                Text("Free public timetable, downloaded again when AT publishes a new one" + (model.hasTimetable ? "" : ". Apple Maps stands in while it downloads"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Live delays") {
                SecureField("AT key", text: $model.settings.atSubscriptionKey, prompt: Text("Paste primary key"))
                // The key's status sits right under it; sign-up help only while there is no working key.
                switch model.realtimeStatus {
                case .live(let at): Text("Working, checked \(at.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                case .rejected, .unreachable: Text(model.realtimeStatus.problem ?? "").font(.caption).foregroundStyle(.orange)
                case .off:
                    if !model.settings.atSubscriptionKey.isEmpty {
                        Text("Saved. Checked at the next refresh").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.settings.atSubscriptionKey.isEmpty || model.realtimeStatus == .rejected {
                    Text("Sign up free at [__dev-portal.at.govt.nz__](https://dev-portal.at.govt.nz), subscribe to the Realtime API and paste the primary key. Without it the app uses the timetable only")
                        .font(.caption).foregroundStyle(.secondary).tint(.white)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private extension AppModel {
    var importFailed: Bool { if case .failed = importPhase { true } else { false } }

    /// The timetable in user voice; the raw failure reason stays in the log.
    var timetableStatus: String {
        if let activity = importActivity { return activity }
        let downloaded = importedAt.map { "Downloaded \($0.formatted(.dateTime.day().month()))" }
        if importFailed {
            // A failed refresh leaves the old timetable in use; say both so nobody thinks planning stopped.
            return downloaded.map { "\($0). Latest download failed" } ?? "Download failed. Check the connection"
        }
        return downloaded ?? "Not downloaded yet"
    }
}
