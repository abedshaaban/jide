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

/// A building block of the bundled words' characters (`components` in words.json).
struct BundledComponent: Codable {
    var char: String
    /// Rank of the first word that uses it.
    var rank: Int
    var pinyinNumbered: String
    var definition: String
    /// Already a bundled word, so it has cards of its own.
    var isWord: Bool
    var count: Int
    var usedIn: [String]

    var wordID: String { isWord ? Word.builtinID(char) : Word.componentID(char) }
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
    private(set) var components: [BundledComponent] = []
    /// Word IDs in the "Character parts" deck: parts, and bundled words that are also parts (女, 口).
    private(set) var componentWordIDs: Set<String> = []
    private var componentsByChar: [String: BundledComponent] = [:]
    /// HSK 2.0 level by word ID, for counting decks without reading words from the store.
    private(set) var hskByWordID: [String: Int] = [:]
    private(set) var dataVersion = 0
    private var sentencesBySimplified: [String: [Sentence]] = [:]
    private var characters: [String: CharacterInfo]?
    private let lock = NSLock()

    private init() {
        struct File: Codable { var version: Int; var words: [BundledWord]; var components: [BundledComponent]? }
        if let url = Bundle.main.url(forResource: "words", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            words = file.words
            dataVersion = file.version
            for w in file.words {
                sentencesBySimplified[w.simplified] = w.sentences
                if let h = w.hsk { hskByWordID[Word.builtinID(w.simplified)] = h }
            }
            components = file.components ?? []
            for c in components { componentsByChar[c.char] = c }
            componentWordIDs = Set(components.map(\.wordID))
        }
    }

    func component(_ char: String) -> BundledComponent? { componentsByChar[char] }

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

    /// Best-guess numbered pinyin from per-character readings, or "" if any character is unknown
    /// (a partial guess would silently drop syllables).
    func guessPinyin(_ text: String) -> String {
        var out: [String] = []
        for ch in text where !ch.isWhitespace {
            guard let p = character(ch)?.pinyin.first else { return "" }
            out.append(Pinyin.normalizeInput(p))
        }
        return out.joined(separator: " ")
    }
}

/// Inserts bundled words into SwiftData and keeps dictionary fields current without touching user data.
enum Seeder {
    static let versionKey = "seededDataVersion"

    enum Outcome: Equatable { case skipped, seeded(inserted: Int, updated: Int) }

    @MainActor
    @discardableResult
    static func run(_ context: ModelContext) -> Outcome {
        run(context, words: Library.shared.words, components: Library.shared.components,
            version: Library.shared.dataVersion, defaults: AppSettings.defaults)
    }

    /// Inserts missing bundled words and character parts (with their cards) and refreshes dictionary fields
    /// of existing ones. Notes, mnemonics, scheduling and custom words are never touched. Skips when this
    /// data version is done.
    @MainActor
    @discardableResult
    static func run(_ context: ModelContext, words bundled: [BundledWord], components: [BundledComponent] = [],
                    version: Int, defaults: UserDefaults) -> Outcome {
        let existingCount = (try? context.fetchCount(FetchDescriptor<Word>(predicate: #Predicate { !$0.isCustom }))) ?? 0
        if existingCount > 0 && defaults.integer(forKey: versionKey) >= version { return .skipped }

        let existing = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        var byID: [String: Word] = [:]
        for w in existing { byID[w.id] = w }
        var inserted = 0, updated = 0
        for bw in bundled {
            let id = Word.builtinID(bw.simplified)
            if let w = byID[id] {
                if w.rank != bw.rank { for c in w.cards { c.rank = bw.rank } }
                w.rank = bw.rank
                w.traditional = bw.traditional
                w.pinyinNumbered = bw.pinyinNumbered
                w.pinyin = Pinyin.marks(fromNumbered: bw.pinyinNumbered)
                w.gloss = bw.gloss
                w.definitions = bw.definitions
                w.hsk = bw.hsk
                w.hsk3 = bw.hsk3
                ensureCards(w, context)
                updated += 1
            } else {
                let w = Word(id: id, rank: bw.rank, simplified: bw.simplified, traditional: bw.traditional,
                             pinyinNumbered: bw.pinyinNumbered, gloss: bw.gloss, definitions: bw.definitions,
                             hsk: bw.hsk, hsk3: bw.hsk3)
                context.insert(w)
                byID[id] = w
                ensureCards(w, context)
                inserted += 1
            }
        }
        for c in components where !c.isWord {
            let id = Word.componentID(c.char)
            let defs = c.definition.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if let w = byID[id] {
                if w.rank != c.rank { for card in w.cards { card.rank = c.rank } }
                w.rank = c.rank
                w.pinyinNumbered = c.pinyinNumbered
                w.pinyin = Pinyin.marks(fromNumbered: c.pinyinNumbered)
                w.gloss = defs.first ?? c.definition
                w.definitions = defs
                ensureCards(w, context)
                updated += 1
            } else {
                let w = Word(id: id, rank: c.rank, simplified: c.char, traditional: c.char,
                             pinyinNumbered: c.pinyinNumbered, gloss: defs.first ?? c.definition, definitions: defs)
                context.insert(w)
                byID[id] = w
                ensureCards(w, context)
                inserted += 1
            }
        }
        do {
            try context.save()
            defaults.set(version, forKey: versionKey)
        } catch {
            // Leave the version unset so the next launch retries.
            context.rollback()
        }
        return .seeded(inserted: inserted, updated: updated)
    }

    @MainActor
    static func ensureCards(_ word: Word, _ context: ModelContext) {
        for d in word.directions where word.card(d) == nil {
            let c = Card(word: word, direction: d)
            context.insert(c)
            c.word = word
        }
    }

    /// Housekeeping after launch: recordings whose word was deleted.
    @MainActor
    static func pruneRecordings(_ context: ModelContext) {
        guard let words = try? context.fetch(FetchDescriptor<Word>()) else { return }
        RecordingStore.pruneOrphans(keeping: Set(words.map(\.id)))
    }
}
