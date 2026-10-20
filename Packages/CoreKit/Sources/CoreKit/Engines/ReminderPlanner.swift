import Foundation

/// Plans every pending notification (§6). Stateless.
public enum ReminderPlanner {
    /// Every regular notification for `now` → `now + horizonDays`, after the daily cap (§6.2), sorted by fire date,
    /// first `maxPending` kept, plus the re-sign notification on top when `signingExpiry` is within 7 days.
    /// Text follows §6.4 exactly; identifiers and links follow §6.3 and §6.5. Notifications whose fire date is not
    /// after `now` are dropped.
    ///
    /// The returned list is sorted by fire date, the re-sign notification included. The horizon warning goes on the
    /// last evening notification that survives the cap.
    public static func plan(snapshot: StoreSnapshot, now: Date, signingExpiry: Date?, horizonDays: Int = 10,
                            maxPending: Int = 60) -> [PlannedNotification] {
        let context = Context(snapshot: snapshot, now: now)
        let windowEnd = Calendar.lockIn.date(byAdding: .day, value: max(0, horizonDays), to: now)!
        let lastDay = LocalDay(windowEnd)

        var regular: [PlannedNotification] = []
        var day = LocalDay(now)
        while day <= lastDay {
            regular += context.notifications(on: day)
            day = day.adding(days: 1)
        }
        regular = regular.filter { $0.fireDate > now && $0.fireDate <= windowEnd }
        regular.sort(by: isEarlier)
        regular = Array(regular.prefix(max(0, maxPending)))

        // Horizon warning (§6.3): the last evening notification still pending tells the user to reopen the app.
        if let index = regular.lastIndex(where: { $0.kind == .evening }) {
            regular[index].body += " Open the app to keep reminders coming."
        }

        var result = regular
        if let resign = resignNotification(expiry: signingExpiry, now: now) {
            result.append(resign)
            result.sort(by: isEarlier)
        }
        return result
    }

    // MARK: - Re-sign (§6.1)

    private static func resignNotification(expiry: Date?, now: Date) -> PlannedNotification? {
        guard let expiry, expiry > now else { return nil }
        let withinAWeek = Calendar.lockIn.date(byAdding: .day, value: 7, to: now)!
        guard expiry <= withinAWeek else { return nil }
        let fire = max(expiry.addingTimeInterval(-48 * 3600), now.addingTimeInterval(60))
        guard fire < expiry else { return nil }
        let expiryDay = LocalDay(expiry)
        let when = "\(CoreFormat.dayMonth(expiryDay)) at \(CoreFormat.time(expiry))"
        return PlannedNotification(id: "resign", fireDate: fire, title: "Re-sign Lock in.",
                                   body: "It stops opening \(when). Your data is safe. Plug in and run Sideloadly.",
                                   link: .settings, kind: .resign)
    }

    private static func isEarlier(_ a: PlannedNotification, _ b: PlannedNotification) -> Bool {
        (a.fireDate, a.id) < (b.fireDate, b.id)
    }

    // MARK: - Per-day planning

    /// Pre-indexed snapshot data so a day's candidates are cheap to build.
    private struct Context {
        let snapshot: StoreSnapshot
        let now: Date
        let settings: AppSettings
        let activeHabits: [Habit]
        let logsByHabit: [UUID: [HabitLog]]
        let systemsByID: [UUID: GoalSystem]
        let nudgeBlocks: [(block: CalendarBlock, fire: Date)]

        init(snapshot: StoreSnapshot, now: Date) {
            self.snapshot = snapshot
            self.now = now
            self.settings = snapshot.settings
            self.activeHabits = snapshot.habits.filter { !$0.isArchived }
            self.logsByHabit = Dictionary(grouping: snapshot.logs, by: \.habitID)
            self.systemsByID = Dictionary(snapshot.systems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.nudgeBlocks = snapshot.blocks
                .filter { $0.nudge && $0.status == .scheduled }
                .map { (block: $0, fire: $0.start.addingTimeInterval(-10 * 60)) }
        }

        func logs(for habit: Habit) -> [HabitLog] { logsByHabit[habit.id] ?? [] }

        /// Notifications for one day after the §6.2 cap (not yet filtered by `now` or the horizon).
        func notifications(on day: LocalDay) -> [PlannedNotification] {
            var result: [PlannedNotification] = []
            let dueHabits = activeHabits.filter { HabitEngine.isDue($0, on: day, logs: logs(for: $0)) }
            let blocksToday = snapshot.blocks.filter {
                ($0.status == .scheduled || $0.status == .clash) && $0.day == day
            }

            if let morning = morning(on: day, dueHabits: dueHabits, blocks: blocksToday) { result.append(morning) }
            if let evening = evening(on: day, dueHabits: dueHabits) { result.append(evening) }

            let checkIn = checkIn(on: day)
            if let checkIn { result.append(checkIn) }

            // Timed slots: habits, block nudges and plan reminders compete by priority, then fire time (§6.2).
            let slots = max(0, settings.maxTimedNudgesPerDay - (checkIn == nil ? 0 : 1))
            let timed = timedCandidates(on: day)
                .sorted { ($0.priority, $0.notification.fireDate, $0.notification.id) < ($1.priority, $1.notification.fireDate, $1.notification.id) }
                .prefix(slots)
            result += timed.map { $0.notification }
            return result
        }

        // Morning (§6.1, §6.4)
        private func morning(on day: LocalDay, dueHabits: [Habit], blocks: [CalendarBlock]) -> PlannedNotification? {
            guard !dueHabits.isEmpty || !blocks.isEmpty else { return nil }
            var timed: [(minutes: Int, title: String)] = blocks.map { (minutes: TimeOfDay.minutes(of: $0.start), title: $0.title) }
            for habit in dueHabits {
                if let time = habit.reminderTime { timed.append((minutes: time, title: habit.title)) }
            }
            timed.sort { ($0.minutes, $0.title) < ($1.minutes, $1.title) }

            let counts = (blocks.isEmpty ? "" : "\(blocks.count) blocks, ") + "\(dueHabits.count) habits"
            let body: String
            if let first = timed.first {
                body = "\(counts). First: \(first.title) at \(TimeOfDay.format(first.minutes))."
            } else {
                body = "\(dueHabits.count) habits today."
            }
            return PlannedNotification(id: "morning-\(day.string)",
                                       fireDate: day.date(minutes: settings.morningTime(on: day.weekday)),
                                       title: "Today.", body: body, link: .today, kind: .morning)
        }

        // Evening tick-off (§6.1, §6.4)
        private func evening(on day: LocalDay, dueHabits: [Habit]) -> PlannedNotification? {
            let unmarked = dueHabits.filter { habit in !logs(for: habit).contains { $0.day == day } }
                .sorted { a, b in
                    (a.priority, a.reminderTime ?? Int.max, a.sortIndex, a.title) < (b.priority, b.reminderTime ?? Int.max, b.sortIndex, b.title)
                }
            guard !unmarked.isEmpty else { return nil }
            let titles = unmarked.prefix(3).map(\.title).joined(separator: ", ")
            let more = unmarked.count > 3 ? " +\(unmarked.count - 3) more" : ""
            return PlannedNotification(id: "evening-\(day.string)", fireDate: day.date(minutes: settings.eveningTime),
                                       title: "Tick off today.", body: "\(unmarked.count) left: \(titles)\(more).",
                                       link: .today, kind: .evening)
        }

        // Check-in (§6.1, §6.4)
        private func checkIn(on day: LocalDay) -> PlannedNotification? {
            guard day.weekday == settings.checkInWeekday else { return nil }
            let lastWeek = Week(containing: day).previous
            let goals = snapshot.goals.filter { $0.status == .active }
            guard goals.contains(where: { snapshot.weekReview(goalID: $0.id, week: lastWeek)?.finishedAt == nil }) else { return nil }
            var onTarget = 0
            var total = 0
            for goal in goals {
                let score = HabitEngine.goalWeekScore(goal: goal, habits: snapshot.habits, week: lastWeek,
                                                      logs: snapshot.logs, now: now, settings: settings)
                onTarget += score.onTarget
                total += score.total
            }
            return PlannedNotification(id: "checkin-\(day.string)", fireDate: day.date(minutes: settings.checkInTime),
                                       title: "Check-in.",
                                       body: "Last week: \(onTarget) of \(total) on target. About 5 minutes.",
                                       link: .week, kind: .checkIn)
        }

        // Timed habits, block nudges and plan reminders (§6.1, §6.4)
        private func timedCandidates(on day: LocalDay) -> [(priority: Int, notification: PlannedNotification)] {
            var candidates: [(priority: Int, notification: PlannedNotification)] = []

            for habit in activeHabits {
                guard let time = habit.reminderTime, HabitEngine.isScheduled(habit, on: day) else { continue }
                let habitLogs = logs(for: habit)
                // Marked D, B or M (skip) that day: no nudge (§6.1, §6.5).
                if habitLogs.contains(where: { $0.day == day }) { continue }
                if case .perWeek(let n) = habit.frequency {
                    guard habit.preferredWeekdays.contains(day.weekday) else { continue }
                    let week = Week(containing: day)
                    let done = habitLogs.filter { week.contains($0.day) && $0.mark != .M }.count
                    guard done < n else { continue }
                }
                let location = habit.systemID.flatMap { systemsByID[$0] }?.location.flatMap { $0.isEmpty ? nil : $0 }
                let at = location.map { " at \($0)" } ?? ""
                let notification = PlannedNotification(
                    id: "habit-\(habit.id.uuidString)-\(day.string)", fireDate: day.date(minutes: time),
                    title: CoreFormat.withFullStop(habit.title),
                    body: "\(TimeOfDay.format(time))\(at). Bad day: \(habit.badDayTitle).",
                    link: .habit(habit.id, day), kind: .habit)
                candidates.append((priority: habit.priority, notification: notification))
            }

            for (block, fire) in nudgeBlocks where LocalDay(fire) == day {
                let notification = PlannedNotification(
                    id: "block-\(block.id.uuidString)", fireDate: fire, title: CoreFormat.withFullStop(block.title),
                    body: "Starts \(CoreFormat.time(block.start)), \(block.durationMinutes) min.",
                    link: .block(block.id), kind: .block)
                candidates.append((priority: 3, notification: notification))
            }

            for reminder in snapshot.reminders where reminder.active {
                let matches = reminder.date.map { $0 == day } ?? reminder.weekdays.contains(day.weekday)
                guard matches else { continue }
                let notification = PlannedNotification(
                    id: "reminder-\(reminder.id.uuidString)-\(day.string)", fireDate: day.date(minutes: reminder.time),
                    title: reminder.title, body: reminder.body, link: .today, kind: .reminder)
                candidates.append((priority: reminder.priority, notification: notification))
            }
            return candidates
        }
    }
}
