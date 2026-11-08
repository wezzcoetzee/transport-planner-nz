import AppKit
import CoreLocation
import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// Central state: owns settings, the GTFS database, the plan refresh loop and notifications.
@Observable @MainActor
final class AppModel {
    nonisolated static let dbPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NZTransportPlanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gtfs.sqlite").path
    }()

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            // A new or cleared key makes the last live result meaningless until the next plan checks it.
            if settings.atSubscriptionKey != oldValue.atSubscriptionKey { realtimeStatus = .off }
            settingsChanged()
        }
    }

    static let shared = AppModel()

    private(set) var journeys: [Journey] = []
    /// Text and symbol shown in the menu bar; refreshed by `startLoop` each time the countdown's minute changes.
    private(set) var menuTitle = ""
    private(set) var menuSymbol = "bus"
    private(set) var menuUrgency = MenuUrgency.calm
    /// Spoken form of the status item, since "12m" and a bare symbol mean nothing to VoiceOver.
    private(set) var menuAccessibilityLabel = "NZ Transport Planner"
    private(set) var recommended: Journey?
    private(set) var fallback: AppleTransitFallback.Estimate?
    private(set) var originStops: [AccessStop] = []
    private(set) var destinationStops: [AccessStop] = []
    /// Stops exist near the place but the user switched every one off, which needs different words than "none".
    private var originAllOff = false
    private var destinationAllOff = false
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    /// A timetable check or download is running.
    private(set) var isImporting = false
    /// The last store open, timetable import or plan failed; cleared by the next success.
    private(set) var hasError = false
    private(set) var statusMessage = "Starting"
    /// The last plan stopped at "no timetable yet", so the headline follows the import instead of `statusMessage`.
    private(set) var awaitingTimetable = false
    /// The last plan found no usable stops near a place, so the popover offers the Route tab.
    private(set) var missingStops = false
    /// The timetable answered and there is nothing left to catch today; the menu bar shows the moon.
    private(set) var nothingToday = false
    private(set) var importPhase: GTFSImporter.Phase = .idle
    private(set) var feedVersion: String?
    /// When the timetable on disk was downloaded.
    private(set) var importedAt: Date?
    private(set) var realtimeStatus: RealtimeStatus = .off
    /// Today's commute is settled: dismissed with "Not today" or confirmed with "Going".
    private(set) var dayDone: DayDone?
    /// Journeys passed on with "Next" today. GTFS trip IDs repeat every day, so these reset at midnight.
    /// In the order they were skipped, so Undo steps back one at a time.
    private(set) var skippedJourneyIDs: [String] = []
    private var skippedOn = ""
    /// Latest fix from Location Services; nil until one arrives or while permission is denied.
    private(set) var location: CLLocation?
    private(set) var locationDenied = false
    /// The Settings tab to show next time Settings opens, so a status in the popover can link to its fix.
    var settingsTab = SettingsView.Tab.commute
    var presence: Presence { Presence(location: location, office: settings.office) }

    enum RealtimeStatus: Equatable {
        case off, live(Date), rejected, unreachable
        var problem: String? {
            switch self {
            case .rejected: "AT key rejected"
            case .unreachable: "Live delays unreachable"
            case .off, .live: nil
            }
        }
    }
    /// Escalates the menu bar as the leave time nears: amber from `soonMinutes`, red once it is time to go.
    enum MenuUrgency: Equatable { case calm, soon, go }
    /// `journey` is the bus the user said "Going" to, kept so the popover can still show it on the way out.
    struct DayDone: Equatable {
        let day: String
        let going: Bool
        var journey: Journey? = nil
        var settledAt = Date.now
        /// When "On your way" becomes "Done for today": the bus's arrival, or an hour after Going when no bus is known.
        var homeBy: Date { journey?.arriveAt ?? settledAt.addingTimeInterval(3600) }
    }
    static let soonMinutes = LeaveNotifier.soonMinutes
    /// Beyond this a countdown is harder to read than a clock time, in the menu bar and the headline alike.
    static let clockThresholdMinutes = 60

    private var store: GTFSStore?
    var hasTimetable: Bool {
        #if DEBUG
        if demoStops != nil { return true }
        #endif
        return store != nil
    }
    private let importer = GTFSImporter(destinationPath: AppModel.dbPath)
    private let notifier = LeaveNotifier()
    private let leavePanel = LeavePanel()
    private let locationMonitor = LocationMonitor()
    private var refreshTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var refreshQueued = false
    private var permissionsAsked = false
    /// The last update check could not reach AT, so an old timetable may be out of date without anything failing.
    private var lastCheckFailed = false
    /// macOS refused the login item; Settings explains instead of silently flipping the toggle back.
    private(set) var loginItemRefused = false
    /// Straight-line distance to street-network walking distance. Settings shows stops with the same factor.
    nonisolated static let walkDetour = 1.3
    private var lastFeedCheck: Date?
    private var stopsResolvedFor: (Place?, Place?, Double, Double, Set<String>)?
    #if DEBUG
    /// Stand-in stop lists for `Screenshots`, which never opens a timetable.
    @ObservationIgnored fileprivate var demoStops: ((Place) -> [(stop: Stop, distance: Double)])?
    #endif

    private init() {
        settings = SettingsStore.load()
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        guard !Screenshots.isEnabled else { return }
        #endif
        Task { [weak self, importer] in await importer.observe { [weak self] p in Task { @MainActor in self?.importPhase = p } } }
        Task { await bootstrap() }
    }

    // MARK: Lifecycle

    private func bootstrap() async {
        AppLog.note("bootstrap: db exists=\(GTFSStore.exists(at: Self.dbPath))")
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
            importedAt = await s.importedAt
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
        // A forced or first download shows as started at once, not after the ETag check returns.
        if force || store == nil { importPhase = .downloading(0) }
        let remote = await GTFSImporter.remoteETag()
        // Unreachable or unchanged: keep the feed we have rather than attempt a 32 MB download.
        lastCheckFailed = remote == nil
        if !force, store != nil, remote == nil || remote == localETag { return }
        do {
            AppLog.note("importing timetable (etag \(remote ?? "unknown"))")
            let started = Date()
            try await importer.run(etag: remote)
            await openStore()
            AppLog.note("import finished in \(Int(Date().timeIntervalSince(started)))s, feed \(self.feedVersion ?? "?")")
            await refresh()
        } catch {
            // With a timetable still on disk, planning carries on; the Data tab says the refresh failed, and the
            // popover only once that timetable is over a week old (`staleTimetableNote`).
            if store == nil { hasError = true; statusMessage = "Timetable download failed" }
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

    /// Notification and location prompts wait until both places are set, so they arrive with an obvious reason and
    /// not while the user is still typing the home address.
    /// Must run after the app finishes launching; asking for notifications earlier fails without a prompt.
    func askPermissionsOnce() {
        guard settings.isConfigured, !permissionsAsked else { return }
        permissionsAsked = true
        locationMonitor.start(
            onUpdate: { [weak self] in self?.locationChanged($0) },
            onError: { [weak self] in
                AppLog.error("location failed: \($0)")
                self?.locationDenied = true // treated like "off": reminders fire anywhere, and Settings says so
            })
        Task {
            do { AppLog.note("notifications allowed=\(try await LeaveNotifier.requestPermission())") }
            catch { AppLog.error("notification permission failed: \(error)") }
            NotificationCenter.default.post(name: .notificationPermissionAnswered, object: nil) // hints re-check now
        }
    }

    private func startLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var plannedAt = Date.distantPast
            while !Task.isCancelled, let self {
                // Runs beside the loop: an import takes long enough that the countdown would freeze.
                Task { await self.refreshFeedIfStale() }
                if Date().timeIntervalSince(plannedAt) >= Double(self.refreshInterval) { await self.refresh(); plannedAt = Date() }
                self.updateMenuTitle()
                try? await Task.sleep(for: .seconds(self.secondsToNextTick))
            }
        }
    }

    /// Wakes just after the countdown's minute changes, so the menu bar flips with the popover; at most 30 s otherwise.
    private var secondsToNextTick: Double {
        guard let left = (recommended?.leaveAt ?? fallback?.departure)?.timeIntervalSinceNow, left > 0 else { return 30 }
        return min(30, left.truncatingRemainder(dividingBy: 60) + Journey.tickOffset)
    }

    /// Titles stay short ("12m", "Go", "5:05") so the status item barely changes width.
    private func updateMenuTitle() {
        menuTitle = ""
        menuUrgency = .calm
        menuSymbol = "bus"
        if let done = doneToday {
            menuSymbol = done.going ? "checkmark.circle" : "moon"
            menuAccessibilityLabel = headline // "On your way", then "Done for today" once home
        } else if presence == .away, recommended != nil || fallback != nil {
            menuAccessibilityLabel = "Away from the office" // no countdown when there is no office to leave
        } else if let f = fallback {
            let mins = Int((f.departure.timeIntervalSinceNow / 60).rounded(.down))
            menuTitle = mins <= 0 ? "Go" : "~" + (mins < Self.clockThresholdMinutes ? "\(mins)m" : Self.menuClock(f.departure))
            setUrgency(minutes: mins) // an estimate's "Go" means the same as a plan's
            menuAccessibilityLabel = Self.spokenEstimate(f.departure, now: .now)
        } else if let r = recommended {
            if case .ride(let route, _, _, _, _, _) = r.firstRide.kind { menuSymbol = route.symbolName }
            let mins = r.minutesUntilLeave(from: .now)
            menuTitle = mins <= 0 ? "Go" : mins < Self.clockThresholdMinutes ? "\(mins)m" : Self.menuClock(r.leaveAt)
            setUrgency(minutes: mins)
            menuAccessibilityLabel = mins <= 0 ? "Leave now"
                : mins < Self.clockThresholdMinutes ? "Leave in \(mins) minutes" : "Leave at \(Self.menuClock(r.leaveAt))"
        } else if !settings.isConfigured {
            menuAccessibilityLabel = "NZ Transport Planner. Set up your commute"
        } else if awaitingTimetable, importActivity != nil {
            menuSymbol = "arrow.down.circle" // a retry in progress outranks the last failure
            menuAccessibilityLabel = headline
        } else if hasError {
            menuSymbol = "exclamationmark.triangle"
            menuAccessibilityLabel = headline
        } else if nothingToday {
            menuSymbol = "moon" // the bare bus then only means "not set up" or "away"
            menuAccessibilityLabel = headline
        } else if awaitingTimetable {
            menuSymbol = "arrow.down.circle"
            menuAccessibilityLabel = headline
        } else if missingStops {
            menuSymbol = "exclamationmark.triangle" // a state with a fix in Settings
            menuAccessibilityLabel = headline
        } else {
            menuAccessibilityLabel = headline
        }
    }

    private func setUrgency(minutes mins: Int) {
        menuUrgency = mins <= 0 ? .go : mins <= Self.soonMinutes ? .soon : .calm
        if menuUrgency == .go { menuSymbol = "figure.walk" }
    }

    /// Later options worth showing beside the recommendation: not skipped, not cancelled, not already gone.
    var alternatives: [Journey] {
        guard let r = recommended else { return [] }
        return journeys.filter {
            $0.id != r.id && !$0.cancelled && !skippedJourneyIDs.contains($0.id) && $0.leaveAt > Date().addingTimeInterval(-60)
        }
    }

    /// The download action named for what it will do in the current state.
    var downloadActionTitle: String {
        if case .failed = importPhase { return "Retry download" }
        return hasTimetable ? "Download again" : "Download"
    }

    /// A refresh failed and the timetable in use is over a week old, so plans may be missing services.
    var staleTimetableNote: String? {
        let failed = if case .failed = importPhase { true } else { false }
        guard failed || lastCheckFailed, let importedAt else { return nil }
        let days = Int(Date().timeIntervalSince(importedAt) / 86_400)
        guard days > 7 else { return nil }
        return "Timetable is \(days) days old. " + (failed ? "Latest download failed" : "Could not check for a newer one")
    }

    /// VoiceOver for an Apple Maps estimate, in the menu bar and popover alike: always "about".
    static func spokenEstimate(_ departure: Date, now: Date) -> String {
        let mins = Int((departure.timeIntervalSince(now) / 60).rounded(.down))
        return "Apple Maps estimate. " + (mins <= 0 ? "Leave now"
            : mins < clockThresholdMinutes ? "Leave in about \(mins) minutes" : "Leave at about \(menuClock(departure))")
    }

    /// The popover headline when there is no plan to count down to.
    var headline: String {
        if let done = doneToday, done.going, done.homeBy < .now { return "Done for today" }
        guard awaitingTimetable else { return statusMessage }
        return switch importPhase {
        case .failed: "Timetable download failed"
        case .idle, .done: "Timetable not downloaded yet"
        case .downloading: "Downloading timetable"
        case .extracting, .importing, .indexing: "Preparing timetable"
        }
    }

    /// A running download in user voice; nil when nothing is downloading. The raw phase stays in the log.
    var importActivity: String? {
        switch importPhase {
        case .downloading(let p) where p > 0: "Timetable \(Int(p * 100))% downloaded"
        case .downloading: "Downloading timetable"
        case .extracting, .importing, .indexing: "Preparing timetable"
        default: nil
        }
    }

    /// Progress under the headline while the plan waits on the first download.
    var importProgress: String? { awaitingTimetable && importActivity != headline ? importActivity : nil }

    /// A download button belongs only beside the status it fixes, not under "On your way" after an old failure.
    var canRetryDownload: Bool { awaitingTimetable && importActivity == nil } // failed, or finished but unusable

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

    /// Saves at once but replans after a pause, so typing a key or tapping a stepper is one plan, not dozens.
    private func settingsChanged() {
        #if DEBUG
        guard !Screenshots.isEnabled else { return } // demo settings must never replace the user's own
        #endif
        SettingsStore.save(settings)
        settingsTask?.cancel()
        settingsTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            askPermissionsOnce()
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
            settings.launchAtLogin = service.status == .enabled // the toggle shows what macOS actually did
            loginItemRefused = true
        }
    }

    /// The login item can be removed in System Settings; Settings calls this on appear so the toggle tells the truth.
    func refreshLoginItemState() {
        let status = SMAppService.mainApp.status
        if status == .requiresApproval { loginItemRefused = true }
        let enabled = status == .enabled
        if settings.launchAtLogin != enabled { settings.launchAtLogin = enabled }
    }

    // MARK: Planning

    private var todayKey: String { GTFSStore.dayKey(Date()) }
    var doneToday: DayDone? { dayDone?.day == todayKey ? dayDone : nil }
    func skipToday() { finishDay(going: false, journey: nil) }
    /// The user is heading out; reminders stop until tomorrow.
    /// `journeyID` names the bus when Going came from a notification; it may no longer be the recommended one.
    func going(journeyID: String? = nil) {
        // A notification's bus that is no longer planned is not swapped for a different one the user never saw.
        finishDay(going: true, journey: journeyID.map { id in journeys.first { $0.id == id } } ?? recommended)
    }
    func resumeToday() { dayDone = nil; Task { await refresh() } }

    private func finishDay(going: Bool, journey: Journey?) {
        dayDone = DayDone(day: todayKey, going: going, journey: journey)
        skippedJourneyIDs = [] // nothing left to undo once the day is settled
        clearPlan(going ? "On your way" : "Not today")
        fallback = nil
        LeaveNotifier.clearDelivered()
        updateMenuTitle()
    }

    func skipRecommended() {
        rollOverDay()
        if let r = recommended { skippedJourneyIDs.append(r.id) }
        notifier.skip(leads: settings.reminderLeadMinutes)
        leavePanel.close()
        LeaveNotifier.clearDelivered()
        Task { await refresh() }
    }

    /// Brings back the most recently skipped option only.
    func undoSkip() { _ = skippedJourneyIDs.popLast(); Task { await refresh() } }

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
        awaitingTimetable = false
        missingStops = false
        nothingToday = false
        notifier.clearIfStale(now: .now) // a reminder for a bus that left must not outlive the plan that made it
        guard let office = settings.office, let home = settings.home else {
            clearPlan(settings.office == nil && settings.home == nil ? "Set up your commute" : settings.office == nil ? "Set your office" : "Set your home")
            fallback = nil; return
        }
        let now = Date()
        rollOverDay()
        // An answer given today outranks the weekday check, so "Going" on a Saturday still reads "On your way".
        if let done = doneToday { clearPlan(done.going ? "On your way" : "Not today"); fallback = nil; return }
        let weekday = GTFSStore.feedCalendar.component(.weekday, from: now)
        guard settings.activeWeekdays.contains(weekday) else {
            clearPlan("No commute today"); fallback = nil; nothingToday = true
            AppLog.note("refresh: weekday \(weekday) not in \(self.settings.activeWeekdays.sorted())"); return
        }

        let window = settings.leaveWindow(on: now, in: GTFSStore.feedTimeZone)
        // Before the window opens, search just the window. Once inside or past it, keep searching from now
        // so there is always a "next best" option after the ideal one is missed.
        let searchWindow = now < window.lowerBound
            ? window
            : now.addingTimeInterval(-60)...max(window.upperBound, now.addingTimeInterval(90 * 60))
        let fallbackAt = max(now, window.lowerBound)
        guard let store else {
            awaitingTimetable = true
            await useFallback(office: office, home: home, at: fallbackAt, reason: headline)
            return
        }

        do {
            let started = Date()
            try await resolveStops(store: store, office: office, home: home)
            guard !originStops.isEmpty, !destinationStops.isEmpty else {
                missingStops = true
                await useFallback(office: office, home: home, at: fallbackAt, reason: originStops.isEmpty
                    ? (originAllOff ? "All stops near the office are off" : "No stops near the office")
                    : (destinationAllOff ? "All stops near home are off" : "No stops near home"))
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
                // The timetable answered: there is nothing to catch. An estimate here would invent a bus (often
                // tomorrow's, or one just skipped), so only the status shows; Maps stays in the footer.
                let t = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
                clearPlan(planned.isEmpty ? "No services between \(t(window.lowerBound)) and \(t(window.upperBound))"
                    : planned.allSatisfy { skippedJourneyIDs.contains($0.id) } ? "No later option today" : "No more services today")
                fallback = nil; nothingToday = true
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
        let estimate = try? await AppleTransitFallback.estimate(from: office, to: home, departingAt: date)
        // Late at night Maps answers with tomorrow's first service, which is not today's leave time.
        fallback = estimate.flatMap { GTFSStore.feedCalendar.isDate($0.departure, inSameDayAs: date) ? $0 : nil }
    }

    private func resolveStops(store: GTFSStore, office: Place, home: Place) async throws {
        let key = (Optional(office), Optional(home), settings.stopSearchRadiusMeters, settings.walkMetersPerSecond, settings.excludedStopIDs)
        if let k = stopsResolvedFor, k == key { return }
        let origin = try await access(store, office)
        let destination = try await access(store, home)
        guard self.store === store else { return } // a new timetable landed mid-lookup; the next pass redoes it
        originStops = origin.usable; destinationStops = destination.usable
        originAllOff = origin.allOff; destinationAllOff = destination.allOff
        stopsResolvedFor = key
    }

    private func access(_ store: GTFSStore, _ place: Place) async throws -> (usable: [AccessStop], allOff: Bool) {
        let near = try await store.stopsNear(place.coordinate, radiusMeters: settings.stopSearchRadiusMeters)
        let usable = near.filter { !settings.excludedStopIDs.contains($0.stop.id) }.map { pair in
            let meters = pair.distance * Self.walkDetour
            return AccessStop(stop: pair.stop, walkMeters: meters, walkSeconds: Int(meters / settings.walkMetersPerSecond))
        }
        return (usable, !near.isEmpty && usable.isEmpty)
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
            if case .unauthorized = error as? ATRealtimeClient.ClientError { realtimeStatus = .rejected } else { realtimeStatus = .unreachable }
            return journeys
        }
    }

    /// All stops within range of a place, for the settings UI. Includes excluded ones so they can be re-enabled.
    func candidateStops(for place: Place) async -> [(stop: Stop, distance: Double)] {
        #if DEBUG
        if let demoStops { return demoStops(place) }
        #endif
        guard let store else { return [] }
        return (try? await store.stopsNear(place.coordinate, radiusMeters: settings.stopSearchRadiusMeters)) ?? []
    }

    // MARK: Notification actions

    /// `journeyID` is the bus the notification was about. "Next" on an old reminder must not skip a newer plan.
    func handleNotificationAction(_ id: String, journeyID: String?) {
        switch id {
        case LeaveNotifier.goingAction: going(journeyID: journeyID)
        case LeaveNotifier.snoozeAction: if journeyID == nil || journeyID == recommended?.id { skipRecommended() }
        case LeaveNotifier.skipAction: skipToday()
        case UNNotificationDefaultActionIdentifier: if recommended != nil, presence != .away { leavePanel.show(model: self) } // show the plan
        default: break
        }
    }
}

#if DEBUG
extension AppModel {
    /// Puts a fixed state on screen for `Screenshots` without opening the timetable or touching the network.
    /// Settings are assigned before the rest so the debounced replan never fires before the app quits.
    func seedForScreenshots(settings: AppSettings, journeys: [Journey] = [], live: Bool = false, status: String = "",
                            phase: GTFSImporter.Phase = .idle, fallback: AppleTransitFallback.Estimate? = nil,
                            done: Bool? = nil, location: CLLocation? = nil, feedVersion: String? = nil,
                            stops: ((Place) -> [(stop: Stop, distance: Double)])? = nil, skipped: [String] = []) {
        self.settings = settings
        self.journeys = journeys
        recommended = done == nil ? journeys.first : nil
        realtimeStatus = live ? .live(.now) : .off
        lastRefresh = .now
        statusMessage = status
        importPhase = phase
        awaitingTimetable = phase != .idle
        self.fallback = fallback
        dayDone = done.map { DayDone(day: todayKey, going: $0, journey: $0 ? journeys.first : nil) }
        self.location = location
        self.feedVersion = feedVersion
        importedAt = feedVersion == nil ? nil : .now.addingTimeInterval(-2 * 24 * 3600)
        demoStops = stops
        skippedJourneyIDs = skipped
        updateMenuTitle()
    }
}
#endif

extension Notification.Name {
    /// Posted once the notification permission prompt has been answered.
    static let notificationPermissionAnswered = Notification.Name("notificationPermissionAnswered")
}
