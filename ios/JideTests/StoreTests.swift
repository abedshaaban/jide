import SwiftData
import UserNotifications
import XCTest
@testable import Jide

@MainActor
final class SeederTests: StoreTestCase {
    func testSeedsOnceWithThreeCardsPerWord() throws {
        XCTAssertEqual(seedFixture(), .seeded(inserted: 3, updated: 0))
        XCTAssertEqual(try words().count, 3)
        XCTAssertEqual(try cards().count, 9)
        XCTAssertTrue(try words().allSatisfy { $0.cards.count == 3 })
        XCTAssertEqual(defaults.integer(forKey: Seeder.versionKey), 1)
    }

    func testRelaunchDoesNotDuplicate() throws {
        seedFixture()
        XCTAssertEqual(seedFixture(), .skipped)
        // Even if the version flag is lost (e.g. settings reset), seeding upserts instead of duplicating.
        defaults.removeObject(forKey: Seeder.versionKey)
        XCTAssertEqual(seedFixture(), .seeded(inserted: 0, updated: 3))
        XCTAssertEqual(try words().count, 3)
        XCTAssertEqual(try cards().count, 9)
    }

    func testVersionBumpUpdatesDictionaryAndKeepsProgressAndNotes() throws {
        seedFixture(version: 1)
        let ni = try word("你")
        ni.note = "my note"
        ni.mnemonic = "a person 亻 pointing at you"
        let card = try XCTUnwrap(ni.card(.hanziToMeaning))
        let progress = SchedulingInfo(state: .review, step: 0, stability: 12, difficulty: 4,
                                      due: Date(timeIntervalSince1970: 2_000_000_000), reps: 6, lapses: 1,
                                      lastReview: Date(timeIntervalSince1970: 1_999_000_000))
        card.scheduling = progress
        card.isLeech = true
        let custom = Word(id: "custom:1", rank: 100_000, simplified: "火锅", traditional: "火鍋", pinyinNumbered: "huo3 guo1",
                          gloss: "hot pot", definitions: ["hot pot"], isCustom: true)
        context.insert(custom)
        try context.save()

        var v2 = Self.fixture
        v2[0].definitions = ["you (informal)"]
        v2[0].rank = 2
        v2[1].rank = 1
        v2.append(BundledWord(rank: 4, simplified: "吗", traditional: "嗎", pinyin: "ma", pinyinNumbered: "ma5",
                              gloss: "question particle", definitions: ["(question particle)"], hsk: 1, hsk3: 1, sentences: []))
        XCTAssertEqual(Seeder.run(context, words: v2, version: 2, defaults: defaults), .seeded(inserted: 1, updated: 3))

        XCTAssertEqual(try words().filter { !$0.isCustom }.count, 4)
        XCTAssertEqual(try cards().count, 12, "4 bundled words x 3 directions")
        let after = try word("你")
        XCTAssertEqual(after.definitions, ["you (informal)"])
        XCTAssertEqual(after.rank, 2)
        XCTAssertTrue(after.cards.allSatisfy { $0.rank == 2 }, "Card rank follows the word for new-card order")
        XCTAssertEqual(after.note, "my note")
        XCTAssertEqual(after.mnemonic, "a person 亻 pointing at you")
        XCTAssertEqual(after.card(.hanziToMeaning)?.scheduling, progress)
        XCTAssertEqual(after.card(.hanziToMeaning)?.isLeech, true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.isCustom })).first?.simplified, "火锅")
        XCTAssertEqual(defaults.integer(forKey: Seeder.versionKey), 2)
    }

    func testRealBundledDataSeeds() throws {
        let lib = Library.shared
        let parts = lib.components.filter { !$0.isWord }.count
        XCTAssertEqual(lib.words.count, 3000)
        XCTAssertGreaterThan(parts, 100)
        let outcome = Seeder.run(context, words: lib.words, components: lib.components, version: lib.dataVersion,
                                 defaults: defaults)
        XCTAssertEqual(outcome, .seeded(inserted: 3000 + parts, updated: 0))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Card>()), 9000 + parts, "Parts get one card")
        XCTAssertEqual(Seeder.run(context, words: lib.words, components: lib.components, version: lib.dataVersion,
                                  defaults: defaults), .skipped)
    }

    /// Going from the 1000-word list to 3000 words plus parts must leave what was learned alone.
    func testGrowingTheListKeepsProgress() throws {
        let lib = Library.shared
        Seeder.run(context, words: Array(lib.words.prefix(1000)), version: 3, defaults: defaults)
        let hao = try word("好")
        hao.mnemonic = "woman + child"
        let progress = SchedulingInfo(state: .review, step: 0, stability: 30, difficulty: 5,
                                      due: Date(timeIntervalSince1970: 2_000_000_000), reps: 9, lapses: 0,
                                      lastReview: Date(timeIntervalSince1970: 1_999_000_000))
        try XCTUnwrap(hao.card(.audioToHanzi)).scheduling = progress
        try context.save()

        let parts = lib.components.filter { !$0.isWord }.count
        XCTAssertEqual(Seeder.run(context, words: lib.words, components: lib.components, version: lib.dataVersion,
                                  defaults: defaults), .seeded(inserted: 2000 + parts, updated: 1000))
        let after = try word("好")
        XCTAssertEqual(after.mnemonic, "woman + child")
        XCTAssertEqual(after.card(.audioToHanzi)?.scheduling, progress)
        XCTAssertEqual(after.cards.count, 3)
    }

    func testPartsAreTaughtRightBeforeTheWordThatUsesThem() throws {
        let part = BundledComponent(char: "亻", rank: 1, pinyinNumbered: "ren2", definition: "man, person; people",
                                    isWord: false, count: 3, usedIn: ["你"])
        let alsoWord = BundledComponent(char: "好", rank: 2, pinyinNumbered: "hao3", definition: "good", isWord: true,
                                        count: 3, usedIn: [])
        XCTAssertEqual(Seeder.run(context, words: Self.fixture, components: [part, alsoWord], version: 1, defaults: defaults),
                       .seeded(inserted: 4, updated: 0), "A part that is already a word gets no second entry")
        let w = try XCTUnwrap(try words().first { $0.id == "cmp:亻" })
        XCTAssertTrue(w.isComponent)
        XCTAssertEqual(w.cards.map(\.direction), [.hanziToMeaning])
        XCTAssertEqual(w.definitions, ["man, person", "people"])
        XCTAssertEqual(w.pinyin, "rén")

        func newCards(_ scope: DeckScope) throws -> [String] {
            StudyQueue.select(from: try cards(), scope: scope, customWordIDs: [], enabled: Set(Direction.allCases),
                              newRemaining: 2, now: Date()).new.map(\.id)
        }
        XCTAssertEqual(try newCards(.all), ["cmp:亻|hanzi_meaning", "zh:你|hanzi_meaning"])
        XCTAssertEqual(try newCards(.rankRange(1...100)).first, "cmp:亻|hanzi_meaning")
        defaults.set(false, forKey: SettingsKey.teachComponents)
        XCTAssertEqual(try newCards(.all), ["zh:你|hanzi_meaning", "zh:你|meaning_hanzi"], "Switched off in Settings")
    }

    func testRealPartsDeck() throws {
        let lib = Library.shared
        XCTAssertEqual(lib.component("女")?.isWord, true)
        XCTAssertTrue(lib.componentWordIDs.contains("zh:女"), "Words that are parts are in the parts deck too")
        XCTAssertTrue(lib.componentWordIDs.contains("cmp:扌"))
        XCTAssertNil(lib.component("丨"), "Single strokes are not taught")
        for c in lib.components {
            XCTAssertFalse(c.definition.isEmpty, c.char)
            XCTAssertGreaterThanOrEqual(c.count, 3, c.char)
            XCTAssertNotNil(HanziGraphics(lib.character(Character(c.char))), "\(c.char) has stroke data")
        }
    }
}

@MainActor
final class BackupTests: StoreTestCase {
    struct Snapshot: Equatable {
        var words: [String]
        var cards: [String]
        var logs: [String]
        var decks: [String]
        var settings: [String]
        var recordings: [String: Data]
    }

    private func ms(_ d: Date?) -> String { d.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? "nil" }

    func snapshot() throws -> Snapshot {
        let ws = try context.fetch(FetchDescriptor<Word>()).sorted { $0.id < $1.id }.map {
            "\($0.id)|\($0.isCustom)|\($0.note)|\($0.mnemonic)|\($0.simplified)|\($0.pinyinNumbered)|\($0.definitions)|\($0.isCustom || !$0.note.isEmpty ? ms($0.createdAt) : "-")"
        }
        let cs = try cards().map {
            "\($0.id)|\($0.stateRaw)|\($0.step)|\($0.stability)|\($0.difficulty)|\(ms($0.due))|\($0.reps)|\($0.lapses)|\(ms($0.lastReview))|\($0.suspended)|\($0.isLeech)"
        }
        let ls = try context.fetch(FetchDescriptor<ReviewLog>()).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\(ms($0.date))|\($0.cardID)|\($0.rating)|\($0.stateBefore)|\($0.elapsedDays)|\($0.scheduledDays)|\($0.durationMs)"
        }
        let ds = try context.fetch(FetchDescriptor<Deck>()).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.name)|\($0.wordIDs)|\(ms($0.createdAt))"
        }
        let ss = SettingsKey.exported.map { "\($0)=\(defaults.object(forKey: $0).map { "\($0)" } ?? "nil")" }
        var recs: [String: Data] = [:]
        for r in RecordingStore.all() { recs[r.wordID] = try Data(contentsOf: r.url) }
        return Snapshot(words: ws, cards: cs, logs: ls, decks: ds, settings: ss, recordings: recs)
    }

    /// Progress, history, notes, a custom word, a deck, changed settings and two recordings.
    func populate() throws {
        seedFixture()
        let ni = try word("你")
        ni.note = "note ✓"
        ni.mnemonic = "mnemonic"
        let c = try XCTUnwrap(ni.card(.meaningToHanzi))
        c.scheduling = SchedulingInfo(state: .review, step: 0, stability: 3.141592653589793, difficulty: 6.02214076,
                                      due: Date().addingTimeInterval(86400 * 2.123456), reps: 4, lapses: 2,
                                      lastReview: Date().addingTimeInterval(-123.456))
        c.isLeech = true
        try word("好").card(.audioToHanzi)?.suspended = true
        let custom = Word(id: "custom:ABC", rank: 100_000, simplified: "火锅", traditional: "火鍋", pinyinNumbered: "huo3 guo1",
                          gloss: "hot pot", definitions: ["hot pot", "fondue"], isCustom: true)
        context.insert(custom)
        Seeder.ensureCards(custom, context)
        custom.card(.hanziToMeaning)?.scheduling = SchedulingInfo(state: .learning, step: 1, stability: 2, difficulty: 5,
                                                                  due: Date().addingTimeInterval(600), reps: 1)
        for i in 0..<5 {
            context.insert(ReviewLog(date: Date().addingTimeInterval(Double(-i) * 3600.5), cardID: c.id, rating: i % 4 + 1,
                                     stateBefore: i % 3, elapsedDays: Double(i) / 3, scheduledDays: Double(i) * 1.5,
                                     durationMs: 1000 + i))
        }
        context.insert(Deck(name: "Food 🍜", wordIDs: [custom.id, ni.id]))
        try context.save()
        defaults.set(25, forKey: SettingsKey.newPerDay)
        defaults.set(false, forKey: SettingsKey.autoPlayAudio)
        defaults.set(0.85, forKey: SettingsKey.desiredRetention)
        defaults.set("hanzi_meaning,audio_hanzi", forKey: SettingsKey.enabledDirections)
        try Data([0, 1, 2, 3, 255]).write(to: RecordingStore.url(for: ni.id))
        try Data("custom audio".utf8).write(to: RecordingStore.url(for: custom.id))
    }

    /// Simulates a fresh install: new store, default settings, no recordings, bundled words seeded.
    func freshInstall() throws {
        container = try Self.makeContainer()
        for k in SettingsKey.exported + [Seeder.versionKey] { defaults.removeObject(forKey: k) }
        try? FileManager.default.removeItem(at: RecordingStore.directory)
        seedFixture()
    }

    func testRoundTripRestoresEverything() throws {
        try populate()
        let before = try snapshot()
        let data = try BackupService.export(context)
        try freshInstall()
        XCTAssertNotEqual(try snapshot(), before)

        let summary = try BackupService.importBackup(data, into: context)
        XCTAssertEqual(summary.recordings, 2)
        XCTAssertEqual(summary.logs, 5)
        XCTAssertEqual(summary.decks, 1)
        let after = try snapshot()
        XCTAssertEqual(after.words, before.words)
        XCTAssertEqual(after.cards, before.cards)
        XCTAssertEqual(after.logs, before.logs)
        XCTAssertEqual(after.decks, before.decks)
        XCTAssertEqual(after.settings, before.settings)
        XCTAssertEqual(after.recordings, before.recordings)
    }

    func testImportTwiceCreatesNoDuplicates() throws {
        try populate()
        let data = try BackupService.export(context)
        try freshInstall()
        _ = try BackupService.importBackup(data, into: context)
        let once = try snapshot()
        let second = try BackupService.importBackup(data, into: context)
        XCTAssertEqual(second.logs, 0, "Known review logs are skipped")
        XCTAssertEqual(try snapshot(), once)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Word>(predicate: #Predicate { $0.isCustom })), 1)
    }

    func testBadFilesFailCleanly() throws {
        try populate()
        let good = try BackupService.export(context)
        let before = try snapshot()

        func expect(_ data: Data, _ error: BackupService.ImportError, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try BackupService.importBackup(data, into: context), file: file, line: line) {
                XCTAssertEqual($0 as? BackupService.ImportError, error, file: file, line: line)
            }
        }
        expect(Data([0xFF, 0x00, 0x13]), .notABackup)
        expect(Data("{}".utf8), .notABackup)
        expect(good.prefix(good.count / 2), .notABackup)  // truncated
        expect(Data(#"{"format":"something-else","version":1}"#.utf8), .notABackup)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        json["version"] = 0
        expect(try JSONSerialization.data(withJSONObject: json), .unsupportedVersion(0))
        json["version"] = 99
        expect(try JSONSerialization.data(withJSONObject: json), .unsupportedVersion(99))

        json["version"] = 1
        var cards = try XCTUnwrap(json["cards"] as? [[String: Any]])
        cards[0]["due"] = "not a date"
        json["cards"] = cards
        XCTAssertThrowsError(try BackupService.importBackup(try JSONSerialization.data(withJSONObject: json), into: context)) {
            guard case .corrupt = $0 as? BackupService.ImportError else { return XCTFail("\($0)") }
        }
        cards[0].removeValue(forKey: "due")
        cards[0]["stability"] = "x"
        json["cards"] = cards
        XCTAssertThrowsError(try BackupService.importBackup(try JSONSerialization.data(withJSONObject: json), into: context))

        XCTAssertEqual(try snapshot(), before, "Failed imports change nothing")
    }

    func testOlderSecondPrecisionDatesStillImport() throws {
        try populate()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try BackupService.export(context)) as? [String: Any])
        json["exportedAt"] = "2026-11-13T08:00:00Z"
        XCTAssertNoThrow(try BackupService.importBackup(try JSONSerialization.data(withJSONObject: json), into: context))
    }

    func testRecordingsForUnknownWordsAreIgnored() throws {
        try populate()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try BackupService.export(context)) as? [String: Any])
        var recs = try XCTUnwrap(json["recordings"] as? [[String: Any]])
        recs.append(["wordId": "custom:gone", "mimeType": "audio/mp4", "data": Data([1]).base64EncodedString()])
        json["recordings"] = recs
        _ = try BackupService.importBackup(try JSONSerialization.data(withJSONObject: json), into: context)
        XCTAssertFalse(RecordingStore.exists("custom:gone"))
    }

    func testPruneOrphanRecordings() throws {
        try populate()
        let custom = try XCTUnwrap(try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.isCustom })).first)
        let id = custom.id
        context.delete(custom)
        try context.save()
        Seeder.pruneRecordings(context)
        XCTAssertFalse(RecordingStore.exists(id))
        XCTAssertTrue(RecordingStore.exists(Word.builtinID("你")))
        XCTAssertEqual(RecordingStore.wordID(fromFileName: RecordingStore.fileName(for: "zh:你")), "zh:你")
    }
}

@MainActor
final class StatsTests: StoreTestCase {
    let cal = Calendar.fixed("America/New_York")

    func days(_ list: [(Int, Int, Int)]) -> Set<Date> { Set(list.map { cal.startOfDay(for: cal.at($0.0, $0.1, $0.2)) }) }
    func today(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.startOfDay(for: cal.at(y, m, d)) }

    func testStreakCountsTodayOrYesterday() {
        let d = days([(2026, 11, 11), (2026, 11, 12), (2026, 11, 13)])
        XCTAssertEqual(StatsBuilder.streaks(days: d, today: today(2026, 11, 13), cal: cal).current, 3)
        XCTAssertEqual(StatsBuilder.streaks(days: d, today: today(2026, 11, 14), cal: cal).current, 3,
                       "Not reviewed yet today: streak still alive")
        XCTAssertEqual(StatsBuilder.streaks(days: d, today: today(2026, 11, 15), cal: cal).current, 0, "Missed a day")
    }

    func testMissedDayResetsButLongestRemains() {
        let d = days([(2026, 11, 1), (2026, 11, 2), (2026, 11, 3), (2026, 11, 4), (2026, 11, 6), (2026, 11, 7)])
        let s = StatsBuilder.streaks(days: d, today: today(2026, 11, 7), cal: cal)
        XCTAssertEqual(s.current, 2)
        XCTAssertEqual(s.longest, 4)
        XCTAssertEqual(StatsBuilder.streaks(days: [], today: today(2026, 11, 7), cal: cal).current, 0)
    }

    func testStreakAcrossDSTDays() {
        let d = days([(2026, 3, 7), (2026, 3, 8), (2026, 3, 9), (2026, 10, 31), (2026, 11, 1), (2026, 11, 2)])
        XCTAssertEqual(StatsBuilder.streaks(days: d, today: today(2026, 3, 9), cal: cal).longest, 3)
        XCTAssertEqual(StatsBuilder.streaks(days: d, today: today(2026, 11, 2), cal: cal).current, 3)
    }

    func testReviewsAroundMidnightLandOnTheRightDay() throws {
        seedFixture()
        for t in [cal.at(2026, 11, 12, 23, 59), cal.at(2026, 11, 13, 0, 1), cal.at(2026, 11, 13, 22, 0)] {
            context.insert(ReviewLog(date: t, cardID: "zh:你|hanzi_meaning", rating: 3, stateBefore: 2, elapsedDays: 1,
                                     scheduledDays: 3, durationMs: 1000))
        }
        let s = StatsBuilder.build(context, now: cal.at(2026, 11, 13, 23, 0), calendar: cal)
        XCTAssertEqual(s.reviewedToday, 2)
        XCTAssertEqual(s.totalReviews, 3)
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.last30.count, 30)
        XCTAssertEqual(s.last30.last?.count, 2)
        XCTAssertEqual(s.last30.dropLast().last?.count, 1)
        XCTAssertEqual(s.retention30, 1)
        XCTAssertEqual(s.forecast.count, 14)
    }

    func testCardStateCounts() throws {
        seedFixture()
        let c = try XCTUnwrap(try word("你").card(.hanziToMeaning))
        c.scheduling = SchedulingInfo(state: .review, stability: 30, difficulty: 5, due: Date().addingTimeInterval(86400 * 3),
                                      reps: 5, lapses: 9, lastReview: Date())
        c.isLeech = true
        let s = StatsBuilder.build(context)
        XCTAssertEqual(s.reviewCards, 1)
        XCTAssertEqual(s.matureCards, 1)
        XCTAssertEqual(s.leeches.count, 1)
        XCTAssertEqual(s.newCards, 8)
        XCTAssertEqual(s.wordsStarted, 1)
        XCTAssertEqual(s.forecast.map(\.count).reduce(0, +), 1)
    }
}

final class ReminderTests: XCTestCase {
    func testRequestUsesLocalWallClockTime() throws {
        let r = Reminders.makeRequest(hour: 7, minute: 30)
        let t = try XCTUnwrap(r.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.hour, 7)
        XCTAssertEqual(t.dateComponents.minute, 30)
        XCTAssertNil(t.dateComponents.timeZone, "No fixed zone: follows the phone's time zone")
        XCTAssertEqual(r.identifier, Reminders.id)
        let clamped = try XCTUnwrap(Reminders.makeRequest(hour: 27, minute: -5).trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(clamped.dateComponents.hour, 23)
        XCTAssertEqual(clamped.dateComponents.minute, 0)
    }

    func testChangingTimeReplacesPendingReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let saved = Reminders.id
        Reminders.id = "daily-review-unittest"
        defer {
            Reminders.cancel()
            Reminders.id = saved
        }
        Reminders.schedule(hour: 8, minute: 0)
        Reminders.schedule(hour: 21, minute: 15)
        try await Task.sleep(for: .milliseconds(500))
        let pending = await center.pendingNotificationRequests().filter { $0.identifier == Reminders.id }
        try XCTSkipIf(pending.isEmpty, "Notifications not authorized for this app on this device")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual((pending[0].trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 21)
    }
}
