import XCTest
@testable import CoreKit

final class ScheduleEngineTests: XCTestCase {
    let settings = AppSettings.defaults

    func chain(overrideMiddle: String? = nil) -> (goal: Goal, objectives: [Objective]) {
        let goal = makeGoal(1, deadline: "2026-12-31", buffer: 7)
        let o1 = Objective(id: uuid(11), goalID: goal.id, title: "First", estimatedDays: 10)
        var o2 = Objective(id: uuid(12), goalID: goal.id, title: "Second", estimatedDays: 14, dependsOnIDs: [o1.id])
        let o3 = Objective(id: uuid(13), goalID: goal.id, title: "Third", estimatedDays: 21, dependsOnIDs: [o2.id])
        if let overrideMiddle {
            o2.deadline = day(overrideMiddle)
            o2.deadlineOverridden = true
        }
        return (goal, [o1, o2, o3])
    }

    // MARK: Back-scheduling (§4.5, F8.3)

    func testBackSchedulesThreeLevelChain() {
        let (goal, objectives) = chain()
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: day("2026-10-20"))
        XCTAssertEqual(result.deadlines[objectives[2].id], day("2026-12-24")) // deadline − 7 buffer days
        XCTAssertEqual(result.deadlines[objectives[1].id], day("2026-12-03")) // − third's 21 days
        XCTAssertEqual(result.deadlines[objectives[0].id], day("2026-11-19")) // − second's 14 days
        XCTAssertTrue(result.startsLateByDays.isEmpty)
    }

    func testChangingGoalDeadlineMovesEveryMilestone() {
        var (goal, objectives) = chain()
        goal.deadline = day("2027-01-31")
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: day("2026-10-20"))
        XCTAssertEqual(result.deadlines[objectives[2].id], day("2027-01-24"))
        XCTAssertEqual(result.deadlines[objectives[0].id], day("2026-12-20"))
    }

    func testOverriddenDeadlineIsKeptAndPropagates() {
        let (goal, objectives) = chain(overrideMiddle: "2026-12-10")
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: day("2026-10-20"))
        XCTAssertEqual(result.deadlines[objectives[1].id], day("2026-12-10"))
        XCTAssertEqual(result.deadlines[objectives[0].id], day("2026-11-26")) // 10 Dec − 14
        XCTAssertEqual(result.deadlines[objectives[2].id], day("2026-12-24"))
    }

    func testStartsLateWarning() {
        let (goal, objectives) = chain()
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: day("2026-11-25"))
        // first: finish 19 Nov − 10 d = 9 Nov, 16 days before today. second: 3 Dec − 14 = 19 Nov, 6 days before.
        XCTAssertEqual(result.startsLateByDays[objectives[0].id], 16)
        XCTAssertEqual(result.startsLateByDays[objectives[1].id], 6)
        XCTAssertNil(result.startsLateByDays[objectives[2].id]) // 24 Dec − 21 = 3 Dec, still ahead
    }

    func testDoneObjectivesDoNotWarn() {
        var (goal, objectives) = chain()
        objectives[0].status = .done
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: day("2026-11-25"))
        XCTAssertNil(result.startsLateByDays[objectives[0].id])
    }

    func testDiamondTakesEarliestRequirement() {
        let goal = makeGoal(1, deadline: "2026-12-31", buffer: 0)
        let root = Objective(id: uuid(21), goalID: goal.id, title: "Root", estimatedDays: 5)
        let left = Objective(id: uuid(22), goalID: goal.id, title: "Left", estimatedDays: 10, dependsOnIDs: [root.id])
        let right = Objective(id: uuid(23), goalID: goal.id, title: "Right", estimatedDays: 30, dependsOnIDs: [root.id])
        let result = ScheduleEngine.backSchedule(objectives: [root, left, right], goal: goal, today: day("2026-10-20"))
        // root must finish before left starts (31 Dec − 10) and before right starts (31 Dec − 30): the earlier wins.
        XCTAssertEqual(result.deadlines[root.id], day("2026-12-01"))
    }

    // MARK: Cycles (F8.2)

    func testWouldCreateCycle() {
        let (_, objectives) = chain()
        let (first, second, third) = (objectives[0].id, objectives[1].id, objectives[2].id)
        XCTAssertTrue(ScheduleEngine.wouldCreateCycle(objectives: objectives, from: first, to: third)) // third → second → first
        XCTAssertTrue(ScheduleEngine.wouldCreateCycle(objectives: objectives, from: first, to: second))
        XCTAssertTrue(ScheduleEngine.wouldCreateCycle(objectives: objectives, from: first, to: first))
        XCTAssertFalse(ScheduleEngine.wouldCreateCycle(objectives: objectives, from: third, to: first))
        XCTAssertFalse(ScheduleEngine.wouldCreateCycle(objectives: objectives, from: second, to: uuid(99)))
    }

    func testTopologicalOrder() {
        let (_, objectives) = chain()
        XCTAssertEqual(ScheduleEngine.topologicalOrder(objectives.reversed()), objectives.map(\.id))
        var cyclic = objectives
        cyclic[0].dependsOnIDs = [objectives[2].id]
        XCTAssertNil(ScheduleEngine.topologicalOrder(cyclic))
    }

    // MARK: Materialising (§5.3)

    func rule(weekdays: [Int] = [7], physical: Bool = false) -> BlockRule {
        BlockRule(id: uuid(60), systemID: uuid(50), title: "Meal prep", durationMinutes: 90, weekdays: weekdays,
                  startTime: 1020, windowStart: 960, windowEnd: 1200, isPhysical: physical, nudge: true)
    }

    func testMaterialiseCreatesOneBlockPerMatchingDay() {
        let system = GoalSystem(id: uuid(50), goalID: uuid(1), title: "Meals")
        let blocks = ScheduleEngine.materialise(rules: [rule()], existing: [], from: day("2026-10-19"), days: 14,
                                                settings: settings, systems: [system])
        XCTAssertEqual(blocks.map(\.day), [day("2026-10-25"), day("2026-11-01")])
        XCTAssertEqual(blocks[0].start, at("2026-10-25", "17:00")) // right on the day the clocks change
        XCTAssertEqual(blocks[0].durationMinutes, 90)
        XCTAssertEqual(blocks[0].goalID, uuid(1))
        XCTAssertEqual(blocks[0].ruleID, uuid(60))
        XCTAssertEqual(blocks[0].status, .scheduled)
        XCTAssertTrue(blocks[0].nudge)
    }

    func testMaterialiseSkipsExistingDatesAndInactiveRules() {
        let existing = CalendarBlock(ruleID: uuid(60), title: "Meal prep", start: at("2026-10-25", "17:00"),
                                     end: at("2026-10-25", "18:30"), status: .cancelled)
        let blocks = ScheduleEngine.materialise(rules: [rule()], existing: [existing], from: day("2026-10-19"), days: 14, settings: settings)
        XCTAssertEqual(blocks.map(\.day), [day("2026-11-01")]) // a cancelled block is not recreated
        var inactive = rule()
        inactive.active = false
        XCTAssertTrue(ScheduleEngine.materialise(rules: [inactive], existing: [], from: day("2026-10-19"), days: 14, settings: settings).isEmpty)
    }

    func testMaterialiseSkipsSaturdayUnlessPhysical() {
        let plain = ScheduleEngine.materialise(rules: [rule(weekdays: [6])], existing: [], from: day("2026-10-19"), days: 7, settings: settings)
        XCTAssertTrue(plain.isEmpty)
        let physical = ScheduleEngine.materialise(rules: [rule(weekdays: [6], physical: true)], existing: [], from: day("2026-10-19"), days: 7, settings: settings)
        XCTAssertEqual(physical.map(\.day), [day("2026-10-24")])
        var open = settings
        open.saturdayOff = false
        XCTAssertEqual(ScheduleEngine.materialise(rules: [rule(weekdays: [6])], existing: [], from: day("2026-10-19"), days: 7, settings: open).count, 1)
    }

    // MARK: Clashes (§5.4, F9.4)

    func block(_ dayText: String = "2026-10-21", from: String = "10:00", to: String = "11:00", status: BlockStatus = .scheduled) -> CalendarBlock {
        CalendarBlock(id: uuid(70), title: "Study", start: at(dayText, from), end: at(dayText, to), status: status)
    }

    func busy(_ dayText: String, _ from: String, _ to: String, id: String? = "ev1") -> BusyInterval {
        BusyInterval(start: at(dayText, from), end: at(dayText, to), eventID: id)
    }

    let now = at("2026-10-20", "09:00")

    func testOverlapBecomesClash() {
        let result = ScheduleEngine.detectClashes(blocks: [block()], busy: [busy("2026-10-21", "10:30", "12:00")], settings: settings, now: now)
        XCTAssertEqual(result[0].status, .clash)
    }

    func testTravelBufferCountsOnBothSides() {
        // 15 min buffer: an event ending 09:50 reaches into a 10:00 block; one ending 09:40 does not.
        let near = ScheduleEngine.detectClashes(blocks: [block()], busy: [busy("2026-10-21", "09:00", "09:50")], settings: settings, now: now)
        XCTAssertEqual(near[0].status, .clash)
        let far = ScheduleEngine.detectClashes(blocks: [block()], busy: [busy("2026-10-21", "09:00", "09:40")], settings: settings, now: now)
        XCTAssertEqual(far[0].status, .scheduled)
        let after = ScheduleEngine.detectClashes(blocks: [block()], busy: [busy("2026-10-21", "11:10", "12:00")], settings: settings, now: now)
        XCTAssertEqual(after[0].status, .clash)
        var noBuffer = settings
        noBuffer.travelBufferMinutes = 0
        let touching = ScheduleEngine.detectClashes(blocks: [block()], busy: [busy("2026-10-21", "11:00", "12:00")], settings: noBuffer, now: now)
        XCTAssertEqual(touching[0].status, .scheduled)
    }

    func testIgnoredEventsDoNotClash() {
        var kept = block()
        kept.ignoredClashEventIDs = ["ev1"]
        let result = ScheduleEngine.detectClashes(blocks: [kept], busy: [busy("2026-10-21", "10:00", "11:00")], settings: settings, now: now)
        XCTAssertEqual(result[0].status, .scheduled)
        let other = ScheduleEngine.detectClashes(blocks: [kept], busy: [busy("2026-10-21", "10:00", "11:00", id: "ev2")], settings: settings, now: now)
        XCTAssertEqual(other[0].status, .clash)
    }

    func testClashClearsWhenEventMoves() {
        var clashing = block(status: .clash)
        clashing.suggestedStart = at("2026-10-21", "12:00")
        let result = ScheduleEngine.detectClashes(blocks: [clashing], busy: [], settings: settings, now: now)
        XCTAssertEqual(result[0].status, .scheduled)
        XCTAssertNil(result[0].suggestedStart)
    }

    func testPastDoneAndCancelledBlocksAreLeftAlone() {
        let overlap = [busy("2026-10-19", "09:00", "12:00"), busy("2026-10-21", "09:00", "12:00")]
        let past = block("2026-10-19")
        let done = block(status: .done)
        let cancelled = block(status: .cancelled)
        let result = ScheduleEngine.detectClashes(blocks: [past, done, cancelled], busy: overlap, settings: settings, now: now)
        XCTAssertEqual(result.map(\.status), [.scheduled, .done, .cancelled])
    }

    func testStillClashingKeepsSuggestion() {
        var clashing = block(status: .clash)
        clashing.suggestedStart = at("2026-10-21", "12:00")
        let result = ScheduleEngine.detectClashes(blocks: [clashing], busy: [busy("2026-10-21", "10:00", "11:00")], settings: settings, now: now)
        XCTAssertEqual(result[0].status, .clash)
        XCTAssertEqual(result[0].suggestedStart, at("2026-10-21", "12:00"))
    }

    // MARK: Slot suggestion (§5.4)

    func sundayRule() -> BlockRule {
        BlockRule(id: uuid(61), systemID: uuid(50), title: "Meal prep", durationMinutes: 90, weekdays: [7],
                  startTime: 1020, windowStart: 960, windowEnd: 1200)
    }

    func testSuggestionIsEarliestFreeStartInsideWindow() {
        let target = CalendarBlock(id: uuid(71), ruleID: uuid(61), title: "Meal prep", start: at("2026-10-25", "17:00"), end: at("2026-10-25", "18:30"))
        // Event 16:30–17:30 plus 15 min buffer blocks until 17:45; 16:00–16:15 is too short for 90 min.
        let slot = ScheduleEngine.suggestSlot(for: target, rule: sundayRule(), busy: [busy("2026-10-25", "16:30", "17:30")], blocks: [target], settings: settings)
        XCTAssertEqual(slot, at("2026-10-25", "17:45"))
        // With nothing in the way the window start wins.
        XCTAssertEqual(ScheduleEngine.suggestSlot(for: target, rule: sundayRule(), busy: [], blocks: [target], settings: settings), at("2026-10-25", "16:00"))
    }

    func testSuggestionSkipsSaturdayAndAvoidsOtherBlocks() {
        let friday = CalendarBlock(id: uuid(72), ruleID: uuid(61), title: "Study", start: at("2026-10-23", "16:00"), end: at("2026-10-23", "17:30"))
        var rule = sundayRule()
        rule.weekdays = [5]
        let fullFriday = busy("2026-10-23", "15:00", "19:00")
        let sundayBlock = CalendarBlock(title: "Other", start: at("2026-10-25", "16:00"), end: at("2026-10-25", "17:30"))
        let slot = ScheduleEngine.suggestSlot(for: friday, rule: rule, busy: [fullFriday], blocks: [friday, sundayBlock], settings: settings)
        // Saturday is skipped; on Sunday the other block holds 16:00–17:30, so the first fit is 17:30–19:00.
        XCTAssertEqual(slot, at("2026-10-25", "17:30"))
    }

    func testPhysicalBlockMayMoveToSaturday() {
        var physical = CalendarBlock(id: uuid(73), ruleID: uuid(61), title: "Run", start: at("2026-10-23", "16:00"), end: at("2026-10-23", "17:30"))
        physical.isPhysical = true
        var rule = sundayRule()
        rule.isPhysical = true
        let slot = ScheduleEngine.suggestSlot(for: physical, rule: rule, busy: [busy("2026-10-23", "15:00", "19:00")], blocks: [physical], settings: settings)
        XCTAssertEqual(slot, at("2026-10-24", "16:00"))
    }

    func testCancelledBlocksDoNotObstructAndNoSlotReturnsNil() {
        let target = CalendarBlock(id: uuid(74), ruleID: uuid(61), title: "Meal prep", start: at("2026-10-25", "17:00"), end: at("2026-10-25", "18:30"))
        let cancelled = CalendarBlock(title: "Gone", start: at("2026-10-25", "16:00"), end: at("2026-10-25", "17:30"), status: .cancelled)
        XCTAssertEqual(ScheduleEngine.suggestSlot(for: target, rule: sundayRule(), busy: [], blocks: [target, cancelled], settings: settings), at("2026-10-25", "16:00"))
        // Busy for the whole of the next 8 days inside the window → nothing free.
        let wall = (0...8).map { busy(day("2026-10-25").adding(days: $0).string, "00:00", "23:59", id: "w\($0)") }
        XCTAssertNil(ScheduleEngine.suggestSlot(for: target, rule: sundayRule(), busy: wall, blocks: [target], settings: settings))
    }

    func testOneOffBlockUsesBestHours() {
        // Wednesday best hours: 08–10, 14–17, 19–21. A 2 h block does not fit 08–10 once 08:30–09:00 is busy (+15 buffer).
        let oneOff = CalendarBlock(id: uuid(75), title: "Revise", start: at("2026-10-21", "08:00"), end: at("2026-10-21", "10:00"))
        let slot = ScheduleEngine.suggestSlot(for: oneOff, rule: nil, busy: [busy("2026-10-21", "08:30", "09:00")], blocks: [oneOff], settings: settings)
        XCTAssertEqual(slot, at("2026-10-21", "14:00"))
    }

    // MARK: Feasibility (§4.7)

    func feasibilitySnapshot(habitMinutes: Int, extra: [Habit] = []) -> (Goal, StoreSnapshot) {
        let goal = makeGoal()
        var settings = AppSettings.defaults
        settings.bestHours = [TimeWindow(weekday: 1, start: 480, end: 1020)] // Monday 08:00–17:00 = 540 min
        var habit = makeHabit(1, goal: goal.id, frequency: .daily)
        habit.durationMinutes = habitMinutes
        return (goal, StoreSnapshot(settings: settings, goals: [goal], habits: [habit] + extra))
    }

    func testFeasibilityWarningThreshold() {
        let now = at("2026-10-19", "00:00")
        // 60 min × 7 = 420 ≤ 0.8 × 540 = 432: fine.
        var (goal, snapshot) = feasibilitySnapshot(habitMinutes: 60)
        var report = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [], now: now)
        XCTAssertEqual(report.freeMinutes, 540)
        XCTAssertEqual(report.neededMinutes, 420)
        XCTAssertFalse(report.isWarning)
        XCTAssertNil(report.message)
        // 65 × 7 = 455 > 432: warn.
        (goal, snapshot) = feasibilitySnapshot(habitMinutes: 65)
        report = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [], now: now)
        XCTAssertTrue(report.isWarning)
        XCTAssertEqual(report.message, "This plan needs 7.6 h a week. You have 9 h free in your best hours.")
    }

    func testFeasibilitySubtractsBusyTimeWithBuffer() {
        let (goal, snapshot) = feasibilitySnapshot(habitMinutes: 30)
        // 10:00–12:00 plus 15 min each side = 150 min of the 540.
        let report = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [busy("2026-10-19", "10:00", "12:00")], now: at("2026-10-19", "00:00"))
        XCTAssertEqual(report.freeMinutes, 390)
        // Busy time outside the best hours changes nothing.
        let evening = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [busy("2026-10-19", "20:00", "22:00")], now: at("2026-10-19", "00:00"))
        XCTAssertEqual(evening.freeMinutes, 540)
    }

    func testFeasibilityCountsBlockRulesAndOtherGoals() {
        var (goal, snapshot) = feasibilitySnapshot(habitMinutes: 30) // 210 min of habits
        let system = GoalSystem(id: uuid(80), goalID: goal.id, title: "Meals")
        snapshot.systems = [system]
        snapshot.blockRules = [BlockRule(systemID: system.id, title: "Prep", durationMinutes: 90, weekdays: [3, 7], startTime: 600)]
        let other = makeGoal(2)
        snapshot.goals.append(other)
        var otherHabit = makeHabit(2, goal: other.id, frequency: .weekdays([1, 2]))
        otherHabit.durationMinutes = 60 // 120 min
        snapshot.habits.append(otherHabit)
        let report = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [], now: at("2026-10-19", "00:00"))
        XCTAssertEqual(report.neededMinutes, 210 + 180)
        XCTAssertEqual(report.freeMinutes, 540 - 120)
    }

    func testFeasibilityExcludesSaturdayWhenOff() {
        var (goal, snapshot) = feasibilitySnapshot(habitMinutes: 15)
        snapshot.settings.bestHours = [TimeWindow(weekday: 6, start: 600, end: 720)]
        XCTAssertEqual(ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [], now: at("2026-10-19", "00:00")).freeMinutes, 0)
        snapshot.settings.saturdayOff = false
        goal = snapshot.goals[0]
        XCTAssertEqual(ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: [], now: at("2026-10-19", "00:00")).freeMinutes, 120)
    }

    // MARK: Map layout (§4.8)

    func testMapLayoutForSampleGoal() {
        let snapshot = SampleData.bodyFatGoal(today: day("2026-10-21"))
        let map = ScheduleEngine.mapLayout(goalID: SampleData.goalID, snapshot: snapshot)
        XCTAssertEqual(map.layers.count, 6)
        XCTAssertEqual(map.layers[0].map(\.kind), [.goal])
        XCTAssertEqual(map.layers[1].map(\.id), [SampleData.principleDeficitID, SampleData.principleMuscleID, SampleData.principleMovementID])
        XCTAssertEqual(map.layers[2].map(\.id), [SampleData.mealsSystemID, SampleData.liftingSystemID, SampleData.walkSystemID])
        XCTAssertEqual(map.layers[3].map(\.id), [SampleData.objective84ID])
        XCTAssertEqual(map.layers[4].map(\.id), [SampleData.objective82ID])
        XCTAssertEqual(map.layers[5].map(\.id), [SampleData.objective80ID])
        XCTAssertEqual(map.sustaining?.id, SampleData.sleepSystemID)
        XCTAssertEqual(map.sustaining?.layer, 6)
        let edges = Set(map.edges)
        XCTAssertTrue(edges.contains(.init(from: SampleData.goalID, to: SampleData.principleMuscleID)))
        XCTAssertTrue(edges.contains(.init(from: SampleData.principleMuscleID, to: SampleData.liftingSystemID)))
        XCTAssertTrue(edges.contains(.init(from: SampleData.mealsSystemID, to: SampleData.objective84ID)))
        XCTAssertTrue(edges.contains(.init(from: SampleData.objective84ID, to: SampleData.objective82ID)))
        XCTAssertFalse(edges.contains(.init(from: SampleData.objective84ID, to: SampleData.objective80ID)))
    }

    func testMapLayoutUsesLongestPathDepthAndMissingGoal() {
        var snapshot = SampleData.bodyFatGoal(today: day("2026-10-21"))
        // 80 kg now also depends directly on the first objective: longest path still puts it on layer 5.
        snapshot.objectives[2].dependsOnIDs.append(SampleData.objective84ID)
        // A free objective with no dependencies sits on layer 3 next to 84.
        snapshot.objectives.append(Objective(goalID: SampleData.goalID, title: "Side quest", sortIndex: 3))
        let map = ScheduleEngine.mapLayout(goalID: SampleData.goalID, snapshot: snapshot)
        XCTAssertEqual(map.layers[3].count, 2)
        XCTAssertEqual(map.layers[5].map(\.id), [SampleData.objective80ID])
        XCTAssertEqual(ScheduleEngine.mapLayout(goalID: uuid(404), snapshot: snapshot), MapLayout())
    }
}
