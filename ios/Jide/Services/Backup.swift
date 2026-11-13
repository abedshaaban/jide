import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Backup file, format "jide-backup" v1. Documented in shared/data/BACKUP_FORMAT.md; Android must match.
struct BackupFile: Codable {
    static let formatName = "jide-backup"
    static let currentVersion = 1

    struct WordEntry: Codable {
        var id: String
        var isCustom: Bool
        var note: String
        var mnemonic: String
        var createdAt: Date
        // Dictionary fields: present for custom words only.
        var rank: Int?
        var simplified: String?
        var traditional: String?
        var pinyinNumbered: String?
        var gloss: String?
        var definitions: [String]?
        var hsk: Int?
        var hsk3: Int?
    }

    struct CardEntry: Codable {
        var id: String
        var wordId: String
        var direction: String
        var state: Int
        var step: Int
        var stability: Double
        var difficulty: Double
        var due: Date
        var reps: Int
        var lapses: Int
        var lastReview: Date?
        var suspended: Bool
        var leech: Bool
    }

    struct LogEntry: Codable {
        var id: UUID
        var date: Date
        var cardId: String
        var rating: Int
        var stateBefore: Int
        var elapsedDays: Double
        var scheduledDays: Double
        var durationMs: Int
    }

    struct DeckEntry: Codable {
        var id: UUID
        var name: String
        var wordIds: [String]
        var createdAt: Date
    }

    struct RecordingEntry: Codable {
        var wordId: String
        var mimeType: String
        var data: Data  // base64 in JSON
    }

    var format: String = formatName
    var version: Int = currentVersion
    var exportedAt: Date
    var platform: String
    var settings: [String: SettingValue]
    var words: [WordEntry]
    var cards: [CardEntry]
    var reviewLogs: [LogEntry]
    var decks: [DeckEntry]
    var recordings: [RecordingEntry]
}

/// A JSON scalar for settings.
enum SettingValue: Codable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        }
    }

    var any: Any {
        switch self {
        case .bool(let b): b
        case .int(let i): i
        case .double(let d): d
        case .string(let s): s
        }
    }

    init?(_ value: Any) {
        // NSNumber bridging: check Bool first via CFBoolean type.
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
            else { self = .int(n.intValue) }
        } else if let s = value as? String {
            self = .string(s)
        } else {
            return nil
        }
    }
}

enum BackupService {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @MainActor
    static func export(_ context: ModelContext) throws -> Data {
        let words = try context.fetch(FetchDescriptor<Word>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.date)]))
        let decks = try context.fetch(FetchDescriptor<Deck>())

        var settings: [String: SettingValue] = [:]
        for k in SettingsKey.exported {
            if let v = UserDefaults.standard.object(forKey: k), let sv = SettingValue(v) { settings[k] = sv }
        }

        let file = BackupFile(
            exportedAt: Date(),
            platform: "ios",
            settings: settings,
            words: words.filter { $0.isCustom || !$0.note.isEmpty || !$0.mnemonic.isEmpty }.map { w in
                BackupFile.WordEntry(
                    id: w.id, isCustom: w.isCustom, note: w.note, mnemonic: w.mnemonic, createdAt: w.createdAt,
                    rank: w.isCustom ? w.rank : nil, simplified: w.isCustom ? w.simplified : nil,
                    traditional: w.isCustom ? w.traditional : nil, pinyinNumbered: w.isCustom ? w.pinyinNumbered : nil,
                    gloss: w.isCustom ? w.gloss : nil, definitions: w.isCustom ? w.definitions : nil,
                    hsk: w.isCustom ? w.hsk : nil, hsk3: w.isCustom ? w.hsk3 : nil)
            },
            cards: cards.filter { $0.reps > 0 || $0.suspended || $0.state != .new }.compactMap { c in
                guard let w = c.word else { return nil }
                return BackupFile.CardEntry(
                    id: c.id, wordId: w.id, direction: c.directionRaw, state: c.stateRaw, step: c.step,
                    stability: c.stability, difficulty: c.difficulty, due: c.due, reps: c.reps, lapses: c.lapses,
                    lastReview: c.lastReview, suspended: c.suspended, leech: c.isLeech)
            },
            reviewLogs: logs.map {
                BackupFile.LogEntry(id: $0.id, date: $0.date, cardId: $0.cardID, rating: $0.rating,
                                    stateBefore: $0.stateBefore, elapsedDays: $0.elapsedDays,
                                    scheduledDays: $0.scheduledDays, durationMs: $0.durationMs)
            },
            decks: decks.map { .init(id: $0.id, name: $0.name, wordIds: $0.wordIDs, createdAt: $0.createdAt) },
            recordings: RecordingStore.all().compactMap { r in
                guard let data = try? Data(contentsOf: r.url) else { return nil }
                return .init(wordId: r.wordID, mimeType: "audio/mp4", data: data)
            })
        return try encoder().encode(file)
    }

    struct ImportSummary {
        var words = 0, cards = 0, logs = 0, decks = 0, recordings = 0
        var text: String {
            "Imported \(cards) cards, \(logs) reviews, \(words) notes/custom words, \(decks) decks, \(recordings) recordings."
        }
    }

    enum ImportError: LocalizedError {
        case notABackup, newerVersion(Int)
        var errorDescription: String? {
            switch self {
            case .notABackup: "This file is not a 记得 backup."
            case .newerVersion(let v): "Backup version \(v) is newer than this app supports."
            }
        }
    }

    /// Merges a backup into the store. Entries in the backup win over local ones with the same ID.
    @MainActor
    static func importBackup(_ data: Data, into context: ModelContext) throws -> ImportSummary {
        let file = try decoder().decode(BackupFile.self, from: data)
        guard file.format == BackupFile.formatName else { throw ImportError.notABackup }
        guard file.version <= BackupFile.currentVersion else { throw ImportError.newerVersion(file.version) }
        var sum = ImportSummary()

        Seeder.run(context)
        var words = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Word>()).map { ($0.id, $0) })
        for e in file.words {
            let w: Word
            if let existing = words[e.id] {
                w = existing
            } else if e.isCustom, let simp = e.simplified {
                w = Word(id: e.id, rank: e.rank ?? 100_000, simplified: simp, traditional: e.traditional ?? simp,
                         pinyinNumbered: e.pinyinNumbered ?? "", gloss: e.gloss ?? "", definitions: e.definitions ?? [],
                         hsk: e.hsk, hsk3: e.hsk3, isCustom: true)
                context.insert(w)
                Seeder.ensureCards(w, context)
                words[e.id] = w
            } else {
                continue
            }
            if e.isCustom, let simp = e.simplified {
                w.simplified = simp
                w.traditional = e.traditional ?? simp
                w.pinyinNumbered = e.pinyinNumbered ?? w.pinyinNumbered
                w.pinyin = Pinyin.marks(fromNumbered: w.pinyinNumbered)
                w.gloss = e.gloss ?? w.gloss
                w.definitions = e.definitions ?? w.definitions
            }
            w.note = e.note
            w.mnemonic = e.mnemonic
            w.createdAt = e.createdAt
            sum.words += 1
        }

        var cards = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Card>()).map { ($0.id, $0) })
        for e in file.cards {
            var card = cards[e.id]
            if card == nil, let w = words[e.wordId], let d = Direction(rawValue: e.direction) {
                let c = Card(word: w, direction: d)
                context.insert(c)
                c.word = w
                cards[c.id] = c
                card = c
            }
            guard let c = card else { continue }
            c.scheduling = SchedulingInfo(state: CardState(rawValue: e.state) ?? .new, step: e.step, stability: e.stability,
                                          difficulty: e.difficulty, due: e.due, reps: e.reps, lapses: e.lapses,
                                          lastReview: e.lastReview)
            c.suspended = e.suspended
            c.isLeech = e.leech
            sum.cards += 1
        }

        let existingLogs = Set(try context.fetch(FetchDescriptor<ReviewLog>()).map(\.id))
        for e in file.reviewLogs where !existingLogs.contains(e.id) {
            context.insert(ReviewLog(id: e.id, date: e.date, cardID: e.cardId, rating: e.rating, stateBefore: e.stateBefore,
                                     elapsedDays: e.elapsedDays, scheduledDays: e.scheduledDays, durationMs: e.durationMs))
            sum.logs += 1
        }

        let decks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Deck>()).map { ($0.id, $0) })
        for e in file.decks {
            if let d = decks[e.id] {
                d.name = e.name
                d.wordIDs = e.wordIds
            } else {
                context.insert(Deck(id: e.id, name: e.name, wordIDs: e.wordIds, createdAt: e.createdAt))
            }
            sum.decks += 1
        }

        for r in file.recordings {
            try r.data.write(to: RecordingStore.url(for: r.wordId), options: .atomic)
            sum.recordings += 1
        }

        for (k, v) in file.settings where SettingsKey.exported.contains(k) {
            UserDefaults.standard.set(v.any, forKey: k)
        }
        try context.save()
        Reminders.refresh()
        return sum
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
