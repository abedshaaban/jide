import SwiftData
import SwiftUI

/// Hear a word, pick the tone of each syllable.
struct ToneQuizView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.toneQuizCorrect) private var lifetimeCorrect = 0
    @AppStorage(SettingsKey.toneQuizTotal) private var lifetimeTotal = 0
    @State private var syllableCount = 1
    @State private var onlyStudied = false
    @State private var word: Word?
    @State private var picks: [Int?] = []
    @State private var checked = false
    @State private var sessionCorrect = 0
    @State private var sessionTotal = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Syllables", selection: $syllableCount) {
                    Text("1 syllable").tag(1)
                    Text("2 syllables").tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: syllableCount) { next() }
                Toggle("Only words I've studied", isOn: $onlyStudied)
                    .onChange(of: onlyStudied) { next() }

                if let word {
                    SpeakButtons(text: word.simplified)
                    let syl = word.syllables
                    ForEach(syl.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            ForEach([1, 2, 3, 4, 5], id: \.self) { t in
                                Button {
                                    if !checked { picks[i] = t }
                                } label: {
                                    Text(t == 5 ? "·" : ["ˉ", "ˊ", "ˇ", "ˋ"][t - 1] + "\(t)")
                                        .font(.title3.bold())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(tint(i, t, correct: syl[i].tone))
                            }
                        }
                    }
                    if checked {
                        VStack(spacing: 6) {
                            HanziText(hanzi: word.simplified, numbered: word.pinyinNumbered, size: 48)
                            PinyinText(numbered: word.pinyinNumbered, font: .title2)
                            Text(word.shortMeaning).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("Next") { next() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Check") { check() }
                            .buttonStyle(.borderedProminent)
                            .disabled(picks.contains { $0 == nil })
                    }
                } else {
                    Text("No words match. Study some cards first, or turn off \"Only words I've studied\".")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Session \(sessionCorrect)/\(sessionTotal)")
                    Spacer()
                    Text("All time \(lifetimeCorrect)/\(lifetimeTotal)")
                }
                .font(.caption).foregroundStyle(.secondary)
                Text("Tones shown are dictionary (citation) tones. Spoken audio applies tone sandhi, e.g. 3+3 → 2+3, 不 and 一 change before 4th tones.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Tone quiz")
        .onAppear { if word == nil { next() } }
    }

    private func tint(_ i: Int, _ t: Int, correct: Int) -> Color {
        if checked {
            if t == correct { return ToneColor.color(t) }
            if picks[i] == t { return .black }
            return .gray.opacity(0.4)
        }
        return picks[i] == t ? ToneColor.color(t) : .gray
    }

    private func check() {
        guard let word else { return }
        checked = true
        let right = zip(picks, word.syllables).allSatisfy { $0 == $1.tone }
        sessionTotal += 1
        lifetimeTotal += 1
        if right { sessionCorrect += 1; lifetimeCorrect += 1 }
    }

    private func next() {
        let n = syllableCount
        let all = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        let pool = all.filter { w in
            let syl = w.syllables
            guard syl.count == n, w.simplified.count == n, syl.allSatisfy({ (1...5).contains($0.tone) }) else { return false }
            if w.simplified.contains("一") || w.simplified.contains("不") { return false }
            if n == 2 && syl[0].tone == 3 && syl[1].tone == 3 { return false }  // sandhi makes audio ambiguous
            return !onlyStudied || w.cards.contains { $0.state != .new }
        }
        word = pool.randomElement()
        picks = Array(repeating: nil, count: n)
        checked = false
        if let w = word { Speech.shared.speak(w.simplified) }
    }
}

/// Writing practice on random characters from studied words.
struct WritingDrillView: View {
    @Environment(\.modelContext) private var context
    @State private var character: Character?
    @State private var word: Word?
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let ch = character, let word, let g = HanziGraphics(Library.shared.character(ch)) {
                    VStack(spacing: 4) {
                        Text(word.shortMeaning).font(.headline).multilineTextAlignment(.center)
                        PinyinText(numbered: word.pinyinNumbered)
                        Text(revealed ? word.simplified : word.simplified.map { $0 == ch ? "＿" : String($0) }.joined())
                            .font(.title)
                    }
                    WritingPracticeView(character: ch, graphics: g).id(ch)
                    HStack {
                        Button(revealed ? "Hide" : "Reveal") { revealed.toggle() }
                        Button("Hear") { Speech.shared.speak(word.simplified) }
                        Spacer()
                        Button("Next") { next() }.buttonStyle(.borderedProminent)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Study a few words first. Characters from words you've reviewed show up here.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Writing drill")
        .onAppear { if character == nil { next() } }
    }

    private func next() {
        let all = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        var studied = all.filter { w in w.cards.contains { $0.state != .new } }
        if studied.isEmpty { studied = all.filter { $0.rank <= 30 } }
        for _ in 0..<20 {
            guard let w = studied.randomElement(), let ch = w.simplified.randomElement() else { break }
            if Library.shared.character(ch)?.strokes != nil {
                word = w
                character = ch
                revealed = false
                return
            }
        }
        character = nil
    }
}

struct LeechListView: View {
    @Query(filter: #Predicate<Card> { $0.isLeech }, sort: \Card.lapses, order: .reverse) private var leeches: [Card]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                ForEach(leeches) { c in
                    if let w = c.word {
                        NavigationLink { WordDetailView(word: w) } label: {
                            VStack(alignment: .leading) {
                                WordRow(word: w)
                                Text("\(c.direction.label) · \(c.lapses) lapses\(c.suspended ? " · suspended" : "")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Clear leech") { c.isLeech = false; c.suspended = false; try? context.save() }
                                .tint(.green)
                        }
                    }
                }
            } footer: {
                Text("A leech is a card you have forgotten \(AppSettings.leechThreshold)+ times. Add a mnemonic, then swipe to clear the flag.")
            }
        }
        .navigationTitle("Leeches")
    }
}
