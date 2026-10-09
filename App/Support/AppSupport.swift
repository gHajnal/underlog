import SwiftUI
import UniformTypeIdentifiers
import UnderlogCore

/// Keys for settings stored with @AppStorage.
enum SettingsKey {
    static let unitSystem = "unitSystem"
    static let defaultWaterType = "defaultWaterType"
    static let maxPPO2 = "maxPPO2"
}

extension UTType {
    static let fitActivity = UTType(importedAs: "com.garmin.fit", conformingTo: .data)
    static let uddf = UTType(importedAs: "org.streit.uddf", conformingTo: .xml)
}

/// Accessibility identifiers shared by the screens and the UI tests.
enum A11yID {
    static let diveList = "diveList"
    static let addMenu = "addMenu"
    static let addDiveButton = "addDiveButton"
    static let importButton = "importButton"
    static let emptyState = "emptyState"
    static let diveRowPrefix = "diveRow-"

    static let editorSave = "editorSave"
    static let editorCancel = "editorCancel"
    static let editorSite = "editorSite"
    static let editorMaxDepth = "editorMaxDepth"
    static let editorDuration = "editorDuration"
    static let editorValidation = "editorValidation"

    static let detailEdit = "detailEdit"
    static let detailMaxDepth = "detailMaxDepth"
    static let profileChart = "profileChart"

    static let toolsDepth = "toolsDepth"
    static let toolsMOD = "toolsMOD"
}

enum Theme {
    /// Depth tint: lighter near the surface, deeper blue lower down.
    static let surfaceWater = Color(red: 0.36, green: 0.72, blue: 0.85)
    static let deepWater = Color(red: 0.05, green: 0.27, blue: 0.52)
}

extension Double {
    /// Rounds for display in editors, so converted values do not show long fractions.
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
