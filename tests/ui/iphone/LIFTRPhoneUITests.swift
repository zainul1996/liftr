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
  private func capture(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
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
    capture("Synthetic recording detail", app: app)
    let samples = app.descendants(matching: .any).matching(identifier: "quality.samples").firstMatch
    reveal(samples, app: app)
    XCTAssertEqual(samples.value as? String, "101")
    capture("Synthetic recording quality", app: app)
    let review = app.buttons["recording.review"]
    reveal(review, app: app)
    review.tap()
    app.buttons["review.exercise"].tap()
    app.buttons["Dumbbell Bicep Curl"].tap()
    replace(app.textFields["review.reps"], with: "12")
    replace(app.textFields["review.weight"], with: "17.5")
    app.buttons["review.save"].tap()
    capture("Saved synthetic review", app: app)
    app.terminate()
    app = launch(reset: false)
    openFixture(app)
    XCTAssertTrue(app.staticTexts["Dumbbell Bicep Curl"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["12"].firstMatch.exists)
    let export = app.buttons["recording.export"]
    reveal(export, app: app)
    export.tap()
    XCTAssertTrue(
      app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
  }
  func testDeleteCancellationKeepsRecordingThenDeleteRemovesIt() {
    let app = launch()
    openFixture(app)
    let delete = app.buttons["recording.delete"]
    reveal(delete, app: app)
    delete.tap()
    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.85)).tap()
    XCTAssertTrue(app.buttons["recording.delete"].exists)
    delete.tap()
    app.buttons["recording.confirmDelete"].firstMatch.tap()
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

  func testReviewedExportCacheIsDeletedWithLocalRecording() {
    let app = launch()
    openFixture(app)
    let review = app.buttons["recording.review"]
    reveal(review, app: app)
    review.tap()
    replace(app.textFields["review.reps"], with: "12")
    app.buttons["review.save"].tap()
    let export = app.buttons["recording.export"]
    reveal(export, app: app)
    export.tap()
    XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
    app.buttons["header.closeButton"].tap()
    let delete = app.buttons["recording.delete"]
    reveal(delete, app: app)
    delete.tap()
    app.buttons["recording.confirmDelete"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Ready for your first set"].waitForExistence(timeout: 5))
    capture("Reviewed export deleted locally", app: app)
  }
  func testReviewCleanupFailureReportsPartialSuccessWithoutStaleRow() {
    let app = launch(extra: ["LIFTR_UI_TEST_REVIEW_FAILURE": "1"])
    if app.alerts.firstMatch.waitForExistence(timeout: 3) { app.alerts.buttons["OK"].tap() }
    openFixture(app)
    let delete = app.buttons["recording.delete"]
    reveal(delete, app: app)
    delete.tap()
    app.buttons["recording.confirmDelete"].firstMatch.tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(
      app.staticTexts["Ready for your first set"].waitForExistence(timeout: 5), app.debugDescription
    )
  }
}
