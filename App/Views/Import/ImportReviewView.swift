import SwiftUI
import SwiftData
import UnderlogCore

/// Files the diver picked for import, plus the start times already in the log (for duplicate detection).
struct ImportSession: Identifiable {
    let id = UUID()
    let urls: [URL]
    let existingStartDates: [Date]
}

/// One dive found in the picked files.
struct ImportCandidate: Identifiable {
    var id: UUID { dive.id }
    let dive: ImportedDive
    let fileName: String
    let isDuplicate: Bool
    var isSelected: Bool
}

struct ImportFailure: Identifiable {
    let id = UUID()
    let fileName: String
    let reason: String
}

enum ImportReader {
    /// Reads and parses files away from the main thread. Each file is tried as the format its extension suggests first.
    static func read(_ files: [(name: String, data: Data)]) async -> (dives: [(String, ImportedDive)], failures: [ImportFailure]) {
        await Task.detached(priority: .userInitiated) {
            var dives: [(String, ImportedDive)] = []
            var failures: [ImportFailure] = []
            for file in files {
                do {
                    let parsed = try parse(file.data, fileName: file.name)
                    dives += parsed.map { (file.name, $0) }
                } catch {
                    failures.append(ImportFailure(fileName: file.name, reason: describe(error)))
                }
            }
            return (dives, failures)
        }.value
    }

    private static func parse(_ data: Data, fileName: String) throws -> [ImportedDive] {
        let isFIT = fileName.lowercased().hasSuffix(".fit")
        do {
            return isFIT ? try FITImporter.importDives(from: data) : try UDDFImporter.importDives(from: data)
        } catch {
            // Fall back to the other format in case the file has an unexpected extension.
            if let dives = try? (isFIT ? UDDFImporter.importDives(from: data) : FITImporter.importDives(from: data)) {
                return dives
            }
            throw error
        }
    }

    private static func describe(_ error: Error) -> String {
        if error as? FITImporter.ImportError == .noDiveData {
            return "This activity has no dive data. Export the dive itself from Garmin Connect."
        }
        if error as? FITDecoder.DecodingError == .notAFITFile || error as? UDDFImporter.ImportError == .notUDDF {
            return "This isn't a Garmin FIT or UDDF file."
        }
        if error as? FITDecoder.DecodingError == .truncated {
            return "The file is incomplete or damaged."
        }
        if error as? UDDFImporter.ImportError == .noDives {
            return "The file doesn't contain any dives."
        }
        return "The file couldn't be read."
    }
}

struct ImportReviewView: View {
    let session: ImportSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKey.defaultWaterType) private var water: WaterType = .salt

    @State private var candidates: [ImportCandidate] = []
    @State private var failures: [ImportFailure] = []
    @State private var isLoading = true

    private var selectedCount: Int { candidates.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Reading files…")
                } else if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("No dives found", systemImage: "doc.questionmark")
                    } description: {
                        Text(failures.map { "\($0.fileName): \($0.reason)" }.joined(separator: "\n"))
                    }
                } else {
                    reviewList
                }
            }
            .navigationTitle("Import dives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedCount)", role: .confirm, action: importSelected)
                        .disabled(selectedCount == 0)
                }
            }
            .task { await load() }
        }
    }

    private var reviewList: some View {
        List {
            if candidates.contains(where: \.isDuplicate) {
                Section {
                    Label("Dives that look like ones already in your log are unticked.", systemImage: "info.circle")
                        .font(.footnote)
                }
            }
            Section("\(candidates.count) found") {
                ForEach($candidates) { $candidate in
                    Toggle(isOn: $candidate.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.dive.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text("\(units.formatDepth(candidate.dive.maxDepth)) · \(UnitSystem.formatDuration(candidate.dive.duration))")
                                .font(.subheadline)
                            Text(candidate.isDuplicate ? "Probably already in your log or listed above" : candidate.fileName)
                                .font(.caption)
                                .foregroundStyle(candidate.isDuplicate ? .orange : .secondary)
                        }
                    }
                }
            }
            if !failures.isEmpty {
                Section("Couldn't import") {
                    ForEach(failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.fileName).font(.subheadline)
                            Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func load() async {
        var files: [(name: String, data: Data)] = []
        for url in session.urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                files.append((url.lastPathComponent, try Data(contentsOf: url)))
            } catch {
                failures.append(ImportFailure(fileName: url.lastPathComponent, reason: "The file couldn't be opened."))
            }
        }
        let result = await ImportReader.read(files)
        failures += result.failures
        // Compare with the log and with dives already listed, so the same dive picked twice
        // (for example as a FIT and a UDDF file) is only ticked once.
        var seenStartDates = session.existingStartDates
        candidates = result.dives
            .sorted { $0.1.startDate > $1.1.startDate }
            .map { name, dive in
                let duplicate = seenStartDates.contains { DuplicateDetector.isLikelyDuplicate($0, dive.startDate) }
                seenStartDates.append(dive.startDate)
                return ImportCandidate(dive: dive, fileName: name, isDuplicate: duplicate, isSelected: !duplicate)
            }
        isLoading = false
    }

    private func importSelected() {
        Logbook.insert(candidates.filter(\.isSelected).map(\.dive), water: water, in: context)
        dismiss()
    }
}
