import SwiftData
import SwiftUI

struct WordDetailView: View {
    @Bindable var word: Word
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var confirmDelete = false
    @State private var editing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HanziText(hanzi: word.simplified, numbered: word.pinyinNumbered, size: 64)
                    PinyinText(numbered: word.pinyinNumbered, font: .title2)
                    HStack(spacing: 8) {
                        if word.traditional != word.simplified { Tag(text: "繁 \(word.traditional)") }
                        if !word.isCustom { Tag(text: "#\(word.rank)") }
                        if let h = word.hsk { Tag(text: "HSK \(h)") }
                        if word.isCustom { Tag(text: "My word") }
                    }
                    SpeakButtons(text: word.simplified)
                }
                .padding(.vertical, 4)
            }

            Section("Meaning") {
                ForEach(Array(word.definitions.enumerated()), id: \.offset) { _, d in Text(d) }
                if !word.gloss.isEmpty && !word.isCustom {
                    Text(word.gloss).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Pronunciation practice") {
                PronunciationPractice(word: word)
                    .padding(.vertical, 4)
            }

            Section {
                TextField("Mnemonic: a story or image to remember it", text: $word.mnemonic, axis: .vertical)
                    .accessibilityIdentifier("word.mnemonic")
                TextField("Notes", text: $word.note, axis: .vertical)
                    .accessibilityIdentifier("word.note")
            } header: {
                Text("Notes & mnemonic")
            }

            Section("Characters") {
                ForEach(Array(Set(word.simplified)).sorted(by: { a, b in
                    word.simplified.firstIndex(of: a)! < word.simplified.firstIndex(of: b)!
                }), id: \.self) { ch in
                    NavigationLink { CharacterDetailView(character: ch) } label: {
                        ComponentRow(character: ch, expandable: false)
                    }
                    .accessibilityIdentifier("char.\(ch)")
                }
            }

            let sentences = Library.shared.sentences(for: word.simplified)
            if !sentences.isEmpty {
                Section {
                    ForEach(sentences) { SentenceRow(sentence: $0) }
                } header: {
                    Text("Examples")
                } footer: {
                    Text("Sentences from Tatoeba (CC BY). Tap to hear. Sentence pinyin is machine-generated.")
                }
            }

            Section("Cards") {
                ForEach(word.cards.sorted { $0.direction.order < $1.direction.order }) { c in
                    CardStatusRow(card: c)
                }
            }

            Section("Decks") {
                if decks.isEmpty {
                    Text("Create a custom deck in the Decks tab.").foregroundStyle(.secondary)
                }
                ForEach(decks) { d in
                    Button {
                        if let i = d.wordIDs.firstIndex(of: word.id) { d.wordIDs.remove(at: i) } else { d.wordIDs.append(word.id) }
                        try? context.save()
                    } label: {
                        HStack {
                            Text(d.name).foregroundStyle(.primary)
                            Spacer()
                            if d.wordIDs.contains(word.id) { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("word.deck.\(d.name)")
                    .accessibilityValue(d.wordIDs.contains(word.id) ? "in deck" : "not in deck")
                }
            }

            if word.isCustom {
                Section {
                    Button("Edit word") { editing = true }
                    Button("Delete word", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(word.simplified)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .sheet(isPresented: $editing) { NavigationStack { AddWordView(editing: word) } }
        .confirmationDialog("Delete \(word.simplified)? Its progress and recording are removed.", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                VoiceRecorder.current?.stop()
                RecordingStore.delete(word.id)
                for d in decks { d.wordIDs.removeAll { $0 == word.id } }
                context.delete(word)
                try? context.save()
                dismiss()
            }
        }
    }
}

struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

struct CardStatusRow: View {
    @Bindable var card: Card
    @Environment(\.modelContext) private var context
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.direction.label)
                if card.isLeech { Image(systemName: "ant.fill").foregroundStyle(.red) }
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if card.state != .new {
                Text(String(format: "Reviews %d · lapses %d · stability %.1fd · difficulty %.1f",
                            card.reps, card.lapses, card.stability, card.difficulty))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(card.suspended ? "Unsuspend" : "Suspend") {
                card.suspended.toggle()
                try? context.save()
            }
            .tint(.orange)
            Button("Reset") { confirmReset = true }.tint(.red)
        }
        .confirmationDialog("Reset this card to new?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { card.reset(); try? context.save() }
        }
    }

    private var status: String {
        if card.suspended { return "suspended" }
        switch card.state {
        case .new: return "new"
        case .learning, .relearning: return "learning"
        case .review:
            return card.due <= Date() ? "due" : "due in \(formatInterval(from: Date(), to: card.due))"
        }
    }
}

struct AddWordView: View {
    var editing: Word?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var hanzi = ""
    @State private var pinyin = ""
    @State private var meaning = ""
    @State private var deckID: UUID?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("汉字", text: $hanzi)
                    .font(.title2)
                    .accessibilityIdentifier("add.hanzi")
                    .onChange(of: hanzi) { _, new in
                        if editing == nil { pinyin = Pinyin.marks(fromNumbered: Library.shared.guessPinyin(new)) }
                    }
                TextField("Pinyin, e.g. ni3 hao3 or nǐ hǎo", text: $pinyin)
                    .accessibilityIdentifier("add.pinyin")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !pinyin.isEmpty { PinyinText(numbered: Pinyin.normalizeInput(pinyin)) }
                TextField("Meaning (separate senses with ;)", text: $meaning, axis: .vertical)
                    .accessibilityIdentifier("add.meaning")
            } footer: {
                Text("Pinyin is guessed from each character; check polyphonic ones. Separate syllables with spaces.")
            }
            if editing == nil && !decks.isEmpty {
                Picker("Add to deck", selection: $deckID) {
                    Text("None").tag(UUID?.none)
                    ForEach(decks) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(editing == nil ? "New word" : "Edit word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).accessibilityIdentifier("add.save")
            }
        }
        .onAppear {
            if let w = editing {
                hanzi = w.simplified
                pinyin = w.pinyin
                meaning = w.definitions.joined(separator: "; ")
            }
        }
    }

    private func save() {
        let h = hanzi.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !m.isEmpty else { error = "汉字 and meaning are required."; return }
        let numbered = Pinyin.normalizeInput(pinyin)
        let defs = m.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let w = editing {
            w.simplified = h
            w.traditional = h
            w.pinyinNumbered = numbered
            w.pinyin = Pinyin.marks(fromNumbered: numbered)
            w.definitions = defs
            w.gloss = defs.first ?? m
        } else {
            let builtinID = Word.builtinID(h)
            let exists = (try? context.fetchCount(FetchDescriptor<Word>(predicate: #Predicate { $0.id == builtinID }))) ?? 0
            if exists > 0 { error = "\(h) is already in the top 1000. Find it in Words."; return }
            let count = (try? context.fetchCount(FetchDescriptor<Word>(predicate: #Predicate { $0.isCustom }))) ?? 0
            let w = Word(id: "custom:\(UUID().uuidString)", rank: 100_000 + count, simplified: h, traditional: h,
                         pinyinNumbered: numbered, gloss: defs.first ?? m, definitions: defs, isCustom: true)
            context.insert(w)
            Seeder.ensureCards(w, context)
            if let id = deckID, let d = decks.first(where: { $0.id == id }) { d.wordIDs.append(w.id) }
        }
        try? context.save()
        dismiss()
    }
}
