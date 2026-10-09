import SwiftUI
import SwiftData
import UnderlogCore

struct DiveListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Dive.startDate, order: .reverse) private var dives: [Dive]
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric

    @State private var searchText = ""
    @State private var isAddingDive = false
    @State private var isPickingFiles = false
    @State private var importSession: ImportSession?
    @State private var diveToDelete: Dive?
    @State private var path: [Dive] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if dives.isEmpty {
                    emptyState
                } else if filteredDives.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    list
                }
            }
            .navigationTitle("Dives")
            .navigationDestination(for: Dive.self) { DiveDetailView(dive: $0) }
            .toolbar { addMenu }
            .searchable(text: $searchText, prompt: "Sites, buddies, trips, notes")
            .sheet(isPresented: $isAddingDive) {
                DiveEditorView(dive: nil)
            }
            .sheet(item: $importSession) { session in
                ImportReviewView(session: session)
            }
            .fileImporter(
                isPresented: $isPickingFiles,
                allowedContentTypes: [.fitActivity, .uddf, .xml, .data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    importSession = ImportSession(urls: urls, existingStartDates: dives.map(\.startDate))
                }
            }
            .confirmationDialog(
                "Delete this dive?",
                isPresented: Binding(get: { diveToDelete != nil }, set: { if !$0 { diveToDelete = nil } }),
                titleVisibility: .visible,
                presenting: diveToDelete
            ) { dive in
                Button("Delete \(dive.title)", role: .destructive) {
                    context.delete(dive)
                    diveToDelete = nil
                }
            } message: { _ in
                Text("The dive, its profile and its cylinders will be removed. This can't be undone.")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.dives) { dive in
                        NavigationLink(value: dive) {
                            DiveRow(dive: dive, units: units)
                        }
                        .accessibilityIdentifier(A11yID.diveRowPrefix + String(dive.number))
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                diveToDelete = dive
                            }
                        }
                    }
                } header: {
                    SectionHeader(section: section, units: units)
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(A11yID.diveList)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No dives yet", systemImage: "water.waves")
        } description: {
            Text("Add your first dive by hand, or import dives from a Garmin FIT or UDDF file.")
        } actions: {
            Button("Add dive") { isAddingDive = true }
                .buttonStyle(.glassProminent)
            Button("Import from file") { isPickingFiles = true }
                .buttonStyle(.glass)
        }
        .accessibilityIdentifier(A11yID.emptyState)
    }

    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Add dive", systemImage: "plus") { isAddingDive = true }
                    .accessibilityIdentifier(A11yID.addDiveButton)
                Button("Import from file", systemImage: "square.and.arrow.down") { isPickingFiles = true }
                    .accessibilityIdentifier(A11yID.importButton)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityIdentifier(A11yID.addMenu)
        }
    }

    // MARK: Filtering and grouping

    private var filteredDives: [Dive] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return dives }
        return dives.filter { dive in
            let fields = [dive.site?.name, dive.trip?.name, dive.notes, dive.suit, String(dive.number)].compactMap { $0 } + dive.buddies
            return fields.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Consecutive dives on the same trip form one section; dives without a trip are grouped by month.
    private var sections: [DiveSection] {
        var result: [DiveSection] = []
        for dive in filteredDives {
            let key: DiveSection.Key = dive.trip.map { .trip($0.persistentModelID) } ?? .month(Self.monthKey(dive.startDate))
            if let last = result.last, last.key == key {
                result[result.count - 1].dives.append(dive)
            } else {
                let title = dive.trip?.name ?? dive.startDate.formatted(.dateTime.month(.wide).year())
                result.append(DiveSection(key: key, title: title, isTrip: dive.trip != nil, dives: [dive]))
            }
        }
        return result
    }

    private static func monthKey(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 100 + (components.month ?? 0)
    }
}

struct DiveSection: Identifiable {
    enum Key: Hashable {
        case trip(PersistentIdentifier)
        case month(Int)
    }

    let key: Key
    let title: String
    let isTrip: Bool
    var dives: [Dive]

    /// Keys can repeat when a trip's dives are interleaved with others, so the id includes the first dive.
    var id: String { "\(key)-\(dives.first?.persistentModelID.hashValue ?? 0)" }
}

private struct SectionHeader: View {
    let section: DiveSection
    let units: UnitSystem

    var body: some View {
        HStack {
            if section.isTrip {
                Label(section.title, systemImage: "suitcase")
            } else {
                Text(section.title)
            }
            Spacer()
            Text("^[\(section.dives.count) dive](inflect: true)")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
