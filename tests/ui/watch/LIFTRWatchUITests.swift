import XCTest

@MainActor
final class LIFTRWatchUITests: XCTestCase {
  func testHomeAndExerciseSelection() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--liftr-ui-testing"]
    app.launchEnvironment = ["LIFTR_UI_TESTING": "1", "LIFTR_UI_TEST_RESET": "1"]
    app.launch()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["watch.exercise"].tap()
    let curl = app.buttons["Dumbbell Bicep Curl"]
    for _ in 0..<5 {
      if curl.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(curl.exists, app.debugDescription)
    curl.tap()
    XCTAssertTrue(app.buttons["watch.start"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Dumbbell Bicep Curl"].exists)
  }
}
