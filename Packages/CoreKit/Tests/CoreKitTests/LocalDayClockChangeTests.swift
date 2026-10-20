import XCTest
@testable import CoreKit

/// `LocalDay.date(minutes:)` is wall-clock time, also on the two days a year the UK clocks change.
final class LocalDayClockChangeTests: XCTestCase {
    func testWallClockTimesSurviveClockChanges() {
        for text in ["2026-10-24", "2026-10-25", "2026-10-26", "2027-03-27", "2027-03-28", "2027-03-29"] {
            let day = LocalDay(text)!
            XCTAssertEqual(TimeOfDay.minutes(of: day.date(minutes: 450)), 450, text)
            XCTAssertEqual(TimeOfDay.minutes(of: day.date(minutes: 1020)), 1020, text)
            XCTAssertEqual(LocalDay(day.date(minutes: 1380)), day, text)
            XCTAssertEqual(day.date(minutes: 0), day.date())
        }
    }

    func testMinutesPastMidnightRollIntoTheNextDay() {
        let sunday = LocalDay("2026-10-25")!
        XCTAssertEqual(sunday.date(minutes: 1440), LocalDay("2026-10-26")!.date())
        XCTAssertEqual(sunday.date(minutes: -60), LocalDay("2026-10-24")!.date(minutes: 1380))
    }

    func testBlockMaterialisedOnClockChangeDayStartsAtItsTime() {
        let rule = BlockRule(systemID: UUID(), title: "Meal prep", durationMinutes: 90, weekdays: [7], startTime: 1020)
        let blocks = ScheduleEngine.materialise(rules: [rule], existing: [], from: LocalDay("2026-10-25")!, days: 1, settings: .defaults)
        XCTAssertEqual(TimeOfDay.minutes(of: blocks[0].start), 1020)
    }
}
