import XCTest
@testable import CoreKit

final class PlanImporterTests: XCTestCase {
    let today = day("2026-10-20")
    let settings = AppSettings.defaults

    // MARK: Fixture

    func basePlan() -> PlanV1 {
        PlanV1(
            goal: .init(key: "g", title: "10% body fat", outcome: "78 kg", deadline: "2026-12-31", bufferDays: 7,
                        result: .init(name: "Weigh-in", unit: "kg", start: 86, target: 78)),
            firstPrinciples: [.init(key: "fp1", title: "Deficit", why: "Fat loss needs one"),
                              .init(key: "fp2", title: "Keep muscle")],
            systems: [.init(key: "s1", firstPrinciple: "fp1", kind: "principle", title: "Meals", location: "Home"),
                      .init(key: "s2", firstPrinciple: "fp2", kind: "principle", title: "Lifting", location: "Gym"),
                      .init(key: "s3", firstPrinciple: nil, kind: "sustaining", title: "Sleep")],
            objectives: [.init(key: "o1", title: "First", estimatedDays: 10),
                         .init(key: "o2", title: "Second", estimatedDays: 14, dependsOn: ["o1"], systems: ["s1"]),
                         .init(key: "o3", title: "Third", estimatedDays: 21, dependsOn: ["o2"])],
            steps: [.init(key: "st1", objective: "o1", title: "Food log", estimatedMinutes: 20)],
            habits: [
                .init(key: "h1", system: "s2", title: "Lift", badDayTitle: "Two lifts", kind: "check", target: 5, badDayTarget: 4,
                      frequency: .init(type: "weekdays", weekdays: [3, 1, 5]), setPointPerWeek: 3, reminderTime: "17:00",
                      durationMinutes: 60, isPhysical: true, priority: 1),
                .init(key: "h2", system: "s1", title: "Protein x4", badDayTitle: "3 portions", kind: "count", target: 4,
                      badDayTarget: 3, unit: "portions", frequency: .init(type: "daily")),
                .init(key: "h3", system: "s2", title: "Walk", badDayTitle: "20 min", frequency: .init(type: "perWeek", timesPerWeek: 5, preferredWeekdays: [1, 2, 3, 4, 5])),
            ],
            blocks: [
                .init(key: "b1", system: "s1", title: "Meal prep", durationMinutes: 90, weekdays: [6], startTime: "17:00",
                      windowStart: "16:00", windowEnd: "20:00"),
                .init(key: "b2", system: "s2", title: "Gym induction", durationMinutes: 45, date: "2026-11-03", startTime: "10:00", nudge: true),
            ],
            reminders: [.init(key: "r1", system: "s1", title: "Order food", body: "Protein, oats", weekdays: [3], time: "10:00", priority: 4)])
    }

    func materialise(_ plan: PlanV1, into snapshot: StoreSnapshot = .empty, today: LocalDay? = nil) -> ImportResult {
        PlanImporter.materialise(plan, into: snapshot, today: today ?? self.today, settings: settings)
    }

    func applied(_ result: ImportResult, to snapshot: StoreSnapshot = .empty) -> StoreSnapshot {
        snapshot.applying(result.changes, now: at("2026-10-20", "09:00"))
    }

    func encoded(_ plan: PlanV1) -> Data { Data(plan.jsonString().utf8) }

    // MARK: Extraction (Appendix A)

    func extracted(_ text: String) -> String? { PlanImporter.extractJSON(from: text).map { String(decoding: $0, as: UTF8.self) } }

    func testExtractTakesTheLastJsonBlock() {
        let text = """
        Here is a draft:
        ```json
        {"draft": true}
        ```
        Changed my mind, final one:
        ```json
        {"final": true}
        ```
        """
        XCTAssertEqual(extracted(text), #"{"final": true}"#)
    }

    func testExtractAcceptsBareFenceAndPrefersJsonTag() {
        XCTAssertEqual(extracted("```\n{\"a\": 1}\n```"), #"{"a": 1}"#)
        let mixed = "```json\n{\"a\": 1}\n```\nnote\n```\nnot json\n```"
        XCTAssertEqual(extracted(mixed), #"{"a": 1}"#)
        XCTAssertEqual(extracted("```swift\nlet x = 1\n```\n```json\n{\"a\": 1}\n```"), #"{"a": 1}"#)
    }

    func testExtractFallsBackToWholeTextAndHandlesEmpty() {
        XCTAssertEqual(extracted("  \n {\"a\": 1}\n "), #"{"a": 1}"#)
        XCTAssertNil(PlanImporter.extractJSON(from: "   \n"))
        XCTAssertEqual(extracted("```json\n{\"a\": 1}"), #"{"a": 1}"#) // fence never closed
        XCTAssertEqual(extracted("```json {\"a\": 1} ```"), #"{"a": 1}"#)
    }

    // MARK: Decoding

    func testDecodeRoundTripAndFencedReply() throws {
        let plan = basePlan()
        XCTAssertEqual(try PlanImporter.decode(encoded(plan)), plan)
        let reply = "Here you go.\n```json\n\(plan.jsonString())\n```\n"
        XCTAssertEqual(try PlanImporter.decode(Data(reply.utf8)), plan)
    }

    func decodeError(_ json: String) -> PlanImportError? {
        do { _ = try PlanImporter.decode(Data(json.utf8)); return nil } catch { return error }
    }

    func testDecodeErrorPaths() {
        let wrongType = #"{"goal":{"key":"g","title":"t","deadline":"2026-12-31","result":{"name":"n","unit":"u","start":1,"target":2}},"habits":[{"key":"a","title":"a","badDayTitle":"b","kind":"check","frequency":{"type":"daily"}},{"key":"b","title":"b","badDayTitle":"b","kind":"check","frequency":{"type":"daily"}},{"key":"c","title":"c","badDayTitle":"b","kind":"check","frequency":{"type":"daily"},"priority":"high"}]}"#
        guard case .decoding(let path, let message)? = decodeError(wrongType) else { return XCTFail("expected a decoding error") }
        XCTAssertEqual(path, "habits[2].priority")
        XCTAssertEqual(message, "expected a whole number")

        let missing = #"{"goal":{"key":"g","title":"t","deadline":"2026-12-31","result":{"name":"n","unit":"u","start":1,"target":2}},"habits":[{"key":"a","title":"a","badDayTitle":"b","kind":"check"}]}"#
        guard case .decoding(let missingPath, _)? = decodeError(missing) else { return XCTFail("expected a decoding error") }
        XCTAssertEqual(missingPath, "habits[0].frequency")

        guard case .decoding(let nested, _)? = decodeError(#"{"goal":{"key":"g","title":"t","deadline":"2026-12-31"}}"#) else { return XCTFail() }
        XCTAssertEqual(nested, "goal.result")
    }

    func testDecodeNotJSONAndSchemaVersion() {
        XCTAssertEqual(decodeError("   "), .noJSON)
        guard case .decoding(let path, _)? = decodeError("this is not json") else { return XCTFail() }
        XCTAssertEqual(path, "plan")
        XCTAssertEqual(decodeError(#"{"schemaVersion": 2, "goal": 5}"#), .unsupportedSchema(2))
        XCTAssertEqual(PlanImportError.unsupportedSchema(2).issue.path, "schemaVersion")
        XCTAssertEqual(PlanImportError.decoding(path: "habits[2].frequency", message: "m").issue.description, "habits[2].frequency: m")
    }

    func testUnknownFieldsAreIgnoredAndSchemaVersionDefaults() throws {
        let json = #"{"extra":1,"goal":{"key":"g","title":"t","deadline":"2026-12-31","colour":"red","result":{"name":"n","unit":"u","start":1,"target":2}}}"#
        let plan = try PlanImporter.decode(Data(json.utf8))
        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertEqual(plan.goal.title, "t")
        XCTAssertTrue(plan.habits.isEmpty)
    }

    // MARK: Validation (§4.4 step 1, F7.2)

    func issues(_ edit: (inout PlanV1) -> Void) -> [PlanIssue] {
        var plan = basePlan()
        edit(&plan)
        return PlanImporter.validate(plan)
    }

    func testValidPlanHasNoIssues() {
        XCTAssertEqual(PlanImporter.validate(basePlan()), [])
    }

    func testWeekdayOutOfRange() {
        let found = issues { $0.habits[2].frequency = .init(type: "weekdays", weekdays: [1, 8]) }
        XCTAssertEqual(found, [PlanIssue(path: "habits[2].frequency.weekdays", message: "8 is not 1–7")])
        XCTAssertEqual(found[0].description, "habits[2].frequency.weekdays: 8 is not 1–7")
        XCTAssertEqual(issues { $0.blocks[0].weekdays = [0] }.map(\.path), ["blocks[0].weekdays"])
        XCTAssertEqual(issues { $0.reminders[0].weekdays = [9] }.map(\.path), ["reminders[0].weekdays"])
    }

    func testBadTimesAndDates() {
        XCTAssertEqual(issues { $0.habits[0].reminderTime = "25:00" }, [PlanIssue(path: "habits[0].reminderTime", message: "\"25:00\" is not HH:mm")])
        XCTAssertEqual(issues { $0.reminders[0].time = "7:30" }.map(\.path), ["reminders[0].time"])
        XCTAssertEqual(issues { $0.blocks[0].startTime = "noon" }.map(\.path), ["blocks[0].startTime"])
        XCTAssertEqual(issues { $0.goal.deadline = "2026-13-01" }, [PlanIssue(path: "goal.deadline", message: "\"2026-13-01\" is not YYYY-MM-DD")])
        XCTAssertEqual(issues { $0.blocks[1].date = "03/11/2026" }.map(\.path), ["blocks[1].date"])
        XCTAssertEqual(issues { $0.objectives[0].deadline = "soon" }.map(\.path), ["objectives[0].deadline"])
        XCTAssertEqual(issues { $0.steps[0].deadline = "2026-02-30" }.map(\.path), ["steps[0].deadline"])
    }

    func testDuplicateKeys() {
        XCTAssertEqual(issues { $0.habits[2].key = "h1" }, [PlanIssue(path: "habits[2].key", message: "duplicate key \"h1\"")])
        XCTAssertEqual(issues { $0.systems[1].key = "s1" }.first?.path, "systems[1].key")
        XCTAssertEqual(issues { $0.reminders.append($0.reminders[0]) }.map(\.path), ["reminders[1].key"])
    }

    func testUnknownReferences() {
        XCTAssertEqual(issues { $0.habits[0].system = "s9" }, [PlanIssue(path: "habits[0].system", message: "unknown reference \"s9\"")])
        XCTAssertEqual(issues { $0.objectives[1].dependsOn = ["o1", "nope"] }.map(\.path), ["objectives[1].dependsOn[1]"])
        XCTAssertEqual(issues { $0.objectives[1].systems = ["zz"] }.map(\.path), ["objectives[1].systems[0]"])
        XCTAssertEqual(issues { $0.steps[0].objective = "o9" }.map(\.path), ["steps[0].objective"])
        XCTAssertEqual(issues { $0.systems[0].firstPrinciple = "fp9" }.map(\.path), ["systems[0].firstPrinciple"])
        XCTAssertEqual(issues { $0.blocks[0].system = "s9" }.map(\.path), ["blocks[0].system"])
        XCTAssertEqual(issues { $0.reminders[0].system = "s9" }.map(\.path), ["reminders[0].system"])
    }

    func testDependsOnCycle() {
        let loop = issues { $0.objectives[0].dependsOn = ["o3"] }
        XCTAssertEqual(loop.count, 1)
        XCTAssertEqual(loop[0].path, "objectives[0].dependsOn")
        XCTAssertEqual(loop[0].message, "cycle in dependsOn: o1 → o3 → o2 → o1")
        XCTAssertEqual(issues { $0.objectives[1].dependsOn = ["o2"] }.map(\.message), ["cycle in dependsOn: o2 → o2"])
    }

    func testExactlyOneSustainingSystem() {
        let none = issues { $0.systems[2].kind = "principle"; $0.systems[2].firstPrinciple = "fp1" }
        XCTAssertEqual(none, [PlanIssue(path: "systems", message: "needs exactly one sustaining system (found 0)")])
        let two = issues { $0.systems[0].kind = "sustaining" }
        XCTAssertEqual(two.first?.message, "needs exactly one sustaining system (found 2)")
    }

    func testCountHabitTargets() {
        let equal = issues { $0.habits[1].badDayTarget = 4 }
        XCTAssertEqual(equal, [PlanIssue(path: "habits[1].badDayTarget", message: "4 is not below target 4")])
        XCTAssertEqual(issues { $0.habits[1].badDayTarget = 5 }.map(\.path), ["habits[1].badDayTarget"])
        XCTAssertEqual(issues { $0.habits[1].target = nil }.map(\.path), ["habits[1].target"])
        // A check habit's targets are forced to 1, so they are not validated.
        XCTAssertEqual(issues { $0.habits[0].badDayTarget = 9 }, [])
    }

    func testSetPointAboveScheduled() {
        XCTAssertEqual(issues { $0.habits[0].setPointPerWeek = 4 },
                       [PlanIssue(path: "habits[0].setPointPerWeek", message: "4 is more than the 3 scheduled a week")])
        XCTAssertEqual(issues { $0.habits[2].setPointPerWeek = 6 }.map(\.path), ["habits[2].setPointPerWeek"])
        XCTAssertEqual(issues { $0.habits[1].setPointPerWeek = 7 }, [])
        XCTAssertEqual(issues { $0.habits[1].setPointPerWeek = 8 }.map(\.path), ["habits[1].setPointPerWeek"])
    }

    func testFrequencyRequirements() {
        XCTAssertEqual(issues { $0.habits[0].frequency = .init(type: "weekdays") }.map(\.path), ["habits[0].frequency.weekdays"])
        XCTAssertEqual(issues { $0.habits[2].frequency = .init(type: "perWeek") }.map(\.path), ["habits[2].frequency.timesPerWeek"])
        XCTAssertEqual(issues { $0.habits[2].frequency = .init(type: "perWeek", timesPerWeek: 9) }.first?.message, "9 is not 1–7")
        XCTAssertEqual(issues { $0.habits[2].frequency = .init(type: "monthly") }.map(\.path), ["habits[2].frequency.type"])
        XCTAssertEqual(issues { $0.habits[1].frequency = .init(type: "daily", weekdays: [12]) }, []) // daily ignores the arrays
    }

    func testBlockWindowChecks() {
        let early = issues { $0.blocks[0].windowStart = "17:30" }
        XCTAssertEqual(early.map(\.path), ["blocks[0].windowStart"])
        let late = issues { $0.blocks[0].windowEnd = "18:00" } // block ends 18:30
        XCTAssertEqual(late.map(\.path), ["blocks[0].windowEnd"])
        XCTAssertEqual(issues { $0.blocks[0].windowEnd = "18:30" }, []) // exactly fits
        XCTAssertEqual(issues { $0.blocks[0].weekdays = nil }.map(\.path), ["blocks[0]"]) // neither weekdays nor date
    }

    func testIssuesComeInDocumentOrder() {
        let found = issues {
            $0.reminders[0].time = "99:00"
            $0.habits[0].reminderTime = "25:00"
            $0.goal.deadline = "bad"
        }
        XCTAssertEqual(found.map(\.path), ["goal.deadline", "habits[0].reminderTime", "reminders[0].time"])
    }

    func testBadGoalIdAndSchemaVersion() {
        XCTAssertEqual(issues { $0.goal.id = "UUID or null" }.map(\.path), ["goal.id"])
        XCTAssertEqual(issues { $0.goal.id = "null" }, [])
        XCTAssertEqual(issues { $0.schemaVersion = 2 }.map(\.path), ["schemaVersion"])
    }

    // MARK: Materialising a new goal (§4.4 step 2)

    func testMaterialiseCreatesEverything() {
        let result = materialise(basePlan())
        let snapshot = applied(result)
        XCTAssertFalse(result.summary.isUpdate)
        XCTAssertEqual(result.summary.goalTitle, "10% body fat")
        XCTAssertEqual([result.summary.principles, result.summary.systems, result.summary.habits, result.summary.blocks, result.summary.reminders],
                       [2, 3, 3, 2, 1])
        XCTAssertEqual(snapshot.goals.count, 1)
        XCTAssertEqual(snapshot.goals[0].id, result.goalID)
        XCTAssertEqual(snapshot.goals[0].planKey, "g")
        XCTAssertEqual(snapshot.goals[0].resultDirection, .down)
        XCTAssertEqual(snapshot.goals[0].deadline, day("2026-12-31"))
        XCTAssertNotNil(snapshot.goals[0].importedPlanJSON)
        XCTAssertEqual(snapshot.firstPrinciples.map(\.planKey), ["fp1", "fp2"])
        XCTAssertEqual(snapshot.systems.map(\.planKey), ["s1", "s2", "s3"])
        XCTAssertEqual(snapshot.objectives.count, 3)
        XCTAssertEqual(snapshot.steps.count, 1)
        XCTAssertEqual(snapshot.habits.count, 3)
        XCTAssertEqual(snapshot.blockRules.count, 1)
        XCTAssertEqual(snapshot.blocks.count, 1)
        XCTAssertEqual(snapshot.reminders.count, 1)
        XCTAssertTrue(snapshot.habits.allSatisfy { $0.goalID == result.goalID })
    }

    func testReferencesAreResolved() {
        let snapshot = applied(materialise(basePlan()))
        let system = { (key: String) in snapshot.systems.first { $0.planKey == key }! }
        XCTAssertEqual(system("s1").firstPrincipleID, snapshot.firstPrinciples.first { $0.planKey == "fp1" }?.id)
        XCTAssertNil(system("s3").firstPrincipleID)
        XCTAssertEqual(system("s3").kind, .sustaining)
        XCTAssertEqual(system("s2").location, "Gym")
        XCTAssertNil(system("s3").location)
        let o = { (key: String) in snapshot.objectives.first { $0.planKey == key }! }
        XCTAssertEqual(o("o2").dependsOnIDs, [o("o1").id])
        XCTAssertEqual(o("o2").systemIDs, [system("s1").id])
        XCTAssertEqual(snapshot.steps[0].objectiveID, o("o1").id)
        XCTAssertEqual(snapshot.habits.first { $0.planKey == "h1" }?.systemID, system("s2").id)
        XCTAssertEqual(snapshot.blockRules[0].systemID, system("s1").id)
        XCTAssertEqual(snapshot.reminders[0].systemID, system("s1").id)
    }

    func testHabitMappingAndDefaults() {
        let snapshot = applied(materialise(basePlan()))
        let lift = snapshot.habits.first { $0.planKey == "h1" }!
        XCTAssertEqual(lift.kind, .check)
        XCTAssertEqual(lift.target, 1) // kind = check forces 1 / 1
        XCTAssertEqual(lift.badDayTarget, 1)
        XCTAssertEqual(lift.frequency, .weekdays([1, 3, 5]))
        XCTAssertEqual(lift.reminderTime, 1020)
        XCTAssertEqual(lift.setPointPerWeek, 3)
        XCTAssertEqual(lift.durationMinutes, 60)
        XCTAssertTrue(lift.isPhysical)
        XCTAssertEqual(lift.priority, 1)

        let protein = snapshot.habits.first { $0.planKey == "h2" }!
        XCTAssertEqual(protein.kind, .count)
        XCTAssertEqual([protein.target, protein.badDayTarget], [4, 3])
        XCTAssertEqual(protein.unit, "portions")
        XCTAssertEqual(protein.setPointPerWeek, 7) // default = scheduled
        XCTAssertEqual(protein.durationMinutes, 15)
        XCTAssertEqual(protein.priority, 3)
        XCTAssertFalse(protein.isPhysical)
        XCTAssertNil(protein.reminderTime)

        let walk = snapshot.habits.first { $0.planKey == "h3" }!
        XCTAssertEqual(walk.frequency, .perWeek(5))
        XCTAssertEqual(walk.preferredWeekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(walk.setPointPerWeek, 5)
        XCTAssertEqual(snapshot.habits.map(\.sortIndex), [0, 1, 2])
    }

    func testGoalDefaults() {
        var plan = basePlan()
        plan.goal.bufferDays = nil
        plan.goal.outcome = nil
        let goal = applied(materialise(plan)).goals[0]
        XCTAssertEqual(goal.bufferDays, 7)
        XCTAssertEqual(goal.outcome, "")
        XCTAssertEqual(goal.status, .active)
    }

    func testBlocksBecomeRulesOrOneOffBlocks() {
        let result = materialise(basePlan())
        let snapshot = applied(result)
        let rule = snapshot.blockRules[0]
        XCTAssertEqual([rule.startTime, rule.windowStart, rule.windowEnd, rule.durationMinutes], [1020, 960, 1200, 90])
        XCTAssertEqual(rule.planKey, "b1")
        XCTAssertTrue(rule.active)
        let oneOff = snapshot.blocks[0]
        XCTAssertNil(oneOff.ruleID)
        XCTAssertEqual(oneOff.title, "Gym induction")
        XCTAssertEqual(oneOff.start, at("2026-11-03", "10:00"))
        XCTAssertEqual(oneOff.end, at("2026-11-03", "10:45"))
        XCTAssertEqual(oneOff.goalID, result.goalID)
        XCTAssertEqual(oneOff.systemID, snapshot.systems.first { $0.planKey == "s2" }?.id)
        XCTAssertTrue(oneOff.nudge)
        XCTAssertEqual(oneOff.status, .scheduled)
    }

    func testSaturdayMove() {
        var plan = basePlan()
        plan.blocks.append(.init(key: "b3", system: "s1", title: "Dentist", durationMinutes: 30, date: "2026-11-07", startTime: "09:00"))
        plan.blocks.append(.init(key: "b4", system: "s2", title: "Park run", durationMinutes: 45, weekdays: [6], startTime: "09:00", isPhysical: true))
        let result = materialise(plan)
        XCTAssertEqual(result.summary.movedOffSaturday, ["Moved off Saturday: Meal prep → Sun 17:00", "Moved off Saturday: Dentist → Sun 09:00"])
        let snapshot = applied(result)
        XCTAssertEqual(snapshot.blockRules.first { $0.planKey == "b1" }?.weekdays, [7])
        XCTAssertEqual(snapshot.blockRules.first { $0.planKey == "b4" }?.weekdays, [6]) // physical stays
        XCTAssertEqual(snapshot.blocks.first { $0.title == "Dentist" }?.day, day("2026-11-08"))
        // With Saturdays on, nothing moves.
        var open = settings
        open.saturdayOff = false
        let untouched = PlanImporter.materialise(plan, into: .empty, today: today, settings: open)
        XCTAssertTrue(untouched.summary.movedOffSaturday.isEmpty)
    }

    func testSaturdayMoveMergesWithExistingSunday() {
        var plan = basePlan()
        plan.blocks[0].weekdays = [6, 7]
        XCTAssertEqual(applied(materialise(plan)).blockRules[0].weekdays, [7])
    }

    func testBackSchedulingWritesDeadlinesAndWarnings() {
        var result = materialise(basePlan())
        var objectives = applied(result).objectives
        XCTAssertEqual(objectives.map(\.deadline), [day("2026-11-19"), day("2026-12-03"), day("2026-12-24")])
        XCTAssertTrue(objectives.allSatisfy { !$0.deadlineOverridden })
        XCTAssertTrue(result.summary.startsLate.isEmpty)

        result = materialise(basePlan(), today: day("2026-11-25"))
        XCTAssertEqual(result.summary.startsLate, ["First: Starts 16 days too late", "Second: Starts 6 days too late"])

        var fixed = basePlan()
        fixed.objectives[1].deadline = "2026-12-10"
        objectives = applied(materialise(fixed)).objectives
        XCTAssertEqual(objectives.map(\.deadline), [day("2026-11-26"), day("2026-12-10"), day("2026-12-24")])
        XCTAssertEqual(objectives.map(\.deadlineOverridden), [false, true, false])
    }

    func testUnattachedHabitAndReminderHangOffTheSustainingSystem() {
        var plan = basePlan()
        plan.habits[1].system = nil
        plan.reminders[0].system = nil
        let snapshot = applied(materialise(plan))
        let sustaining = snapshot.systems.first { $0.kind == .sustaining }!.id
        XCTAssertEqual(snapshot.habits.first { $0.planKey == "h2" }?.systemID, sustaining)
        XCTAssertEqual(snapshot.habits.first { $0.planKey == "h2" }?.goalID, snapshot.goals[0].id)
        XCTAssertEqual(snapshot.reminders[0].systemID, sustaining)
    }

    func testNewGoalsAppendToTheDashboardOrder() {
        let first = applied(materialise(basePlan()))
        var second = basePlan()
        second.goal.key = "other"
        let both = applied(materialise(second, into: first), to: first)
        XCTAssertEqual(both.goals.count, 2)
        XCTAssertEqual(both.sortedGoals.map(\.planKey), ["g", "other"])
    }

    // MARK: Update mode (§4.4 step 3, F10.4)

    func updateFixture() -> (snapshot: StoreSnapshot, goalID: UUID) {
        let first = materialise(basePlan())
        var snapshot = applied(first)
        // Marks, a finished review and generated blocks that must survive.
        let lift = snapshot.habits.first { $0.planKey == "h1" }!
        snapshot.logs = [HabitLog(habitID: lift.id, day: day("2026-10-19"), mark: .D),
                         HabitLog(habitID: snapshot.habits.first { $0.planKey == "h3" }!.id, day: day("2026-10-19"), mark: .B)]
        snapshot.weekReviews = [WeekReview(goalID: first.goalID, weekStart: day("2026-10-12"), resultValue: 85, finishedAt: at("2026-10-19", "19:30"))]
        let rule = snapshot.blockRules[0]
        snapshot.blocks += ScheduleEngine.materialise(rules: [rule], existing: [], from: day("2026-10-11"), days: 60, settings: settings)
        return (snapshot, first.goalID)
    }

    func updatePlan(_ goalID: UUID, _ edit: (inout PlanV1) -> Void = { _ in }) -> PlanV1 {
        var plan = basePlan()
        plan.goal.id = goalID.uuidString
        edit(&plan)
        return plan
    }

    func testUpdateWithSamePlanChangesNothingStructural() {
        let (snapshot, goalID) = updateFixture()
        let result = materialise(updatePlan(goalID), into: snapshot)
        XCTAssertTrue(result.summary.isUpdate)
        XCTAssertEqual(result.goalID, goalID)
        XCTAssertEqual(result.summary.inserted, 0)
        XCTAssertEqual(result.summary.removed, 0)
        XCTAssertEqual(result.summary.changed, 0)
        XCTAssertTrue(result.changes.deletes.isEmpty)
        let after = applied(result, to: snapshot)
        XCTAssertEqual(after.goals.count, 1)
        XCTAssertEqual(after.habits, snapshot.habits)
        XCTAssertEqual(after.objectives, snapshot.objectives)
        XCTAssertEqual(after.logs, snapshot.logs)
        XCTAssertEqual(after.blockRules, snapshot.blockRules)
    }

    func testUpdateKeepsIdsAndUpdatesFields() {
        let (snapshot, goalID) = updateFixture()
        let before = snapshot.habits.first { $0.planKey == "h1" }!
        let plan = updatePlan(goalID) {
            $0.habits[0].title = "Heavy lift"
            $0.habits[0].reminderTime = "18:00"
            $0.goal.title = "9% body fat"
        }
        let result = materialise(plan, into: snapshot)
        let after = applied(result, to: snapshot)
        let lift = after.habits.first { $0.planKey == "h1" }!
        XCTAssertEqual(lift.id, before.id)
        XCTAssertEqual(lift.title, "Heavy lift")
        XCTAssertEqual(lift.reminderTime, 1080)
        XCTAssertEqual(lift.createdAt, before.createdAt)
        XCTAssertEqual(after.habits.count, 3)
        XCTAssertEqual(after.goals[0].title, "9% body fat")
        XCTAssertEqual(after.goals[0].id, goalID)
        XCTAssertEqual(result.summary.changed, 1)
        XCTAssertEqual(result.summary.inserted, 0)
    }

    func testUpdateInsertsNewKeys() {
        let (snapshot, goalID) = updateFixture()
        let plan = updatePlan(goalID) {
            $0.habits.append(.init(key: "h4", system: "s1", title: "Sleep", badDayTitle: "Midnight", frequency: .init(type: "daily")))
            $0.reminders.append(.init(key: "r2", system: "s1", title: "Weigh in", weekdays: [1], time: "07:00"))
        }
        let result = materialise(plan, into: snapshot)
        XCTAssertEqual(result.summary.inserted, 2)
        let after = applied(result, to: snapshot)
        XCTAssertEqual(after.habits.count, 4)
        XCTAssertEqual(after.reminders.count, 2)
    }

    func testUpdateArchivesMissingHabitsAndKeepsLogs() {
        let (snapshot, goalID) = updateFixture()
        let result = materialise(updatePlan(goalID) { $0.habits.removeLast() }, into: snapshot)
        XCTAssertEqual(result.summary.removed, 1)
        let after = applied(result, to: snapshot)
        let walk = after.habits.first { $0.planKey == "h3" }!
        XCTAssertTrue(walk.isArchived)
        XCTAssertEqual(after.habits.count, 3) // archived, not deleted
        XCTAssertEqual(after.logs, snapshot.logs) // logs untouched
        XCTAssertEqual(after.weekReviews, snapshot.weekReviews)
        XCTAssertEqual(after.logs(habitID: walk.id).count, 1)
    }

    func testUpdateDeletesMissingRuleWithFutureBlocksAndReminders() {
        let (snapshot, goalID) = updateFixture()
        let rule = snapshot.blockRules[0]
        let pastBefore = snapshot.blocks.filter { $0.ruleID == rule.id && $0.start < at("2026-10-20", "09:00") }
        XCTAssertFalse(pastBefore.isEmpty)
        let plan = updatePlan(goalID) {
            $0.blocks.removeFirst()
            $0.reminders.removeAll()
        }
        let result = materialise(plan, into: snapshot)
        XCTAssertEqual(Set(result.changes.deletes), [EntityRef(.blockRule, rule.id), EntityRef(.reminder, snapshot.reminders[0].id)])
        XCTAssertEqual(result.summary.removed, 2)
        let after = applied(result, to: snapshot)
        XCTAssertTrue(after.blockRules.isEmpty)
        XCTAssertTrue(after.reminders.isEmpty)
        XCTAssertFalse(after.blocks.contains { $0.ruleID == rule.id })
        XCTAssertEqual(after.blocks.filter { $0.title == "Meal prep" }.count, pastBefore.count) // past instances stay as one-offs
        XCTAssertEqual(after.blocks.filter { $0.title == "Gym induction" }.count, 1)
    }

    func testUpdateDeletesMissingObjectivesAndSteps() {
        let (snapshot, goalID) = updateFixture()
        let result = materialise(updatePlan(goalID) { $0.objectives.removeLast(); $0.steps.removeAll() }, into: snapshot)
        let after = applied(result, to: snapshot)
        XCTAssertEqual(after.objectives.map(\.planKey), ["o1", "o2"])
        XCTAssertTrue(after.steps.isEmpty)
        XCTAssertEqual(result.summary.removed, 2)
        // Deleting an objective takes its steps with it, counted but not deleted twice.
        let cascade = materialise(updatePlan(goalID) { $0.objectives.removeFirst(); $0.objectives[0].dependsOn = []; $0.steps.removeAll() }, into: snapshot)
        XCTAssertEqual(cascade.summary.removed, 2)
        XCTAssertEqual(cascade.changes.deletes.filter { $0.kind == .step }.count, 0)
    }

    func testUpdateRecomputesDeadlinesFromTheNewGoalDeadline() {
        let (snapshot, goalID) = updateFixture()
        let result = materialise(updatePlan(goalID) { $0.goal.deadline = "2027-01-31" }, into: snapshot)
        XCTAssertEqual(applied(result, to: snapshot).objectives.map(\.deadline), [day("2026-12-20"), day("2027-01-03"), day("2027-01-24")])
    }

    func testUnknownGoalIdCreatesANewGoal() {
        let (snapshot, _) = updateFixture()
        let result = materialise(updatePlan(uuid(777)), into: snapshot)
        XCTAssertFalse(result.summary.isUpdate)
        XCTAssertEqual(applied(result, to: snapshot).goals.count, 2)
    }

    func testUpdateOnlyTouchesTheMatchedGoal() {
        let (snapshot, goalID) = updateFixture()
        var second = basePlan()
        second.goal.key = "other"
        let both = applied(materialise(second, into: snapshot), to: snapshot)
        let before = both.habits.filter { $0.goalID != goalID }
        let result = materialise(updatePlan(goalID) { $0.habits.removeAll() }, into: both)
        let after = applied(result, to: both)
        XCTAssertEqual(after.habits.filter { $0.goalID != goalID }, before)
    }

    func testHandMadeEntitiesAreNeverRemovedByAnUpdate() {
        var (snapshot, goalID) = updateFixture()
        let system = snapshot.systems.first { $0.planKey == "s1" }!
        let mine = Habit(systemID: system.id, goalID: goalID, title: "Mine", badDayTitle: "Less")
        snapshot.habits.append(mine)
        let result = materialise(updatePlan(goalID), into: snapshot)
        XCTAssertEqual(result.summary.removed, 0)
        XCTAssertFalse(applied(result, to: snapshot).habits.first { $0.id == mine.id }!.isArchived)
    }

    // MARK: PlanV1 rebuild (Appendix C)

    func testRebuildSampleGoalValidatesAndUpdatesInPlace() throws {
        let snapshot = SampleData.bodyFatGoal(today: today)
        let plan = try XCTUnwrap(PlanV1(goalID: SampleData.goalID, snapshot: snapshot))
        XCTAssertEqual(plan.goal.id, SampleData.goalID.uuidString)
        XCTAssertEqual(plan.firstPrinciples.map(\.key), ["fp1", "fp2", "fp3"])
        XCTAssertEqual(plan.systems.map(\.key), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(plan.systems[3].kind, "sustaining")
        XCTAssertNil(plan.systems[3].firstPrinciple)
        XCTAssertEqual(plan.objectives.map(\.key), ["o1", "o2", "o3"])
        XCTAssertEqual(plan.objectives[1].dependsOn, ["o1"])
        XCTAssertEqual(plan.habits.map(\.key), ["h1", "h2", "h3", "h4", "h5"])
        XCTAssertEqual(plan.habits[1].frequency, .init(type: "perWeek", timesPerWeek: 5, preferredWeekdays: [1, 2, 3, 4, 5]))
        XCTAssertEqual(plan.habits[0].reminderTime, "17:00")
        XCTAssertEqual(plan.blocks.map(\.key), ["b1"])
        XCTAssertEqual(plan.blocks[0].weekdays, [7])
        XCTAssertEqual(plan.reminders.map(\.key), ["r1"])
        XCTAssertEqual(PlanImporter.validate(plan), [])
        // Through JSON and back, importing it in update mode creates nothing new and removes nothing.
        let decoded = try PlanImporter.decode(Data(plan.jsonString().utf8))
        XCTAssertEqual(decoded, plan)
        let result = PlanImporter.materialise(decoded, into: snapshot, today: today, settings: snapshot.settings)
        XCTAssertTrue(result.summary.isUpdate)
        XCTAssertEqual(result.summary.inserted, 0)
        XCTAssertEqual(result.summary.removed, 0)
        let after = snapshot.applying(result.changes)
        XCTAssertEqual(after.habits.map(\.id), snapshot.habits.map(\.id))
        XCTAssertEqual(after.systems.map(\.id), snapshot.systems.map(\.id))
        XCTAssertEqual(after.blockRules.map(\.id), snapshot.blockRules.map(\.id))
        XCTAssertEqual(after.logs, snapshot.logs)
    }

    func testRebuildSkipsArchivedHabitsAndMissingGoals() {
        var snapshot = SampleData.bodyFatGoal(today: today)
        snapshot.habits[0].isArchived = true
        let plan = PlanV1(goalID: SampleData.goalID, snapshot: snapshot)!
        XCTAssertFalse(plan.habits.contains { $0.key == "h1" })
        XCTAssertNil(PlanV1(goalID: uuid(404), snapshot: snapshot))
    }

    func testRebuildGivesStableKeysToHandMadeEntitiesAndRoundTripsThem() throws {
        var snapshot = SampleData.bodyFatGoal(today: today)
        let mine = Habit(id: uuid(321), systemID: SampleData.mealsSystemID, goalID: SampleData.goalID, title: "Mine", badDayTitle: "Less")
        snapshot.habits.append(mine)
        let first = PlanV1(goalID: SampleData.goalID, snapshot: snapshot)!
        let second = PlanV1(goalID: SampleData.goalID, snapshot: snapshot)!
        let key = try XCTUnwrap(first.habits.first { $0.title == "Mine" }?.key)
        XCTAssertEqual(key, "h-000000000321")
        XCTAssertEqual(first, second)
        let result = PlanImporter.materialise(first, into: snapshot, today: today, settings: snapshot.settings)
        let after = snapshot.applying(result.changes)
        XCTAssertEqual(after.habits.count, snapshot.habits.count) // matched by generated key, not duplicated
        XCTAssertEqual(after.habits.first { $0.id == mine.id }?.planKey, key)
    }

    func testRebuildIncludesFutureOneOffBlocksAndInactiveRules() throws {
        var snapshot = SampleData.bodyFatGoal(today: today)
        snapshot.blockRules[0].active = false
        snapshot.blocks = [
            CalendarBlock(systemID: SampleData.liftingSystemID, goalID: SampleData.goalID, title: "Far future",
                          start: at("2099-01-04", "10:00"), end: at("2099-01-04", "11:30")),
            CalendarBlock(systemID: SampleData.liftingSystemID, goalID: SampleData.goalID, title: "Long ago",
                          start: at("2001-01-04", "10:00"), end: at("2001-01-04", "11:00")),
            CalendarBlock(systemID: SampleData.liftingSystemID, goalID: SampleData.goalID, title: "Dropped",
                          start: at("2099-01-05", "10:00"), end: at("2099-01-05", "11:00"), status: .cancelled),
        ]
        let plan = try XCTUnwrap(PlanV1(goalID: SampleData.goalID, snapshot: snapshot))
        XCTAssertEqual(plan.blocks.count, 2) // the rule (kept so a re-import doesn't delete it) and the far-future one-off
        let oneOff = try XCTUnwrap(plan.blocks.first { $0.date != nil })
        XCTAssertEqual(oneOff.title, "Far future")
        XCTAssertEqual(oneOff.date, "2099-01-04")
        XCTAssertEqual(oneOff.startTime, "10:00")
        XCTAssertEqual(oneOff.windowEnd, "11:30")
        XCTAssertEqual(oneOff.durationMinutes, 90)
        XCTAssertEqual(PlanImporter.validate(plan), [])
        // Re-import matches the one-off by its generated key; the inactive rule stays inactive.
        let result = PlanImporter.materialise(plan, into: snapshot, today: today, settings: snapshot.settings)
        let after = snapshot.applying(result.changes)
        XCTAssertEqual(after.blocks.filter { $0.title == "Far future" }.count, 1)
        XCTAssertFalse(after.blockRules[0].active)
    }
}
