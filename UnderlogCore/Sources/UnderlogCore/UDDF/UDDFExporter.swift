import Foundation

/// Writes dives as a UDDF 3.2 file so the whole log can be moved to any other dive software.
public enum UDDFExporter {
    public static func export(_ dives: [ImportedDive], generatorName: String = "Underlog", generatorVersion: String = "1.0") -> Data {
        var mixIDs: [GasMix: String] = [:]
        var buddyIDs: [String: String] = [:]
        var siteIDs: [ImportedSite: String] = [:]

        for dive in dives {
            for cylinder in dive.cylinders where mixIDs[cylinder.gas] == nil {
                mixIDs[cylinder.gas] = "mix\(mixIDs.count + 1)"
            }
            for buddy in dive.buddies where buddyIDs[buddy] == nil {
                buddyIDs[buddy] = "buddy\(buddyIDs.count + 1)"
            }
            if let site = dive.site, siteIDs[site] == nil {
                siteIDs[site] = "site\(siteIDs.count + 1)"
            }
        }

        var x = XMLWriter()
        x.line("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        x.open("uddf", attributes: ["version": "3.2.0", "xmlns": "http://www.streit.cc/uddf/3.2/"])

        x.open("generator")
        x.element("name", generatorName)
        x.element("version", generatorVersion)
        x.element("datetime", formatDate(Date()))
        x.close("generator")

        if !mixIDs.isEmpty {
            x.open("gasdefinitions")
            for (mix, id) in mixIDs.sorted(by: { $0.value < $1.value }) {
                x.open("mix", attributes: ["id": id])
                x.element("name", mix.name)
                x.element("o2", number(mix.oxygen))
                x.element("n2", number(mix.nitrogen))
                x.element("he", number(mix.helium))
                x.close("mix")
            }
            x.close("gasdefinitions")
        }

        x.open("diver")
        x.open("owner", attributes: ["id": "owner"])
        x.close("owner")
        for (name, id) in buddyIDs.sorted(by: { $0.value < $1.value }) {
            x.open("buddy", attributes: ["id": id])
            x.open("personal")
            let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
            x.element("firstname", parts.first ?? name)
            if parts.count > 1 { x.element("lastname", parts[1]) }
            x.close("personal")
            x.close("buddy")
        }
        x.close("diver")

        if !siteIDs.isEmpty {
            x.open("divesite")
            for (site, id) in siteIDs.sorted(by: { $0.value < $1.value }) {
                x.open("site", attributes: ["id": id])
                x.element("name", site.name)
                if let lat = site.latitude, let lon = site.longitude {
                    x.open("geography")
                    x.element("latitude", number(lat))
                    x.element("longitude", number(lon))
                    x.close("geography")
                }
                x.close("site")
            }
            x.close("divesite")
        }

        x.open("profiledata")
        x.open("repetitiongroup", attributes: ["id": "rg1"])
        for (index, dive) in dives.sorted(by: { $0.startDate < $1.startDate }).enumerated() {
            x.open("dive", attributes: ["id": "dive\(index + 1)"])

            x.open("informationbeforedive")
            if let site = dive.site, let id = siteIDs[site] { x.empty("link", attributes: ["ref": id]) }
            for buddy in dive.buddies { if let id = buddyIDs[buddy] { x.empty("link", attributes: ["ref": id]) } }
            x.element("datetime", formatDate(dive.startDate))
            if let number = dive.diveNumber { x.element("divenumber", String(number)) }
            x.close("informationbeforedive")

            for cylinder in dive.cylinders {
                x.open("tankdata")
                if let id = mixIDs[cylinder.gas] { x.empty("link", attributes: ["ref": id]) }
                if let v = cylinder.volumeLiters { x.element("tankvolume", number(v / 1000)) }
                if let p = cylinder.startPressureBar { x.element("tankpressurebegin", number(p * 100_000)) }
                if let p = cylinder.endPressureBar { x.element("tankpressureend", number(p * 100_000)) }
                x.close("tankdata")
            }

            if !dive.samples.isEmpty {
                x.open("samples")
                for (i, sample) in dive.samples.enumerated() {
                    x.open("waypoint")
                    if i == 0 { x.empty("divemode", attributes: ["type": uddfMode(dive.mode)]) }
                    x.element("depth", number(sample.depth))
                    x.element("divetime", number(sample.time))
                    if let t = sample.temperature { x.element("temperature", number(t + 273.15)) }
                    if let p = sample.tankPressure { x.element("tankpressure", number(p * 100_000)) }
                    if let hr = sample.heartRate { x.element("heartrate", number(hr)) }
                    if let ndl = sample.noDecoTime { x.element("nodecotime", number(ndl)) }
                    if let stop = sample.stopDepth, stop > 0 {
                        x.empty("decostop", attributes: ["kind": "mandatory", "decodepth": number(stop), "duration": "0"])
                    }
                    x.close("waypoint")
                }
                x.close("samples")
            }

            x.open("informationafterdive")
            x.element("greatestdepth", number(dive.maxDepth))
            if let avg = dive.averageDepth { x.element("averagedepth", number(avg)) }
            x.element("diveduration", number(dive.duration))
            if let t = dive.minTemperature { x.element("lowesttemperature", number(t + 273.15)) }
            if let notes = dive.notes, !notes.isEmpty {
                x.open("notes")
                for para in notes.components(separatedBy: "\n\n") { x.element("para", para) }
                x.close("notes")
            }
            if let rating = dive.rating {
                x.open("rating")
                x.element("ratingvalue", String(rating * 2))
                x.close("rating")
            }
            x.close("informationafterdive")

            x.close("dive")
        }
        x.close("repetitiongroup")
        x.close("profiledata")
        x.close("uddf")
        return Data(x.output.utf8)
    }

    private static func uddfMode(_ mode: DiveMode) -> String {
        switch mode {
        case .freedive: "apnoe"
        case .closedCircuitRebreather: "closedcircuit"
        case .openCircuit, .gauge: "opencircuit"
        }
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct XMLWriter {
    private(set) var output = ""
    private var depth = 0

    mutating func line(_ text: String) {
        output += String(repeating: "  ", count: depth) + text + "\n"
    }

    mutating func open(_ name: String, attributes: [String: String] = [:]) {
        line("<\(name)\(Self.attributes(attributes))>")
        depth += 1
    }

    mutating func close(_ name: String) {
        depth -= 1
        line("</\(name)>")
    }

    mutating func empty(_ name: String, attributes: [String: String] = [:]) {
        line("<\(name)\(Self.attributes(attributes))/>")
    }

    mutating func element(_ name: String, _ value: String) {
        line("<\(name)>\(Self.escape(value))</\(name)>")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func attributes(_ attributes: [String: String]) -> String {
        attributes.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(escape($0.value))\"" }.joined()
    }
}
