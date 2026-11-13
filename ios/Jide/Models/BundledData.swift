import Foundation
import SwiftData

struct Sentence: Codable, Hashable, Identifiable {
    var id: Int
    var zh: String
    var pinyin: String
    var en: String
}

struct BundledWord: Codable {
    var rank: Int
    var simplified: String
    var traditional: String
    var pinyin: String
    var pinyinNumbered: String
    var gloss: String
    var definitions: [String]
    var hsk: Int?
    var hsk3: Int?
    var sentences: [Sentence]
}

struct CharacterInfo: Codable {
    struct Etymology: Codable {
        var type: String?
        var hint: String?
        var phonetic: String?
        var semantic: String?
    }
    var definition: String?
    var pinyin: [String]
    var decomposition: String
    var radical: String
    var etymology: Etymology?
    var strokes: [String]?
    var medians: [[[Double]]]?

    /// Direct components from the Ideographic Description Sequence.
    var components: [Character] {
        decomposition.filter { ch in
            guard let v = ch.unicodeScalars.first?.value else { return false }
            return !(0x2FF0...0x2FFF).contains(v) && ch != "？"
        }.map { $0 }
    }
}

/// Read-only data shipped in the app bundle (shared/data).
final class Library {
    static let shared = Library()

    private(set) var words: [BundledWord] = []
    private(set) var dataVersion = 0
    private var sentencesBySimplified: [String: [Sentence]] = [:]
    private var characters: [String: CharacterInfo]?
    private let lock = NSLock()

    private init() {
        struct File: Codable { var version: Int; var words: [BundledWord] }
        if let url = Bundle.main.url(forResource: "words", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            words = file.words
            dataVersion = file.version
            for w in file.words { sentencesBySimplified[w.simplified] = w.sentences }
        }
    }

    func sentences(for simplified: String) -> [Sentence] {
        if let s = sentencesBySimplified[simplified] { return s }
        return []
    }

    func character(_ ch: Character) -> CharacterInfo? {
        loadCharacters()[String(ch)]
    }

    /// Loads characters.json (1.7 MB) on first use; call `preload()` early to warm it off the main thread.
    private func loadCharacters() -> [String: CharacterInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let c = characters { return c }
        struct File: Codable { var characters: [String: CharacterInfo] }
        var result: [String: CharacterInfo] = [:]
        if let url = Bundle.main.url(forResource: "characters", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            result = file.characters
        }
        characters = result
        return result
    }

    func preload() {
        DispatchQueue.global(qos: .utility).async { _ = self.loadCharacters() }
    }

    /// Best-guess numbered pinyin for arbitrary text, from per-character readings.
    func guessPinyin(_ text: String) -> String {
        text.compactMap { ch -> String? in
            guard let p = character(ch)?.pinyin.first else { return nil }
            return Pinyin.normalizeInput(p)
        }.joined(separator: " ")
    }
}

/// Inserts bundled words into SwiftData and keeps dictionary fields current without touching user data.
enum Seeder {
    private static let key = "seededDataVersion"

    @MainActor
    static func run(_ context: ModelContext) {
        let lib = Library.shared
        let existingCount = (try? context.fetchCount(FetchDescriptor<Word>())) ?? 0
        if existingCount > 0 && UserDefaults.standard.integer(forKey: key) >= lib.dataVersion { return }

        let existing = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for bw in lib.words {
            let id = Word.builtinID(bw.simplified)
            if let w = byID[id] {
                w.rank = bw.rank
                w.traditional = bw.traditional
                w.pinyinNumbered = bw.pinyinNumbered
                w.pinyin = Pinyin.marks(fromNumbered: bw.pinyinNumbered)
                w.gloss = bw.gloss
                w.definitions = bw.definitions
                w.hsk = bw.hsk
                w.hsk3 = bw.hsk3
                for c in w.cards { c.rank = bw.rank }
                ensureCards(w, context)
            } else {
                let w = Word(id: id, rank: bw.rank, simplified: bw.simplified, traditional: bw.traditional,
                             pinyinNumbered: bw.pinyinNumbered, gloss: bw.gloss, definitions: bw.definitions,
                             hsk: bw.hsk, hsk3: bw.hsk3)
                context.insert(w)
                byID[id] = w
                ensureCards(w, context)
            }
        }
        try? context.save()
        UserDefaults.standard.set(lib.dataVersion, forKey: key)
    }

    static func ensureCards(_ word: Word, _ context: ModelContext) {
        for d in Direction.allCases where word.card(d) == nil {
            let c = Card(word: word, direction: d)
            context.insert(c)
            c.word = word
        }
    }
}
