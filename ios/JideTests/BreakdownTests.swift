import XCTest
@testable import Jide

final class BreakdownTests: XCTestCase {
    func testShortDefinition() {
        XCTAssertEqual(WordBreakdown.short("woman, girl; female"), "woman")
        XCTAssertEqual(WordBreakdown.short("roof; house"), "roof")
        XCTAssertEqual(WordBreakdown.short(nil), "")
    }

    func testStories() {
        let hao = Library.shared.character("好")
        XCTAssertEqual(hao?.components, ["女", "子"])
        XCTAssertEqual(WordBreakdown.story(hao?.etymology), "A woman 女 with a son 子")
        XCTAssertEqual(WordBreakdown.story(Library.shared.character("想")?.etymology),
                       "心 gives the meaning (mind), 相 gives the sound.")
        XCTAssertNil(WordBreakdown.story(nil))
    }
}
