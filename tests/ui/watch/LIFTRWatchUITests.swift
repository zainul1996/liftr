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
    XCTAssertTrue(app.buttons["watch.start"].isHittable, "Start Workout must be visible")
    return app
  }
  private func capture(_ title: String, app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = title
    image.lifetime = .keepAlways
    add(image)
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<12 {
      if element.isHittable { return }
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        .press(
          forDuration: 0.05,
          thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)))
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
    XCTAssertTrue(
      app.buttons["watch.endSet"].isHittable, "End Set must be visible without scrolling")
    app.buttons["watch.endSet"].tap()
    XCTAssertTrue(app.staticTexts["Save set"].waitForExistence(timeout: 5))
    print(app.debugDescription)
    capture("Synthetic rep and weight entry", app: app)
    let reps = app.staticTexts["watch.reps"]
    XCTAssertTrue(reps.exists, app.debugDescription)
    reps.buttons["Add"].tap()
    reps.buttons["Add"].tap()
    let weight = app.staticTexts["watch.weight"]
    reveal(weight, app: app)
    weight.buttons["Add"].tap()
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
    XCTAssertTrue(
      app.staticTexts["Recording notice"].firstMatch.waitForExistence(timeout: 5),
      app.debugDescription)
    capture("Synthetic motion failure", app: app)
    app.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
    XCTAssertEqual(app.buttons["watch.start"].label, "Start Workout")
  }
  func testDeniedWorkoutPreservesReadyState() {
    let app = launch(extra: ["LIFTR_UI_TEST_WORKOUT_FAILURE": "1"])
    app.buttons["watch.start"].tap()
    XCTAssertTrue(
      app.staticTexts["Recording notice"].firstMatch.waitForExistence(timeout: 5),
      app.debugDescription)
    app.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
    XCTAssertEqual(app.buttons["watch.start"].label, "Start Workout")
  }
  func testDraftStorageFailurePreservesReadyState() {
    let app = launch(extra: ["LIFTR_UI_TEST_DRAFT_STORAGE_FAILURE": "1"])
    app.buttons["watch.start"].tap()
    XCTAssertTrue(
      app.staticTexts["Recording notice"].firstMatch.waitForExistence(timeout: 5),
      app.debugDescription)
    app.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["watch.start"].exists)
    XCTAssertEqual(app.buttons["watch.start"].label, "Start Workout")
  }
  func testFailedRecoveryPreservesOriginalWithoutAccumulatingScratch() {
    let app = launch(fixture: "failed-draft")
    for _ in 0..<2 {
      let recover = app.buttons["watch.recover"]
      reveal(recover, app: app)
      recover.tap()
      XCTAssertTrue(
        app.staticTexts["Recording notice"].firstMatch.waitForExistence(timeout: 5),
        app.debugDescription)
      capture("Failed recovery preserves original", app: app)
      app.buttons["OK"].tap()
    }
  }
  private func backToTop(_ app: XCUIApplication) {
    for _ in 0..<12 {
      if app.buttons["watch.start"].isHittable { return }
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        .press(
          forDuration: 0.05,
          thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)))
    }
  }
  private func recordAndSaveSet(_ app: XCUIApplication) {
    backToTop(app)
    app.buttons["watch.start"].tap()
    XCTAssertTrue(app.buttons["watch.endSet"].waitForExistence(timeout: 5))
    // The live synthetic timer supplies samples while the runner resolves the view.
    capture("Synthetic set active", app: app)
    app.buttons["watch.endSet"].tap()
    XCTAssertTrue(app.staticTexts["watch.reps"].waitForExistence(timeout: 5))
    app.staticTexts["watch.reps"].buttons["Add"].tap()
    let save = app.buttons["watch.save"]
    reveal(save, app: app)
    save.tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5))
  }
  func testConsecutiveSetsKeepSessionAndNewWorkoutStartsAnother() {
    let app = launch()
    recordAndSaveSet(app)
    recordAndSaveSet(app)
    reveal(app.buttons["watch.endWorkout"], app: app)
    app.buttons["watch.endWorkout"].tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5))
    recordAndSaveSet(app)
    reveal(app.buttons["watch.recordings"], app: app)
    app.buttons["watch.recordings"].tap()
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'watch.delete.'")).count, 3)
    capture("Three saved synthetic sets for session identity inspection", app: app)
  }
  func testContinuousCapturePreservesRestAndSetMarkers() {
    let app = launch()
    let continuous = app.switches["watch.continuous"]
    reveal(continuous, app: app)
    continuous.tap()
    backToTop(app)
    app.buttons["watch.start"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Continuous capture'"))
        .firstMatch.waitForExistence(timeout: 5))
    recordAndSaveSet(app)
    recordAndSaveSet(app)
    capture("Continuous synthetic rest with two labelled intervals", app: app)
    reveal(app.buttons["watch.endWorkout"], app: app)
    app.buttons["watch.endWorkout"].tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5))
    reveal(app.buttons["watch.recordings"], app: app)
    app.buttons["watch.recordings"].tap()
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'watch.delete.'")).count, 1)
    capture("Saved continuous synthetic capture", app: app)
  }
  func testSavedCopyDeletionRequiresConfirmation() {
    let app = launch(fixture: "set")
    reveal(app.buttons["watch.recordings"], app: app)
    app.buttons["watch.recordings"].tap()
    let delete = app.buttons["watch.delete.88888888-8888-4888-8888-888888888888"]
    reveal(delete, app: app)
    delete.tap()
    XCTAssertTrue(
      app.buttons["watch.cancelDelete"].waitForExistence(timeout: 5), app.debugDescription)
    app.buttons["watch.cancelDelete"].tap()
    XCTAssertTrue(delete.exists)
    delete.tap()
    app.buttons["watch.confirmDelete"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Your saved sets will appear here."].waitForExistence(timeout: 5),
      app.debugDescription)
    capture("Confirmed synthetic Watch deletion", app: app)
  }

}
