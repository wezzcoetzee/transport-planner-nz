import SwiftUI
import MapKit

/// Text field with MapKit completions, resolving a selection to a `Place`.
struct PlaceSearchField: View {
    let title: String
    @Binding var place: Place?
    /// Focus the field when it opens empty; only one field per form should ask for this.
    var autofocus = false
    @State private var query = ""
    /// Searching for a replacement. The saved place stays until a new one is picked, so backing out loses nothing.
    @State private var editing = false
    @State private var results: [MKLocalSearchCompletion] = []
    @State private var completer = Completer()
    @State private var notFound = false
    @State private var resolveFailed = false
    @FocusState private var focused: Bool

    var body: some View {
        if let p = place, !editing {
            LabeledContent(title) {
                HStack {
                    Text(p.name).lineLimit(1).truncationMode(.middle).help(p.name) // the suburb is at the end
                    Button("Change") { editing = true }.buttonStyle(.borderless).accessibilityLabel("Change \(title.lowercased())")
                }
            }
        } else {
            LabeledContent(title) {
                // Suggestions and messages sit directly under the field, not across the form under the label.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // The prompt is a placeholder; a plain title would render as a second label in a grouped form.
                        TextField(title, text: $query, prompt: Text("Search address or place"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading) // text and suggestions share one left edge
                            .focused($focused)
                            .onAppear { if editing || (autofocus && place == nil) { focused = true } } // typing goes straight in
                            .onChange(of: autofocus) { _, on in if on, place == nil { focused = true } } // Home after Office
                            .onChange(of: query) { _, q in
                                notFound = false; resolveFailed = false
                                completer.search(q, region: aucklandRegion) { results = $0 }
                            }
                            // An empty answer is a dead end worth saying, once typing pauses rather than on every key.
                            .task(id: query) {
                                try? await Task.sleep(for: .milliseconds(700))
                                if !Task.isCancelled, !query.isEmpty, results.isEmpty { notFound = true }
                            }
                            .onSubmit { if let first = results.first { Task { await resolve(first) } } }
                            .onExitCommand { cancel() }
                        if place != nil {
                            Button("Cancel") { cancel() }.buttonStyle(.borderless).accessibilityLabel("Keep the saved \(title.lowercased())")
                        }
                    }
                    if resolveFailed {
                        Text("Could not look that place up. Try again").font(.caption).foregroundStyle(.orange)
                    } else if notFound, results.isEmpty {
                        Text("No matches. Check the connection or try another search").font(.caption).foregroundStyle(.secondary)
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
                    }
                }
            }
        }
    }

    private var aucklandRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: .init(latitude: -36.85, longitude: 174.76), latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    private func resolve(_ completion: MKLocalSearchCompletion) async {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { resolveFailed = true; return }
        let c = item.location.coordinate
        place = Place(name: [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", "), latitude: c.latitude, longitude: c.longitude)
        cancel()
    }

    private func cancel() { query = ""; results = []; editing = false; notFound = false; resolveFailed = false }

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
        func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) { handler?([]) }
    }
}
