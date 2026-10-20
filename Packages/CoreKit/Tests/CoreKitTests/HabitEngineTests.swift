import XCTest
@testable import CoreKit

final class HabitEngineTests: XCTestCase {
    let goal = makeGoal()
    let settings = AppSettings.defaults

    // MARK: Day boundary (F2.3)

    func testLogicalDayBoundary() {
        XCTAssertEqual(HabitEngine.logicalDay(for: at("2026-10-20", "01:30")), day("2026-10-19"))
        XCTAssertEqual(HabitEngine.logicalDay(for: at("2026-10-20", "03:59")), day("2026-10-19"))
        XCTAssertEqual(HabitEngine.logicalDay(for: at("2026-10-20", "04:00")), day("2026-10-20"))
    }

    func testLogicalDayOnClockChangeNight() {
        // 01:30 on 25 Oct happens twice; either way it is still the 24th.
        XCTAssertEqual(HabitEngine.logicalDay(for: at("2026-10-25", "01:30")), day("2026-10-24"))
    }

    // MARK: isScheduled / isDue (F1.1, F1.2)

    func testWeekdaysHabitOnlyDueOnItsDays() {
        let habit = makeHabit(1, frequency: .weekdays([1, 3, 5]))
        XCTAssertTrue(HabitEngine.isDue(habit, on: day("2026-10-19"), logs: []))
        XCTAssertFalse(HabitEngine.isDue(habit, on: day("2026-10-20"), logs: []))
        XCTAssertTrue(HabitEngine.isDue(habit, on: day("2026-10-21"), logs: []))
        XCTAssertFalse(HabitEngine.isDue(habit, on: day("2026-10-24"), logs: []))
    }

    func testPerWeekHabitStopsAfterNMarksUntilMonday() {
        let habit = makeHabit(2, frequency: .perWeek(5))
        let marks = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"].map { makeLog(habit, $0, .D) }
        // Shows on each day while fewer than 5 marks sit before it (the day itself still shows once marked).
        XCTAssertTrue(HabitEngine.isDue(habit, on: day("2026-10-23"), logs: marks))
        XCTAssertFalse(HabitEngine.isDue(habit, on: day("2026-10-24"), logs: marks))
        XCTAssertFalse(HabitEngine.isDue(habit, on: day("2026-10-25"), logs: marks))
        XCTAssertTrue(HabitEngine.isDue(habit, on: day("2026-10-26"), logs: marks))
    }

    func testPerWeekIgnoresMissedMarks() {
        let habit = makeHabit(3, frequency: .perWeek(2))
        let logs = [makeLog(habit, "2026-10-19", .M), makeLog(habit, "2026-10-20", .B)]
        XCTAssertTrue(HabitEngine.isDue(habit, on: day("2026-10-21"), logs: logs)) // 1 of 2
    }

    func testArchivedHabitIsNeverDue() {
        let habit = makeHabit(4, archived: true)
        XCTAssertFalse(HabitEngine.isDue(habit, on: day("2026-10-19"), logs: []))
    }

    // MARK: Marks (F2.2, §3.7)

    func testDerivedMark() {
        let habit = Habit(title: "Protein", badDayTitle: "3 portions", kind: .count, target: 4, badDayTarget: 3)
        XCTAssertEqual(HabitEngine.derivedMark(count: 4, habit: habit), .D)
        XCTAssertEqual(HabitEngine.derivedMark(count: 5, habit: habit), .D)
        XCTAssertEqual(HabitEngine.derivedMark(count: 3, habit: habit), .B)
        XCTAssertEqual(HabitEngine.derivedMark(count: 2, habit: habit), .M)
    }

    func testMarkComputedMissedForFinishedDays() {
        let habit = makeHabit(5, frequency: .weekdays([1, 3, 5]))
        let now = at("2026-10-21", "12:00") // Wednesday
        let logs = [makeLog(habit, "2026-10-21", .D)]
        XCTAssertEqual(HabitEngine.mark(for: habit, on: day("2026-10-19"), logs: logs, now: now), .M) // unlogged, finished
        XCTAssertEqual(HabitEngine.mark(for: habit, on: day("2026-10-20"), logs: logs, now: now), nil) // not scheduled
        XCTAssertEqual(HabitEngine.mark(for: habit, on: day("2026-10-21"), logs: logs, now: now), .D)  // logged
        XCTAssertNil(HabitEngine.mark(for: habit, on: day("2026-10-23"), logs: logs, now: now))        // future
    }

    func testTodayStaysOpenUntilFourAm() {
        let habit = makeHabit(6)
        // 01:30 on Tuesday: Monday is still open, Sunday is finished.
        let now = at("2026-10-20", "01:30")
        XCTAssertNil(HabitEngine.mark(for: habit, on: day("2026-10-19"), logs: [], now: now))
        XCTAssertEqual(HabitEngine.mark(for: habit, on: day("2026-10-18"), logs: [], now: now), .M)
        XCTAssertEqual(HabitEngine.mark(for: habit, on: day("2026-10-19"), logs: [], now: at("2026-10-20", "04:00")), .M)
    }

    func testPerWeekHabitNeverGetsComputedMiss() {
        let habit = makeHabit(7, frequency: .perWeek(3))
        XCTAssertNil(HabitEngine.mark(for: habit, on: day("2026-10-19"), logs: [], now: at("2026-10-25", "12:00")))
    }

    // MARK: Week score (F3.1, F3.2)

    func testHitAtSetPoint() {
        let habit = makeHabit(8, frequency: .perWeek(5), setPoint: 5)
        let logs = ["2026-10-19", "2026-10-20", "2026-10-22", "2026-10-24", "2026-10-25"].map { makeLog(habit, $0, .D) }
        let score = HabitEngine.weekScore(habit: habit, week: Week(containing: day("2026-10-21")), logs: logs)
        XCTAssertEqual(score.scheduled, 5)
        XCTAssertEqual(score.done, 5)
        XCTAssertTrue(score.hit)
        XCTAssertFalse(score.badDayFlag)
    }

    func testBMarksCountAsDone() {
        let habit = makeHabit(9, frequency: .perWeek(5), setPoint: 5)
        let logs = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22"].map { makeLog(habit, $0, .D) } + [makeLog(habit, "2026-10-23", .B)]
        let score = HabitEngine.weekScore(habit: habit, week: Week(containing: day("2026-10-21")), logs: logs)
        XCTAssertEqual(score.done, 5)
        XCTAssertEqual(score.bad, 1)
        XCTAssertTrue(score.hit)
    }

    func testPerWeekDoneIsCappedAtN() {
        let habit = makeHabit(10, frequency: .perWeek(3), setPoint: 3)
        let logs = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"].map { makeLog(habit, $0, .D) }
        let score = HabitEngine.weekScore(habit: habit, week: Week(containing: day("2026-10-21")), logs: logs)
        XCTAssertEqual(score.done, 3)
    }

    func testMissedAndOtherWeeksDoNotCount() {
        let habit = makeHabit(11, setPoint: 5)
        let logs = [makeLog(habit, "2026-10-19", .M), makeLog(habit, "2026-10-18", .D), makeLog(habit, "2026-10-26", .D),
                    makeLog(habit, "2026-10-20", .D)]
        let score = HabitEngine.weekScore(habit: habit, week: Week(containing: day("2026-10-21")), logs: logs)
        XCTAssertEqual(score.done, 1)
        XCTAssertFalse(score.hit)
    }

    func testBadDayFlag() {
        let habit = makeHabit(12, frequency: .daily, setPoint: 3)
        let flagged = ["2026-10-19", "2026-10-20"].map { makeLog(habit, $0, .B) } + [makeLog(habit, "2026-10-21", .D)]
        let week = Week(containing: day("2026-10-19"))
        let score = HabitEngine.weekScore(habit: habit, week: week, logs: flagged)
        XCTAssertEqual(score.done, 3)
        XCTAssertEqual(score.bad, 2)
        XCTAssertTrue(score.badDayFlag) // 3 done, 2 of them B
        let fine = [makeLog(habit, "2026-10-19", .B), makeLog(habit, "2026-10-20", .D), makeLog(habit, "2026-10-21", .D)]
        XCTAssertFalse(HabitEngine.weekScore(habit: habit, week: week, logs: fine).badDayFlag)
        let single = [makeLog(habit, "2026-10-19", .B)]
        XCTAssertFalse(HabitEngine.weekScore(habit: habit, week: week, logs: single).badDayFlag) // needs done >= 2
        let half = [makeLog(habit, "2026-10-19", .B), makeLog(habit, "2026-10-20", .D)]
        XCTAssertFalse(HabitEngine.weekScore(habit: habit, week: week, logs: half).badDayFlag) // bad is not more than half
    }

    func testOtherHabitsLogsAreIgnored() {
        let a = makeHabit(13)
        let b = makeHabit(14)
        let score = HabitEngine.weekScore(habit: a, week: Week(containing: day("2026-10-19")), logs: [makeLog(b, "2026-10-19", .D)])
        XCTAssertEqual(score.done, 0)
    }

    // MARK: Goal score (§4.6)

    func goalFixtures() -> (habits: [Habit], logs: [HabitLog]) {
        let daily = makeHabit(20, goal: goal.id, frequency: .daily, setPoint: 5)
        let mwf = makeHabit(21, goal: goal.id, frequency: .weekdays([1, 3, 5]), setPoint: 3)
        let other = makeHabit(22, goal: uuid(99), frequency: .daily)
        let archived = makeHabit(23, goal: goal.id, archived: true)
        let logs = ["2026-10-19", "2026-10-20", "2026-10-21"].map { makeLog(daily, $0, .D) }
            + ["2026-10-19", "2026-10-21"].map { makeLog(mwf, $0, .D) }
        return ([daily, mwf, other, archived], logs)
    }

    func testGoalWeekScoreTotals() {
        let (habits, logs) = goalFixtures()
        let week = Week(containing: day("2026-10-19"))
        let score = HabitEngine.goalWeekScore(goal: goal, habits: habits, week: week, logs: logs,
                                              now: at("2026-10-22", "12:00"), settings: settings)
        XCTAssertEqual(score.total, 2) // other goals' and archived habits are out
        XCTAssertEqual(score.onTarget, 0)
        XCTAssertEqual(score.doneOcc, 5)
        XCTAssertEqual(score.schedOcc, 10)
        XCTAssertEqual(score.setOcc, 8)
        XCTAssertEqual(score.dashboardLabel, "5 of 10")
        XCTAssertEqual(score.weekLabel, "0 of 2 on target")
        XCTAssertEqual(score.fraction, 0.5, accuracy: 0.0001)
    }

    func testExpectedSoFarBeforeAndAfterEvening() {
        let (habits, logs) = goalFixtures()
        let week = Week(containing: day("2026-10-19"))
        // Wed 12:00: Mon + Tue elapsed. daily 5·2/7 = 1.43; mwf 3·1/3 = 1 → ⌊2.43⌋ = 2.
        let midday = HabitEngine.goalWeekScore(goal: goal, habits: habits, week: week, logs: logs,
                                               now: at("2026-10-21", "12:00"), settings: settings)
        XCTAssertEqual(midday.expectedSoFar, 2)
        XCTAssertEqual(midday.dashboardState, .onTrack) // 5 done ≥ 2
        // Wed 22:00 is past 21:30: Mon–Wed elapsed. daily 5·3/7 = 2.14; mwf 3·2/3 = 2 → ⌊4.14⌋ = 4.
        let evening = HabitEngine.goalWeekScore(goal: goal, habits: habits, week: week, logs: logs,
                                                now: at("2026-10-21", "22:00"), settings: settings)
        XCTAssertEqual(evening.expectedSoFar, 4)
    }

    func testBehindWhenBelowExpected() {
        let daily = makeHabit(24, goal: goal.id, setPoint: 7)
        let week = Week(containing: day("2026-10-19"))
        let score = HabitEngine.goalWeekScore(goal: goal, habits: [daily], week: week, logs: [],
                                              now: at("2026-10-24", "12:00"), settings: settings)
        XCTAssertEqual(score.expectedSoFar, 5) // 5 days elapsed
        XCTAssertEqual(score.dashboardState, .behind)
        XCTAssertEqual(score.weekState, .behind)
    }

    func testPerWeekExpectedUsesDaysElapsed() {
        let walk = makeHabit(25, goal: goal.id, frequency: .perWeek(5), setPoint: 5)
        let week = Week(containing: day("2026-10-19"))
        // 4 days elapsed: 5 · (5·4/7) / 5 = 2.86 → 2
        let score = HabitEngine.goalWeekScore(goal: goal, habits: [walk], week: week, logs: [],
                                              now: at("2026-10-23", "08:00"), settings: settings)
        XCTAssertEqual(score.expectedSoFar, 2)
    }

    func testFinishedWeekIsFullyElapsed() {
        let daily = makeHabit(26, goal: goal.id, setPoint: 6)
        let score = HabitEngine.goalWeekScore(goal: goal, habits: [daily], week: Week(containing: day("2026-10-12")),
                                              logs: [], now: at("2026-10-21", "08:00"), settings: settings)
        XCTAssertEqual(score.expectedSoFar, 6)
    }

    func testGoalWithoutHabitsIsNeutral() {
        let score = HabitEngine.goalWeekScore(goal: goal, habits: [], week: Week(containing: day("2026-10-19")), logs: [],
                                              now: at("2026-10-21", "08:00"), settings: settings)
        XCTAssertEqual(score.dashboardState, .neutral)
        XCTAssertEqual(score.weekState, .neutral)
        XCTAssertEqual(score.fraction, 0)
    }

    // MARK: Streaks (F3.3)

    func fullWeek(_ habit: Habit, start: String, marks: Int) -> [HabitLog] {
        (0..<marks).map { makeLog(habit, day(start).adding(days: $0).string, .D) }
    }

    func testGoalStreakCountsOnlyWeeksWhereEveryHabitHit() {
        let a = makeHabit(30, goal: goal.id, setPoint: 5)
        let b = makeHabit(31, goal: goal.id, frequency: .weekdays([1, 3, 5]), setPoint: 3)
        var logs: [HabitLog] = []
        // Weeks of 5 Oct and 12 Oct: both hit. Week of 28 Sep: b misses.
        for start in ["2026-10-05", "2026-10-12"] {
            logs += fullWeek(a, start: start, marks: 5)
            logs += ["0", "2", "4"].map { makeLog(b, day(start).adding(days: Int($0)!).string, .D) }
        }
        logs += fullWeek(a, start: "2026-09-28", marks: 5)
        logs += [makeLog(b, "2026-09-28", .D)]
        let current = Week(containing: day("2026-10-19"))
        XCTAssertEqual(HabitEngine.goalStreak(goal: goal, habits: [a, b], logs: logs, currentWeek: current), 2)
        // One habit short in the latest week resets the streak.
        let short = logs.filter { !($0.habitID == a.id && $0.day >= day("2026-10-16")) }
        XCTAssertEqual(HabitEngine.goalStreak(goal: goal, habits: [a, b], logs: short, currentWeek: current), 0)
    }

    func testStreakIgnoresCurrentWeekAndEmptyGoals() {
        let a = makeHabit(32, goal: goal.id, setPoint: 3)
        let logs = fullWeek(a, start: "2026-10-19", marks: 5)
        let current = Week(containing: day("2026-10-21"))
        XCTAssertEqual(HabitEngine.goalStreak(goal: goal, habits: [a], logs: logs, currentWeek: current), 0)
        XCTAssertEqual(HabitEngine.goalStreak(goal: goal, habits: [], logs: logs, currentWeek: current), 0)
    }

    func testHabitStreak() {
        let habit = makeHabit(33, setPoint: 4)
        let logs = fullWeek(habit, start: "2026-10-12", marks: 4) + fullWeek(habit, start: "2026-10-05", marks: 4)
            + fullWeek(habit, start: "2026-09-28", marks: 2)
        XCTAssertEqual(HabitEngine.habitStreak(habit: habit, logs: logs, currentWeek: Week(containing: day("2026-10-19"))), 2)
    }

    // MARK: Bottleneck and system status (§4.6)

    func testSuggestedBottleneckLowestRatio() {
        let a = makeHabit(40, setPoint: 4, priority: 3)
        let b = makeHabit(41, setPoint: 2, priority: 3)
        let week = Week(containing: day("2026-10-19"))
        // a: 2/4 = 0.5, b: 1/2 = 0.5 → tie → priority → sortIndex. Make b the lower-priority number.
        let logs = fullWeek(a, start: "2026-10-19", marks: 2) + fullWeek(b, start: "2026-10-19", marks: 1)
        var low = b; low.priority = 1
        XCTAssertEqual(HabitEngine.suggestedBottleneck(habits: [a, low], week: week, logs: logs), low.id)
        var first = a; first.sortIndex = 0
        var second = b; second.sortIndex = 1
        XCTAssertEqual(HabitEngine.suggestedBottleneck(habits: [second, first], week: week, logs: logs), first.id)
        let worse = fullWeek(a, start: "2026-10-19", marks: 1) + fullWeek(b, start: "2026-10-19", marks: 2)
        XCTAssertEqual(HabitEngine.suggestedBottleneck(habits: [a, b], week: week, logs: worse), a.id)
        XCTAssertNil(HabitEngine.suggestedBottleneck(habits: [], week: week, logs: []))
    }

    func testSuggestedBottleneckSkipsArchived() {
        let archived = makeHabit(42, setPoint: 4, archived: true)
        let live = makeHabit(43, setPoint: 4)
        let week = Week(containing: day("2026-10-19"))
        XCTAssertEqual(HabitEngine.suggestedBottleneck(habits: [archived, live], week: week, logs: fullWeek(live, start: "2026-10-19", marks: 4)), live.id)
    }

    func testSystemStatus() {
        let system = uuid(500)
        let a = makeHabit(44, system: system, setPoint: 7)
        let b = makeHabit(45, system: system, setPoint: 7)
        let week = Week(containing: day("2026-10-19"))
        let now = at("2026-10-22", "12:00") // Mon–Wed elapsed: ⌊7·3/7⌋ = 3 expected each
        let both = fullWeek(a, start: "2026-10-19", marks: 3) + fullWeek(b, start: "2026-10-19", marks: 3)
        XCTAssertEqual(HabitEngine.systemStatus(systemID: system, habits: [a, b], week: week, logs: both, now: now, settings: settings), .onTrack)
        let oneShort = fullWeek(a, start: "2026-10-19", marks: 3) + fullWeek(b, start: "2026-10-19", marks: 2)
        XCTAssertEqual(HabitEngine.systemStatus(systemID: system, habits: [a, b], week: week, logs: oneShort, now: now, settings: settings), .behind)
        XCTAssertEqual(HabitEngine.systemStatus(systemID: uuid(501), habits: [a, b], week: week, logs: both, now: now, settings: settings), .neutral)
    }
}
