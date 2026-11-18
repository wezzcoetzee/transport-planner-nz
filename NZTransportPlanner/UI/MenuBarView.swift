import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The headline and its captions are one block; the 10 pt gaps separate blocks.
            VStack(alignment: .leading, spacing: 2) {
                header
                if isAway {
                    // The consequence of "away" belongs next to it, not only in Settings.
                    Text("Reminders paused").font(.caption).foregroundStyle(.secondary)
                }
                if model.recommended == nil { statusDetail }
                if let note = model.staleTimetableNote {
                    HStack(alignment: .firstTextBaseline) {
                        Text(note).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(model.downloadActionTitle) { Task { await model.refreshFeedIfStale(force: true) } }
                            .remedyButtonStyle().disabled(model.isImporting)
                    }
                }
            }
            if let r = model.recommended {
                RecommendedRow(journey: r, reason: model.recommendationReason)
                alternatives(excluding: r)
            } else {
                statusAction
            }
            // Permission is asked once both places are set; before that there is nothing to warn about.
            if model.settings.isConfigured { NotificationHint() }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 360)
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            headline
                .font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // The source badge describes a plan, so it only appears beside one. It stays its own element so
            // VoiceOver can reach the button inside it.
            if model.recommended != nil { realtimeBadge.font(.caption) }
        }
    }

    /// Status ("On your way", "No commute today") outranks presence; away only hides the countdown, the menu bar's
    /// rule too. An Apple Maps estimate counts down like a plan, marked "~" as approximate.
    private var isAway: Bool { (model.recommended != nil || model.fallback != nil) && model.presence == .away }

    @ViewBuilder private var headline: some View {
        if isAway {
            Text("Away from the office")
        } else if let r = model.recommended {
            TimelineView(r.countdownSchedule) { ctx in
                Text(Self.leaveText(r.leaveAt, now: ctx.date)).accessibilityLabel(AppModel.spokenLeave(r.leaveAt, now: ctx.date))
            }
        } else if let f = model.fallback {
            TimelineView(Journey.countdownSchedule(to: f.departure)) { ctx in
                Text(Self.leaveText(f.departure, now: ctx.date, approximate: true))
                    .accessibilityLabel(AppModel.spokenEstimate(f.departure, now: ctx.date))
            }
        } else {
            Text(model.headline)
        }
    }

    static func leaveText(_ leaveAt: Date, now: Date, approximate: Bool = false) -> String {
        let mins = Int((leaveAt.timeIntervalSince(now) / 60).rounded(.down))
        let about = approximate ? "~" : ""
        if mins <= 0 { return "Leave now" }
        if mins < AppModel.clockThresholdMinutes { return "Leave in \(about)\(mins) min" }
        return "Leave at \(about)\(leaveAt.sentenceClock)"
    }

    @ViewBuilder private var realtimeBadge: some View {
        // Without an AT key there is no badge: the absence of "Live" says it.
        switch model.realtimeStatus {
        case .live(let at): Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
            .help("Live delays at \(at.sentenceClock)")
        case .rejected:
            // Only a rejected key has a fix in Settings; a network failure has nothing to open.
            Button { showSettings(.data) } label: { Label("Live unavailable", systemImage: "exclamationmark.triangle") }
                .buttonStyle(.borderless).foregroundStyle(.orange)
                .help("AT key rejected. Open the Data tab").accessibilityHint("AT key rejected. Opens Settings")
        case .unreachable:
            Label("Live unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                .help("Could not reach AT for live delays. Using timetable times")
        case .off: EmptyView()
        }
    }

    /// The one action that resolves the headline status, when there is one.
    @ViewBuilder private var statusAction: some View {
        Group {
            if !model.settings.isConfigured {
                Button("Open Settings") { showSettings(.commute) }
            } else if model.canRetryDownload {
                Button(model.downloadActionTitle) { Task { await model.refreshFeedIfStale(force: true) } }.disabled(model.isImporting)
            } else if model.missingStops {
                Button("Open Route settings") { showSettings(.route) }
            }
        }
        .remedyButtonStyle()
    }

    @ViewBuilder private func alternatives(excluding r: Journey) -> some View {
        let others = model.alternatives.prefix(4)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(others)) {
                    AlternativeRow(journey: $0, showsStop: $0.firstBoardStop != r.firstBoardStop,
                                   showsMode: $0.firstRoute?.type != r.firstRoute?.type)
                }
            }
        }
    }

    /// Evidence under a headline with no plan: the bus you are on your way to, or the Apple Maps estimate and why.
    @ViewBuilder private var statusDetail: some View {
        let reason = model.importProgress ?? (model.fallback == nil ? nil : model.headline)
        let caught = model.doneToday?.journey.flatMap { $0.arriveAt > .now ? $0 : nil } // gone once you are home
        if let caught { JourneyLines(journey: caught) }
        if model.fallback != nil || reason != nil {
            VStack(alignment: .leading, spacing: 2) {
                // Away, the estimate describes a departure from somewhere the user is not.
                if let f = model.fallback, !isAway {
                    Text("Apple Maps estimate, home \(f.arrival.sentenceClock)")
                }
                if let reason { Text(reason).foregroundStyle(.secondary) }
            }
            .font(.caption).monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }

    /// Actions follow the state: only what would do something right now is offered. Each answer has a key, and a key
    /// only works while its word is shown, so Return cannot end the day before Going is offered.
    private var footer: some View {
        HStack(spacing: 12) {
            if let r = model.recommended {
                // Going means "leaving now"; offered from the orange threshold so it cannot end the day by accident.
                if r.minutesUntilLeave(from: .now) <= AppModel.soonMinutes {
                    Button("Going") { model.going() }.fontWeight(.semibold)
                        .keyboardShortcut(.defaultAction).help("Leaving now (↩)")
                }
                Button("Next") { model.skipRecommended() }.disabled(model.alternatives.isEmpty)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help(model.nextHelp)
            }
            if !model.skipped.isEmpty, model.doneToday == nil {
                Button("Previous") { model.undoSkip() }.keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Bring back the option passed over with Next (←)")
            }
            if model.doneToday != nil {
                Button("Undo") { model.resumeToday() }.keyboardShortcut("z")
                    .help("Take back Going or Not today and plan again (⌘Z)")
                    .accessibilityHint(model.doneToday?.going == true ? "Takes back Going" : "Takes back Not today")
            } else if model.recommended != nil || model.fallback != nil {
                Button("Not today") { model.skipToday() }.keyboardShortcut(.delete).help("No reminders until tomorrow (⌘⌫)")
            }
            Spacer()
            // Maps is about this journey, so it stays beside the answers; app-level actions go behind the gear.
            if let o = model.settings.office, let h = model.settings.home {
                Button { AppleTransitFallback.openInMaps(from: o, to: h) } label: { Image(systemName: "map") }
                    .accessibilityLabel("Open in Apple Maps").help("Open this commute in Apple Maps")
            }
            appMenu
        }
        .buttonStyle(FooterButtonStyle())
        .lineLimit(1).fixedSize(horizontal: false, vertical: true)
        .font(.callout) // the answers are the title size, not the smallest text on the board
    }

    /// Settings, Refresh and Quit: rare actions, kept out of the answer row so a stray click cannot quit the app.
    private var appMenu: some View {
        Menu {
            Button("Settings…") { showSettings(.commute) }.keyboardShortcut(",")
            if model.settings.isConfigured {
                // Shows ⌘R; the app command in NZTransportPlannerApp is what answers it while this menu is closed.
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r").disabled(model.isRefreshing)
                if let at = model.lastRefresh { Text("Updated \(at.sentenceClock)") }
            }
            Divider()
            Button("Quit NZ Transport Planner") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small) // AppKit draws the menu at its own size; small matches the callout-sized Maps icon
        .fixedSize()
        .padding(.leading, -6) // AppKit insets the menu button; this keeps the footer's 12 pt gap beside Maps
        .accessibilityLabel("Settings, refresh and quit").help("Settings, refresh and quit")
    }

    private func showSettings(_ tab: SettingsView.Tab) { model.settingsTab = tab; openSettings(); NSApp.activate() }
}

/// Footer words: primary text, never accent-colored (green and orange are the only lamps), with a hit area taller
/// than the caption so the most-used actions are easy to click. Dims while pressed or disabled.
private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
            // A custom style draws no system focus ring, so keyboard focus gets its own quiet outline.
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(isFocused ? 0.5 : 0)))
    }
}

/// The leave-time column shared by every row, wide enough for "leave 12:56" on the recommended one.
private let boardTimeColumn: CGFloat = 70

/// The recommended journey in full: every leg, the bus time at the stop, and when you get home.
struct RecommendedRow: View {
    let journey: Journey
    /// Why this bus won, as hover help (VoiceOver reads it after the row); the board itself stays as evidence.
    var reason: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Named once, like "home": the alternatives below carry only the values.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("leave").font(.caption).foregroundStyle(.secondary)
                Text(journey.leaveAt.boardClock).font(.callout.weight(.semibold)).monospacedDigit()
            }
            .frame(width: boardTimeColumn, alignment: .leading)
            // Reads in travel order: walk, bus, where to get off, then home on that same line.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shownLegs) { legRow($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDetail)
        .help(reason ?? "")
    }

    /// The full sentence plus what only this row shows: the walk to the stop and where to get off.
    private var spokenDetail: String {
        var parts = [journey.spokenSummary]
        if case .walk = journey.legs.first?.kind, let walk = journey.legs.first {
            parts.append("\(max(1, Int((walk.duration / 60).rounded(.up)))) min walk to the stop")
        }
        if case .ride(_, _, _, let alight, _, _) = journey.rides.last?.kind { parts.append("off at \(alight.name)") }
        return parts.joined(separator: ", ")
    }

    /// A same-stop transfer is a zero-metre walk, and the walk home is already inside the "home" time.
    private var shownLegs: [Leg] {
        journey.legs.enumerated().filter { i, leg in
            guard case .walk(let m) = leg.kind else { return true }
            return m >= 1 && i < journey.legs.count - 1
        }.map(\.element)
    }

    @ViewBuilder private func legRow(_ leg: Leg) -> some View {
        switch leg.kind {
        case .walk:
            Label("\(max(1, Int((leg.duration / 60).rounded(.up)))) min walk", systemImage: "figure.walk")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        case .ride(let route, let trip, let board, let alight, _, _):
            // Realtime applies to the first bus: the expected time, with the delay beside it to say why it moved.
            let timetable = leg.id == journey.firstRide.id ? journey.timetableBoardTime : nil
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: route.symbolName)
                    Text(route.shortName).fontWeight(.semibold)
                    Text(leg.departure.boardClock).fontWeight(.semibold).monospacedDigit()
                    if timetable != nil, let d = journey.delayNote { DelayText(text: d) }
                }
                // The stop line below already gives the direction; the timetable time is detail for the curious.
                .help(timetable.map { "\(trip.headsign). Timetable \($0.sentenceClock)" } ?? trip.headsign)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(board.name) → \(alight.name)").lineLimit(3)
                    if leg.id == journey.rides.last?.id {
                        Spacer(minLength: 8)
                        Text("home \(journey.arriveAt.boardClock)").monospacedDigit()
                            .foregroundStyle(.secondary).fixedSize() // evidence, dimmed like every arrival line; never squeezed
                    }
                }
            }
            .font(.caption)
        }
    }
}

/// "4 min late" in orange: the one lamp a journey carries. Only delays of three minutes or more are shown.
struct DelayText: View {
    let text: String

    var body: some View { Text(text).monospacedDigit().foregroundStyle(.orange).fixedSize() }
}

extension View {
    /// Remedy buttons in the popover, panel and hints: small and bordered, never accent-colored.
    func remedyButtonStyle() -> some View { buttonStyle(.bordered).controlSize(.small) }
}

/// The bus and the trip home in two lines, shared by the leave panel and "On your way".
struct JourneyLines: View {
    let journey: Journey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(journey.boardingLine).lineLimit(2)
                if let d = journey.delayNote { DelayText(text: d) }
            }
            Text(journey.arrivalLine).foregroundStyle(.secondary)
        }
        .font(.caption).monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// A later option as one departure-board line: leave time, routes, where to board if not the usual stop, home time.
/// The recommended row above names the columns ("home"), so these rows carry only the values.
struct AlternativeRow: View {
    let journey: Journey
    let showsStop: Bool
    let showsMode: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(journey.leaveAt.boardClock).font(.callout).monospacedDigit()
                .frame(width: boardTimeColumn, alignment: .leading).opacity(dim)
            HStack(spacing: 4) {
                Group {
                    if showsMode, let route = journey.firstRoute { Image(systemName: route.symbolName) }
                    Text(journey.summary).fontWeight(.semibold).lineLimit(1).layoutPriority(1) // routes outlast the stop name
                }
                .opacity(dim)
                // A real delay is a lamp, so it stays at full strength while the rest of the row recedes.
                if let d = journey.delayNote { DelayText(text: d) }
                // "from" so the stop reads as where you board, not where you change.
                if showsStop, let stop = journey.firstBoardStop { Text("from \(stop.name)").lineLimit(1).opacity(dim) }
            }
            .font(.caption)
            Spacer(minLength: 4)
            Text(journey.arriveAt.boardClock).font(.caption).monospacedDigit().opacity(dim).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(journey.spokenSummary)
    }

    /// One dimming step keeps small text above 4.5:1; Increase Contrast lifts it further.
    private var dim: Double { contrast == .increased ? 0.85 : 0.6 }
}

extension Journey {
    var firstRoute: Route? { if case .ride(let route, _, _, _, _, _) = firstRide.kind { route } else { nil } }

    /// One sentence for VoiceOver: "Leave 5:02 pm, INN 5:08 pm from Lower Albert Street, 4 min late, home 5:23 pm".
    var spokenSummary: String { "Leave \(leaveAt.sentenceClock), \(notificationBody)" }

    /// Redraws a countdown once a minute, just after the rounded-down minute to `leaveAt` changes.
    var countdownSchedule: PeriodicTimelineSchedule { Self.countdownSchedule(to: leaveAt) }

    static func countdownSchedule(to date: Date) -> PeriodicTimelineSchedule {
        .periodic(from: date.addingTimeInterval(tickOffset - 24 * 3600), by: 60)
    }
}
