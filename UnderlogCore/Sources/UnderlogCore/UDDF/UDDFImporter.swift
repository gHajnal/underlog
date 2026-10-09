import Foundation

/// Reads dives from Universal Dive Data Format (UDDF) files, the open interchange format many
/// dive logs and dive computers export. UDDF stores everything in SI units:
/// metres, seconds, Kelvin, Pascal and cubic metres.
public enum UDDFImporter {
    public enum ImportError: Error, Equatable {
        case notUDDF
        case noDives
    }

    public static func importDives(from data: Data) throws -> [ImportedDive] {
        let root = try XMLTreeParser.parse(data)
        guard root.localName == "uddf" else { throw ImportError.notUDDF }

        var mixes: [String: GasMix] = [:]
        for mix in root.descendants("mix") {
            guard let id = mix.attributes["id"] else { continue }
            let o2 = mix.child("o2")?.doubleValue ?? 0.21
            let he = mix.child("he")?.doubleValue ?? 0
            let gas = GasMix(oxygen: o2, helium: he)
            if gas.isValid { mixes[id] = gas }
        }

        var people: [String: String] = [:]
        for buddy in root.descendants("buddy") {
            guard let id = buddy.attributes["id"] else { continue }
            people[id] = personName(buddy)
        }

        var sites: [String: ImportedSite] = [:]
        for site in root.descendants("site") {
            guard let id = site.attributes["id"] else { continue }
            let name = site.child("name")?.trimmedText ?? ""
            let geo = site.child("geography")
            sites[id] = ImportedSite(
                name: name,
                latitude: geo?.child("latitude")?.doubleValue,
                longitude: geo?.child("longitude")?.doubleValue
            )
        }

        let diveNodes = (root.child("profiledata") ?? root).descendants("dive")
        var dives: [ImportedDive] = []
        for node in diveNodes {
            if let dive = parseDive(node, mixes: mixes, people: people, sites: sites) {
                dives.append(dive)
            }
        }
        guard !dives.isEmpty else { throw ImportError.noDives }
        return dives
    }

    private static func parseDive(
        _ node: XMLElementNode,
        mixes: [String: GasMix],
        people: [String: String],
        sites: [String: ImportedSite]
    ) -> ImportedDive? {
        let before = node.child("informationbeforedive")
        let after = node.child("informationafterdive")

        guard let dateText = before?.child("datetime")?.trimmedText, let startDate = parseDate(dateText) else {
            return nil
        }

        var site: ImportedSite?
        var buddies: [String] = []
        for link in before?.children("link") ?? [] {
            guard let ref = link.attributes["ref"] else { continue }
            if let s = sites[ref] { site = s }
            if let person = people[ref] { buddies.append(person) }
        }

        var cylinders: [ImportedCylinder] = []
        for tank in node.children("tankdata") {
            var cylinder = ImportedCylinder()
            if let ref = tank.child("link")?.attributes["ref"], let mix = mixes[ref] { cylinder.gas = mix }
            cylinder.volumeLiters = tank.child("tankvolume")?.doubleValue.map { $0 * 1000 }
            cylinder.startPressureBar = tank.child("tankpressurebegin")?.doubleValue.map { $0 / 100_000 }
            cylinder.endPressureBar = tank.child("tankpressureend")?.doubleValue.map { $0 / 100_000 }
            cylinders.append(cylinder)
        }

        var mode = DiveMode.openCircuit
        var samples: [DiveSample] = []
        for waypoint in node.child("samples")?.children("waypoint") ?? [] {
            if let type = waypoint.child("divemode")?.attributes["type"]?.lowercased() {
                mode = switch type {
                case "apnoe", "apnea": .freedive
                case "closedcircuit": .closedCircuitRebreather
                default: .openCircuit
                }
            }
            guard let time = waypoint.child("divetime")?.doubleValue,
                  let depth = waypoint.child("depth")?.doubleValue else { continue }
            var sample = DiveSample(time: time, depth: depth)
            sample.temperature = waypoint.child("temperature")?.doubleValue.map { $0 - 273.15 }
            sample.tankPressure = waypoint.child("tankpressure")?.doubleValue.map { $0 / 100_000 }
            sample.heartRate = waypoint.child("heartrate")?.doubleValue
            sample.noDecoTime = waypoint.child("nodecotime")?.doubleValue
            sample.stopDepth = waypoint.child("decostop")?.attributes["decodepth"]
                .flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            samples.append(sample)
        }

        let notes = after?.child("notes")?.children("para").map(\.trimmedText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        // UDDF ratings run from 1 to 10; the app uses 1 to 5.
        let rating = after?.path("rating", "ratingvalue")?.doubleValue
            .flatMap { Int(exactly: (min(max($0, 1), 10) / 2).rounded(.up)) }

        var dive = ImportedDive(
            startDate: startDate,
            duration: after?.child("diveduration")?.doubleValue ?? 0,
            maxDepth: after?.child("greatestdepth")?.doubleValue ?? 0,
            averageDepth: after?.child("averagedepth")?.doubleValue,
            minTemperature: after?.child("lowesttemperature")?.doubleValue.map { $0 - 273.15 },
            diveNumber: before?.child("divenumber")?.doubleValue.flatMap { Int(exactly: $0.rounded()) },
            mode: mode,
            cylinders: cylinders,
            samples: samples,
            site: site,
            buddies: buddies,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            rating: rating
        )
        dive.deriveMissingValuesFromProfile()
        return dive.maxDepth > 0 || dive.duration > 0 ? dive : nil
    }

    private static func personName(_ node: XMLElementNode) -> String {
        let personal = node.child("personal")
        let first = personal?.child("firstname")?.trimmedText ?? ""
        let last = personal?.child("lastname")?.trimmedText ?? ""
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        return personal?.child("nickname")?.trimmedText ?? node.attributes["id"] ?? "Buddy"
    }

    /// UDDF dates are ISO 8601, often without a time zone; those are read as local time.
    static func parseDate(_ text: String) -> Date? {
        let withZone = ISO8601DateFormatter()
        withZone.formatOptions = [.withInternetDateTime]
        if let date = withZone.date(from: text) { return date }
        withZone.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withZone.date(from: text) { return date }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
