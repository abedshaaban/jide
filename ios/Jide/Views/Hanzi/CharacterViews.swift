import SwiftUI

/// Component breakdown of one character, recursively expandable.
struct ComponentRow: View {
    var character: Character
    var depth = 0
    /// Off inside NavigationLink rows, where the row tap navigates instead.
    var expandable = true
    @State private var expanded = false

    var body: some View {
        let info = Library.shared.character(character)
        let comps = info?.components ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(character)).font(.system(size: depth == 0 ? 34 : 26))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let p = info?.pinyin.first {
                            Text(p).foregroundStyle(ToneColor.color(Pinyin.tone(ofMarked: p)))
                        }
                        if let r = info?.radical, r == String(character) {
                            Text("radical").font(.caption2).padding(.horizontal, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                    .font(.subheadline)
                    Text(info?.definition ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if expandable && !comps.isEmpty && depth < 3 {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(expanded ? "Hide components" : "Show components")
                    .accessibilityIdentifier("component.expand.\(character)")
                }
            }
            if expanded {
                if let e = info?.etymology {
                    EtymologyText(etymology: e).padding(.leading, 8)
                }
                ForEach(Array(comps.enumerated()), id: \.offset) { _, c in
                    ComponentRow(character: c, depth: depth + 1)
                        .padding(.leading, 16)
                }
            }
        }
    }
}

struct EtymologyText: View {
    var etymology: CharacterInfo.Etymology
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let t = etymology.type { Text(t.capitalized).font(.caption.bold()) }
            if let h = etymology.hint { Text(h).font(.caption) }
            if let s = etymology.semantic { Text("Meaning: \(s)").font(.caption) }
            if let p = etymology.phonetic { Text("Sound: \(p)").font(.caption) }
        }
        .foregroundStyle(.secondary)
    }
}

/// How each character of a word is built, shown on the answer side of a card:
/// 好 = 女 woman + 子 child, "A woman 女 with a son 子". Tap a row for the character page.
struct WordBreakdown: View {
    var text: String

    /// Characters worth a row: known ones, skipping a lone character that has no parts to show.
    private var characters: [Character] {
        let known = text.filter { Library.shared.character($0) != nil }
        if known.count == 1, let ch = known.first, Library.shared.character(ch)?.components.isEmpty != false { return [] }
        var seen = Set<Character>()
        return known.filter { seen.insert($0).inserted }
    }

    var body: some View {
        let chars = characters
        if !chars.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("How it's built").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(chars, id: \.self) { ch in
                    NavigationLink { CharacterDetailView(character: ch) } label: { row(ch) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("breakdown.\(ch)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
        }
    }

    private func row(_ ch: Character) -> some View {
        let info = Library.shared.character(ch)
        let comps = info?.components ?? []
        return HStack(alignment: .top, spacing: 12) {
            Text(String(ch)).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let p = info?.pinyin.first {
                        Text(p).foregroundStyle(ToneColor.color(Pinyin.tone(ofMarked: p)))
                    }
                    Text(Self.short(info?.definition)).foregroundStyle(.primary)
                }
                .font(.subheadline)
                if !comps.isEmpty {
                    Text(comps.map { c in
                        let d = Self.short(Library.shared.character(c)?.definition)
                        return d.isEmpty ? String(c) : "\(c) \(d)"
                    }.joined(separator: "  +  "))
                        .font(.subheadline.weight(.medium))
                }
                if let story = Self.story(info?.etymology) {
                    Text(story).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// First sense of a dictionary definition: "woman, girl; female" → "woman".
    static func short(_ definition: String?) -> String {
        let first = (definition ?? "").split(whereSeparator: { $0 == "," || $0 == ";" }).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// One sentence on why the character looks the way it does.
    static func story(_ e: CharacterInfo.Etymology?) -> String? {
        guard let e else { return nil }
        let hint = e.hint?.replacingOccurrences(of: "\u{00A0}", with: " ")
        if let semantic = e.semantic, let phonetic = e.phonetic {
            let meaning = hint.map { " (\($0))" } ?? ""
            return "\(semantic) gives the meaning\(meaning), \(phonetic) gives the sound."
        }
        if e.type == "pictographic", let hint { return "Picture: \(hint)" }
        return hint
    }
}

/// Answer side of a character-part card: the characters it helps build, e.g. 扌 → 打 找 把.
struct PartUses: View {
    var character: String

    var body: some View {
        let chars = (Library.shared.component(character)?.usedIn ?? []).compactMap(\.first)
        if !chars.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You will see it in").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(chars.prefix(5), id: \.self) { ch in
                    let info = Library.shared.character(ch)
                    NavigationLink { CharacterDetailView(character: ch) } label: {
                        HStack(spacing: 12) {
                            Text(String(ch)).font(.system(size: 30))
                            if let p = info?.pinyin.first {
                                Text(p).foregroundStyle(ToneColor.color(Pinyin.tone(ofMarked: p)))
                            }
                            Text(WordBreakdown.short(info?.definition)).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
        }
    }
}

/// Character page: breakdown, stroke order, writing practice.
struct CharacterDetailView: View {
    var character: Character
    @State private var tab = 0

    var body: some View {
        let info = Library.shared.character(character)
        let graphics = HanziGraphics(info)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    Text(String(character)).font(.system(size: 72))
                    VStack(alignment: .leading, spacing: 4) {
                        if let info {
                            Text(info.pinyin.joined(separator: ", "))
                                .foregroundStyle(ToneColor.color(Pinyin.tone(ofMarked: info.pinyin.first ?? "")))
                                .font(.title3)
                            Text(info.definition ?? "").font(.subheadline)
                            Text("Radical \(info.radical) · \(info.decomposition)").font(.caption).foregroundStyle(.secondary)
                        }
                        SpeakButtons(text: String(character), compact: true)
                    }
                }
                if let e = info?.etymology { EtymologyText(etymology: e) }

                if let graphics {
                    Picker("", selection: $tab) {
                        Text("Stroke order").tag(0)
                        Text("Write").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("char.tab")
                    if tab == 0 {
                        StrokeOrderView(graphics: graphics).frame(maxWidth: 320).frame(maxWidth: .infinity)
                    } else {
                        WritingPracticeView(character: character, graphics: graphics)
                    }
                } else {
                    Text("No stroke data for this character.").foregroundStyle(.secondary)
                        .accessibilityIdentifier("char.noStrokes")
                }

                if let comps = info?.components, !comps.isEmpty {
                    Text("Components").font(.headline)
                    ForEach(Array(comps.enumerated()), id: \.offset) { _, c in
                        ComponentRow(character: c, depth: 1)
                        Divider()
                    }
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle(String(character))
        .navigationBarTitleDisplayMode(.inline)
    }
}
