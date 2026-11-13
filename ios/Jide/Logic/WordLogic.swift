import Foundation

/// Word search used by the Words tab: 汉字, toneless pinyin (any syllable start), or English.
enum WordSearch {
    struct Query {
        let raw: String
        let lower: String
        let pinyinKey: String
        let hasHanzi: Bool

        init(_ text: String) {
            raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            lower = raw.lowercased()
            hasHanzi = raw.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
            pinyinKey = hasHanzi ? "" : Pinyin.searchKey(raw)
        }

        var isEmpty: Bool { raw.isEmpty }
    }

    /// Toneless pinyin suffixes starting at each syllable: "nǐ hǎo" -> ["nihao", "hao"].
    static func pinyinSuffixes(_ pinyinMarks: String) -> [String] {
        let syl = pinyinMarks.split(separator: " ").map { Pinyin.searchKey(String($0)) }
        return syl.indices.map { syl[$0...].joined() }
    }

    static func matches(simplified: String, traditional: String, pinyin: String, gloss: String,
                        definitions: [String], query q: Query) -> Bool {
        if q.isEmpty { return true }
        if q.hasHanzi { return simplified.contains(q.raw) || traditional.contains(q.raw) }
        if !q.pinyinKey.isEmpty && pinyinSuffixes(pinyin).contains(where: { $0.hasPrefix(q.pinyinKey) }) { return true }
        // English: whole-word prefix match ("eat" finds "to eat", not "great").
        let needle = q.lower
        guard needle.count >= 2 || needle == "i" || needle == "a" else { return false }
        return ([gloss] + definitions).contains { englishMatch($0.lowercased(), needle) }
    }

    static func englishMatch(_ text: String, _ needle: String) -> Bool {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: needle, range: search) {
            if r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter { return true }
            search = r.upperBound..<text.endIndex
        }
        return false
    }

    static func matches(_ w: Word, _ q: Query) -> Bool {
        matches(simplified: w.simplified, traditional: w.traditional, pinyin: w.pinyin, gloss: w.gloss,
                definitions: w.definitions, query: q)
    }
}

/// Rules for the tone quiz.
enum ToneQuiz {
    /// Answer buttons for each syllable: tones 1-4 and neutral (5).
    static let options = [1, 2, 3, 4, 5]

    /// Words whose audio unambiguously matches their dictionary tones.
    static func isEligible(simplified: String, syllables: [Pinyin.Syllable], count: Int) -> Bool {
        guard syllables.count == count, simplified.count == count else { return false }
        guard syllables.allSatisfy({ (1...5).contains($0.tone) && !$0.isErhua }) else { return false }
        // 一 and 不 change tone with context (yí gè, bú shì).
        if simplified.contains("一") || simplified.contains("不") { return false }
        // Third-tone sandhi: 3+3 is spoken 2+3.
        for (a, b) in zip(syllables, syllables.dropFirst()) where a.tone == 3 && b.tone == 3 { return false }
        return true
    }

    /// Correct answer per syllable.
    static func answer(_ syllables: [Pinyin.Syllable]) -> [Int] { syllables.map(\.tone) }

    static func grade(picks: [Int?], syllables: [Pinyin.Syllable]) -> Bool {
        picks.count == syllables.count && zip(picks, answer(syllables)).allSatisfy { $0 == $1 }
    }
}
