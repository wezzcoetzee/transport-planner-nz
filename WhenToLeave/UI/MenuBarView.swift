import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let r = model.recommended {
                JourneyCard(journey: r, highlighted: true)
                alternatives(excluding: r)
            } else {
                if let f = model.fallback { fallbackView(f) }
                statusAction
            }
            NotificationHint()
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
            // Status ("On your way", "No commute today") outranks presence; away only hides the countdown.
            if model.recommended == nil {
                Text(model.statusMessage).font(.title3.weight(.semibold))
            } else if model.presence == .away {
                Text("Not at the office").font(.title3.weight(.semibold))
            } else if let r = model.recommended {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    Text(leaveText(r, now: ctx.date)).font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
            Spacer()
            realtimeBadge
        }
    }

    private func leaveText(_ j: Journey, now: Date) -> String {
        let mins = Int((j.leaveAt.timeIntervalSince(now) / 60).rounded(.down))
        if mins <= 0 { return "Leave now" }
        if mins < 60 { return "Leave in \(mins) min" }
        return "Leave at \(j.leaveAt.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private var realtimeBadge: some View {
        switch model.realtimeStatus {
        case .live: Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
        case .error(let e): Label("Schedule", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).help(e)
        case .off: Text("Schedule").font(.caption).foregroundStyle(.secondary).help("Add an AT API key in Settings for live delays")
        }
    }

    /// The one action that resolves the headline status, when there is one.
    @ViewBuilder private var statusAction: some View {
        if !model.settings.isConfigured {
            Button("Open Settings") { openSettings(); NSApp.activate() }.buttonStyle(.borderless).font(.caption)
        } else if case .failed = model.importPhase {
            Button("Retry download") { Task { await model.refreshFeedIfStale(force: true) } }.buttonStyle(.borderless).font(.caption)
        }
    }

    @ViewBuilder private func alternatives(excluding r: Journey) -> some View {
        let others = model.journeys.filter {
            $0.id != r.id && !$0.cancelled && !model.skippedJourneyIDs.contains($0.id) && $0.leaveAt > Date().addingTimeInterval(-60)
        }.prefix(4)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(others)) { JourneyCard(journey: $0, highlighted: false) }
            }
        }
    }

    private func fallbackView(_ f: AppleTransitFallback.Estimate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apple Maps: leave \(f.departure.formatted(date: .omitted, time: .shortened)), home \(f.arrival.formatted(date: .omitted, time: .shortened))")
                .font(.callout).monospacedDigit()
            Text("\(Int(f.travelTime / 60)) min via transit").foregroundStyle(.secondary).font(.caption).monospacedDigit()
        }
    }

    private var footer: some View {
        HStack {
            Button(model.isRefreshing ? "Updating" : "Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r").disabled(model.isRefreshing)
                .help(model.lastRefresh.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not yet updated")
            if model.recommended != nil { Button("Next option") { model.skipRecommended() } }
            if !model.skippedJourneyIDs.isEmpty { Button("Undo") { model.restoreSkipped() } }
            if model.doneToday != nil { Button("Resume") { model.resumeToday() } } else { Button("Not today") { model.skipToday() } }
            if let o = model.settings.office, let h = model.settings.home {
                Button("Maps") { AppleTransitFallback.openInMaps(from: o, to: h) }
            }
            Spacer()
            Button { openSettings(); NSApp.activate() } label: { Image(systemName: "gear") }
                .accessibilityLabel("Settings").help("Settings").keyboardShortcut(",")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .accessibilityLabel("Quit When To Leave").help("Quit").keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

struct JourneyCard: View {
    let journey: Journey
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(journey.leaveAt.formatted(date: .omitted, time: .shortened)).monospacedDigit().font(.callout.weight(highlighted ? .semibold : .regular))
                Text(journey.arriveAt.formatted(date: .omitted, time: .shortened)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                // A same-stop transfer is a zero-metre walk; the two ride legs already show the change.
                ForEach(journey.legs.filter { if case .walk(let m) = $0.kind { m >= 1 } else { true } }) { leg in legRow(leg) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(journey.duration / 60)) min").font(.caption).monospacedDigit()
                Text("^[\(journey.stopCount) stop](inflect: true)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if let d = journey.realtimeDelay {
                    Text(d >= 60 ? "+\(d / 60) min late" : d <= -60 ? "\(-d / 60) min early" : "on time")
                        .font(.caption2).monospacedDigit().foregroundStyle(d >= 180 ? .orange : .green)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(highlighted ? 1 : 0.7)
    }

    @ViewBuilder private func legRow(_ leg: Leg) -> some View {
        switch leg.kind {
        case .walk(let meters):
            Label("\(max(1, Int((leg.duration / 60).rounded(.up)))) min walk · \(Int(meters)) m", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        case .ride(let route, let trip, let board, let alight, _, _):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: route.symbolName)
                    Text(route.shortName).fontWeight(.semibold)
                    Text(trip.headsign).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(board.name) → \(alight.name)").lineLimit(1).truncationMode(.middle)
            }
            .font(.caption)
        }
    }
}
