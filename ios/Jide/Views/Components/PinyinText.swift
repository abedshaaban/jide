import SwiftUI

enum ToneColor {
    static func color(_ tone: Int) -> Color {
        switch tone {
        case 1: Color(red: 0.86, green: 0.15, blue: 0.15)   // red
        case 2: Color(red: 0.12, green: 0.62, blue: 0.25)   // green
        case 3: Color(red: 0.15, green: 0.40, blue: 0.90)   // blue
        case 4: Color(red: 0.58, green: 0.22, blue: 0.80)   // purple
        default: Color.gray
        }
    }

    static func name(_ tone: Int) -> String {
        switch tone {
        case 1: "1st ˉ"
        case 2: "2nd ˊ"
        case 3: "3rd ˇ"
        case 4: "4th ˋ"
        default: "neutral"
        }
    }
}

/// Pinyin with each syllable colored by tone.
struct PinyinText: View {
    var numbered: String
    var font: Font = .title3

    var body: some View {
        let syl = Pinyin.syllables(numbered: numbered)
        syl.enumerated().reduce(Text("")) { acc, item in
            let (i, s) = item
            let t = Text(s.text).foregroundColor(ToneColor.color(s.tone))
            return i == 0 ? acc + t : acc + Text(" ") + t
        }
        .font(font)
    }
}

/// Hanzi with each character colored by the tone of its syllable (when counts match).
struct HanziText: View {
    var hanzi: String
    var numbered: String
    var size: CGFloat = 64
    var colored = true

    var body: some View {
        let chars = Array(hanzi)
        let syl = Pinyin.syllables(numbered: numbered)
        let match = colored && chars.count == syl.count
        chars.enumerated().reduce(Text("")) { acc, item in
            let (i, ch) = item
            return acc + Text(String(ch)).foregroundColor(match ? ToneColor.color(syl[i].tone) : .primary)
        }
        .font(.system(size: size, weight: .regular))
    }
}

/// Sentence pinyin with one syllable per space-separated token, colored by tone mark.
struct MarkedPinyinText: View {
    var text: String
    var font: Font = .subheadline

    var body: some View {
        let tokens = text.split(separator: " ")
        tokens.enumerated().reduce(Text("")) { acc, item in
            let (i, w) = item
            let t = Text(String(w)).foregroundColor(ToneColor.color(Pinyin.tone(ofMarked: String(w))))
            return i == 0 ? acc + t : acc + Text(" ") + t
        }
        .font(font)
    }
}
