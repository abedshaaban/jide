import SwiftData
import SwiftUI

struct DecksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var counts: [String: StudyQueue.Counts] = [:]
    @State private var studying: DeckScope?
    @State private var newDeckName = ""
    @State private var showNewDeck = false

    private let rankScopes: [DeckScope] = stride(from: 1, to: 1000, by: 100).map { .rankRange($0...($0 + 99)) }
    private let hskScopes: [DeckScope] = (1...6).map { .hsk($0) }

    var body: some View {
        NavigationStack {
            List {
                Section { row(.all) }
                Section("By frequency") { ForEach(rankScopes) { row($0) } }
                Section("HSK 2.0 level") { ForEach(hskScopes) { row($0) } }
                Section {
                    ForEach(decks) { d in
                        let scope = DeckScope.custom(d.id, d.name)
                        NavigationLink {
                            CustomDeckView(deck: d)
                        } label: {
                            DeckRowLabel(title: d.name, subtitle: "\(d.wordIDs.count) words", counts: counts[scope.id])
                        }
                        .swipeActions(edge: .leading) {
                            Button("Study") { studying = scope }.tint(.accentColor)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(decks[i]) }
                        try? context.save()
                    }
                    Button { showNewDeck = true } label: { Label("New deck", systemImage: "plus") }
                } header: {
                    Text("Custom")
                } footer: {
                    Text("Add words to a custom deck from a word's page. Swipe right on a deck to study it.")
                }
                Section { row(.leeches) }
            }
            .navigationTitle("Decks")
            .onAppear(perform: refresh)
            .fullScreenCover(item: $studying, onDismiss: refresh) { ReviewView(scope: $0) }
            .alert("New deck", isPresented: $showNewDeck) {
                TextField("Name", text: $newDeckName)
                Button("Create") {
                    let name = newDeckName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { context.insert(Deck(name: name)); try? context.save() }
                    newDeckName = ""
                }
                Button("Cancel", role: .cancel) { newDeckName = "" }
            }
        }
    }

    private func row(_ scope: DeckScope) -> some View {
        Button { studying = scope } label: {
            DeckRowLabel(title: scope.title, subtitle: nil, counts: counts[scope.id])
        }
        .foregroundStyle(.primary)
    }

    private func refresh() {
        var c: [String: StudyQueue.Counts] = [:]
        for s in [DeckScope.all, .leeches] + rankScopes + hskScopes + decks.map({ .custom($0.id, $0.name) }) {
            c[s.id] = StudyQueue.counts(s, context)
        }
        counts = c
    }
}

struct DeckRowLabel: View {
    var title: String
    var subtitle: String?
    var counts: StudyQueue.Counts?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let c = counts {
                HStack(spacing: 8) {
                    Text("\(c.new)").foregroundStyle(.blue)
                    Text("\(c.learning)").foregroundStyle(.orange)
                    Text("\(c.review)").foregroundStyle(.green)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }
}

struct CustomDeckView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]
    @State private var studying: DeckScope?

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: allWords.map { ($0.id, $0) })
        List {
            Section {
                TextField("Name", text: $deck.name)
                Button("Study this deck") { studying = .custom(deck.id, deck.name) }
                    .disabled(deck.wordIDs.isEmpty)
            }
            Section("\(deck.wordIDs.count) words") {
                ForEach(deck.wordIDs, id: \.self) { id in
                    if let w = byID[id] {
                        NavigationLink { WordDetailView(word: w) } label: { WordRow(word: w) }
                    }
                }
                .onDelete { idx in
                    deck.wordIDs.remove(atOffsets: idx)
                    try? context.save()
                }
            }
        }
        .navigationTitle(deck.name)
        .fullScreenCover(item: $studying) { ReviewView(scope: $0) }
    }
}
