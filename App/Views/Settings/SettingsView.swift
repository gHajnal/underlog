import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UnderlogCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Dive.startDate) private var dives: [Dive]
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKey.defaultWaterType) private var water: WaterType = .salt
    @AppStorage(SettingsKey.maxPPO2) private var maxPPO2 = 1.4

    @State private var exportDocument: UDDFDocument?
    @State private var exportMessage: String?
    @State private var isConfirmingRenumber = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $units) {
                        ForEach(UnitSystem.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Default water", selection: $water) {
                        ForEach(WaterType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Max ppO₂", selection: $maxPPO2) {
                        ForEach([1.2, 1.3, 1.4, 1.5, 1.6], id: \.self) { Text("\(UnitSystem.format($0, decimals: 1)) bar").tag($0) }
                    }
                } header: {
                    Text("Diving defaults")
                } footer: {
                    Text("Used for new dives, imports and the gas tools. Most dive computers use EN 13319 unless set to fresh or salt water.")
                }

                Section {
                    Button("Export all dives as UDDF", systemImage: "square.and.arrow.up") {
                        exportDocument = UDDFDocument(data: UDDFExporter.export(dives.map(Logbook.exportable)))
                    }
                    .disabled(dives.isEmpty)
                    Button("Renumber dives by date", systemImage: "number") {
                        isConfirmingRenumber = true
                    }
                    .disabled(dives.isEmpty)
                } header: {
                    Text("Logbook")
                } footer: {
                    Text("UDDF is an open format most dive logs can import, so your data is never locked in.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    LabeledContent("Dives in log", value: "\(dives.count)")
                }
            }
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .uddf,
                defaultFilename: "Underlog \(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                switch result {
                case .success: exportMessage = "Your log was exported."
                case .failure(let error): exportMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .alert(exportMessage ?? "", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Renumber all dives?", isPresented: $isConfirmingRenumber, titleVisibility: .visible) {
                Button("Renumber \(dives.count) dives") { Logbook.renumber(in: context) }
            } message: {
                Text("Dives will be numbered 1, 2, 3… from your oldest dive onwards. Current numbers will be replaced.")
            }
        }
    }
}

struct UDDFDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.uddf]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
