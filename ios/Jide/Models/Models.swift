import Foundation
import SwiftData

enum Direction: String, CaseIterable, Codable, Identifiable {
    case hanziToMeaning = "hanzi_meaning"
    case meaningToHanzi = "meaning_hanzi"
    case audioToHanzi = "audio_hanzi"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .hanziToMeaning: "汉字 → meaning"
        case .meaningToHanzi: "Meaning → 汉字"
        case .audioToHanzi: "Audio → 汉字"
        }
    }
    var order: Int { Direction.allCases.firstIndex(of: self)! }
}

@Model
final class Word {
    /// "zh:<simplified>" for bundled words, "custom:<uuid>" for words the owner added.
    @Attribute(.unique) var id: String
    var rank: Int
    var simplified: String
    var traditional: String
    var pinyin: String
    var pinyinNumbered: String
    var gloss: String
    var definitions: [String]
    var hsk: Int?
    var hsk3: Int?
    var isCustom: Bool
    var note: String = ""
    var mnemonic: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Card.word) var cards: [Card] = []

    init(id: String, rank: Int, simplified: String, traditional: String, pinyinNumbered: String,
         gloss: String, definitions: [String], hsk: Int? = nil, hsk3: Int? = nil, isCustom: Bool = false) {
        self.id = id
        self.rank = rank
        self.simplified = simplified
        self.traditional = traditional
        self.pinyinNumbered = pinyinNumbered
        self.pinyin = Pinyin.marks(fromNumbered: pinyinNumbered)
        self.gloss = gloss
        self.definitions = definitions
        self.hsk = hsk
        self.hsk3 = hsk3
        self.isCustom = isCustom
    }

    static func builtinID(_ simplified: String) -> String { "zh:\(simplified)" }

    /// Short meaning for the front of meaning→汉字 cards.
    var shortMeaning: String {
        let defs = definitions.prefix(3).joined(separator: "; ")
        return defs.isEmpty ? gloss : defs
    }

    var syllables: [Pinyin.Syllable] { Pinyin.syllables(numbered: pinyinNumbered) }

    func card(_ d: Direction) -> Card? { cards.first { $0.direction == d } }

    var searchKey: String { Pinyin.searchKey(pinyin) }
}

@Model
final class Card {
    /// "<wordID>|<direction>"
    @Attribute(.unique) var id: String
    var word: Word?
    var directionRaw: String
    var rank: Int
    var stateRaw: Int = 0
    var step: Int = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = Date.distantPast
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?
    var suspended: Bool = false
    var isLeech: Bool = false

    init(word: Word, direction: Direction) {
        // `word` is set after insertion (see Seeder.ensureCards) so SwiftData maintains the inverse.
        self.id = "\(word.id)|\(direction.rawValue)"
        self.directionRaw = direction.rawValue
        self.rank = word.rank
    }

    var direction: Direction { Direction(rawValue: directionRaw) ?? .hanziToMeaning }
    var state: CardState { CardState(rawValue: stateRaw) ?? .new }

    var scheduling: SchedulingInfo {
        get {
            SchedulingInfo(state: state, step: step, stability: stability, difficulty: difficulty, due: due,
                           reps: reps, lapses: lapses, lastReview: lastReview)
        }
        set {
            stateRaw = newValue.state.rawValue
            step = newValue.step
            stability = newValue.stability
            difficulty = newValue.difficulty
            due = newValue.due
            reps = newValue.reps
            lapses = newValue.lapses
            lastReview = newValue.lastReview
        }
    }

    func reset() {
        scheduling = SchedulingInfo()
        isLeech = false
    }
}

@Model
final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var cardID: String
    var rating: Int
    var stateBefore: Int
    var elapsedDays: Double
    var scheduledDays: Double
    var durationMs: Int

    init(id: UUID = UUID(), date: Date, cardID: String, rating: Int, stateBefore: Int, elapsedDays: Double,
         scheduledDays: Double, durationMs: Int) {
        self.id = id
        self.date = date
        self.cardID = cardID
        self.rating = rating
        self.stateBefore = stateBefore
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.durationMs = durationMs
    }
}

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var wordIDs: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, wordIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.wordIDs = wordIDs
        self.createdAt = createdAt
    }
}

/// What a study session draws cards from.
enum DeckScope: Hashable, Identifiable {
    case all
    case rankRange(ClosedRange<Int>)
    case hsk(Int)
    case custom(UUID, String)
    case leeches

    var id: String {
        switch self {
        case .all: "all"
        case .rankRange(let r): "rank:\(r.lowerBound)-\(r.upperBound)"
        case .hsk(let l): "hsk:\(l)"
        case .custom(let id, _): "custom:\(id)"
        case .leeches: "leeches"
        }
    }

    var title: String {
        switch self {
        case .all: "All words"
        case .rankRange(let r): "Top \(r.lowerBound)–\(r.upperBound)"
        case .hsk(let l): "HSK \(l)"
        case .custom(_, let name): name
        case .leeches: "Leeches"
        }
    }

    func contains(_ card: Card, customWordIDs: Set<String>) -> Bool {
        guard let word = card.word else { return false }
        return contains(wordID: word.id, isCustom: word.isCustom, rank: word.rank, hsk: word.hsk,
                        isLeech: card.isLeech, customWordIDs: customWordIDs)
    }

    func contains(wordID: String, isCustom: Bool, rank: Int, hsk: Int?, isLeech: Bool,
                  customWordIDs: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .rankRange(let r): !isCustom && r.contains(rank)
        case .hsk(let l): hsk == l
        case .custom: customWordIDs.contains(wordID)
        case .leeches: isLeech
        }
    }
}
