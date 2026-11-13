import SwiftData
import SwiftUI

struct BrowseView: View {
    @Query(sort: \Word.rank) private var words: [Word]
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var showAdd = false

    enum Filter: String, CaseIterable {
        case all = "All", learning = "Studied", fresh = "New", custom = "Mine", notes = "Notes", leech = "Leeches"
    }

    var body: some View {
        NavigationStack {
            List(filtered) { w in
                NavigationLink { WordDetailView(word: w) } label: { WordRow(word: w) }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "汉字, pinyin or English")
            .navigationTitle("Words")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { NavigationStack { AddWordView() } }
        }
    }

    private var filtered: [Word] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let key = Pinyin.searchKey(q)
        return words.filter { w in
            switch filter {
            case .all: break
            case .learning: guard w.cards.contains(where: { $0.state != .new }) else { return false }
            case .fresh: guard w.cards.allSatisfy({ $0.state == .new }) else { return false }
            case .custom: guard w.isCustom else { return false }
            case .notes: guard !w.note.isEmpty || !w.mnemonic.isEmpty else { return false }
            case .leech: guard w.cards.contains(where: \.isLeech) else { return false }
            }
            guard !q.isEmpty else { return true }
            if w.simplified.contains(q) || w.traditional.contains(q) { return true }
            if !key.isEmpty && w.searchKey.hasPrefix(key) { return true }
            if q.count >= 2 && (w.gloss.lowercased().contains(q) || w.definitions.contains { $0.lowercased().contains(q) }) {
                return true
            }
            return false
        }
    }
}

struct WordRow: View {
    var word: Word
    var body: some View {
        HStack(spacing: 12) {
            Text(word.simplified).font(.title2).frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                PinyinText(numbered: word.pinyinNumbered, font: .subheadline)
                Text(word.shortMeaning).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(word.isCustom ? "mine" : "#\(word.rank)").font(.caption2).foregroundStyle(.secondary)
                if word.cards.contains(where: \.isLeech) { Image(systemName: "ant.fill").font(.caption2).foregroundStyle(.red) }
            }
        }
    }
}
