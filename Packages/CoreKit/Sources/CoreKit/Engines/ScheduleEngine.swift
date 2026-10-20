import Foundation

/// §4.5 result.
public struct BackScheduleResult: Equatable, Sendable {
    /// Computed (or overridden) deadline per objective id.
    public var deadlines: [UUID: LocalDay]
    /// Objectives where `latestFinish − estimatedDays < today`: N in "Starts N days too late".
    public var startsLateByDays: [UUID: Int]

    public init(deadlines: [UUID: LocalDay] = [:], startsLateByDays: [UUID: Int] = [:]) {
        self.deadlines = deadlines; self.startsLateByDays = startsLateByDays
    }
}

/// §4.7 result.
public struct FeasibilityReport: Equatable, Sendable {
    public var neededMinutes: Int
    public var freeMinutes: Int

    public init(neededMinutes: Int, freeMinutes: Int) {
        self.neededMinutes = neededMinutes; self.freeMinutes = freeMinutes
    }

    /// needed > 0.8 × free
    public var isWarning: Bool { Double(neededMinutes) > 0.8 * Double(freeMinutes) }

    /// "This plan needs 6.5 h a week. You have 4 h free in your best hours." or nil when no warning.
    public var message: String? {
        guard isWarning else { return nil }
        return "This plan needs \(Self.hours(neededMinutes)) a week. You have \(Self.hours(freeMinutes)) free in your best hours."
    }

    static func hours(_ minutes: Int) -> String {
        let h = Double(minutes) / 60
        return h == h.rounded() ? "\(Int(h)) h" : String(format: "%.1f h", h)
    }
}

/// §4.8 — the goal map as layers, nodes and edges (no coordinates; M5 lays it out).
public struct MapLayout: Equatable, Sendable {
    public enum NodeKind: String, Equatable, Sendable {
        case goal, principle, system, objective
    }

    public struct Node: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var kind: NodeKind
        public var title: String
        public var layer: Int

        public init(id: UUID, kind: NodeKind, title: String, layer: Int) {
            self.id = id; self.kind = kind; self.title = title; self.layer = layer
        }
    }

    public struct Edge: Hashable, Sendable {
        public var from: UUID
        public var to: UUID

        public init(from: UUID, to: UUID) {
            self.from = from; self.to = to
        }
    }

    /// Layer 0: goal; 1: principles; 2: principle systems; 3+: objectives by longest-path depth.
    public var layers: [[Node]]
    /// The sustaining system, drawn full-width and dashed below the last layer.
    public var sustaining: Node?
    public var edges: [Edge]

    public init(layers: [[Node]] = [], sustaining: Node? = nil, edges: [Edge] = []) {
        self.layers = layers; self.sustaining = sustaining; self.edges = edges
    }
}

/// Back-scheduling, DAG checks, block materialising, clashes, slot suggestions, feasibility and map layout. Stateless.
public enum ScheduleEngine {
    /// §4.5. Sinks finish at `goal.deadline − bufferDays`; predecessors at min over successors of
    /// (latestFinish(s) − s.estimatedDays). Overridden deadlines are kept and propagate.
    ///
    /// `startsLateByDays` is filled for objectives that are not `done`. Every objective in `objectives` is scheduled
    /// (the caller passes the goal's objectives).
    public static func backSchedule(objectives: [Objective], goal: Goal, today: LocalDay) -> BackScheduleResult {
        guard !objectives.isEmpty else { return BackScheduleResult() }
        var byID: [UUID: Objective] = [:]
        for objective in objectives where byID[objective.id] == nil { byID[objective.id] = objective }

        var successors: [UUID: [UUID]] = [:]
        for objective in objectives {
            for dependency in Set(objective.dependsOnIDs) where dependency != objective.id && byID[dependency] != nil {
                successors[dependency, default: []].append(objective.id)
            }
        }

        let sinkFinish = goal.deadline.adding(days: -goal.bufferDays)
        // Dependencies first; reversed, every objective comes after all of its successors. A cycle (which validation
        // and the UI prevent) falls back to document order and the sink date for anything not yet scheduled.
        let order = topologicalOrder(objectives) ?? objectives.map(\.id)
        var finish: [UUID: LocalDay] = [:]
        for id in order.reversed() {
            guard let objective = byID[id] else { continue }
            if objective.deadlineOverridden, let stored = objective.deadline {
                finish[id] = stored
                continue
            }
            let candidates = (successors[id] ?? []).compactMap { successorID -> LocalDay? in
                guard let successor = byID[successorID], let latest = finish[successorID] else { return nil }
                return latest.adding(days: -successor.estimatedDays)
            }
            finish[id] = candidates.min() ?? sinkFinish
        }

        var late: [UUID: Int] = [:]
        for objective in objectives where objective.status != .done {
            guard let latest = finish[objective.id] else { continue }
            let start = latest.adding(days: -objective.estimatedDays)
            if start < today { late[objective.id] = start.days(to: today) }
        }
        return BackScheduleResult(deadlines: finish, startsLateByDays: late)
    }

    /// Whether making objective `from` depend on objective `to` (adding `to` to `from.dependsOnIDs`) would create a loop.
    public static func wouldCreateCycle(objectives: [Objective], from: UUID, to: UUID) -> Bool {
        if from == to { return true }
        var dependencies: [UUID: [UUID]] = [:]
        for objective in objectives { dependencies[objective.id] = objective.dependsOnIDs }
        // A loop appears exactly when `to` already depends (directly or not) on `from`.
        var stack = [to]
        var seen = Set<UUID>()
        while let node = stack.popLast() {
            if node == from { return true }
            guard seen.insert(node).inserted else { continue }
            stack.append(contentsOf: dependencies[node] ?? [])
        }
        return false
    }

    /// Dependencies first. nil if the `dependsOnIDs` graph has a cycle.
    public static func topologicalOrder(_ objectives: [Objective]) -> [UUID]? {
        var seenIDs = Set<UUID>()
        var pending = objectives.filter { seenIDs.insert($0.id).inserted }
        let known = Set(pending.map(\.id))
        var emitted = Set<UUID>()
        var order: [UUID] = []
        while !pending.isEmpty {
            let ready = pending.filter { objective in
                objective.dependsOnIDs.allSatisfy { !known.contains($0) || emitted.contains($0) }
            }
            if ready.isEmpty { return nil }
            for objective in ready {
                order.append(objective.id)
                emitted.insert(objective.id)
            }
            pending.removeAll { emitted.contains($0.id) }
        }
        return order
    }

    /// §5.3. For each active rule, one block per matching weekday from `from` for `days` days, skipping dates that
    /// already have a block for that rule. Returns only the new blocks. Saturday rules are skipped for non-physical
    /// rules when `saturdayOff`. `goalID` comes from the rule's system in `systems`.
    ///
    /// "Already has a block" means any block of the rule (whatever its status, so a cancelled block is not
    /// resurrected) whose start falls on that date. Blocks are returned in date order.
    public static func materialise(rules: [BlockRule], existing: [CalendarBlock], from: LocalDay, days: Int,
                                   settings: AppSettings, systems: [GoalSystem] = []) -> [CalendarBlock] {
        guard days > 0 else { return [] }
        var taken = Set<RuleDay>()
        for block in existing {
            if let ruleID = block.ruleID { taken.insert(RuleDay(ruleID: ruleID, day: block.day)) }
        }
        let goalBySystem = Dictionary(systems.map { ($0.id, $0.goalID) }, uniquingKeysWith: { first, _ in first })
        var created: [CalendarBlock] = []
        for offset in 0..<days {
            let day = from.adding(days: offset)
            for rule in rules where rule.active && rule.weekdays.contains(day.weekday) {
                if day.weekday == 6 && settings.saturdayOff && !rule.isPhysical { continue }
                guard taken.insert(RuleDay(ruleID: rule.id, day: day)).inserted else { continue }
                let start = day.date(minutes: rule.startTime)
                created.append(CalendarBlock(ruleID: rule.id, systemID: rule.systemID, goalID: goalBySystem[rule.systemID],
                                             title: rule.title, start: start,
                                             end: start.addingTimeInterval(TimeInterval(rule.durationMinutes) * 60),
                                             isPhysical: rule.isPhysical, nudge: rule.nudge))
            }
        }
        return created
    }

    private struct RuleDay: Hashable {
        var ruleID: UUID
        var day: LocalDay
    }

    /// §5.4. Returns `blocks` with statuses updated: a future `scheduled` block overlapping a busy interval
    /// (expanded by `travelBufferMinutes`, event not in `ignoredClashEventIDs`) becomes `clash`; a `clash` block that
    /// no longer overlaps goes back to `scheduled` with `suggestedStart = nil`. The caller fills `suggestedStart`
    /// with `suggestSlot`. Busy intervals are passed raw.
    ///
    /// "Future" means the block starts at or after `now`; blocks that have started, and `done` / `cancelled` blocks,
    /// are returned unchanged.
    public static func detectClashes(blocks: [CalendarBlock], busy: [BusyInterval], settings: AppSettings,
                                     now: Date) -> [CalendarBlock] {
        let buffer = TimeInterval(max(0, settings.travelBufferMinutes)) * 60
        return blocks.map { block in
            guard block.status == .scheduled || block.status == .clash, block.start >= now else { return block }
            let clashes = busy.contains { interval in
                if let id = interval.eventID, block.ignoredClashEventIDs.contains(id) { return false }
                return CoreFormat.overlaps(block.start, block.end,
                                           interval.start.addingTimeInterval(-buffer), interval.end.addingTimeInterval(buffer))
            }
            var result = block
            if clashes {
                result.status = .clash
            } else if block.status == .clash {
                result.status = .scheduled
                result.suggestedStart = nil
            }
            return result
        }
    }

    /// §5.4. Earliest free start of the same duration: same day inside the rule's window (one-off blocks: the day's
    /// bestHours), then the same window on the following days up to 7 days ahead, skipping Saturday unless physical
    /// (when saturdayOff), never overlapping busy (with travel buffer) or other non-cancelled blocks. nil = "No free slot this week".
    ///
    /// The search has no clock: it starts at the beginning of the window on the block's own day, so the caller
    /// (which only asks for future blocks) may get a slot earlier that day.
    public static func suggestSlot(for block: CalendarBlock, rule: BlockRule?, busy: [BusyInterval],
                                   blocks: [CalendarBlock], settings: AppSettings) -> Date? {
        let duration = block.end.timeIntervalSince(block.start)
        guard duration > 0 else { return nil }
        let buffer = TimeInterval(max(0, settings.travelBufferMinutes)) * 60
        let skipSaturday = settings.saturdayOff && !block.isPhysical && !(rule?.isPhysical ?? false)

        var obstacles: [(start: Date, end: Date)] = busy.map {
            (start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer))
        }
        for other in blocks where other.id != block.id && other.status != .cancelled {
            obstacles.append((start: other.start, end: other.end))
        }
        let blocked = CoreFormat.merged(obstacles)

        let firstDay = block.day
        for offset in 0...7 {
            let day = firstDay.adding(days: offset)
            if skipSaturday && day.weekday == 6 { continue }
            for window in windows(on: day, rule: rule, settings: settings) {
                var cursor = day.date(minutes: window.lowerBound)
                let windowEnd = day.date(minutes: window.upperBound)
                for obstacle in blocked {
                    if obstacle.end <= cursor { continue }
                    if obstacle.start >= windowEnd { break }
                    if obstacle.start.timeIntervalSince(cursor) >= duration { return cursor }
                    cursor = max(cursor, obstacle.end)
                }
                if windowEnd.timeIntervalSince(cursor) >= duration { return cursor }
            }
        }
        return nil
    }

    /// The windows a block may sit in on `day`: the rule's window, or the day's bestHours for one-off blocks.
    private static func windows(on day: LocalDay, rule: BlockRule?, settings: AppSettings) -> [Range<Int>] {
        if let rule {
            let start = max(0, rule.windowStart)
            let end = min(1440, rule.windowEnd)
            return start < end ? [start..<end] : []
        }
        let merged = settings.bestHours.filter { $0.weekday == day.weekday && $0.start < $0.end }
            .sorted { $0.start < $1.start }
        var result: [Range<Int>] = []
        for window in merged {
            let range = max(0, window.start)..<min(1440, window.end)
            guard range.lowerBound < range.upperBound else { continue }
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// §4.7. Busy intervals are passed raw for the next 7 days from `now`.
    ///
    /// `needed` counts the goal's non-archived habits (duration × scheduled occurrences a week) and the active block
    /// rules of its systems (duration × weekdays). `free` is the time inside `bestHours` from `now` to `now + 7 days`
    /// (Saturday excluded when `saturdayOff`) minus busy time (with `travelBufferMinutes`, §5.4) minus the `needed`
    /// of every other active goal, never below zero.
    public static func feasibility(goal: Goal, snapshot: StoreSnapshot, busy: [BusyInterval], now: Date) -> FeasibilityReport {
        let settings = snapshot.settings
        let needed = neededMinutes(goalID: goal.id, snapshot: snapshot)

        let end = Calendar.lockIn.date(byAdding: .day, value: 7, to: now)!
        var windows: [(start: Date, end: Date)] = []
        let firstDay = LocalDay(now)
        for offset in 0...7 {
            let day = firstDay.adding(days: offset)
            if settings.saturdayOff && day.weekday == 6 { continue }
            for window in settings.bestHours where window.weekday == day.weekday {
                let start = max(day.date(minutes: window.start), now)
                let finish = min(day.date(minutes: window.end), end)
                if start < finish { windows.append((start: start, end: finish)) }
            }
        }
        let bestWindows = CoreFormat.merged(windows)
        let buffer = TimeInterval(max(0, settings.travelBufferMinutes)) * 60
        let busyWindows = CoreFormat.merged(busy.map {
            (start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer))
        })

        var freeSeconds: TimeInterval = 0
        for window in bestWindows {
            freeSeconds += window.end.timeIntervalSince(window.start)
            for blocked in busyWindows {
                let start = max(window.start, blocked.start)
                let finish = min(window.end, blocked.end)
                if start < finish { freeSeconds -= finish.timeIntervalSince(start) }
            }
        }
        let othersNeeded = snapshot.goals.filter { $0.id != goal.id && $0.status == .active }
            .reduce(0) { $0 + neededMinutes(goalID: $1.id, snapshot: snapshot) }
        let free = max(0, Int((freeSeconds / 60).rounded()) - othersNeeded)
        return FeasibilityReport(neededMinutes: needed, freeMinutes: free)
    }

    /// Weekly minutes a goal asks for (§4.7).
    private static func neededMinutes(goalID: UUID, snapshot: StoreSnapshot) -> Int {
        let habitMinutes = snapshot.habits.filter { $0.goalID == goalID && !$0.isArchived }
            .reduce(0) { $0 + $1.durationMinutes * Habit.scheduledPerWeek($1.frequency) }
        let systemIDs = Set(snapshot.systems.filter { $0.goalID == goalID }.map(\.id))
        let blockMinutes = snapshot.blockRules.filter { $0.active && systemIDs.contains($0.systemID) }
            .reduce(0) { $0 + $1.durationMinutes * Set($1.weekdays).count }
        return habitMinutes + blockMinutes
    }

    /// §4.8 layers, nodes and edges for a goal.
    public static func mapLayout(goalID: UUID, snapshot: StoreSnapshot) -> MapLayout {
        guard let goal = snapshot.goal(goalID) else { return MapLayout() }
        let principles = snapshot.firstPrinciples(goalID: goalID)
        let allSystems = snapshot.systems(goalID: goalID)
        let objectives = snapshot.objectives(goalID: goalID)

        var layers: [[MapLayout.Node]] = [
            [MapLayout.Node(id: goal.id, kind: .goal, title: goal.title, layer: 0)],
            principles.map { MapLayout.Node(id: $0.id, kind: .principle, title: $0.title, layer: 1) },
        ]

        // Layer 2: principle systems, grouped under their principle (principle order, then sortIndex).
        let principleSystems = allSystems.filter { $0.kind == .principle }
        var orderedSystems: [GoalSystem] = []
        for principle in principles {
            orderedSystems += principleSystems.filter { $0.firstPrincipleID == principle.id }
        }
        let principleIDs = Set(principles.map(\.id))
        orderedSystems += principleSystems.filter { system in
            guard let parent = system.firstPrincipleID else { return true }
            return !principleIDs.contains(parent)
        }
        layers.append(orderedSystems.map { MapLayout.Node(id: $0.id, kind: .system, title: $0.title, layer: 2) })

        // Layer 3+: objectives by longest-path depth (no dependencies = layer 3).
        let objectiveIDs = Set(objectives.map(\.id))
        let byID = Dictionary(objectives.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var depth: [UUID: Int] = [:]
        func layer(of id: UUID, visiting: Set<UUID>) -> Int {
            if let known = depth[id] { return known }
            guard let objective = byID[id], !visiting.contains(id) else { return 3 }
            let dependencies = objective.dependsOnIDs.filter { objectiveIDs.contains($0) && $0 != id }
            let value = dependencies.isEmpty ? 3 : 1 + (dependencies.map { layer(of: $0, visiting: visiting.union([id])) }.max() ?? 2)
            depth[id] = value
            return value
        }
        for objective in objectives {
            let level = layer(of: objective.id, visiting: [])
            while layers.count <= level { layers.append([]) }
            layers[level].append(MapLayout.Node(id: objective.id, kind: .objective, title: objective.title, layer: level))
        }
        while layers.count > 1, layers.last?.isEmpty == true { layers.removeLast() }

        let sustaining = allSystems.first { $0.kind == .sustaining }.map {
            MapLayout.Node(id: $0.id, kind: .system, title: $0.title, layer: layers.count)
        }

        // Edges: goal→principle, principle→system, system→objective, objective→dependent objective.
        var edges: [MapLayout.Edge] = []
        var seen = Set<MapLayout.Edge>()
        func addEdge(_ from: UUID, _ to: UUID) {
            let edge = MapLayout.Edge(from: from, to: to)
            if seen.insert(edge).inserted { edges.append(edge) }
        }
        for principle in principles { addEdge(goal.id, principle.id) }
        for system in orderedSystems {
            if let parent = system.firstPrincipleID, principleIDs.contains(parent) { addEdge(parent, system.id) }
        }
        let systemIDs = Set(allSystems.map(\.id))
        for objective in objectives {
            for systemID in objective.systemIDs where systemIDs.contains(systemID) { addEdge(systemID, objective.id) }
        }
        for objective in objectives {
            for dependency in objective.dependsOnIDs where objectiveIDs.contains(dependency) && dependency != objective.id {
                addEdge(dependency, objective.id)
            }
        }
        return MapLayout(layers: layers, sustaining: sustaining, edges: edges)
    }
}
