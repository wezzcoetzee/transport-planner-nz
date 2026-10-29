import SwiftUI
import MapKit

/// Text field with MapKit completions, resolving a selection to a `Place`.
struct PlaceSearchField: View {
    let title: String
    @Binding var place: Place?
    @State private var query = ""
    /// Searching for a replacement. The saved place stays until a new one is picked, so backing out loses nothing.
    @State private var editing = false
    @State private var results: [MKLocalSearchCompletion] = []
    @State private var completer = Completer()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = place, !editing {
                LabeledContent(title) {
                    HStack {
                        Text(p.name).lineLimit(1)
                        Button("Change") { editing = true }.buttonStyle(.borderless)
                    }
                }
            } else {
                HStack {
                    Text(title).frame(width: 60, alignment: .leading)
                    TextField("Search address or place", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _, q in completer.search(q, region: aucklandRegion) { results = $0 } }
                        .onSubmit { if let first = results.first { Task { await resolve(first) } } }
                        .onExitCommand { cancel() }
                    if place != nil { Button("Cancel") { cancel() }.buttonStyle(.borderless) }
                }
            }
            ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, r in
                Button {
                    Task { await resolve(r) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(r.title)
                        Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 68)
            }
        }
    }

    private var aucklandRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: .init(latitude: -36.85, longitude: 174.76), latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    private func resolve(_ completion: MKLocalSearchCompletion) async {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return }
        let c = item.location.coordinate
        place = Place(name: [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", "), latitude: c.latitude, longitude: c.longitude)
        cancel()
    }

    private func cancel() { query = ""; results = []; editing = false }

    @MainActor
    final class Completer: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
        private let completer = MKLocalSearchCompleter()
        private var handler: (([MKLocalSearchCompletion]) -> Void)?
        override init() { super.init(); completer.delegate = self; completer.resultTypes = [.address, .pointOfInterest] }
        func search(_ q: String, region: MKCoordinateRegion, _ handler: @escaping ([MKLocalSearchCompletion]) -> Void) {
            self.handler = handler
            completer.region = region
            if q.isEmpty { completer.cancel(); handler([]) } else { completer.queryFragment = q }
        }
        func completerDidUpdateResults(_ c: MKLocalSearchCompleter) { handler?(c.results) }
    }
}
