import SwiftUI
import XCTest
@testable import Jide

final class PinyinTests: XCTestCase {
    func testNumberToMarks() {
        let cases: [(String, String)] = [
            ("ni3", "nǐ"), ("hao3", "hǎo"), ("ma1", "mā"), ("ma2", "má"), ("ma4", "mà"), ("ma5", "ma"),
            ("xiong2", "xióng"), ("gou3", "gǒu"), ("ou1", "ōu"), ("liu2", "liú"), ("dui4", "duì"), ("shui3", "shuǐ"),
            ("er2", "ér"), ("e4", "è"), ("a1", "ā"), ("zhuang4", "zhuàng"), ("jiao4", "jiào"), ("lüe4", "lüè"),
            ("Zhong1", "Zhōng"), ("Ou1", "Ōu"),
        ]
        for (num, marks) in cases {
            XCTAssertEqual(Pinyin.syllable(fromNumbered: num).text, marks, num)
        }
        XCTAssertEqual(Pinyin.marks(fromNumbered: "ni3 hao3"), "nǐ hǎo")
    }

    func testToneNumbersAndColors() {
        XCTAssertEqual(Pinyin.syllables(numbered: "ni3 hao3 ma5 shi4 Zhong1 guo2").map(\.tone), [3, 3, 5, 4, 1, 2])
        XCTAssertEqual(ToneColor.color(1), Color(red: 0.86, green: 0.15, blue: 0.15))
        XCTAssertEqual(ToneColor.color(5), Color.gray)
        XCTAssertEqual(ToneColor.color(0), Color.gray, "Non-syllables are gray")
        let colors = (1...4).map { ToneColor.color($0) }
        XCTAssertEqual(Set(colors.map { "\($0)" }).count, 4, "Each tone has its own color")
    }

    func testNeutralTone() {
        let s = Pinyin.syllable(fromNumbered: "le5")
        XCTAssertEqual(s.text, "le")
        XCTAssertEqual(s.tone, 5)
        XCTAssertEqual(Pinyin.tone(ofMarked: "le"), 5)
        XCTAssertEqual(Pinyin.normalizeInput("ma"), "ma5")
    }

    func testUmlautAndV() {
        XCTAssertEqual(Pinyin.syllable(fromNumbered: "lu:4").text, "lǜ")
        XCTAssertEqual(Pinyin.syllable(fromNumbered: "nu:3").text, "nǚ")
        XCTAssertEqual(Pinyin.syllable(fromNumbered: "lv4").text, "lǜ")
        XCTAssertEqual(Pinyin.normalizeInput("lv4"), "lu:4")
        XCTAssertEqual(Pinyin.normalizeInput("nü3 ren2"), "nu:3 ren2")
        XCTAssertEqual(Pinyin.normalizeInput("nǚ rén"), "nu:3 ren2")
        XCTAssertEqual(Pinyin.normalizeInput("lǜ"), "lu:4")
        XCTAssertEqual(Pinyin.searchKey("lǜ"), "lu")
        XCTAssertEqual(Pinyin.searchKey("lv"), "lu")
    }

    func testErhua() {
        // CC-CEDICT: 一点儿 = yi1 dian3 r5
        XCTAssertEqual(Pinyin.marks(fromNumbered: "yi1 dian3 r5"), "yī diǎnr")
        XCTAssertEqual(Pinyin.syllables(numbered: "yi1 dian3 r5").count, 3, "One syllable per hanzi for coloring 一点儿")
        XCTAssertTrue(Pinyin.syllables(numbered: "yi1 dian3 r5")[2].isErhua)
        XCTAssertEqual(Pinyin.joined(Pinyin.syllables(numbered: "yi1 dian3 r5")).map(\.tone), [1, 3])
        XCTAssertEqual(Pinyin.syllable(fromNumbered: "huar4").text, "huàr")
        XCTAssertEqual(Pinyin.normalizeInput("yī diǎn r"), "yi1 dian3 r5")
    }

    func testRoundTripThroughInput() {
        for numbered in ["ni3 hao3", "xie4 xie5", "lu:4 se4", "Zhong1 guo2"] {
            XCTAssertEqual(Pinyin.normalizeInput(Pinyin.marks(fromNumbered: numbered)), numbered.lowercased())
        }
    }
}

final class SearchTests: XCTestCase {
    struct W { var s, t, p, g: String; var d: [String] }
    let words = [
        W(s: "你好", t: "你好", p: "nǐ hǎo", g: "hello", d: ["hello", "hi"]),
        W(s: "吃", t: "吃", p: "chī", g: "eat", d: ["to eat"]),
        W(s: "大", t: "大", p: "dà", g: "big", d: ["big", "great"]),
        W(s: "女人", t: "女人", p: "nǚ rén", g: "woman", d: ["woman"]),
        W(s: "说", t: "說", p: "shuō", g: "speak", d: ["to speak", "to say"]),
    ]

    func results(_ q: String) -> [String] {
        let query = WordSearch.Query(q)
        return words.filter {
            WordSearch.matches(simplified: $0.s, traditional: $0.t, pinyin: $0.p, gloss: $0.g, definitions: $0.d, query: query)
        }.map(\.s)
    }

    func testHanzi() {
        XCTAssertEqual(results("你"), ["你好"])
        XCTAssertEqual(results("說"), ["说"], "Traditional form matches")
        XCTAssertEqual(results("人"), ["女人"])
    }

    func testTonelessPinyin() {
        XCTAssertEqual(results("nihao"), ["你好"])
        XCTAssertEqual(results("ni hao"), ["你好"])
        XCTAssertEqual(results("hao"), ["你好"], "Matches from any syllable start")
        XCTAssertEqual(results("ni3hao3"), ["你好"])
        XCTAssertEqual(results("nǐ"), ["你好"])
        XCTAssertEqual(results("nuren"), ["女人"])
        XCTAssertEqual(results("nvren"), ["女人"])
        XCTAssertEqual(results("ihao"), [], "Not from the middle of a syllable")
    }

    func testEnglish() {
        XCTAssertEqual(results("eat"), ["吃"], "Whole-word prefix: 'great' does not match 'eat'")
        XCTAssertEqual(results("HELLO"), ["你好"])
        XCTAssertEqual(results("say"), ["说"])
        XCTAssertEqual(results("wom"), ["女人"])
        XCTAssertEqual(results("zzz"), [])
        XCTAssertEqual(results("  "), words.map(\.s), "Empty query shows everything")
    }
}

final class ToneQuizTests: XCTestCase {
    func syl(_ s: String) -> [Pinyin.Syllable] { Pinyin.syllables(numbered: s) }

    func testOptionsAndAnswer() {
        XCTAssertEqual(ToneQuiz.options, [1, 2, 3, 4, 5])
        XCTAssertEqual(ToneQuiz.answer(syl("Zhong1 guo2")), [1, 2])
        XCTAssertEqual(ToneQuiz.answer(syl("le5")), [5])
        XCTAssertTrue(ToneQuiz.grade(picks: [1, 2], syllables: syl("Zhong1 guo2")))
        XCTAssertFalse(ToneQuiz.grade(picks: [1, 4], syllables: syl("Zhong1 guo2")))
        XCTAssertFalse(ToneQuiz.grade(picks: [1, nil], syllables: syl("Zhong1 guo2")))
        XCTAssertFalse(ToneQuiz.grade(picks: [1], syllables: syl("Zhong1 guo2")))
    }

    func testSandhiFilter() {
        XCTAssertTrue(ToneQuiz.isEligible(simplified: "你", syllables: syl("ni3"), count: 1))
        XCTAssertTrue(ToneQuiz.isEligible(simplified: "中国", syllables: syl("Zhong1 guo2"), count: 2))
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "你好", syllables: syl("ni3 hao3"), count: 2), "3+3 is spoken 2+3")
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "不", syllables: syl("bu4"), count: 1))
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "一个", syllables: syl("yi1 ge4"), count: 2))
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "一点儿", syllables: syl("yi1 dian3 r5"), count: 3), "Erhua")
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "中国", syllables: syl("Zhong1 guo2"), count: 1), "Wrong length")
        XCTAssertFalse(ToneQuiz.isEligible(simplified: "很多", syllables: syl("hen3"), count: 2), "Pinyin/hanzi mismatch")
    }

    func testBundledPoolsAreUsable() {
        let words = Library.shared.words
        XCTAssertEqual(words.count, 1000)
        for n in 1...2 {
            let pool = words.filter { ToneQuiz.isEligible(simplified: $0.simplified, syllables: syl($0.pinyinNumbered), count: n) }
            XCTAssertGreaterThan(pool.count, 100, "n=\(n)")
            XCTAssertFalse(pool.contains { w in
                let t = syl(w.pinyinNumbered).map(\.tone)
                return zip(t, t.dropFirst()).contains { $0 == 3 && $1 == 3 }
            })
        }
    }
}

final class BundledDataTests: XCTestCase {
    func testWordsAreClean() {
        let words = Library.shared.words
        XCTAssertEqual(Set(words.map(\.simplified)).count, words.count, "No duplicate words")
        XCTAssertEqual(words.map(\.rank), Array(1...words.count))
        for w in words {
            XCTAssertFalse(w.definitions.joined().trimmingCharacters(in: .whitespaces).isEmpty, w.simplified)
            let syl = Pinyin.syllables(numbered: w.pinyinNumbered)
            XCTAssertEqual(syl.count, w.simplified.count, "\(w.simplified) \(w.pinyinNumbered)")
            XCTAssertTrue(syl.allSatisfy { (1...5).contains($0.tone) }, w.simplified)
        }
        XCTAssertEqual(words.first { $0.simplified == "吗" }?.pinyinNumbered, "ma5")
    }

    func testPinyinGuessForCustomWords() {
        XCTAssertEqual(Library.shared.guessPinyin("火锅"), "huo3 guo1", "锅 is outside the top 1000 but still known")
        XCTAssertEqual(Library.shared.guessPinyin("你好"), "ni3 hao3")
        XCTAssertEqual(Library.shared.guessPinyin("你A"), "", "No partial guesses")
        XCTAssertEqual(Library.shared.character("锅")?.strokes, nil)
        XCTAssertEqual(Library.shared.character("锅")?.components.isEmpty, false)
    }

    func testEveryWordCharacterHasStrokes() {
        for ch in Set(Library.shared.words.flatMap { Array($0.simplified) }) {
            let info = Library.shared.character(ch)
            XCTAssertNotNil(HanziGraphics(info), String(ch))
        }
    }
}
