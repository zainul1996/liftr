import XCTest

@MainActor
final class LIFTRPhoneUITests: XCTestCase {
  private let fixtureID = "88888888-8888-4888-8888-888888888888"
  private func launch(reset: Bool = true, fixture: String = "set", extra: [String: String] = [:])
    -> XCUIApplication
  {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--liftr-ui-testing"]
    app.launchEnvironment = [
      "LIFTR_UI_TESTING": "1", "LIFTR_UI_TEST_RESET": reset ? "1" : "0",
      "LIFTR_UI_TEST_FIXTURE": fixture,
    ].merging(extra) { _, new in new }
    app.launch()
    return app
  }
  private func openFixture(_ app: XCUIApplication) {
    let row = app.buttons["recording.row." + fixtureID]
    XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
    row.tap()
    XCTAssertTrue(app.staticTexts["Motion preview"].waitForExistence(timeout: 5))
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<7 {
      if element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable, app.debugDescription)
  }
  private func replace(_ field: XCUIElement, with text: String) {
    field.tap()
    let existing = field.value as? String ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    field.typeText(text)
  }
  func testReviewPersistsAndExportsActualReviewedFile() {
    var app = launch()
    openFixture(app)
    let review = app.buttons["recording.review"]
    reveal(review, app: app)
    review.tap()
    app.buttons["review.exercise"].tap()
    app.buttons["Dumbbell Bicep Curl"].tap()
    replace(app.textFields["review.reps"], with: "12")
    replace(app.textFields["review.weight"], with: "17.5")
    app.buttons["review.save"].tap()
    app.terminate()
    app = launch(reset: false)
    openFixture(app)
    XCTAssertTrue(app.staticTexts["Dumbbell Bicep Curl"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["12"].firstMatch.exists)
    let export = app.buttons["recording.export"]
    reveal(export, app: app)
    export.tap()
    XCTAssertTrue(
      app.otherElements["recording.shareSheet"].waitForExistence(timeout: 5)
        || app.buttons["Copy"].waitForExistence(timeout: 3), app.debugDescription)
  }
  func testDeleteCancellationKeepsRecordingThenDeleteRemovesIt() {
    let app = launch()
    openFixture(app)
    let delete = app.buttons["recording.delete"]
    reveal(delete, app: app)
    delete.tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["recording.delete"].exists)
    delete.tap()
    app.buttons["Delete from iPhone"].lastMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Ready for your first set"].waitForExistence(timeout: 5), app.debugDescription
    )
  }
  func testCorruptRecordingDoesNotHideHealthyRecording() {
    let app = launch(fixture: "corrupt")
    XCTAssertTrue(app.buttons["recording.row." + fixtureID].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "need recovery"))
        .firstMatch.exists, app.debugDescription)
  }
  func testExportStorageFailurePreservesOriginalRecording() {
    let app = launch(extra: ["LIFTR_UI_TEST_EXPORT_FAILURE": "1"])
    openFixture(app)
    let export = app.buttons["recording.export"]
    reveal(export, app: app)
    export.tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["recording.delete"].exists)
  }
}
