import Foundation

/// Preview and test data matching the design mockups.
public enum SampleData {
    // Fixed ids so previews and tests can refer to them.
    public static let goalID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    public static let principleDeficitID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    public static let principleMuscleID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
    public static let principleMovementID = UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!
    public static let mealsSystemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    public static let liftingSystemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
    public static let walkSystemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!
    public static let sleepSystemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C004")!
    public static let liftHabitID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    public static let inclineWalkHabitID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
    public static let proteinHabitID = UUID(uuidString: "00000000-0000-0000-0000-00000000D003")!
    public static let postGymMealHabitID = UUID(uuidString: "00000000-0000-0000-0000-00000000D004")!
    public static let sleepHabitID = UUID(uuidString: "00000000-0000-0000-0000-00000000D005")!
    public static let mealPrepRuleID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
    public static let objective84ID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
    public static let objective82ID = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!
    public static let objective80ID = UUID(uuidString: "00000000-0000-0000-0000-00000000F003")!

    /// Goal "10% body fat": 3 principles, systems Meals / Lifting M/W/F / Walk, habits Lift, Incline walk, Protein x4,
    /// Post-gym meal, sustaining system "Sleep by 23:30", a 3-milestone chain, a Sunday meal-prep block rule, and marks
    /// for last week and this week up to yesterday. Onboarding is marked done.
    public static func bodyFatGoal(today: LocalDay = .today) -> StoreSnapshot {
        let created = today.adding(days: -21).date(minutes: 600)
        var settings = AppSettings.defaults
        settings.onboardingDone = true

        let goal = Goal(id: goalID, planKey: "g", title: "10% body fat",
                        outcome: "Weigh-in average at 78 kg with lifts holding steady",
                        deadline: today.adding(days: 75), bufferDays: 7, resultName: "Weigh-in average", resultUnit: "kg",
                        resultStart: 86, resultTarget: 78, resultDirection: .down, bottleneckHabitID: inclineWalkHabitID,
                        createdAt: created)

        let principles = [
            FirstPrinciple(id: principleDeficitID, planKey: "fp1", goalID: goalID, title: "Eat in a calorie deficit",
                           why: "Fat loss only happens below maintenance.", sortIndex: 0),
            FirstPrinciple(id: principleMuscleID, planKey: "fp2", goalID: goalID, title: "Keep muscle while cutting",
                           why: "Lifting and protein stop the deficit eating muscle.", sortIndex: 1),
            FirstPrinciple(id: principleMovementID, planKey: "fp3", goalID: goalID, title: "Move every day",
                           why: "Low-intensity movement adds burn without hurting recovery.", sortIndex: 2),
        ]

        let systems = [
            GoalSystem(id: mealsSystemID, planKey: "s1", goalID: goalID, firstPrincipleID: principleDeficitID,
                       title: "Meals", location: "Home", sortIndex: 0),
            GoalSystem(id: liftingSystemID, planKey: "s2", goalID: goalID, firstPrincipleID: principleMuscleID,
                       title: "Lifting M/W/F", location: "Gym", sortIndex: 1),
            GoalSystem(id: walkSystemID, planKey: "s3", goalID: goalID, firstPrincipleID: principleMovementID,
                       title: "Walk", location: "Gym", sortIndex: 2),
            GoalSystem(id: sleepSystemID, planKey: "s4", goalID: goalID, kind: .sustaining, title: "Sleep by 23:30",
                       sortIndex: 3),
        ]

        let habits = [
            Habit(id: liftHabitID, planKey: "h1", systemID: liftingSystemID, goalID: goalID, title: "Lift",
                  badDayTitle: "Two main lifts only", frequency: .weekdays([1, 3, 5]), reminderTime: 1020,
                  durationMinutes: 60, isPhysical: true, priority: 1, createdAt: created, sortIndex: 0),
            Habit(id: inclineWalkHabitID, planKey: "h2", systemID: walkSystemID, goalID: goalID, title: "Incline walk",
                  badDayTitle: "20 min walk", frequency: .perWeek(5), preferredWeekdays: [1, 2, 3, 4, 5],
                  reminderTime: 495, durationMinutes: 40, isPhysical: true, priority: 2, createdAt: created, sortIndex: 1),
            Habit(id: proteinHabitID, planKey: "h3", systemID: mealsSystemID, goalID: goalID, title: "Protein x4",
                  badDayTitle: "3 portions", kind: .count, target: 4, badDayTarget: 3, unit: "portions",
                  frequency: .daily, setPointPerWeek: 6, durationMinutes: 10, priority: 3, createdAt: created, sortIndex: 2),
            Habit(id: postGymMealHabitID, planKey: "h4", systemID: mealsSystemID, goalID: goalID, title: "Post-gym meal",
                  badDayTitle: "Shake and a banana", frequency: .weekdays([1, 3, 5]), reminderTime: 1140,
                  durationMinutes: 20, priority: 4, createdAt: created, sortIndex: 3),
            Habit(id: sleepHabitID, planKey: "h5", systemID: sleepSystemID, goalID: goalID, title: "In bed by 23:30",
                  badDayTitle: "In bed by midnight", frequency: .daily, setPointPerWeek: 5, reminderTime: 1365,
                  durationMinutes: 15, priority: 3, createdAt: created, sortIndex: 4),
        ]

        let objectives = [
            Objective(id: objective84ID, planKey: "o1", goalID: goalID, title: "84.0 kg", estimatedDays: 21,
                      status: .inProgress, systemIDs: [mealsSystemID, walkSystemID], sortIndex: 0),
            Objective(id: objective82ID, planKey: "o2", goalID: goalID, title: "82.0 kg", estimatedDays: 21,
                      dependsOnIDs: [objective84ID], systemIDs: [mealsSystemID, liftingSystemID, walkSystemID], sortIndex: 1),
            Objective(id: objective80ID, planKey: "o3", goalID: goalID, title: "80.0 kg", estimatedDays: 21,
                      dependsOnIDs: [objective82ID], systemIDs: [mealsSystemID, liftingSystemID, walkSystemID], sortIndex: 2),
        ]

        let steps = [
            Step(planKey: "st1", objectiveID: objective84ID, title: "Set up a food log", estimatedMinutes: 20, done: true),
            Step(planKey: "st2", objectiveID: objective84ID, title: "Weigh in every morning for a week", estimatedMinutes: 5,
                 sortIndex: 1),
        ]

        let rules = [
            BlockRule(id: mealPrepRuleID, planKey: "b1", systemID: mealsSystemID, title: "Meal prep", durationMinutes: 90,
                      weekdays: [7], startTime: 1020, windowStart: 960, windowEnd: 1200),
        ]

        let reminders = [
            PlanReminder(planKey: "r1", systemID: mealsSystemID, title: "Order the food shop",
                         body: "Protein, oats, frozen veg.", weekdays: [6], time: 600, priority: 4),
        ]

        // Marks: last week mostly on target with a bad-day-heavy incline walk; this week up to yesterday.
        var logs: [HabitLog] = []
        func log(_ habitID: UUID, _ day: LocalDay, _ mark: Mark, count: Int? = nil) {
            logs.append(HabitLog(habitID: habitID, day: day, mark: mark, count: count, loggedAt: day.date(minutes: 1260)))
        }
        let lastWeek = Week(containing: today).previous
        for (i, day) in lastWeek.days.enumerated() {
            if [1, 3, 5].contains(day.weekday) {
                log(liftHabitID, day, .D)
                log(postGymMealHabitID, day, day.weekday == 5 ? .B : .D)
            }
            if i < 5 { log(inclineWalkHabitID, day, i % 2 == 0 ? .B : .D) }
            log(proteinHabitID, day, i == 2 ? .B : .D, count: i == 2 ? 3 : 4)
            log(sleepHabitID, day, i == 5 ? .M : .D)
        }
        for day in Week(containing: today).days where day < today {
            if [1, 3, 5].contains(day.weekday) { log(liftHabitID, day, .D) }
            log(inclineWalkHabitID, day, .D)
            log(proteinHabitID, day, .B, count: 3)
        }

        let reviews = [
            WeekReview(goalID: goalID, weekStart: lastWeek.previous.start, resultValue: 84.6,
                       bottleneckHabitID: inclineWalkHabitID, finishedAt: lastWeek.start.date(minutes: 1170)),
        ]

        return StoreSnapshot(settings: settings, goals: [goal], firstPrinciples: principles, systems: systems,
                             objectives: objectives, steps: steps, habits: habits, logs: logs, weekReviews: reviews,
                             blockRules: rules, blocks: [], reminders: reminders)
    }

    /// Uni timetable events for the current week (Mon–Fri lectures), for calendar previews.
    public static func timetable(today: LocalDay = .today) -> [ExternalEvent] {
        let week = Week(containing: today)
        var events: [ExternalEvent] = []
        for day in week.days where day.weekday <= 5 {
            events.append(ExternalEvent(id: "lecture-\(day.string)-am", title: "Engineering Maths",
                                        start: day.date(minutes: 540), end: day.date(minutes: 660), calendarColorHex: "#34C759"))
            if day.weekday != 3 {
                events.append(ExternalEvent(id: "lecture-\(day.string)-pm", title: "Statics lab",
                                            start: day.date(minutes: 780), end: day.date(minutes: 900),
                                            calendarColorHex: "#FF9F0A"))
            }
        }
        return events
    }
}
