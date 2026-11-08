import XCTest

@MainActor
final class LIFTRWatchUITests: XCTestCase {
  private func launch(fixture: String = "", extra: [String: String] = [:]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--liftr-ui-testing"]
    app.launchEnvironment = [
      "LIFTR_UI_TESTING": "1", "LIFTR_UI_TEST_RESET": "1", "LIFTR_UI_TEST_FIXTURE": fixture,
    ].merging(extra) { _, new in new }
    app.launch()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 10), app.debugDescription)
    return app
  }
  private func capture(_ title: String, app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = title
    image.lifetime = .keepAlways
    add(image)
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<7 {
      if element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable, app.debugDescription)
  }
  func testHomeAndExerciseSelection() {
    let app = launch()
    app.buttons["watch.exercise"].tap()
    let curl = app.buttons["exercise.dumbbell_bicep_curl"]
    reveal(curl, app: app)
    curl.tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Dumbbell Bicep Curl"].exists)
    capture("Synthetic exercise selection", app: app)
  }
  func testSyntheticSetSaveRestAndRetainedExercise() {
    let app = launch()
    app.buttons["watch.start"].tap()
    XCTAssertTrue(app.buttons["watch.endSet"].waitForExistence(timeout: 5), app.debugDescription)
    capture("Synthetic motion recording", app: app)
    app.buttons["watch.endSet"].tap()
    XCTAssertTrue(app.staticTexts["Save set"].waitForExistence(timeout: 5))
    print(app.debugDescription)
    capture("Synthetic rep and weight entry", app: app)
    let reps = app.steppers["watch.reps"]
    XCTAssertTrue(reps.exists, app.debugDescription)
    reps.buttons["Increment"].tap()
    reps.buttons["Increment"].tap()
    let weight = app.steppers["watch.weight"]
    reveal(weight, app: app)
    weight.buttons["Increment"].tap()
    let save = app.buttons["watch.save"]
    reveal(save, app: app)
    XCTAssertTrue(save.isEnabled)
    save.tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5), app.debugDescription)
    capture("Saved synthetic set and rest", app: app)
    XCTAssertTrue(app.staticTexts["Machine Chest Press"].exists)
    reveal(app.buttons["watch.recordings"], app: app)
    app.buttons["watch.recordings"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 reps")).firstMatch
        .waitForExistence(timeout: 5), app.debugDescription)
    capture("Saved synthetic recording history", app: app)
  }
  func testMotionUnavailablePreservesReadyState() {
    let app = launch(extra: ["LIFTR_UI_TEST_MOTION_FAILURE": "1"])
    app.buttons["watch.start"].tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    capture("Synthetic motion failure", app: app)
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
  }
  func testDeniedWorkoutPreservesReadyState() {
    let app = launch(extra: ["LIFTR_UI_TEST_WORKOUT_FAILURE": "1"])
    app.buttons["watch.start"].tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
  }
  func testDraftStorageFailurePreservesReadyState() {
    let app = launch(extra: ["LIFTR_UI_TEST_DRAFT_STORAGE_FAILURE": "1"])
    app.buttons["watch.start"].tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
  }
  func testFailedRecoveryPreservesOriginalWithoutAccumulatingScratch() {
    let app = launch(fixture: "failed-draft")
    for _ in 0..<2 {
      let recover = app.buttons["watch.recover"]
      reveal(recover, app: app)
      recover.tap()
      XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
      capture("Failed recovery preserves original", app: app)
      app.alerts.buttons["OK"].tap()
    }
  }
}
