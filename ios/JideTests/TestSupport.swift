import Foundation
import SwiftData
import XCTest
@testable import Jide

/// Fresh in-memory store, settings suite and recordings folder for each test.
@MainActor
class StoreTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        container = try Self.makeContainer()
        suiteName = "jide.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        AppSettings.defaults = defaults
        SettingsKey.registerDefaults(defaults)
        RecordingStore.baseDirectory = FileManager.default.temporaryDirectory.appending(path: "jide-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: RecordingStore.baseDirectory)
        container = nil
        try await super.tearDown()
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Word.self, Card.self, ReviewLog.self, Deck.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    static let fixture: [BundledWord] = [
        BundledWord(rank: 1, simplified: "你", traditional: "你", pinyin: "nǐ", pinyinNumbered: "ni3", gloss: "you",
                    definitions: ["you"], hsk: 1, hsk3: 1, sentences: []),
        BundledWord(rank: 2, simplified: "好", traditional: "好", pinyin: "hǎo", pinyinNumbered: "hao3", gloss: "good",
                    definitions: ["good", "well"], hsk: 1, hsk3: 1, sentences: []),
        BundledWord(rank: 3, simplified: "中国", traditional: "中國", pinyin: "Zhōng guó", pinyinNumbered: "Zhong1 guo2",
                    gloss: "China", definitions: ["China"], hsk: 1, hsk3: 1, sentences: []),
    ]

    @discardableResult
    func seedFixture(version: Int = 1) -> Seeder.Outcome {
        Seeder.run(context, words: Self.fixture, version: version, defaults: defaults)
    }

    func words() throws -> [Word] { try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.rank)])) }
    func cards() throws -> [Card] { try context.fetch(FetchDescriptor<Card>(sortBy: [SortDescriptor(\.id)])) }
    func word(_ simplified: String) throws -> Word {
        let id = Word.builtinID(simplified)
        return try XCTUnwrap(context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.id == id })).first)
    }
}

extension Calendar {
    static func fixed(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
