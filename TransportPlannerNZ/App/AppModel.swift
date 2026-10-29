import AppKit
import CoreLocation
import Foundation
import Observation
import ServiceManagement

/// Central state: owns settings, the GTFS database, the plan refresh loop and notifications.
@Observable @MainActor
final class AppModel {
    nonisolated static let dbPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransportPlannerNZ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gtfs.sqlite").path
    }()

    var settings: AppSettings { didSet { if settings != oldValue { settingsChanged() } } }

    static let shared = AppModel()

    private(set) var journeys: [Journey] = []
    /// Text and symbol shown in the menu bar; refreshed every 30 s by `startLoop`.
    private(set) var menuTitle = ""
    private(set) var menuSymbol = "bus"
    private(set) var menuUrgency = MenuUrgency.calm
    private(set) var recommended: Journey?
    private(set) var fallback: AppleTransitFallback.Estimate?
    private(set) var originStops: [AccessStop] = []
    private(set) var destinationStops: [AccessStop] = []
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    /// A timetable check or download is running.
    private(set) var isImporting = false
    /// The last store open, timetable import or plan failed; cleared by the next success.
    private(set) var hasError = false
    private(set) var statusMessage = "Starting"
    private(set) var importPhase: GTFSImporter.Phase = .idle
    private(set) var feedVersion: String?
    private(set) var realtimeStatus: RealtimeStatus = .off
    /// Today's commute is settled: dismissed with "Not today" or confirmed with "Going".
    private(set) var dayDone: DayDone?
    /// Journeys passed on with "Next option" today. GTFS trip IDs repeat every day, so these reset at midnight.
    private(set) var skippedJourneyIDs: Set<String> = []
    private var skippedOn = ""
    /// Latest fix from Location Services; nil until one arrives or while permission is denied.
    private(set) var location: CLLocation?
    private(set) var locationDenied = false
    var presence: Presence { Presence(location: location, office: settings.office) }

    enum RealtimeStatus: Equatable { case off, live(Date), error(String) }
    /// Escalates the menu bar as the leave time nears: amber from `soonMinutes`, red once it is time to go.
    enum MenuUrgency: Equatable { case calm, soon, go }
    struct DayDone: Equatable { let day: String; let going: Bool }
    static let soonMinutes = 10

    private var store: GTFSStore?
    var hasTimetable: Bool { store != nil }
    private let importer = GTFSImporter(destinationPath: AppModel.dbPath)
    private let notifier = LeaveNotifier()
    private let leavePanel = LeavePanel()
    private let locationMonitor = LocationMonitor()
    private var refreshTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var refreshQueued = false
    private var lastFeedCheck: Date?
    private var stopsResolvedFor: (Place?, Place?, Double, Double, Set<String>)?

    private init() {
        settings = SettingsStore.load()
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { [weak self, importer] in await importer.observe { [weak self] p in Task { @MainActor in self?.importPhase = p } } }
        Task { await bootstrap() }
    }

    // MARK: Lifecycle

    private func bootstrap() async {
        AppLog.note("bootstrap: db exists=\(GTFSStore.exists(at: Self.dbPath))")
        locationMonitor.start(
            onUpdate: { [weak self] in self?.locationChanged($0) },
            onError: { AppLog.error("location failed: \($0)") })
        // The countdown is up to 30 s stale after sleep; replan straight away instead.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.startLoop() }
        }
        if GTFSStore.exists(at: Self.dbPath) { await openStore() }
        startLoop() // shows the Apple Maps estimate while a first download runs
    }

    private func openStore() async {
        do {
            let s = try GTFSStore(path: Self.dbPath)
            store = s
            feedVersion = await s.feedVersion
            stopsResolvedFor = nil
            hasError = false
        } catch {
            AppLog.error("open store failed: \(error)")
            hasError = true
            statusMessage = "Timetable needs re-downloading"
        }
    }

    /// Imports when there is no feed on disk, or when it is older than six days and AT has published a new file.
    /// Unforced calls check at most hourly (every five minutes with no timetable yet), so the refresh loop can
    /// call this on every tick.
    func refreshFeedIfStale(force: Bool = false) async {
        guard !isImporting else { return }
        if !force, let last = lastFeedCheck, Date().timeIntervalSince(last) < (store == nil ? 300 : 3600) { return }
        isImporting = true
        defer { isImporting = false }
        lastFeedCheck = Date()

        let localETag = await store?.meta("etag")
        let importedAt = await store?.importedAt
        let stale = importedAt.map { Date().timeIntervalSince($0) > 6 * 24 * 3600 } ?? true
        guard force || store == nil || stale else { return }
        let remote = await GTFSImporter.remoteETag()
        // Unreachable or unchanged: keep the feed we have rather than attempt a 32 MB download.
        if !force, store != nil, remote == nil || remote == localETag { return }
        do {
            AppLog.note("importing timetable (etag \(remote ?? "unknown"))")
            let started = Date()
            try await importer.run(etag: remote)
            await openStore()
            AppLog.note("import finished in \(Int(Date().timeIntervalSince(started)))s, feed \(self.feedVersion ?? "?")")
            await refresh()
        } catch {
            hasError = true
            statusMessage = "Timetable download failed"
            AppLog.error("import failed: \(error)")
        }
    }

    private func locationChanged(_ fix: CLLocation?) {
        let before = presence
        location = fix
        locationDenied = fix == nil
        guard presence != before else { return }
        AppLog.note("presence: \(before) -> \(presence)")
        if presence == .away { leavePanel.close() }
        updateMenuTitle()
        if presence == .atOffice { Task { await refresh() } } // a reminder may have come due while away
    }

    private func startLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var sinceRefresh = Int.max
            while !Task.isCancelled, let self {
                // Runs beside the loop: an import takes long enough that the countdown would freeze.
                Task { await self.refreshFeedIfStale() }
                if sinceRefresh >= self.refreshInterval { await self.refresh(); sinceRefresh = 0 }
                self.updateMenuTitle()
                try? await Task.sleep(for: .seconds(30))
                sinceRefresh += 30
            }
        }
    }

    /// Titles stay short ("12m", "Go", "5:05") so the status item barely changes width.
    private func updateMenuTitle() {
        menuTitle = ""
        menuUrgency = .calm
        if let done = doneToday {
            menuSymbol = done.going ? "figure.walk" : "moon"
        } else if presence == .away {
            menuSymbol = "bus" // no countdown when there is no office to leave
        } else if let f = fallback {
            menuSymbol = "bus"
            menuTitle = "~" + Self.menuClock(f.departure)
        } else if let r = recommended {
            if case .ride(let route, _, _, _, _, _) = r.firstRide.kind { menuSymbol = route.symbolName }
            let mins = Int((r.leaveAt.timeIntervalSinceNow / 60).rounded(.down))
            menuTitle = mins <= 0 ? "Go" : mins < 90 ? "\(mins)m" : Self.menuClock(r.leaveAt)
            menuUrgency = mins <= 0 ? .go : mins <= Self.soonMinutes ? .soon : .calm
            if menuUrgency == .go { menuSymbol = "figure.walk" }
        } else if !settings.isConfigured {
            menuSymbol = "gear"
        } else if hasError {
            menuSymbol = "exclamationmark.triangle"
        } else {
            menuSymbol = "bus"
        }
    }

    /// "5:05" without am/pm; the menu bar has no room for it and the hour is never ambiguous within a workday.
    private static func menuClock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    /// Poll faster as the leave time approaches so realtime delays are caught.
    private var refreshInterval: Int {
        guard let r = recommended else { return 120 }
        let m = r.leaveAt.timeIntervalSinceNow / 60
        return m < 15 ? 30 : m < 60 ? 60 : 300
    }

    /// Saves at once but replans after a pause, so typing a key or dragging a slider is one plan, not dozens.
    private func settingsChanged() {
        SettingsStore.save(settings)
        settingsTask?.cancel()
        settingsTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            syncLoginItem()
            await refresh()
        }
    }

    private func syncLoginItem() {
        let service = SMAppService.mainApp
        guard settings.launchAtLogin != (service.status == .enabled) else { return }
        do {
            if settings.launchAtLogin { try service.register() } else { try service.unregister() }
        } catch {
            AppLog.error("launch at login failed: \(error)")
        }
    }

    // MARK: Planning

    private var todayKey: String { GTFSStore.dayKey(Date()) }
    var doneToday: DayDone? { dayDone?.day == todayKey ? dayDone : nil }
    func skipToday() { finishDay(going: false) }
    /// The user is heading out; reminders stop until tomorrow.
    func going() { finishDay(going: true) }
    func resumeToday() { dayDone = nil; Task { await refresh() } }

    private func finishDay(going: Bool) {
        dayDone = DayDone(day: todayKey, going: going)
        clearPlan(going ? "On your way" : "Skipped for today")
        fallback = nil
        LeaveNotifier.clearDelivered()
        updateMenuTitle()
    }

    func skipRecommended() {
        rollOverDay()
        if let r = recommended { skippedJourneyIDs.insert(r.id) }
        notifier.skip(leads: settings.reminderLeadMinutes)
        leavePanel.close()
        LeaveNotifier.clearDelivered()
        Task { await refresh() }
    }

    func restoreSkipped() { skippedJourneyIDs = []; Task { await refresh() } }

    /// Overlapping calls (timer, settings, wake, a click) collapse into one more pass after the running one.
    func refresh() async {
        guard !isRefreshing else { refreshQueued = true; return }
        isRefreshing = true
        repeat {
            refreshQueued = false
            await refreshPlan()
        } while refreshQueued
        updateMenuTitle()
        isRefreshing = false
    }

    /// Forgets yesterday's "Going", "Not today" and skipped journeys.
    private func rollOverDay() {
        let today = todayKey
        if let done = dayDone, done.day != today { dayDone = nil }
        if skippedOn != today { skippedJourneyIDs = []; skippedOn = today }
    }

    /// Drops the current plan and puts `message` in the headline.
    private func clearPlan(_ message: String) {
        journeys = []; recommended = nil
        leavePanel.close()
        statusMessage = message
    }

    private func refreshPlan() async {
        guard settings.isConfigured, let office = settings.office, let home = settings.home else {
            clearPlan("Set your office and home in Settings"); fallback = nil; return
        }
        let now = Date()
        rollOverDay()
        let weekday = GTFSStore.feedCalendar.component(.weekday, from: now)
        guard settings.activeWeekdays.contains(weekday) else {
            clearPlan("No commute today"); fallback = nil
            AppLog.note("refresh: weekday \(weekday) not in \(self.settings.activeWeekdays.sorted())"); return
        }
        if let done = doneToday { clearPlan(done.going ? "On your way" : "Skipped for today"); fallback = nil; return }

        let window = settings.leaveWindow(on: now, in: GTFSStore.feedTimeZone)
        // Before the window opens, search just the window. Once inside or past it, keep searching from now
        // so there is always a "next best" option after the ideal one is missed.
        let searchWindow = now < window.lowerBound
            ? window
            : now.addingTimeInterval(-60)...max(window.upperBound, now.addingTimeInterval(90 * 60))
        let fallbackAt = max(now, window.lowerBound)
        guard let store else {
            let reason = switch importPhase {
            case .failed: "Timetable download failed"
            case .idle, .done: "Timetable not downloaded yet"
            default: "Downloading timetable"
            }
            await useFallback(office: office, home: home, at: fallbackAt, reason: reason)
            return
        }

        do {
            let started = Date()
            try await resolveStops(store: store, office: office, home: home)
            guard !originStops.isEmpty, !destinationStops.isEmpty else {
                await useFallback(office: office, home: home, at: fallbackAt, reason: originStops.isEmpty ? "No stops near the office" : "No stops near home")
                return
            }
            var req = PlanRequest(originStops: originStops, destinationStops: destinationStops, leaveWindow: searchWindow)
            req.maxTransfers = settings.maxTransfers
            req.boardingBufferSeconds = settings.boardingBufferSeconds
            req.walkMetersPerSecond = settings.walkMetersPerSecond
            var planned = try await JourneyPlanner(store: store).plan(req)
            planned = await applyRealtime(to: planned)
            guard doneToday == nil else { return } // "Going" or "Not today" landed while planning
            journeys = planned
            let prefs = JourneyChooser.Preferences(preferredLeave: settings.preferredLeave(on: now, in: GTFSStore.feedTimeZone), now: now)
            recommended = JourneyChooser.best(from: planned.filter { !skippedJourneyIDs.contains($0.id) }, prefs)
            lastRefresh = now
            hasError = false
            AppLog.note("planned in \(Date().timeIntervalSince(started))s: \(planned.count) journeys, recommended \(self.recommended?.summary ?? "none") leaving \(self.recommended?.leaveAt.description ?? "-")")
            // The prompt is about one bus; once the plan moves on it is stale.
            if leavePanel.journeyID != recommended?.id { leavePanel.close() }
            if let r = recommended {
                statusMessage = "Leave \(r.leaveAt.formatted(date: .omitted, time: .shortened))"
                fallback = nil
                // Away from the office the plan stays visible but quiet, and the schedule does not advance.
                guard presence != .away,
                      let reminder = notifier.evaluate(journey: r, windowEnd: window.upperBound, leads: settings.reminderLeadMinutes, now: now)
                else { return }
                switch reminder {
                case .lead(0): leavePanel.show(model: self); AppLog.note("notified: leave now for \(r.summary)")
                case .lead(let lead): AppLog.note("notified: \(lead) min lead for \(r.summary)")
                case .missed: leavePanel.close(); AppLog.note("notified: missed, next \(r.summary)")
                }
                do { try await notifier.post(reminder, journey: r, now: now) }
                catch { AppLog.error("notification failed: \(error)") }
            } else {
                await useFallback(office: office, home: home, at: fallbackAt, reason: planned.isEmpty ? "No direct services found" : "No more services today")
            }
        } catch {
            AppLog.error("planning failed: \(error)")
            hasError = true
            await useFallback(office: office, home: home, at: fallbackAt, reason: "Could not plan a route")
        }
    }

    private func useFallback(office: Place, home: Place, at date: Date, reason: String) async {
        clearPlan(reason)
        AppLog.note("fallback: \(reason)")
        fallback = try? await AppleTransitFallback.estimate(from: office, to: home, departingAt: date)
    }

    private func resolveStops(store: GTFSStore, office: Place, home: Place) async throws {
        let key = (Optional(office), Optional(home), settings.stopSearchRadiusMeters, settings.walkMetersPerSecond, settings.excludedStopIDs)
        if let k = stopsResolvedFor, k == key { return }
        let origin = try await access(store, office)
        let destination = try await access(store, home)
        guard self.store === store else { return } // a new timetable landed mid-lookup; the next pass redoes it
        originStops = origin; destinationStops = destination
        stopsResolvedFor = key
    }

    private func access(_ store: GTFSStore, _ place: Place) async throws -> [AccessStop] {
        try await store.stopsNear(place.coordinate, radiusMeters: settings.stopSearchRadiusMeters)
            .filter { !settings.excludedStopIDs.contains($0.stop.id) }
            .map { pair in
                let meters = pair.distance * 1.3 // straight line to street network detour factor
                return AccessStop(stop: pair.stop, walkMeters: meters, walkSeconds: Int(meters / settings.walkMetersPerSecond))
            }
    }

    private func applyRealtime(to journeys: [Journey]) async -> [Journey] {
        let key = settings.atSubscriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !journeys.isEmpty else { realtimeStatus = .off; return journeys }
        let tripIDs = Array(Set(journeys.compactMap { j -> String? in
            if case .ride(_, let t, _, _, _, _) = j.firstRide.kind { t.id } else { nil }
        }))
        do {
            let updates = try await ATRealtimeClient(subscriptionKey: key).tripUpdates(for: tripIDs)
            realtimeStatus = .live(Date())
            return RealtimeAdjuster.apply(updates, to: journeys)
        } catch {
            AppLog.error("realtime failed: \(error.localizedDescription)")
            realtimeStatus = .error("Live delays unavailable. Check the key")
            return journeys
        }
    }

    /// All stops within range of a place, for the settings UI. Includes excluded ones so they can be re-enabled.
    func candidateStops(for place: Place) async -> [(stop: Stop, distance: Double)] {
        guard let store else { return [] }
        return (try? await store.stopsNear(place.coordinate, radiusMeters: settings.stopSearchRadiusMeters)) ?? []
    }

    // MARK: Notification actions

    func handleNotificationAction(_ id: String) {
        switch id {
        case LeaveNotifier.goingAction: going()
        case LeaveNotifier.snoozeAction: skipRecommended()
        case LeaveNotifier.skipAction: skipToday()
        default: break
        }
    }
}
