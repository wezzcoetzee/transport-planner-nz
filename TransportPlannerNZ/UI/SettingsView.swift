import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            CommuteSettings(model: model).tabItem { Label("Commute", systemImage: "bus") }
            StopsSettings(model: model).tabItem { Label("Stops", systemImage: "mappin") }
            DataSettings(model: model).tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 520, height: 460)
        .preferredColorScheme(.dark)
        .background(.black)
    }
}

private struct CommuteSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Places") {
                PlaceSearchField(title: "Office", place: $model.settings.office)
                PlaceSearchField(title: "Home", place: $model.settings.home)
            }
            Section("When to leave") {
                DatePicker("Ideal time", selection: leaveTime, displayedComponents: .hourAndMinute)
                Stepper(value: $model.settings.earliestLeaveOffsetMinutes, in: 0...90, step: 5) {
                    Text("Earliest: \(model.settings.earliestLeaveOffsetMinutes) min before").monospacedDigit()
                }
                Stepper(value: $model.settings.latestLeaveOffsetMinutes, in: 0...120, step: 5) {
                    Text("Latest: \(model.settings.latestLeaveOffsetMinutes) min after").monospacedDigit()
                }
                WeekdayPicker(selection: $model.settings.activeWeekdays)
                Picker("Transfers", selection: $model.settings.maxTransfers) { Text("Direct only").tag(0); Text("Up to one").tag(1) }
                Stepper(value: $model.settings.boardingBufferSeconds, in: 0...600, step: 60) {
                    Text("Be at the stop \(model.settings.boardingBufferSeconds / 60) min early").monospacedDigit()
                }
            }
            Section("Reminders") {
                LeadPicker(leads: $model.settings.reminderLeadMinutes)
                NotificationHint()
                LocationHint(model: model)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let days = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]

    var body: some View {
        HStack {
            Text("Days")
            Spacer()
            ForEach(days, id: \.0) { day in
                Toggle(day.1, isOn: Binding(get: { selection.contains(day.0) }, set: { on in if on { selection.insert(day.0) } else { selection.remove(day.0) } }))
                    .toggleStyle(.button)
                    .controlSize(.small)
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
                    Button("Fix") { Task { await fix() } }.controlSize(.small)
                }
            }
        }
        .task { problem = await LeaveNotifier.problem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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

/// Reminders only fire at the office; this says whether the app can tell where that is.
private struct LocationHint: View {
    let model: AppModel

    var body: some View {
        HStack {
            Text(text).font(.caption).foregroundStyle(model.locationDenied ? .orange : .secondary)
            Spacer()
            if model.locationDenied {
                Button("Fix") { NSWorkspace.shared.open(Self.settingsURL) }.controlSize(.small)
            }
        }
    }

    private var text: String {
        switch model.presence {
        case .atOffice: "At the office"
        case .away: "Away from the office. Reminders paused"
        case .unknown: model.locationDenied ? "Location is off. Reminders fire anywhere" : "Finding your location"
        }
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices")!
}

private struct LeadPicker: View {
    @Binding var leads: [Int]
    private let options = [30, 20, 15, 10, 5, 2, 0]

    var body: some View {
        HStack {
            Text("Notify")
            Spacer()
            ForEach(options, id: \.self) { m in
                Toggle(m == 0 ? "Now" : "\(m)m", isOn: Binding(
                    get: { leads.contains(m) },
                    set: { on in leads = on ? (leads + [m]).sorted(by: >) : leads.filter { $0 != m } }))
                .toggleStyle(.button)
                .controlSize(.small)
            }
        }
        .help("Minutes before the leave time")
    }
}

private struct StopsSettings: View {
    @Bindable var model: AppModel
    @State private var officeStops: [(stop: Stop, distance: Double)] = []
    @State private var homeStops: [(stop: Stop, distance: Double)] = []

    var body: some View {
        Form {
            Section {
                Slider(value: $model.settings.stopSearchRadiusMeters, in: 200...1500, step: 50) { Text("Search radius \(Int(model.settings.stopSearchRadiusMeters)) m").monospacedDigit() }
                Slider(value: $model.settings.walkMetersPerSecond, in: 0.8...2.0, step: 0.1) { Text("Walking pace \(String(format: "%.1f", model.settings.walkMetersPerSecond * 3.6)) km/h").monospacedDigit() }
            }
            stopList("Near the office", place: model.settings.office, missing: "Set the office in Commute", officeStops)
            stopList("Near home", place: model.settings.home, missing: "Set the home in Commute", homeStops)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task(id: StopQuery(office: model.settings.office, home: model.settings.home,
                            radius: model.settings.stopSearchRadiusMeters, hasTimetable: model.hasTimetable, feed: model.feedVersion)) {
            officeStops = if let o = model.settings.office { await model.candidateStops(for: o) } else { [] }
            homeStops = if let h = model.settings.home { await model.candidateStops(for: h) } else { [] }
        }
    }

    /// Reloads the lists when a place, the radius or the timetable changes.
    private struct StopQuery: Equatable {
        let office: Place?, home: Place?, radius: Double, hasTimetable: Bool, feed: String?
    }

    private func stopList(_ title: String, place: Place?, missing: String, _ stops: [(stop: Stop, distance: Double)]) -> some View {
        Section(title) {
            if place == nil {
                Text(missing).foregroundStyle(.secondary)
            } else if !model.hasTimetable {
                Text(model.importPhase == .idle ? "Download the timetable in Data" : model.timetableStatus).foregroundStyle(.secondary)
            } else if stops.isEmpty {
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
                        Text("\(Int(entry.distance)) m").monospacedDigit().foregroundStyle(.secondary)
                    }
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
                LabeledContent("Status", value: model.timetableStatus)
                if let v = model.feedVersion { LabeledContent("Feed version", value: v).font(.caption) }
                Button("Download latest timetable") { Task { await model.refreshFeedIfStale(force: true) } }
                    .disabled(model.isImporting)
                Text("Free public GTFS feed, refreshed automatically every few days.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Live delays (optional)") {
                SecureField("AT subscription key", text: $model.settings.atSubscriptionKey)
                Text("Sign up free at dev-portal.at.govt.nz, subscribe to the Realtime API and paste the primary key. Without it the app uses the timetable only.")
                    .font(.caption).foregroundStyle(.secondary)
                switch model.realtimeStatus {
                case .live(let at): Text("Live delays applied at \(at.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.green).monospacedDigit()
                case .error(let e): Text(e).font(.caption).foregroundStyle(.orange)
                case .off: EmptyView()
                }
            }
            Section("Fallback") {
                Text("If the timetable is unavailable, the app asks Apple Maps for a transit estimate. No key needed.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private extension AppModel {
    /// Import phase in user voice; the raw failure reason stays in the log.
    var timetableStatus: String {
        switch importPhase {
        case .idle: feedVersion == nil ? "Not downloaded" : "Ready"
        case .failed: "Download failed. Check the connection and try again"
        default: importPhase.label
        }
    }
}
