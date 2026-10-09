import SwiftUI
import SwiftData
import UnderlogCore

/// Adds a new dive (when `dive` is nil) or edits an existing one.
struct DiveEditorView: View {
    let dive: Dive?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKey.defaultWaterType) private var defaultWater: WaterType = .salt
    @Query(sort: \DiveSite.name) private var sites: [DiveSite]
    @Query(sort: \Trip.name) private var trips: [Trip]

    @State private var draft = DiveDraft()
    @State private var didLoad = false
    @State private var showErrors = false
    @State private var newBuddy = ""
    @FocusState private var siteFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if showErrors, !draft.validationErrors.isEmpty {
                    Section {
                        ForEach(draft.validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityIdentifier(A11yID.editorValidation)
                }

                Section("When") {
                    DatePicker("Start", selection: $draft.startDate)
                }

                siteSection
                depthAndTimeSection
                if draft.mode != .freedive { gasSection }
                buddiesSection

                Section("Trip") {
                    TextField("Trip name (optional)", text: $draft.tripName)
                        .textInputAutocapitalization(.words)
                    let matches = suggestions(for: draft.tripName, in: trips.map(\.name))
                    ForEach(matches, id: \.self) { name in
                        Button { draft.tripName = name } label: { Label(name, systemImage: "suitcase") }
                    }
                }

                conditionsSection

                Section("Rating") {
                    StarRatingControl(rating: $draft.rating)
                }

                Section("Notes") {
                    TextField("What happened on this dive?", text: $draft.notes, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle(dive == nil ? "New dive" : "Edit dive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier(A11yID.editorCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .accessibilityIdentifier(A11yID.editorSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Sections

    private var siteSection: some View {
        Section("Site") {
            TextField("Site name", text: $draft.siteName)
                .textInputAutocapitalization(.words)
                .focused($siteFieldFocused)
                .accessibilityIdentifier(A11yID.editorSite)
            if siteFieldFocused {
                ForEach(suggestions(for: draft.siteName, in: sites.map(\.name)), id: \.self) { name in
                    Button {
                        draft.siteName = name
                        if let site = sites.first(where: { $0.name == name }) {
                            draft.latitude = site.latitude
                            draft.longitude = site.longitude
                        }
                        siteFieldFocused = false
                    } label: {
                        Label(name, systemImage: "mappin.and.ellipse")
                    }
                }
            }
            DisclosureGroup("Coordinates") {
                NumberField("Latitude", value: $draft.latitude, unit: "°")
                NumberField("Longitude", value: $draft.longitude, unit: "°")
            }
        }
    }

    private var depthAndTimeSection: some View {
        Section("Depth and time") {
            NumberField("Max depth", value: converted($draft.maxDepth, toDisplay: units.depth(fromMeters:), toStored: units.meters(fromDepth:)),
                        unit: units.depthUnit, identifier: A11yID.editorMaxDepth)
            NumberField("Duration", value: $draft.durationMinutes, unit: "min", identifier: A11yID.editorDuration)
            NumberField("Average depth", value: converted($draft.averageDepth, toDisplay: units.depth(fromMeters:), toStored: units.meters(fromDepth:)), unit: units.depthUnit)
            NumberField("Water temperature", value: converted($draft.temperature, toDisplay: units.temperature(fromCelsius:), toStored: units.celsius(fromTemperature:)), unit: units.temperatureUnit, allowsNegative: true)
        }
    }

    private var gasSection: some View {
        Section {
            ForEach($draft.cylinders) { $cylinder in
                NavigationLink {
                    CylinderEditorView(cylinder: $cylinder, water: draft.water)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cylinder.gas.name).font(.headline)
                        Text(cylinderSubtitle(cylinder))
                            .font(.subheadline)
                            .foregroundStyle(cylinder.validationError == nil ? Color.secondary : Color.red)
                    }
                }
            }
            .onDelete { draft.cylinders.remove(atOffsets: $0) }
            Button("Add cylinder", systemImage: "plus.circle") {
                var cylinder = CylinderDraft()
                if let last = draft.cylinders.last {
                    cylinder.oxygenPercent = last.oxygenPercent
                    cylinder.volumeLiters = last.volumeLiters
                }
                draft.cylinders.append(cylinder)
            }
        } header: {
            Text("Gas")
        }
    }

    private var buddiesSection: some View {
        Section("Buddies") {
            ForEach(draft.buddies, id: \.self) { buddy in
                Text(buddy)
            }
            .onDelete { draft.buddies.remove(atOffsets: $0) }
            HStack {
                TextField("Add a buddy", text: $newBuddy)
                    .textInputAutocapitalization(.words)
                    .onSubmit(addBuddy)
                Button("Add", action: addBuddy)
                    .disabled(newBuddy.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var conditionsSection: some View {
        Section("Conditions") {
            Picker("Dive type", selection: $draft.mode) {
                ForEach(DiveMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Water", selection: $draft.water) {
                ForEach(WaterType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField("Visibility", value: converted($draft.visibility, toDisplay: units.depth(fromMeters:), toStored: units.meters(fromDepth:)), unit: units.depthUnit)
            TextField("Suit (for example 5 mm wetsuit)", text: $draft.suit)
            NumberField("Weight", value: converted($draft.weight, toDisplay: { units == .metric ? $0 : $0 * 2.204_62 }, toStored: { units == .metric ? $0 : $0 / 2.204_62 }), unit: units == .metric ? "kg" : "lb")
        }
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        draft = dive.map(DiveDraft.init(dive:)) ?? DiveDraft(defaultWater: defaultWater)
    }

    private func addBuddy() {
        let name = newBuddy.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !draft.buddies.contains(name) else { return }
        draft.buddies.append(name)
        newBuddy = ""
    }

    private func save() {
        guard draft.validationErrors.isEmpty else {
            withAnimation { showErrors = true }
            return
        }
        if let dive {
            draft.apply(to: dive, in: context)
        } else {
            let newDive = Dive(number: Logbook.nextDiveNumber(in: context), startDate: draft.startDate)
            context.insert(newDive)
            draft.apply(to: newDive, in: context)
        }
        dismiss()
    }

    // MARK: Helpers

    private func cylinderSubtitle(_ cylinder: CylinderDraft) -> String {
        if let error = cylinder.validationError { return error }
        var parts: [String] = []
        if let volume = cylinder.volumeLiters { parts.append("\(UnitSystem.format(volume, decimals: 1)) L") }
        if let start = cylinder.startPressureBar, let end = cylinder.endPressureBar {
            parts.append("\(units.formatPressure(start)) → \(units.formatPressure(end))")
        }
        return parts.isEmpty ? "Tap to add details" : parts.joined(separator: " · ")
    }

    private func suggestions(for text: String, in names: [String]) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(Set(names))
            .filter { $0.localizedCaseInsensitiveContains(query) && $0.localizedCaseInsensitiveCompare(query) != .orderedSame }
            .sorted()
            .prefix(4)
            .map { $0 }
    }

    /// A binding that shows a stored metric value in the chosen display unit.
    private func converted(
        _ binding: Binding<Double?>,
        toDisplay: @escaping (Double) -> Double,
        toStored: @escaping (Double) -> Double
    ) -> Binding<Double?> {
        Binding(
            get: { binding.wrappedValue.map(toDisplay) },
            set: { binding.wrappedValue = $0.map(toStored) }
        )
    }
}

/// A labelled numeric text field with its unit. Accepts both "." and "," as the decimal separator.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    let unit: String
    var allowsNegative = false
    var identifier: String?

    @State private var text = ""

    init(_ title: String, value: Binding<Double?>, unit: String, allowsNegative: Bool = false, identifier: String? = nil) {
        self.title = title
        self._value = value
        self.unit = unit
        self.allowsNegative = allowsNegative
        self.identifier = identifier
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    .accessibilityLabel("\(title), \(unit)")
                    .accessibilityIdentifier(identifier ?? title)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(title)
                .accessibilityHidden(true)
        }
        .onAppear { text = Self.display(value) }
        .onChange(of: text) { _, newText in
            let parsed = Self.parse(newText)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            // Only rewrite the text when the value changed from outside (for example a unit switch),
            // not when it is just the typed value coming back through a unit conversion.
            if !Self.nearlyEqual(Self.parse(text), newValue) { text = Self.display(newValue) }
        }
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let number = Double(cleaned), number.isFinite else { return nil }
        return number
    }

    static func nearlyEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) < 0.005
        default: false
        }
    }

    static func display(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// Five tappable stars that VoiceOver users can adjust by swiping up or down.
struct StarRatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? 0 : star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(star <= rating ? .yellow : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}
