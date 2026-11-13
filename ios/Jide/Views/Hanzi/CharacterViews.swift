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
        }
        .navigationTitle(String(character))
        .navigationBarTitleDisplayMode(.inline)
    }
}
