import XCTest
@testable import CoreKit

final class ReminderPlannerTests: XCTestCase {
    // Tuesday 20 Oct 2026, 06:00. The next Monday is the 26th.
    let now = at("2026-10-20", "06:00")
    let goal = makeGoal()

    func snapshot(habits: [Habit] = [], logs: [HabitLog] = [], blocks: [CalendarBlock] = [], reminders: [PlanReminder] = [],
                  systems: [GoalSystem] = [], goals: [Goal]? = nil, settings: AppSettings = .defaults) -> StoreSnapshot {
        StoreSnapshot(settings: settings, goals: goals ?? [goal], systems: systems, habits: habits, logs: logs,
                      blockRules: [], blocks: blocks, reminders: reminders)
    }

    func plan(_ snapshot: StoreSnapshot, expiry: Date? = nil, now: Date? = nil) -> [PlannedNotification] {
        ReminderPlanner.plan(snapshot: snapshot, now: now ?? self.now, signingExpiry: expiry)
    }

    func ofKind(_ kind: NotificationKind, _ list: [PlannedNotification]) -> [PlannedNotification] { list.filter { $0.kind == kind } }
    func on(_ dayText: String, _ list: [PlannedNotification]) -> [PlannedNotification] {
        list.filter { LocalDay($0.fireDate) == day(dayText) }
    }

    /// A goal with no habits keeps the Monday check-in out of the way of tests that don't care about it.
    var noGoals: [Goal] { [] }

    // MARK: Text templates (§6.4)

    func testTimedHabitText() {
        let system = GoalSystem(id: uuid(50), goalID: goal.id, title: "Walk", location: "Gym")
        var walk = makeHabit(1, title: "Incline walk", goal: goal.id, system: system.id, reminder: "08:15")
        walk.badDayTitle = "20 min walk"
        let list = plan(snapshot(habits: [walk], systems: [system], goals: noGoals))
        let nudge = ofKind(.habit, list).first!
        XCTAssertEqual(nudge.id, "habit-\(walk.id.uuidString)-2026-10-20")
        XCTAssertEqual(nudge.title, "Incline walk.")
        XCTAssertEqual(nudge.body, "08:15 at Gym. Bad day: 20 min walk.")
        XCTAssertEqual(nudge.fireDate, at("2026-10-20", "08:15"))
        XCTAssertEqual(nudge.link, .habit(walk.id, day("2026-10-20")))
    }

    func testTimedHabitWithoutLocation() {
        var walk = makeHabit(1, title: "Read", reminder: "20:00")
        walk.badDayTitle = "1 page"
        let nudge = ofKind(.habit, plan(snapshot(habits: [walk], goals: noGoals))).first!
        XCTAssertEqual(nudge.body, "20:00. Bad day: 1 page.")
    }

    func testMorningTextWithBlocksAndFirstItem() {
        let lift = makeHabit(1, title: "Lift", reminder: "17:00")
        let early = makeHabit(2, title: "Stretch", reminder: "08:15")
        let untimed = makeHabit(3, title: "Protein")
        let prep = CalendarBlock(title: "Meal prep", start: at("2026-10-21", "09:00"), end: at("2026-10-21", "10:30"))
        let list = plan(snapshot(habits: [lift, early, untimed], blocks: [prep], goals: noGoals))
        let tuesday = ofKind(.morning, on("2026-10-21", list)).first!
        XCTAssertEqual(tuesday.id, "morning-2026-10-21")
        XCTAssertEqual(tuesday.title, "Today.")
        XCTAssertEqual(tuesday.body, "1 blocks, 3 habits. First: Stretch at 08:15.")
        XCTAssertEqual(tuesday.fireDate, at("2026-10-21", "07:30"))
        XCTAssertEqual(tuesday.link, .today)
        // No blocks that day: the "0 blocks, " part is left out.
        let thursday = ofKind(.morning, on("2026-10-22", list)).first!
        XCTAssertEqual(thursday.body, "3 habits. First: Stretch at 08:15.")
    }

    func testMorningTextWhenNothingIsTimed() {
        let list = plan(snapshot(habits: [makeHabit(1), makeHabit(2)], goals: noGoals))
        XCTAssertEqual(ofKind(.morning, list).first!.body, "2 habits today.")
    }

    func testMorningUsesWeekendTimeAndNeedsSomethingToDo() {
        let mwf = makeHabit(1, frequency: .weekdays([1, 3, 5]))
        let list = plan(snapshot(habits: [mwf], goals: noGoals))
        XCTAssertEqual(ofKind(.morning, list).map(\.id), ["morning-2026-10-21", "morning-2026-10-23", "morning-2026-10-26", "morning-2026-10-28"]) // Fri 30 Oct 07:30 is past the window end (06:00)
        let weekend = plan(snapshot(habits: [makeHabit(2)], goals: noGoals))
        XCTAssertEqual(ofKind(.morning, on("2026-10-24", weekend)).first!.fireDate, at("2026-10-24", "09:00"))
        XCTAssertEqual(ofKind(.morning, on("2026-10-23", weekend)).first!.fireDate, at("2026-10-23", "07:30"))
    }

    func testMorningCountsABlockOnItsOwn() {
        let block = CalendarBlock(title: "Gym", start: at("2026-10-21", "18:00"), end: at("2026-10-21", "19:00"))
        let list = plan(snapshot(blocks: [block], goals: noGoals))
        XCTAssertEqual(ofKind(.morning, list).map(\.body), ["1 blocks, 0 habits. First: Gym at 18:00."])
    }

    func testBlockNudgeText() {
        let block = CalendarBlock(title: "Meal prep", start: at("2026-10-21", "09:00"), end: at("2026-10-21", "10:30"), nudge: true)
        let list = plan(snapshot(blocks: [block], goals: noGoals))
        let nudge = ofKind(.block, list).first!
        XCTAssertEqual(nudge.id, "block-\(block.id.uuidString)")
        XCTAssertEqual(nudge.title, "Meal prep.")
        XCTAssertEqual(nudge.body, "Starts 09:00, 90 min.")
        XCTAssertEqual(nudge.fireDate, at("2026-10-21", "08:50"))
        XCTAssertEqual(nudge.link, .block(block.id))
    }

    func testBlockNudgeOnlyForScheduledNudgeBlocks() {
        func block(_ status: BlockStatus, nudge: Bool) -> CalendarBlock {
            CalendarBlock(title: "B", start: at("2026-10-21", "09:00"), end: at("2026-10-21", "10:00"), status: status, nudge: nudge)
        }
        let blocks = [block(.scheduled, nudge: false), block(.clash, nudge: true), block(.done, nudge: true), block(.cancelled, nudge: true)]
        XCTAssertTrue(ofKind(.block, plan(snapshot(blocks: blocks, goals: noGoals))).isEmpty)
    }

    func testPlanReminderText() {
        let once = PlanReminder(title: "Order the food shop", body: "Protein, oats, frozen veg.", date: day("2026-10-22"), time: 600)
        let weekly = PlanReminder(title: "Weigh in", body: "Before breakfast.", weekdays: [1], time: 450)
        let list = plan(snapshot(reminders: [once, weekly], goals: noGoals))
        let reminders = ofKind(.reminder, list)
        XCTAssertEqual(reminders.map(\.id), ["reminder-\(once.id.uuidString)-2026-10-22", "reminder-\(weekly.id.uuidString)-2026-10-26"])
        XCTAssertEqual(reminders[0].title, "Order the food shop")
        XCTAssertEqual(reminders[0].body, "Protein, oats, frozen veg.")
        XCTAssertEqual(reminders[0].fireDate, at("2026-10-22", "10:00"))
        var inactive = once
        inactive.active = false
        XCTAssertTrue(ofKind(.reminder, plan(snapshot(reminders: [inactive], goals: noGoals))).isEmpty)
    }

    func testEveningTextAndMoreSuffix() {
        let habits = (1...5).map { makeHabit($0, title: "H\($0)", priority: $0) }
        let list = plan(snapshot(habits: habits, goals: noGoals))
        let evening = ofKind(.evening, on("2026-10-20", list)).first!
        XCTAssertEqual(evening.id, "evening-2026-10-20")
        XCTAssertEqual(evening.title, "Tick off today.")
        XCTAssertEqual(evening.body, "5 left: H1, H2, H3 +2 more.")
        XCTAssertEqual(evening.fireDate, at("2026-10-20", "21:30"))
        XCTAssertEqual(evening.link, .today)
        let three = plan(snapshot(habits: Array(habits.prefix(3)), goals: noGoals))
        XCTAssertEqual(ofKind(.evening, on("2026-10-20", three)).first!.body, "3 left: H1, H2, H3.")
        let one = plan(snapshot(habits: Array(habits.prefix(1)), goals: noGoals))
        XCTAssertEqual(ofKind(.evening, on("2026-10-20", one)).first!.body, "1 left: H1.")
    }

    func testEveningOnlyListsUnmarkedHabits() {
        let a = makeHabit(1, title: "A")
        let b = makeHabit(2, title: "B")
        let list = plan(snapshot(habits: [a, b], logs: [makeLog(a, "2026-10-20", .D)], goals: noGoals))
        XCTAssertEqual(ofKind(.evening, on("2026-10-20", list)).first!.body, "1 left: B.")
        // Everything marked: no evening at all that day, but tomorrow still has one.
        let done = plan(snapshot(habits: [a], logs: [makeLog(a, "2026-10-20", .B)], goals: noGoals))
        XCTAssertTrue(ofKind(.evening, on("2026-10-20", done)).isEmpty)
        XCTAssertFalse(ofKind(.evening, on("2026-10-21", done)).isEmpty)
    }

    func testCheckInTextAndCondition() {
        let habit = makeHabit(1, goal: goal.id, frequency: .daily, setPoint: 2)
        let logs = [makeLog(habit, "2026-10-12", .D), makeLog(habit, "2026-10-13", .D)] // last week: on target
        let list = plan(snapshot(habits: [habit], logs: logs, goals: [goal]), now: at("2026-10-17", "06:00"))
        let checkIn = ofKind(.checkIn, list)
        // Monday the 19th looks back at the week of 12 Oct; Monday the 26th at the week of 19 Oct.
        XCTAssertEqual(checkIn.map(\.id), ["checkin-2026-10-19", "checkin-2026-10-26"])
        XCTAssertEqual(checkIn[0].title, "Check-in.")
        XCTAssertEqual(checkIn[0].body, "Last week: 1 of 1 on target. About 5 minutes.")
        XCTAssertEqual(checkIn[0].fireDate, at("2026-10-19", "19:00"))
        XCTAssertEqual(checkIn[0].link, .week)
        XCTAssertEqual(checkIn[1].body, "Last week: 0 of 1 on target. About 5 minutes.")
    }

    func testFinishedReviewRemovesThatCheckIn() {
        let habit = makeHabit(1, goal: goal.id)
        let review = WeekReview(goalID: goal.id, weekStart: day("2026-10-12"), finishedAt: at("2026-10-19", "19:30"))
        var snap = snapshot(habits: [habit], goals: [goal])
        snap.weekReviews = [review]
        let list = plan(snap, now: at("2026-10-19", "08:00"))
        XCTAssertEqual(ofKind(.checkIn, list).map(\.id), ["checkin-2026-10-26"])
        var paused = goal
        paused.status = .paused
        XCTAssertTrue(ofKind(.checkIn, plan(snapshot(habits: [habit], goals: [paused]))).isEmpty)
    }

    func testResignText() {
        let expiry = at("2026-10-24", "12:00")
        let list = plan(snapshot(goals: noGoals), expiry: expiry)
        let resign = ofKind(.resign, list).first!
        XCTAssertEqual(resign.id, "resign")
        XCTAssertEqual(resign.title, "Re-sign Lock in.")
        XCTAssertEqual(resign.body, "It stops opening Sat 24 Oct at 12:00. Your data is safe. Plug in and run Sideloadly.")
        XCTAssertEqual(resign.fireDate, at("2026-10-22", "12:00")) // expiry − 48 h
        XCTAssertEqual(resign.link, .settings)
    }

    func testResignTimingAndWindow() {
        // Inside 48 h: later of the two → now + 1 min.
        let soon = ofKind(.resign, plan(snapshot(goals: noGoals), expiry: at("2026-10-21", "12:00"))).first!
        XCTAssertEqual(soon.fireDate, now.addingTimeInterval(60))
        // More than 7 days away, already expired, or unknown: nothing.
        XCTAssertTrue(ofKind(.resign, plan(snapshot(goals: noGoals), expiry: at("2026-10-28", "12:00"))).isEmpty)
        XCTAssertTrue(ofKind(.resign, plan(snapshot(goals: noGoals), expiry: at("2026-10-19", "12:00"))).isEmpty)
        XCTAssertTrue(ofKind(.resign, plan(snapshot(goals: noGoals), expiry: nil)).isEmpty)
        // Exactly 7 days is still within 7 days.
        XCTAssertEqual(ofKind(.resign, plan(snapshot(goals: noGoals), expiry: at("2026-10-27", "06:00"))).count, 1)
    }

    // MARK: Timed rules (§6.1)

    func testHabitMarkedBeforeReminderGetsNoNudge() {
        let walk = makeHabit(1, reminder: "08:15")
        let open = ofKind(.habit, on("2026-10-20", plan(snapshot(habits: [walk], goals: noGoals))))
        XCTAssertEqual(open.count, 1)
        for mark in [Mark.D, .B, .M] { // M is a skip and cancels it too (§6.5)
            let marked = ofKind(.habit, on("2026-10-20", plan(snapshot(habits: [walk], logs: [makeLog(walk, "2026-10-20", mark)], goals: noGoals))))
            XCTAssertTrue(marked.isEmpty, "mark \(mark)")
        }
        // Tomorrow's nudge is unaffected.
        let tomorrow = ofKind(.habit, on("2026-10-21", plan(snapshot(habits: [walk], logs: [makeLog(walk, "2026-10-20", .D)], goals: noGoals))))
        XCTAssertEqual(tomorrow.count, 1)
    }

    func testNudgeOnlyOnScheduledDays() {
        let lift = makeHabit(1, frequency: .weekdays([1, 3, 5]), reminder: "17:00")
        let list = ofKind(.habit, plan(snapshot(habits: [lift], goals: noGoals)))
        XCTAssertEqual(list.map { LocalDay($0.fireDate).string }, ["2026-10-21", "2026-10-23", "2026-10-26", "2026-10-28"]) // Fri 30 Oct 17:00 is past the window end (06:00)
    }

    func testPerWeekNudgeNeedsPreferredDayAndShortOfN() {
        let walk = makeHabit(1, frequency: .perWeek(2), reminder: "08:15", preferred: [2, 4])
        let marks = [makeLog(walk, "2026-10-19", .D), makeLog(walk, "2026-10-20", .D)]
        let fresh = ofKind(.habit, plan(snapshot(habits: [walk], goals: noGoals)))
        // Preferred days only: Tue 20 (today, 08:15 still ahead), Thu 22, Tue 27, Thu 29.
        XCTAssertEqual(fresh.map { LocalDay($0.fireDate).string }, ["2026-10-20", "2026-10-22", "2026-10-27", "2026-10-29"])
        // Two D marks this week: the rest of this week goes quiet, next week is back.
        let done = ofKind(.habit, plan(snapshot(habits: [walk], logs: marks, goals: noGoals)))
        XCTAssertEqual(done.map { LocalDay($0.fireDate).string }, ["2026-10-27", "2026-10-29"])
        // No preferred days: no nudges.
        var noDays = walk
        noDays.preferredWeekdays = []
        XCTAssertTrue(ofKind(.habit, plan(snapshot(habits: [noDays], goals: noGoals))).isEmpty)
    }

    func testArchivedHabitsDoNotNotify() {
        let walk = makeHabit(1, reminder: "08:15", archived: true)
        XCTAssertTrue(plan(snapshot(habits: [walk], goals: noGoals)).isEmpty)
    }

    // MARK: Daily cap and priority (§6.2, F4.2)

    func sixTimedHabits() -> [Habit] {
        // Priorities 1…6 would be invalid, so use 1,1,2,3,4,5 with distinct times; later times win ties by earliest.
        [(1, "10:00", 4), (2, "09:00", 5), (3, "11:00", 1), (4, "12:00", 3), (5, "13:00", 2), (6, "08:00", 1)].map { n, time, priority in
            makeHabit(n, title: "T\(n)", reminder: time, priority: priority)
        }
    }

    func testOnlyFourTimedNudgesPerDay() {
        let list = plan(snapshot(habits: sixTimedHabits(), goals: noGoals))
        let tuesday = ofKind(.habit, on("2026-10-21", list))
        XCTAssertEqual(tuesday.count, 4)
        // Kept: priority 1 (T6 08:00, T3 11:00), 2 (T5), 3 (T4). Dropped: priority 4 and 5.
        XCTAssertEqual(tuesday.map(\.title), ["T6.", "T3.", "T4.", "T5."])
        // Day total: morning + evening + 4 = 6, never more.
        XCTAssertEqual(on("2026-10-21", list).count, 6)
        // The dropped ones still show up in the evening tick-off count.
        XCTAssertTrue(ofKind(.evening, on("2026-10-21", list)).first!.body.hasPrefix("6 left:"))
    }

    func testEqualPriorityGoesToTheEarlierNudge() {
        let habits = (1...5).map { makeHabit($0, title: "E\($0)", reminder: String(format: "%02d:00", 18 - $0), priority: 3) }
        let list = plan(snapshot(habits: habits, goals: noGoals))
        XCTAssertEqual(ofKind(.habit, on("2026-10-21", list)).map(\.title), ["E5.", "E4.", "E3.", "E2."]) // E1 at 17:00 loses
    }

    func testCheckInTakesOneTimedSlotOnMonday() {
        let habits = sixTimedHabits().map { habit -> Habit in var h = habit; h.goalID = goal.id; return h }
        let list = plan(snapshot(habits: habits, goals: [goal]))
        let monday = on("2026-10-26", list)
        XCTAssertEqual(ofKind(.checkIn, monday).count, 1)
        XCTAssertEqual(ofKind(.habit, monday).count, 3)
        XCTAssertEqual(monday.count, 6) // morning + evening + check-in + 3
        // On other days all 4 remain.
        XCTAssertEqual(ofKind(.habit, on("2026-10-27", list)).count, 4)
    }

    func testBlocksAndRemindersCompeteWithHabitsByPriority() {
        let habits = (1...4).map { makeHabit($0, title: "H\($0)", reminder: "10:0\($0)", priority: 4) }
        let block = CalendarBlock(title: "Lab", start: at("2026-10-21", "15:00"), end: at("2026-10-21", "16:00"), nudge: true)
        let urgent = PlanReminder(title: "Submit form", date: day("2026-10-21"), time: 1080, priority: 1)
        let list = on("2026-10-21", plan(snapshot(habits: habits, blocks: [block], reminders: [urgent], goals: noGoals)))
        let timed = list.filter { [.habit, .block, .reminder].contains($0.kind) }
        XCTAssertEqual(timed.count, 4)
        XCTAssertTrue(timed.contains { $0.title == "Submit form" }) // priority 1 beats the rest
        XCTAssertEqual(timed.filter { $0.kind == .habit }.count, 2) // 3 + 3 + 3 + 3 vs one 1: habits H1, H2 by time
        XCTAssertEqual(timed.filter { $0.kind == .block }.count, 1)
        XCTAssertFalse(timed.contains { $0.title == "H3." })
    }

    func testMarkingFreesSlotForTheNextPriority() {
        let habits = sixTimedHabits()
        let marked = makeLog(habits[5], "2026-10-21", .D) // T6, priority 1, 08:00
        let list = plan(snapshot(habits: habits, logs: [marked], goals: noGoals))
        XCTAssertEqual(ofKind(.habit, on("2026-10-21", list)).map(\.title), ["T1.", "T3.", "T4.", "T5."])
    }

    // MARK: 60-pending limit (§6.3, F4.4)

    func busySnapshot() -> StoreSnapshot {
        snapshot(habits: sixTimedHabits(), goals: [goal])
    }

    func testAtMostSixtyRegularPlusResign() {
        let list = plan(busySnapshot(), expiry: at("2026-10-23", "12:00"))
        let regular = list.filter { $0.kind != .resign }
        XCTAssertEqual(regular.count, 60)
        XCTAssertEqual(list.count, 61)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count)
        XCTAssertTrue(list.allSatisfy { $0.fireDate > now })
    }

    func testListIsSortedByFireDate() {
        let list = plan(busySnapshot(), expiry: at("2026-10-23", "12:00"))
        XCTAssertEqual(list.map(\.fireDate), list.map(\.fireDate).sorted())
    }

    func testWindowIsTenDaysAndPastIsDropped() {
        let list = plan(snapshot(habits: [makeHabit(1)], goals: noGoals))
        XCTAssertTrue(list.allSatisfy { $0.fireDate > now && $0.fireDate <= at("2026-10-30", "06:00") })
        // Tuesday's morning (07:30) is after 06:00, so it is in; if it is 08:00 already, it is not.
        XCTAssertTrue(list.contains { $0.id == "morning-2026-10-20" })
        let later = plan(snapshot(habits: [makeHabit(1)], goals: noGoals), now: at("2026-10-20", "08:00"))
        XCTAssertFalse(later.contains { $0.id == "morning-2026-10-20" })
        XCTAssertTrue(later.contains { $0.id == "evening-2026-10-20" })
    }

    func testCustomLimits() {
        let list = ReminderPlanner.plan(snapshot: busySnapshot(), now: now, signingExpiry: nil, horizonDays: 3, maxPending: 5)
        XCTAssertEqual(list.count, 5)
    }

    // MARK: Horizon warning (§6.3)

    func testHorizonWarningOnLastEveningOnly() {
        let list = plan(snapshot(habits: [makeHabit(1)], goals: noGoals))
        let evenings = ofKind(.evening, list)
        let suffix = " Open the app to keep reminders coming."
        XCTAssertEqual(evenings.filter { $0.body.hasSuffix(suffix) }.map(\.id), [evenings.last!.id])
        // The window ends Fri 30 Oct 06:00, so the last evening is the 29th.
        XCTAssertEqual(evenings.last!.id, "evening-2026-10-29")
        XCTAssertEqual(evenings.last!.body, "1 left: Habit. Open the app to keep reminders coming.")
        XCTAssertEqual(evenings.first!.body, "1 left: Habit.")
    }

    func testHorizonWarningLandsOnLastKeptEveningWhenCapped() {
        let list = plan(busySnapshot())
        let evenings = ofKind(.evening, list)
        XCTAssertEqual(evenings.filter { $0.body.contains("Open the app") }.count, 1)
        XCTAssertTrue(evenings.last!.body.hasSuffix("Open the app to keep reminders coming."))
    }

    // MARK: Identifiers

    func testIdentifierFormats() {
        let habit = makeHabit(1, reminder: "08:00")
        let block = CalendarBlock(title: "B", start: at("2026-10-21", "09:00"), end: at("2026-10-21", "10:00"), nudge: true)
        let reminder = PlanReminder(title: "R", date: day("2026-10-21"), time: 700)
        let list = plan(snapshot(habits: [habit], blocks: [block], reminders: [reminder]), expiry: at("2026-10-24", "12:00"))
        let ids = Set(list.map(\.id))
        for expected in ["morning-2026-10-21", "evening-2026-10-21", "checkin-2026-10-26", "habit-\(habit.id.uuidString)-2026-10-21",
                         "block-\(block.id.uuidString)", "reminder-\(reminder.id.uuidString)-2026-10-21", "resign"] {
            XCTAssertTrue(ids.contains(expected), expected)
        }
    }
}
