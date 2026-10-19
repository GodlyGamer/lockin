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
    public static func backSchedule(objectives: [Objective], goal: Goal, today: LocalDay) -> BackScheduleResult {
        // M1: implement (§4.5).
        BackScheduleResult()
    }

    /// Whether making objective `from` depend on objective `to` (adding `to` to `from.dependsOnIDs`) would create a loop.
    public static func wouldCreateCycle(objectives: [Objective], from: UUID, to: UUID) -> Bool {
        // M1: implement (§4.8).
        from == to
    }

    /// Dependencies first. nil if the `dependsOnIDs` graph has a cycle.
    public static func topologicalOrder(_ objectives: [Objective]) -> [UUID]? {
        // M1: implement.
        objectives.map(\.id)
    }

    /// §5.3. For each active rule, one block per matching weekday from `from` for `days` days, skipping dates that
    /// already have a block for that rule. Returns only the new blocks. Saturday rules are skipped for non-physical
    /// rules when `saturdayOff`. `goalID` comes from the rule's system in `systems`.
    public static func materialise(rules: [BlockRule], existing: [CalendarBlock], from: LocalDay, days: Int,
                                   settings: AppSettings, systems: [GoalSystem] = []) -> [CalendarBlock] {
        // M1: implement (§5.3).
        []
    }

    /// §5.4. Returns `blocks` with statuses updated: a future `scheduled` block overlapping a busy interval
    /// (expanded by `travelBufferMinutes`, event not in `ignoredClashEventIDs`) becomes `clash`; a `clash` block that
    /// no longer overlaps goes back to `scheduled` with `suggestedStart = nil`. The caller fills `suggestedStart`
    /// with `suggestSlot`. Busy intervals are passed raw.
    public static func detectClashes(blocks: [CalendarBlock], busy: [BusyInterval], settings: AppSettings,
                                     now: Date) -> [CalendarBlock] {
        // M1: implement (§5.4).
        blocks
    }

    /// §5.4. Earliest free start of the same duration: same day inside the rule's window (one-off blocks: the day's
    /// bestHours), then the same window on the following days up to 7 days ahead, skipping Saturday unless physical
    /// (when saturdayOff), never overlapping busy (with travel buffer) or other non-cancelled blocks. nil = "No free slot this week".
    public static func suggestSlot(for block: CalendarBlock, rule: BlockRule?, busy: [BusyInterval],
                                   blocks: [CalendarBlock], settings: AppSettings) -> Date? {
        // M1: implement (§5.4).
        nil
    }

    /// §4.7. Busy intervals are passed raw for the next 7 days from `now`.
    public static func feasibility(goal: Goal, snapshot: StoreSnapshot, busy: [BusyInterval], now: Date) -> FeasibilityReport {
        // M1: implement (§4.7).
        FeasibilityReport(neededMinutes: 0, freeMinutes: 0)
    }

    /// §4.8 layers, nodes and edges for a goal.
    public static func mapLayout(goalID: UUID, snapshot: StoreSnapshot) -> MapLayout {
        // M1: implement (§4.8).
        MapLayout()
    }
}
