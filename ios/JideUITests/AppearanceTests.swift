import XCTest

/// Captures key screens in dark mode at the largest accessibility text size (attachments in the .xcresult).
final class AppearanceTests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func run(_ args: [String], prefix: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + args
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        shot(app, "\(prefix)-today")
        let study = app.descendants(matching: .any)["today.study"]
        if study.waitForExistence(timeout: 5) {
            study.tap()
            let show = app.descendants(matching: .any)["review.show"]
            if show.waitForExistence(timeout: 5) {
                shot(app, "\(prefix)-card-front")
                show.tap()
                shot(app, "\(prefix)-card-back")
            }
            app.descendants(matching: .any)["review.close"].tap()
        }
        for t in ["Decks", "Words", "Stats", "Settings"] {
            let b = app.tabBars.buttons[t]
            if b.exists { b.tap(); sleep(1); shot(app, "\(prefix)-\(t.lowercased())") }
        }
        app.tabBars.buttons["Today"].tap()
        let quiz = app.descendants(matching: .any)["today.toneQuiz"]
        for _ in 0..<5 where !(quiz.exists && quiz.isHittable) { app.swipeUp() }
        if quiz.exists {
            quiz.tap()
            sleep(1)
            app.descendants(matching: .any)["quiz.pick.0.3"].tap()
            app.descendants(matching: .any)["quiz.check"].tap()
            shot(app, "\(prefix)-tonequiz")
        }
    }

    func testDarkLargestText() { run(["-uitest-dark", "-uitest-ax"], prefix: "dark-ax5") }
    func testDarkDefaultText() { run(["-uitest-dark"], prefix: "dark") }
}
