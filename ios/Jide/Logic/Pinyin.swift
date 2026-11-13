import Foundation

/// Pinyin conversion between CC-CEDICT numbered form ("ni3 hao3") and tone marks ("nǐ hǎo").
enum Pinyin {
    struct Syllable: Hashable {
        var text: String
        /// 1-4, 5 = neutral, 0 = not a syllable (punctuation, letters).
        var tone: Int
    }

    private static let marks: [Character: [Character]] = [
        "a": ["ā", "á", "ǎ", "à"], "e": ["ē", "é", "ě", "è"], "i": ["ī", "í", "ǐ", "ì"],
        "o": ["ō", "ó", "ǒ", "ò"], "u": ["ū", "ú", "ǔ", "ù"], "ü": ["ǖ", "ǘ", "ǚ", "ǜ"],
    ]
    private static let markToBase: [Character: (Character, Int)] = {
        var out: [Character: (Character, Int)] = [:]
        for (base, ms) in marks {
            for (i, m) in ms.enumerated() {
                out[m] = (base, i + 1)
                out[Character(m.uppercased())] = (Character(base.uppercased()), i + 1)
            }
        }
        return out
    }()

    /// "lu:4" -> ("lǜ", 4). Returns tone 0 for tokens that are not numbered syllables.
    static func syllable(fromNumbered token: String) -> Syllable {
        let body0 = token.replacingOccurrences(of: "u:", with: "ü").replacingOccurrences(of: "U:", with: "Ü")
            .replacingOccurrences(of: "v", with: "ü")
        guard let last = body0.last, let tone = last.wholeNumberValue, (1...5).contains(tone), body0.count > 1 else {
            return Syllable(text: body0, tone: 0)
        }
        let body = String(body0.dropLast())
        guard body.allSatisfy({ $0.isLetter }) else { return Syllable(text: body0, tone: 0) }
        if tone == 5 { return Syllable(text: body, tone: 5) }
        let lower = Array(body.lowercased())
        var idx: Int?
        if let a = lower.firstIndex(of: "a") { idx = a }
        else if let e = lower.firstIndex(of: "e") { idx = e }
        else if let o = lower.firstIndex(of: "o"), o + 1 < lower.count, lower[o + 1] == "u" { idx = o }
        else { idx = lower.lastIndex(where: { "iouü".contains($0) }) }
        guard let i = idx else { return Syllable(text: body, tone: tone) }
        var chars = Array(body)
        let ch = chars[i]
        guard let m = marks[Character(ch.lowercased())]?[tone - 1] else { return Syllable(text: body, tone: tone) }
        chars[i] = ch.isUppercase ? Character(m.uppercased()) : m
        return Syllable(text: String(chars), tone: tone)
    }

    static func syllables(numbered: String) -> [Syllable] {
        numbered.split(whereSeparator: { $0.isWhitespace }).map { syllable(fromNumbered: String($0)) }
    }

    static func marks(fromNumbered numbered: String) -> String {
        syllables(numbered: numbered).map(\.text).joined(separator: " ")
    }

    /// Tone of a syllable written with marks ("hǎo" -> 3, "ma" -> 5).
    static func tone(ofMarked syllable: String) -> Int {
        for ch in syllable { if let (_, t) = markToBase[ch] { return t } }
        return 5
    }

    /// Turns user input in either style ("ni3 hao3", "nǐ hǎo") into numbered form.
    /// Syllables must be separated by spaces when written with marks.
    static func normalizeInput(_ input: String) -> String {
        input.split(whereSeparator: { $0.isWhitespace || $0 == "'" }).map { tokenSub in
            let token = String(tokenSub)
            if let last = token.last, last.isNumber { return token.lowercased().replacingOccurrences(of: "ü", with: "u:") }
            var tone = 5
            var plain = ""
            for ch in token {
                if let (base, t) = markToBase[ch] { tone = t; plain.append(base) } else { plain.append(ch) }
            }
            return plain.lowercased().replacingOccurrences(of: "ü", with: "u:") + String(tone)
        }.joined(separator: " ")
    }

    /// Lowercase pinyin without tones, spaces or digits, for search ("nǐ hǎo" -> "nihao").
    static func searchKey(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if let (base, _) = markToBase[ch] { out.append(base == "ü" ? "u" : base) }
            else if ch == "ü" { out.append("u") }
            else if ch.isLetter { out.append(ch) }
        }
        return out.replacingOccurrences(of: "u:", with: "u")
    }
}
