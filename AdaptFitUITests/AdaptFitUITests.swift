import XCTest

/// One end-to-end journey through the app with the mock coach:
/// onboarding → plan week → check-in → workout → adjust → chat →
/// feedback → history → Coach's Notes. Screenshots are attached at
/// every screen (kept always) so CI artifacts show the whole app.
final class AdaptFitUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-mock-llm"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps an element after making sure it's on screen, scrolling a
    /// bounded number of times if needed (Form content can be off-screen).
    private func scrollToAndTap(_ element: XCUIElement, attempts: Int = 6) {
        var remaining = attempts
        while !(element.exists && element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
        XCTAssertTrue(element.exists, "Expected \(element) to exist after scrolling")
        if element.isHittable {
            element.tap()
        } else {
            // Coordinate tap works even when hit-testing says otherwise
            // (e.g. row partly under a bar).
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func testFullJourney() throws {
        // MARK: Onboarding
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Onboarding should show first")
        snap("01-onboarding-blank")

        nameField.tap()
        nameField.typeText("Asha\n")

        scrollToAndTap(app.buttons["Start training"])

        // MARK: Today (empty state, no plan yet)
        // Milestone: the tab bar — section header text is unreliable
        // (Forms render headers uppercased).
        let planTab = app.tabBars.buttons["Plan"]
        if !planTab.waitForExistence(timeout: 5), app.buttons["Start training"].exists {
            // Retry once in case the first tap landed before the form settled.
            scrollToAndTap(app.buttons["Start training"])
        }
        XCTAssertTrue(planTab.waitForExistence(timeout: 10), "Tab bar should appear after onboarding")
        snap("02-today-checkin-noplan")

        // MARK: Plan the week
        app.tabBars.buttons["Plan"].tap()
        snap("03-plan-empty")

        app.buttons["Plan my week"].tap()
        let firstSession = app.staticTexts["Lower-body strength"]
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "Planned sessions should appear")
        snap("04-plan-week")

        // MARK: Generate today's workout from the block
        app.tabBars.buttons["Today"].tap()
        scrollToAndTap(app.buttons["Create today's workout"])

        let workoutTitle = app.staticTexts["Steady Strength"]
        XCTAssertTrue(workoutTitle.waitForExistence(timeout: 20), "Generated workout should appear")
        snap("05-todays-workout")

        // MARK: Adjust one exercise
        let squat = app.staticTexts["Goblet Squat"]
        if squat.waitForExistence(timeout: 5) {
            squat.tap()
            let saveAdjust = app.buttons["Save"]
            if saveAdjust.waitForExistence(timeout: 5) {
                snap("06-adjust-exercise")
                saveAdjust.tap()
            }
        }

        // MARK: Chat with the coach
        let chatButton = app.buttons["Chat with coach"]
        if chatButton.waitForExistence(timeout: 5) {
            chatButton.tap()
            let input = app.descendants(matching: .any)["chatInput"].firstMatch
            if input.waitForExistence(timeout: 5) {
                input.tap()
                input.typeText("My wrists hurt, can you swap the push-ups?")
                app.descendants(matching: .any)["chatSend"].firstMatch.tap()
                _ = app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS %@", "band rows")
                ).firstMatch.waitForExistence(timeout: 20)
                snap("07-chat-edit")
            }
            app.buttons["Done"].tap()
        }

        // MARK: Complete + feedback
        scrollToAndTap(app.buttons["I'm done — log how it felt"])
        let feedbackTitle = app.navigationBars["Nice work!"]
        XCTAssertTrue(feedbackTitle.waitForExistence(timeout: 10), "Feedback sheet should appear")
        snap("08-feedback")
        scrollToAndTap(app.buttons["Save"])

        let completed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Completed")
        ).firstMatch
        _ = completed.waitForExistence(timeout: 10)
        snap("09-workout-completed")

        // MARK: History
        app.tabBars.buttons["History"].tap()
        snap("10-history")

        // MARK: Settings and Coach's Notes
        app.tabBars.buttons["Settings"].tap()
        snap("11-settings")

        app.buttons["Coach's Notes"].tap()
        let rebuildButton = app.buttons["Rebuild from history"]
        XCTAssertTrue(rebuildButton.waitForExistence(timeout: 10), "Coach's Notes should open")
        // Give the background scribe a moment to update pages.
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Coach's Log")
        ).firstMatch.waitForExistence(timeout: 10)
        snap("12-coach-notes")

        app.staticTexts["Coach's Log"].firstMatch.tap()
        snap("13-coach-log-page")
    }
}
