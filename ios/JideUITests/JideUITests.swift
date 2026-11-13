import XCTest

/// Runs against an isolated store/settings/recordings (launch argument -uitest), so the owner's data is untouched.
final class JideUITests: XCTestCase {
    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        // System permission prompts (microphone, notifications): allow them.
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30), "App did not finish first-run seeding")
    }

    // MARK: Helpers

    func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// Scrolls the current screen until the element is on screen.
    @discardableResult
    func scrollTo(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        for _ in 0..<10 where !(e.exists && e.isHittable) { app.swipeUp() }
        XCTAssertTrue(e.exists && e.isHittable, "Could not scroll to \(e)", file: file, line: line)
        return e
    }

    @discardableResult
    func wait(_ e: XCUIElement, _ timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Missing \(e)", file: file, line: line)
        return e
    }

    /// Taps a system alert button directly if the interruption monitor has not handled it yet.
    func allowSystemAlert(timeout: TimeInterval = 4) {
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: timeout) {
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return
            }
        }
        app.tap()  // lets the interruption monitor run if needed
    }

    func search(_ text: String) {
        tab("Words")
        let field = app.searchFields.firstMatch
        wait(field).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    func openWord(_ hanzi: String) {
        search(hanzi)
        wait(el("word.\(hanzi)")).tap()
        wait(app.navigationBars[hanzi])
    }

    // MARK: Tests

    func testEveryTabAndScreen() {
        wait(el("today.study"))
        el("today.toneQuiz").tap()
        wait(app.navigationBars["Tone quiz"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
        el("today.writingDrill").tap()
        wait(app.navigationBars["Writing drill"])
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab("Decks")
        wait(el("deck.all"))
        XCTAssertTrue(el("deck.hsk:1").exists)
        XCTAssertTrue(el("deck.rank:1-100").exists)
        scrollTo(el("deck.leeches")).tap()
        wait(el("review.empty"))  // no leeches yet: empty state, not a blank screen
        el("review.close").tap()

        tab("Words")
        wait(el("word.一"))
        tab("Stats")
        wait(app.navigationBars["Stats"])
        XCTAssertTrue(app.staticTexts["Reviews today"].exists)
        tab("Settings")
        scrollTo(el("settings.export"))
        tab("Today")
    }

    func testReviewAllDirectionsAndRatings() {
        el("today.study").tap()
        wait(el("review.show"), 10)
        var directions = Set<String>()
        var ratings = Set<String>()
        let order = ["again", "hard", "good", "easy"]
        for i in 0..<40 {
            if ratings.count == 4 && directions.count == 3 { break }
            if el("review.studyNow").exists { el("review.studyNow").tap() }
            if el("review.complete").exists { break }
            guard el("review.show").waitForExistence(timeout: 5) else { continue }
            if let d = el("review.direction").value as? String { directions.insert(d) }
            el("review.show").tap()
            let r = ratings.count < 4 ? order[ratings.count] : order[2 + i % 2]
            wait(el("rate.\(r)")).tap()
            ratings.insert(r)
        }
        XCTAssertEqual(directions, ["hanzi_meaning", "meaning_hanzi", "audio_hanzi"])
        XCTAssertEqual(ratings, Set(order))
        el("review.close").tap()
        wait(el("today.study"))
    }

    func testEditNotesPersist() {
        openWord("你")
        let mnemonic = el("word.mnemonic")
        wait(mnemonic).tap()
        mnemonic.typeText("Person radical points at you")
        let note = el("word.note")
        note.tap()
        note.typeText("Most common pronoun")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(el("word.你")).tap()
        XCTAssertEqual(wait(el("word.mnemonic")).value as? String, "Person radical points at you")
        XCTAssertEqual(el("word.note").value as? String, "Most common pronoun")
    }

    func testAddCustomWordToCustomDeck() {
        tab("Decks")
        scrollTo(el("decks.new")).tap()
        wait(app.alerts.textFields.firstMatch).typeText("UITest Deck")
        app.alerts.buttons["Create"].tap()
        wait(el("deck.custom.UITest Deck"))

        tab("Words")
        el("words.add").tap()
        wait(el("add.hanzi")).tap()
        el("add.hanzi").typeText("火锅")
        let pinyin = el("add.pinyin")
        XCTAssertEqual(pinyin.value as? String, "huǒ guō", "Pinyin is guessed from the characters")
        el("add.meaning").tap()
        el("add.meaning").typeText("hot pot")
        el("add.save").tap()

        openWord("火锅")
        let deckRow = scrollTo(el("word.deck.UITest Deck"))
        deckRow.tap()
        XCTAssertEqual(deckRow.value as? String, "in deck")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab("Decks")
        scrollTo(el("deck.custom.UITest Deck")).tap()
        wait(el("word.火锅"))
        XCTAssertTrue(el("deck.study").isEnabled)
    }

    func testSearch() {
        search("xiexie")
        wait(el("word.谢谢"))
        search("eat")
        wait(el("word.吃"))
        search("学")
        wait(el("word.学生"))
        search("qqqzzz")
        XCTAssertFalse(el("word.谢谢").exists)
    }

    func testStrokeOrderAndWritingModes() {
        openWord("你")
        scrollTo(el("char.你")).tap()
        wait(el("strokeOrder.canvas"))
        el("strokeOrder.next").tap()
        el("strokeOrder.show").tap()
        el("strokeOrder.animate").tap()

        app.segmentedControls["char.tab"].buttons["Write"].tap()
        let modes = wait(app.segmentedControls["writing.mode"])
        XCTAssertEqual(wait(el("writing.progress")).label, "Stroke 1 of 7")
        // A deliberately wrong stroke (bottom edge, right to left) is rejected.
        let canvas = el("writing.canvas")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.95)))
        XCTAssertEqual(el("writing.progress").label, "Stroke 1 of 7")
        // First stroke of 你 is the short slanted stroke at the top left.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.40)))
        XCTAssertEqual(el("writing.progress").label, "Stroke 2 of 7")

        modes.buttons["Trace"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        modes.buttons["Blank"].tap()
        el("writing.restart").tap()
        modes.buttons["Quiz"].tap()
        XCTAssertEqual(wait(el("writing.progress")).label, "Stroke 1 of 7")
    }

    func testToneQuizRound() {
        el("today.toneQuiz").tap()
        wait(el("quiz.check"))
        XCTAssertFalse(el("quiz.check").isEnabled, "Check needs a pick per syllable")
        el("quiz.pick.0.1").tap()
        XCTAssertTrue(el("quiz.check").isEnabled)
        el("quiz.check").tap()
        wait(el("quiz.result"))
        el("quiz.next").tap()
        app.segmentedControls["quiz.syllables"].buttons["2 syllables"].tap()
        wait(el("quiz.pick.1.4"))
        el("quiz.pick.0.2").tap()
        el("quiz.pick.1.4").tap()
        el("quiz.check").tap()
        wait(el("quiz.result"))
    }

    func testRecordingAndMicrophonePermission() {
        openWord("你")
        let record = scrollTo(el("audio.record"))
        record.tap()
        allowSystemAlert()
        // After permission the button turns into Stop.
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 6))
        sleep(2)
        stop.tap()
        XCTAssertTrue(el("audio.mine").isEnabled)
        el("audio.compare").tap()
    }

    func testReminderPermissionAndTime() {
        tab("Settings")
        let toggle = scrollTo(el("settings.reminder"))
        toggle.switches.firstMatch.tap()
        allowSystemAlert()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Reminder set for'")).firstMatch
            .waitForExistence(timeout: 6))
        toggle.switches.firstMatch.tap()  // leave no test reminder behind
    }

    func testExportShowsSaveSheet() {
        tab("Settings")
        scrollTo(el("settings.export")).tap()
        // The system Files exporter, already pointing at a JSON file to save.
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Export sheet did not appear")
        XCTAssertEqual(save.label, "Save")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value BEGINSWITH 'jide-backup-'")).firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'jide-backup-'")).firstMatch.exists,
            "Suggested file name")
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Cancel'")).firstMatch.tap()
        XCTAssertTrue(el("settings.export").waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Cancelling must not show an error")
    }
}

/// Cold start of the normal app (owner's data, no seeding), measured by XCTest.
final class LaunchPerformanceTests: XCTestCase {
    func testColdLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            XCUIApplication().launch()
        }
    }
}
