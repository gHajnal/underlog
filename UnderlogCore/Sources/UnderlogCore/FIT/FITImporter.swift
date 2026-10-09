import Foundation

/// Turns Garmin FIT activity files (for example from a Descent dive computer) into dives.
public enum FITImporter {
    public enum ImportError: Error, Equatable {
        /// The file decoded but contains no dive: no depth samples and no dive summary.
        case noDiveData
    }

    /// Global message numbers from the FIT profile.
    enum Message {
        static let fileID: UInt16 = 0
        static let sport: UInt16 = 12
        static let session: UInt16 = 18
        static let record: UInt16 = 20
        static let deviceInfo: UInt16 = 23
        static let diveGas: UInt16 = 259
        static let diveSummary: UInt16 = 268
        static let tankUpdate: UInt16 = 319
        static let tankSummary: UInt16 = 323
    }

    enum Sport {
        static let diving: Double = 53
    }

    enum SubSport {
        static let singleGas: Double = 53
        static let multiGas: Double = 54
        static let gauge: Double = 55
        static let apnea: Double = 56
        static let apneaHunting: Double = 57
        static let ccr: Double = 63
    }

    public static func importDives(from data: Data) throws -> [ImportedDive] {
        let messages = try FITDecoder.decode(data)
        return try dives(from: messages)
    }

    static func dives(from messages: [FITMessage]) throws -> [ImportedDive] {
        let records = messages.filter { $0.globalNumber == Message.record && $0.value(253) != nil }
        let summaries = messages.filter { $0.globalNumber == Message.diveSummary }
        // A file can hold summaries for laps as well as sessions. Field 0 (reference_mesg) says which
        // kind a summary describes and field 1 (reference_index) which one, so match by reference.
        let sessionSummaries = summaries.filter { $0.value(0) == Double(Message.session) }
        let sessions = messages.filter { $0.globalNumber == Message.session }

        let hasDepth = records.contains { $0.value(92) != nil }
        guard hasDepth || !summaries.isEmpty else { throw ImportError.noDiveData }

        let deviceName = messages.first { $0.globalNumber == Message.fileID }?.strings[8]
            ?? messages.first { $0.globalNumber == Message.deviceInfo }?.strings[27]

        let gases: [GasMix] = messages
            .filter { $0.globalNumber == Message.diveGas && ($0.value(2) ?? 1) != 0 } // status 0 = disabled
            .sorted { ($0.value(254) ?? 0) < ($1.value(254) ?? 0) }
            .compactMap { message in
                guard let o2 = message.value(1) else { return nil }
                let mix = GasMix(oxygen: o2 / 100, helium: (message.value(0) ?? 0) / 100)
                return mix.isValid ? mix : nil
            }

        let tankPressures: [(time: Double, bar: Double)] = messages
            .filter { $0.globalNumber == Message.tankUpdate }
            .compactMap { message in
                guard let t = message.value(253), let p = message.value(1) else { return nil }
                return (t, p / 100)
            }
            .sorted { $0.time < $1.time }

        let tankSummary = messages.first { $0.globalNumber == Message.tankSummary }

        // One dive per session window when sessions are present, otherwise the whole file is one dive.
        let windows: [(start: Double, end: Double, session: FITMessage?, sessionIndex: Int?)]
        let sessionWindows = sessions.enumerated().compactMap { position, session -> (start: Double, end: Double, session: FITMessage?, sessionIndex: Int?)? in
            guard let start = session.value(2) ?? session.value(253) else { return nil }
            let elapsed = (session.value(7) ?? 0) / 1000
            // A session's own message_index (field 254) is what summaries refer to; fall back to its position.
            let sessionIndex = session.value(254).flatMap { Int(exactly: $0) } ?? position
            return (start: start, end: elapsed > 0 ? start + elapsed : .infinity, session: session, sessionIndex: sessionIndex)
        }
        if !sessionWindows.isEmpty {
            windows = sessionWindows.sorted { $0.start < $1.start }
        } else {
            let first = records.compactMap { $0.value(253) }.min() ?? 0
            windows = [(first, .infinity, nil, nil)]
        }

        var dives: [ImportedDive] = []
        for (index, window) in windows.enumerated() {
            let windowRecords = records.filter {
                guard let t = $0.value(253) else { return false }
                return t >= window.start && t <= window.end
            }
            let summary: FITMessage?
            if !sessionSummaries.isEmpty {
                summary = window.sessionIndex.flatMap { sessionIndex in
                    sessionSummaries.first { $0.value(1) == Double(sessionIndex) }
                } ?? (sessionSummaries.count == 1 ? sessionSummaries[0] : nil)
            } else {
                summary = summaries.indices.contains(index) ? summaries[index] : summaries.last
            }
            let start = window.start

            let samples: [DiveSample] = windowRecords.compactMap { record in
                guard let t = record.value(253), let depthMm = record.value(92) else { return nil }
                var sample = DiveSample(time: t - start, depth: depthMm / 1000)
                sample.temperature = record.value(13)
                sample.heartRate = record.value(3)
                sample.noDecoTime = record.value(96)
                sample.stopDepth = record.value(93).map { $0 / 1000 }
                sample.tankPressure = pressure(at: t, in: tankPressures)
                return sample
            }

            let profile = DiveProfile(samples: samples)
            let session = window.session
            let mode = diveMode(subSport: session?.value(6) ?? messages.first { $0.globalNumber == Message.sport }?.value(1))

            let duration = (summary?.value(11)).map { $0 / 1000 }
                ?? (session?.value(7)).map { $0 / 1000 }
                ?? profile.duration

            var cylinders = gases.map { ImportedCylinder(gas: $0) }
            if cylinders.isEmpty, mode != .freedive { cylinders = [ImportedCylinder(gas: .air)] }
            if let tankSummary, !cylinders.isEmpty {
                cylinders[0].startPressureBar = tankSummary.value(1).map { $0 / 100 }
                cylinders[0].endPressureBar = tankSummary.value(2).map { $0 / 100 }
            }

            var site: ImportedSite?
            if let lat = session?.value(3), let lon = session?.value(4) {
                site = ImportedSite(name: "", latitude: semicirclesToDegrees(lat), longitude: semicirclesToDegrees(lon))
            }

            var dive = ImportedDive(
                startDate: FITDecoder.epoch.addingTimeInterval(start),
                duration: duration,
                maxDepth: (summary?.value(3)).map { $0 / 1000 } ?? profile.maxDepth,
                averageDepth: (summary?.value(2)).map { $0 / 1000 },
                minTemperature: profile.minTemperature,
                diveNumber: (summary?.value(10)).flatMap { Int(exactly: $0.rounded()) },
                mode: mode,
                cylinders: cylinders,
                samples: profile.samples,
                site: site,
                deviceName: deviceName
            )
            dive.deriveMissingValuesFromProfile()
            if dive.maxDepth > 0 || !dive.samples.isEmpty {
                dives.append(dive)
            }
        }
        guard !dives.isEmpty else { throw ImportError.noDiveData }
        return dives
    }

    static func diveMode(subSport: Double?) -> DiveMode {
        guard let subSport else { return .openCircuit }
        return switch subSport {
        case SubSport.gauge: .gauge
        case SubSport.apnea, SubSport.apneaHunting: .freedive
        case SubSport.ccr: .closedCircuitRebreather
        default: .openCircuit
        }
    }

    static func semicirclesToDegrees(_ value: Double) -> Double {
        value * 180 / 2_147_483_648
    }

    /// The most recent tank pressure reading at or before a time.
    static func pressure(at time: Double, in readings: [(time: Double, bar: Double)]) -> Double? {
        guard !readings.isEmpty else { return nil }
        var low = 0, high = readings.count - 1, match: Int?
        while low <= high {
            let mid = (low + high) / 2
            if readings[mid].time <= time {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let match, time - readings[match].time <= 30 else { return nil }
        return readings[match].bar
    }
}
