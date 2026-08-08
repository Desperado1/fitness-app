import XCTest

/// One end-to-end journey through the app with the mock coach:
/// onboarding → plan week → check-in → workout → adjust → chat →
/// feedback → history → Coach's Notes. Screenshots are attached at
/// every screen (kept always) so CI artifacts show the whole app.
final class FlowFitUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-mock-llm", "-mock-voice"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Prints the accessibility tree with a marker the CI log filter keeps,
    /// so failures are diagnosable straight from the job log.
    private func dumpTree(_ tag: String) {
        for line in app.debugDescription.components(separatedBy: "\n") {
            print("AXTREE[\(tag)] \(line)")
        }
    }

    /// Switches tabs via a coordinate tap. Plain .tap() on tab buttons can
    /// fail with kAXErrorCannotComplete right after a sheet dismissal;
    /// coordinate taps skip the AX scroll-to-visible machinery.
    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab \(name) should exist")
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Taps a segment of a PillToggle by coordinate. Same reason as tabs:
    /// right after a sheet dismissal, plain .tap() can fail in the AX
    /// scroll-to-visible machinery.
    private func tapPill(_ label: String) {
        let pill = app.buttons["pill-\(label)"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Pill \(label) should exist")
        pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Taps an element after making sure it's on screen, scrolling a
    /// bounded number of times if needed (Form content can be off-screen).
    private func scrollToAndTap(_ element: XCUIElement, attempts: Int = 10) {
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
        tapTab("Plan")
        snap("03-plan-empty")

        scrollToAndTap(app.buttons["Plan my week"])
        let firstSession = app.staticTexts["Lower-body strength"]
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "Planned sessions should appear")
        snap("04-plan-week")

        // MARK: The check-in landing page is the orb
        tapTab("Today")
        let orb = app.descendants(matching: .any)["voiceOrb"].firstMatch
        XCTAssertTrue(orb.waitForExistence(timeout: 15), "Voice is the default way in")
        snap("04b-voice-landing")

        // MARK: Form mode — the same check-in, tapped instead of spoken
        tapPill("Form")
        XCTAssertTrue(
            orb.waitForNonExistence(timeout: 10),
            "The toggle should swap the orb out for the form"
        )
        snap("04c-form-mode")

        // The typed conversation, still reachable from form mode.
        scrollToAndTap(app.buttons["startIntake"])
        let intakeInput = app.descendants(matching: .any)["intakeInput"].firstMatch
        XCTAssertTrue(intakeInput.waitForExistence(timeout: 15), "Check-in conversation should open")
        // The greeting is written on-device, so it's there immediately rather
        // than after a round-trip.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "How are you feeling"))
                .firstMatch.waitForExistence(timeout: 10),
            "The coach should open the conversation itself"
        )
        snap("04d-checkin-conversation")
        app.buttons["intakeAdjustByHand"].firstMatch.tap()

        // MARK: Hands-free voice mode
        // -mock-voice swaps in scripted speech, so CI drives the whole loop:
        // the coach speaks, "hears" an answer, and moves on with no taps.
        // Switching back must not lose the conversation started in form mode.
        tapPill("Voice")
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "The orb should come back")
        let startTalking = app.buttons["voiceStartStop"].firstMatch
        XCTAssertTrue(startTalking.waitForExistence(timeout: 10))
        startTalking.tap()
        snap("04e-voice-mode")

        // The soreness chip only renders once that field is actually known,
        // so its appearance proves spoken words reached the check-in.
        XCTAssertTrue(
            app.descendants(matching: .any)["intakeChip-soreness"].firstMatch.waitForExistence(timeout: 30),
            "Chips should fill in from what the coach heard"
        )
        snap("04f-voice-chips-filled")

        // The next scripted utterance completes the check-in; voice mode then
        // builds the workout itself rather than asking for a tap.

        let workoutTitle = app.staticTexts["Steady Strength"]
        XCTAssertTrue(workoutTitle.waitForExistence(timeout: 20), "Generated workout should appear")
        snap("05-todays-workout")

        // MARK: Adjust one exercise (exercise rows are tappable cards)
        let squat = app.staticTexts["Goblet Squat"]
        if squat.waitForExistence(timeout: 5) {
            scrollToAndTap(squat)
            let saveAdjust = app.navigationBars.buttons["Save"].firstMatch
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

        // MARK: Regenerate — one-tap "try a different workout"
        let regenerate = app.buttons["regenerateWorkout"]
        if regenerate.waitForExistence(timeout: 5) {
            scrollToAndTap(regenerate)
            // If changes were logged a confirmation appears; otherwise it
            // regenerates directly. Handle both.
            let confirm = app.buttons["Get a different workout"]
            if confirm.waitForExistence(timeout: 3) {
                confirm.tap()
            }
            let alternativeTitle = app.staticTexts["Gentle Mobility Flow"]
            XCTAssertTrue(alternativeTitle.waitForExistence(timeout: 20), "Regenerated alternative workout should appear")
            snap("07b-regenerated-workout")
        }

        // MARK: Complete + feedback
        scrollToAndTap(app.buttons["I'm done — log how it felt"])
        let feedbackBar = app.navigationBars["Nice work!"]
        XCTAssertTrue(feedbackBar.waitForExistence(timeout: 10), "Feedback sheet should appear")
        snap("08-feedback")
        feedbackBar.buttons["Save"].tap()

        // The sheet must actually dismiss before the tab bar is tappable —
        // taps on it are otherwise swallowed by the sheet overlay.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: feedbackBar, handler: nil)
        waitForExpectations(timeout: 10)

        let completed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Completed")
        ).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 10), "Workout should show as completed")
        snap("09-workout-completed")

        // MARK: History
        tapTab("History")
        snap("10-history")

        // MARK: Settings and Coach's Notes
        tapTab("Settings")
        snap("11-settings")

        // NavigationLink rows aren't always exposed as buttons — try the
        // label's static text, then any element type, then dump the tree.
        var notesRow = app.staticTexts["Coach's Notes"].firstMatch
        if !notesRow.waitForExistence(timeout: 5) {
            notesRow = app.descendants(matching: .any)["Coach's Notes"].firstMatch
        }
        if !notesRow.waitForExistence(timeout: 5) {
            dumpTree("settings")
            XCTFail("Coach's Notes row not found in Settings — see AXTREE dump in log")
        }
        notesRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let rebuildButton = app.buttons["Rebuild from history"]
        XCTAssertTrue(rebuildButton.waitForExistence(timeout: 10), "Coach's Notes should open")
        // Give the background scribe a moment to update pages.
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Coach's Log")
        ).firstMatch.waitForExistence(timeout: 10)
        snap("12-coach-notes")

        let logRow = app.staticTexts["Coach's Log"].firstMatch
        if logRow.waitForExistence(timeout: 5) {
            logRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        snap("13-coach-log-page")
    }
}
