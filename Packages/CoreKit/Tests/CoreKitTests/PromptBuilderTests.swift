import XCTest
@testable import CoreKit

final class PromptBuilderTests: XCTestCase {
    let settings = AppSettings.defaults
    let now = at("2026-10-19", "09:00") // Monday

    func answers() -> IntakeAnswers {
        var answers = IntakeAnswers.defaults(today: day("2026-10-19"), settings: settings)
        answers.goal = "10% body fat"
        answers.resultName = "Weigh-in average"
        answers.unit = "kg"
        answers.current = 86
        answers.target = 78.5
        answers.triedBefore = "Keto, stopped when exams hit"
        answers.hardLimits = "Knee injury"
        answers.hoursPerWeek = 6
        answers.bestPlaces = ["Library", "Gym"]
        answers.stoppers = ["Busy weeks", "Boredom"]
        answers.badDayVersion = "20 min walk"
        return answers
    }

    func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    // MARK: Intake (Appendix B, F6.1, F6.2)

    func testDefaultsAreFilledSoNextAlwaysWorks() {
        let defaults = IntakeAnswers.defaults(today: day("2026-10-19"), settings: settings)
        XCTAssertEqual(defaults.deadline, day("2027-01-17")) // today + 90
        XCTAssertEqual(defaults.hoursPerWeek, 5)
        XCTAssertTrue(defaults.saturdaysOff)
        XCTAssertEqual(defaults.goal, "10% body fat")
        XCTAssertEqual(defaults.bestTimes, [.early, .morning, .afternoon, .evening]) // overlaps the default best hours
        let prompt = PromptBuilder.intakePrompt(answers: defaults, busy: [], settings: settings, now: now)
        XCTAssertTrue(prompt.contains("Goal: 10% body fat"))
    }

    func testIntakePromptMatchesTemplate() {
        let busy = [BusyInterval(start: at("2026-10-20", "09:00"), end: at("2026-10-20", "11:00"), eventID: "a"),
                    BusyInterval(start: at("2026-10-20", "13:00"), end: at("2026-10-20", "15:00"), eventID: "b")]
        let prompt = PromptBuilder.intakePrompt(answers: answers(), busy: busy, settings: settings, now: now)
        let expectedHead = """
        New goal for my goal system. Use my method: work backwards to first principles, one system per principle, one sustaining system, and a DAG of milestones with deadlines. Grill me on anything you still need first, then give the plan and finish with the Lock in plan JSON (schema v1).

        Goal: 10% body fat
        Measured by: Weigh-in average (kg). Now: 86. Target: 78.5. Deadline: 2027-01-17.
        Tried before: Keto, stopped when exams hit
        Resources: Uni gym, £30 a month, a friend who lifts
        Hard limits: Knee injury
        Why it matters: —
        Hours a week: 6
        Best times: Early 06–09, Morning 09–12, Afternoon 12–17, Evening 17–21
        Best places: Library, Gym
        Saturdays off for goal work: yes (physical activity still fine)
        What usually makes me stop: Busy weeks, Boredom
        Smallest bad-day version: 20 min walk
        Today: Mon 19 Oct 2026
        Busy times, next 14 days (06:00–24:00, titles hidden):
        Mon 19 Oct: free
        Tue 20 Oct: 09:00–11:00, 13:00–15:00
        """
        XCTAssertTrue(prompt.hasPrefix(expectedHead), prompt)
        let all = lines(prompt)
        XCTAssertEqual(all.suffix(14).first, "Mon 19 Oct: free")
        XCTAssertEqual(all.last, "Sun 1 Nov: free")
        XCTAssertEqual(all.suffix(14).count, 14)
    }

    func testBusyTimesNotAvailableWhenCalendarIsOff() {
        let prompt = PromptBuilder.intakePrompt(answers: answers(), busy: nil, settings: settings, now: now)
        XCTAssertEqual(lines(prompt).last, "Busy times: not available (calendar access off)")
        XCTAssertFalse(prompt.contains("Busy times, next 14 days"))
        XCTAssertFalse(prompt.contains("free"))
    }

    func testBusyLinesAreClippedAndMerged() {
        let busy = [
            BusyInterval(start: at("2026-10-19", "05:00"), end: at("2026-10-19", "07:00")),        // clipped to 06:00
            BusyInterval(start: at("2026-10-19", "06:30"), end: at("2026-10-19", "08:00")),        // overlaps → merged
            BusyInterval(start: at("2026-10-19", "08:00"), end: at("2026-10-19", "09:00")),        // touches → merged
            BusyInterval(start: at("2026-10-19", "22:00"), end: at("2026-10-20", "02:00")),        // runs past midnight
            BusyInterval(start: at("2026-10-21", "01:00"), end: at("2026-10-21", "05:30")),        // before 06:00 → nothing
            BusyInterval(start: at("2026-10-22", "10:00"), end: at("2026-10-22", "10:00")),        // empty
        ]
        let out = lines(PromptBuilder.intakePrompt(answers: answers(), busy: busy, settings: settings, now: now))
        XCTAssertTrue(out.contains("Mon 19 Oct: 06:00–09:00, 22:00–24:00"), out.joined(separator: "\n"))
        XCTAssertTrue(out.contains("Tue 20 Oct: free")) // the overnight event only reaches 02:00, before the 06:00 start
        XCTAssertTrue(out.contains("Wed 21 Oct: free"))
        XCTAssertTrue(out.contains("Thu 22 Oct: free"))
    }

    func testBusyLinesOnClockChangeDay() {
        let busy = [BusyInterval(start: at("2026-10-25", "17:00"), end: at("2026-10-25", "18:30"))]
        let out = lines(PromptBuilder.intakePrompt(answers: answers(), busy: busy, settings: settings, now: now))
        XCTAssertTrue(out.contains("Sun 25 Oct: 17:00–18:30"))
    }

    func testNoEventTitlesOrIdentifiersLeak() {
        let events = [ExternalEvent(id: "SECRET-ID", title: "Therapy with Dr Smith", start: at("2026-10-20", "10:00"),
                                    end: at("2026-10-20", "11:00"))]
        let busy = events.compactMap(\.busyInterval)
        let prompt = PromptBuilder.intakePrompt(answers: answers(), busy: busy, settings: settings, now: now)
        XCTAssertFalse(prompt.contains("Therapy"))
        XCTAssertFalse(prompt.contains("Smith"))
        XCTAssertFalse(prompt.contains("SECRET"))
        XCTAssertTrue(prompt.contains("Tue 20 Oct: 10:00–11:00"))
    }

    func testEmptyOptionalAnswersUseDash() {
        var blank = answers()
        blank.triedBefore = ""
        blank.bestPlaces = []
        blank.stoppers = []
        blank.badDayVersion = "  "
        let prompt = PromptBuilder.intakePrompt(answers: blank, busy: nil, settings: settings, now: now)
        for line in ["Tried before: —", "Best places: —", "What usually makes me stop: —", "Smallest bad-day version: —"] {
            XCTAssertTrue(prompt.contains(line), line)
        }
    }

    func testSaturdaysOffNoAndMonthNames() {
        var open = answers()
        open.saturdaysOff = false
        let prompt = PromptBuilder.intakePrompt(answers: open, busy: nil, settings: settings, now: at("2026-09-03", "09:00"))
        XCTAssertTrue(prompt.contains("Saturdays off for goal work: no (physical activity still fine)"))
        XCTAssertTrue(prompt.contains("Today: Thu 3 Sep 2026"))
    }

    func testPromptAddOnContainsSchema() {
        XCTAssertTrue(PromptBuilder.promptAddOn.contains("Lock in plan schema v1:"))
        XCTAssertTrue(PromptBuilder.promptAddOn.contains("\"schemaVersion\": 1"))
    }

    // MARK: Check-in (Appendix C, F10.3)

    func checkInSnapshot() -> StoreSnapshot {
        var snapshot = SampleData.bodyFatGoal(today: day("2026-10-26"))
        // Last week is 19–25 Oct. Replace the sample marks with a known pattern.
        let week = Week(containing: day("2026-10-19"))
        snapshot.logs.removeAll { week.contains($0.day) }
        func log(_ id: UUID, _ dayText: String, _ mark: Mark, count: Int? = nil) {
            snapshot.logs.append(HabitLog(habitID: id, day: day(dayText), mark: mark, count: count))
        }
        log(SampleData.liftHabitID, "2026-10-19", .D)
        log(SampleData.liftHabitID, "2026-10-21", .B)
        log(SampleData.liftHabitID, "2026-10-23", .B)
        log(SampleData.inclineWalkHabitID, "2026-10-20", .D)
        log(SampleData.inclineWalkHabitID, "2026-10-22", .D)
        for dayText in ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"] {
            log(SampleData.proteinHabitID, dayText, .D, count: 4)
        }
        snapshot.weekReviews = [WeekReview(goalID: SampleData.goalID, weekStart: week.start, resultValue: 84.6,
                                           bottleneckHabitID: SampleData.inclineWalkHabitID, note: "Knee sore on Thursday")]
        return snapshot
    }

    func testCheckInPromptContent() {
        let prompt = PromptBuilder.checkInPrompt(goalID: SampleData.goalID, snapshot: checkInSnapshot(), week: Week(containing: day("2026-10-19")))
        let out = lines(prompt)
        XCTAssertEqual(out[0], "Weekly check-in for goal \"10% body fat\" (goalId: \(SampleData.goalID.uuidString)). Week 19 Oct–25 Oct.")
        XCTAssertEqual(out[1], "Result: Weigh-in average 84.6kg (target 78kg, start 86kg).")
        XCTAssertEqual(out[2], "Scorecard (D = done, B = bad-day version, M = missed, - = not scheduled):")
        // Lift (Mon Wed Fri): D on Mon, B on Wed and Fri → 3 done, 2 B → flagged.
        XCTAssertEqual(out[3], "Lift: D-B-B-- — 3/3 — FLAG: 2 of 3 were B")
        // Incline walk is perWeek: unlogged days show "-".
        XCTAssertEqual(out[4], "Incline walk: -D-D--- — 2/5")
        XCTAssertEqual(out[5], "Protein x4: DDDDDDM — 6/6")
        XCTAssertEqual(out[6], "Post-gym meal: M-M-M-- — 0/3")
        XCTAssertEqual(out[7], "In bed by 23:30: MMMMMMM — 0/5")
        XCTAssertEqual(out[8], "On target: 2 of 5. Streak: 0 weeks. Bottleneck I picked: Incline walk.") // Lift and Protein hit
        XCTAssertEqual(out[9], "Note: Knee sore on Thursday")
        XCTAssertEqual(out[10], "Current plan JSON (keep keys the same):")
        XCTAssertEqual(out.last, "Redesign anything flagged or below set point, then finish with the full updated plan JSON (schema v1, same goalId and keys).")
    }

    func testCheckInPromptEmbedsDecodablePlanWithSameGoalAndKeys() throws {
        let snapshot = checkInSnapshot()
        let prompt = PromptBuilder.checkInPrompt(goalID: SampleData.goalID, snapshot: snapshot, week: Week(containing: day("2026-10-19")))
        let out = lines(prompt)
        let start = try XCTUnwrap(out.firstIndex(of: "Current plan JSON (keep keys the same):")) + 1
        let json = out[start..<(out.count - 1)].joined(separator: "\n")
        let plan = try PlanImporter.decode(Data(json.utf8))
        XCTAssertEqual(plan.goal.id, SampleData.goalID.uuidString)
        XCTAssertEqual(plan.habits.map(\.key), ["h1", "h2", "h3", "h4", "h5"])
        XCTAssertEqual(PlanImporter.validate(plan), [])
    }

    func testCheckInPromptWithoutReviewOrMarks() {
        var snapshot = SampleData.bodyFatGoal(today: day("2026-10-26"))
        snapshot.logs = []
        snapshot.weekReviews = []
        snapshot.goals[0].bottleneckHabitID = nil
        let out = lines(PromptBuilder.checkInPrompt(goalID: SampleData.goalID, snapshot: snapshot, week: Week(containing: day("2026-10-19"))))
        XCTAssertEqual(out[1], "Result: Weigh-in average — (target 78kg, start 86kg).")
        XCTAssertTrue(out.contains("Note: —"))
        XCTAssertTrue(out.contains { $0.hasPrefix("On target: 0 of 5. Streak: 0 weeks. Bottleneck I picked: ") })
        XCTAssertEqual(PromptBuilder.checkInPrompt(goalID: uuid(404), snapshot: snapshot, week: Week(containing: day("2026-10-19"))),
                       "Weekly check-in: goal not found.")
    }

    func testCheckInStreakCountsTheReviewedWeek() {
        var snapshot = SampleData.bodyFatGoal(today: day("2026-10-26"))
        snapshot.logs = []
        // Two on-target weeks (12 Oct and 19 Oct): every habit hits its set point.
        for start in ["2026-10-12", "2026-10-19"] {
            for habit in snapshot.habits {
                let needed = habit.setPointPerWeek
                for offset in 0..<needed {
                    snapshot.logs.append(HabitLog(habitID: habit.id, day: day(start).adding(days: offset), mark: .D))
                }
            }
        }
        let out = lines(PromptBuilder.checkInPrompt(goalID: SampleData.goalID, snapshot: snapshot, week: Week(containing: day("2026-10-19"))))
        XCTAssertTrue(out.contains { $0.hasPrefix("On target: 5 of 5. Streak: 2 weeks.") }, out.joined(separator: "\n"))
    }
}
