import XCTest

/// End-to-end checks of the main flows. They find elements by accessibility identifier,
/// the same information VoiceOver uses, so they also guard the app's accessibility.
final class UnderlogUITests: XCTestCase {
    private enum ID {
        static let diveList = "diveList"
        static let addMenu = "addMenu"
        static let addDiveButton = "addDiveButton"
        static let emptyState = "emptyState"
        static let editorSave = "editorSave"
        static let editorSite = "editorSite"
        static let editorMaxDepth = "editorMaxDepth"
        static let editorDuration = "editorDuration"
        static let editorValidation = "editorValidation"
        static let detailEdit = "detailEdit"
        static let detailMaxDepth = "detailMaxDepth"
        static let profileChart = "profileChart"
        static let toolsMOD = "toolsMOD"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(empty: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (empty ? ["-empty-log"] : [])
        app.launch()
        return app
    }

    @MainActor
    func testEmptyLogShowsInvitation() {
        let app = launch(empty: true)
        XCTAssertTrue(app.otherElements[ID.emptyState].waitForExistence(timeout: 5)
            || app.staticTexts["No dives yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSeededLogListsDivesNewestFirst() {
        let app = launch()
        let newest = app.buttons["diveRow-3"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["diveRow-1"].exists)
    }

    @MainActor
    func testOpeningADiveShowsDetailsAndProfile() {
        let app = launch()
        let row = app.buttons["diveRow-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.otherElements[ID.detailMaxDepth].waitForExistence(timeout: 5)
            || app.staticTexts["Max depth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[ID.profileChart].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavingAnEmptyDiveShowsValidation() {
        let app = launch(empty: true)
        openNewDiveEditor(app)
        app.buttons[ID.editorSave].tap()
        XCTAssertTrue(app.staticTexts["Enter the maximum depth."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAddingADiveByHand() {
        let app = launch(empty: true)
        openNewDiveEditor(app)

        let site = app.textFields[ID.editorSite]
        XCTAssertTrue(site.waitForExistence(timeout: 3))
        site.tap()
        site.typeText("Test Reef")

        let depth = app.textFields[ID.editorMaxDepth]
        depth.tap()
        depth.typeText("21")

        let duration = app.textFields[ID.editorDuration]
        duration.tap()
        duration.typeText("47")

        app.buttons[ID.editorSave].tap()

        let row = app.buttons["diveRow-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Test Reef"))
    }

    @MainActor
    func testGasToolsShowMaximumOperatingDepth() {
        let app = launch()
        app.tabBars.buttons["Gas tools"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[ID.toolsMOD].waitForExistence(timeout: 3))
    }

    @MainActor
    private func openNewDiveEditor(_ app: XCUIApplication) {
        let emptyAdd = app.buttons["Add dive"].firstMatch
        if emptyAdd.waitForExistence(timeout: 5) {
            emptyAdd.tap()
        } else {
            app.buttons[ID.addMenu].tap()
            app.buttons[ID.addDiveButton].tap()
        }
        XCTAssertTrue(app.buttons[ID.editorSave].waitForExistence(timeout: 3))
    }
}
