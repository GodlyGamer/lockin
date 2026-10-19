import XCTest
@testable import CoreKit

/// Wave 1 tests for the parts of CoreKit that are already implemented. M1 adds one file per engine.
final class FoundationTests: XCTestCase {
    func testLocalDayParsesAndFormats() {
        XCTAssertEqual(LocalDay("2026-10-19")?.string, "2026-10-19")
        XCTAssertNil(LocalDay("2026-02-30"))
        XCTAssertNil(LocalDay("2026-1-5"))
        XCTAssertEqual(LocalDay("2026-10-19")?.weekday, 1) // Monday
        XCTAssertEqual(LocalDay("2026-10-25")?.weekday, 7) // Sunday
        XCTAssertEqual(LocalDay("2026-10-25")?.weekStart.string, "2026-10-19")
        XCTAssertEqual(LocalDay("2026-12-31")!.adding(days: 1).string, "2027-01-01")
    }

    func testLocalDayAcrossClockChange() {
        // UK clocks go back on Sun 25 Oct 2026.
        let sat = LocalDay("2026-10-24")!
        XCTAssertEqual(sat.days(to: LocalDay("2026-10-26")!), 2)
        XCTAssertEqual(TimeOfDay.minutes(of: LocalDay("2026-10-26")!.date(minutes: 450)), 450)
    }

    func testTimeOfDay() {
        XCTAssertEqual(TimeOfDay.parse("07:30"), 450)
        XCTAssertNil(TimeOfDay.parse("7:30"))
        XCTAssertNil(TimeOfDay.parse("24:00"))
        XCTAssertEqual(TimeOfDay.format(1290), "21:30")
    }

    func testDeepLinkRoundTrip() {
        let id = UUID()
        let links: [DeepLink] = [.habit(id, LocalDay("2026-10-19")!), .today, .week, .goal(id), .block(id), .settings]
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertEqual(DeepLink.habit(id, LocalDay("2026-10-19")!).url.absoluteString,
                       "lockin://habit/\(id.uuidString)?day=2026-10-19")
    }

    func testFrequencyCoding() throws {
        for frequency in [Frequency.daily, .weekdays([1, 3, 5]), .perWeek(5)] {
            let data = try JSONEncoder().encode(frequency)
            XCTAssertEqual(try JSONDecoder().decode(Frequency.self, from: data), frequency)
        }
    }

    func testBackupRoundTrip() throws {
        let snapshot = SampleData.bodyFatGoal(today: LocalDay("2026-10-21")!)
        let data = BackupCodec.encode(snapshot)
        let decoded = try BackupCodec.decode(data)
        XCTAssertEqual(decoded.habits.map(\.id), snapshot.habits.map(\.id))
        XCTAssertEqual(decoded.logs.count, snapshot.logs.count)
        XCTAssertEqual(decoded.goals.first?.title, "10% body fat")
    }

    func testBackupRejectsNewerVersion() {
        let json = #"{"format":"lockin-backup","schemaVersion":2,"exportedAt":"2026-10-19T19:00:00Z","appVersion":"2","data":{}}"#
        XCTAssertThrowsError(try BackupCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .newerVersion(2))
        }
    }

    func testBackupFileNames() {
        XCTAssertEqual(BackupCodec.fileName(for: LocalDay("2026-10-19")!), "lockin-backup-2026-10-19.json")
        XCTAssertEqual(BackupCodec.day(fromFileName: "lockin-backup-2026-10-19.json"), LocalDay("2026-10-19"))
        XCTAssertNil(BackupCodec.day(fromFileName: "lockin-backup-latest.json"))
    }

    func testSnapshotDeleteRules() {
        let snapshot = SampleData.bodyFatGoal(today: LocalDay("2026-10-21")!)
        // Deleting a system leaves its habits standalone.
        let noWalk = snapshot.applying(ChangeSet(deletes: [EntityRef(.system, SampleData.walkSystemID)]))
        let walk = noWalk.habit(SampleData.inclineWalkHabitID)
        XCTAssertNotNil(walk)
        XCTAssertNil(walk?.systemID)
        XCTAssertNil(walk?.goalID)
        // Deleting the goal cascades principles, systems, objectives, steps and reviews; habits stay standalone.
        let noGoal = snapshot.applying(ChangeSet(deletes: [EntityRef(.goal, SampleData.goalID)]))
        XCTAssertTrue(noGoal.systems.isEmpty)
        XCTAssertTrue(noGoal.objectives.isEmpty)
        XCTAssertTrue(noGoal.steps.isEmpty)
        XCTAssertTrue(noGoal.weekReviews.isEmpty)
        XCTAssertTrue(noGoal.blockRules.isEmpty)
        XCTAssertEqual(noGoal.habits.count, snapshot.habits.count)
        // A second log for the same habit and day replaces the first.
        let day = LocalDay("2026-10-20")!
        let replaced = snapshot.applying(ChangeSet(upserts: [.log(HabitLog(habitID: SampleData.liftHabitID, day: day, mark: .M))]))
        XCTAssertEqual(replaced.logs.filter { $0.habitID == SampleData.liftHabitID && $0.day == day }.count, 1)
    }

    @MainActor
    func testInMemoryStoreRevision() throws {
        let store = InMemoryStore(snapshot: SampleData.bodyFatGoal())
        XCTAssertEqual(store.revision, 0)
        try store.delete(EntityRef(.habit, SampleData.liftHabitID))
        XCTAssertEqual(store.revision, 1)
        XCTAssertNil(store.snapshot().habit(SampleData.liftHabitID))
    }

    func testLogicalDayBoundary() {
        // 01:30 on Tuesday 20 Oct → Monday 19 Oct.
        let tuesday = LocalDay("2026-10-20")!
        XCTAssertEqual(HabitEngine.logicalDay(for: tuesday.date(minutes: 90)), LocalDay("2026-10-19"))
        XCTAssertEqual(HabitEngine.logicalDay(for: tuesday.date(minutes: 240)), tuesday)
    }

    func testPromptAddOnIsVerbatim() {
        XCTAssertTrue(PromptBuilder.promptAddOn.hasPrefix("When the plan is final, end your reply with exactly one ```json"))
        XCTAssertTrue(PromptBuilder.promptAddOn.hasSuffix("A block uses either weekdays (repeating) or date (one-off)."))
    }
}
