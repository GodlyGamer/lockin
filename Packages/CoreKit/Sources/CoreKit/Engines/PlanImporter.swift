import Foundation

/// A validation problem, shown as `path: message` (e.g. `habits[2].frequency.weekdays: 8 is not 1–7`).
public struct PlanIssue: Equatable, Sendable, CustomStringConvertible {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path; self.message = message
    }

    public var description: String { "\(path): \(message)" }
}

public enum PlanImportError: Error, Equatable, Sendable {
    /// No JSON object found in the pasted text.
    case noJSON
    /// The text is not valid JSON, or a field has the wrong type / is missing. `path` like `habits[2].frequency`.
    case decoding(path: String, message: String)
    /// `schemaVersion` is not 1.
    case unsupportedSchema(Int)

    /// One `path: message` line, for the Import error box.
    public var issue: PlanIssue {
        switch self {
        case .noJSON: PlanIssue(path: "plan", message: "no JSON found. Paste the whole reply or just the ```json block")
        case .decoding(let path, let message): PlanIssue(path: path, message: message)
        case .unsupportedSchema(let v): PlanIssue(path: "schemaVersion", message: "\(v) is not supported (expected 1)")
        }
    }
}

/// The Import review (§7.7).
public struct ImportSummary: Equatable, Sendable {
    public var goalTitle: String
    /// true when `goal.id` matched an existing goal (update mode, §4.4).
    public var isUpdate: Bool
    public var principles: Int
    public var systems: Int
    public var habits: Int
    public var blocks: Int
    public var reminders: Int
    /// Update mode: "+{inserted} new, {changed} changed, {removed} removed".
    public var inserted: Int
    public var changed: Int
    public var removed: Int
    /// "Moved off Saturday: Meal prep → Sun 17:00"
    public var movedOffSaturday: [String]
    /// "{objective title}: Starts N days too late"
    public var startsLate: [String]

    public init(goalTitle: String, isUpdate: Bool = false, principles: Int = 0, systems: Int = 0, habits: Int = 0,
                blocks: Int = 0, reminders: Int = 0, inserted: Int = 0, changed: Int = 0, removed: Int = 0,
                movedOffSaturday: [String] = [], startsLate: [String] = []) {
        self.goalTitle = goalTitle; self.isUpdate = isUpdate; self.principles = principles; self.systems = systems
        self.habits = habits; self.blocks = blocks; self.reminders = reminders; self.inserted = inserted
        self.changed = changed; self.removed = removed; self.movedOffSaturday = movedOffSaturday; self.startsLate = startsLate
    }
}

public struct ImportResult: Sendable {
    /// The goal created or updated.
    public var goalID: UUID
    /// Apply with `store.apply`, then `await calendar.sync()`.
    public var changes: ChangeSet
    public var summary: ImportSummary

    public init(goalID: UUID, changes: ChangeSet, summary: ImportSummary) {
        self.goalID = goalID; self.changes = changes; self.summary = summary
    }
}

/// Plan JSON → app entities (§4.4, Appendix A). Stateless.
public enum PlanImporter {
    // MARK: - Extraction

    /// The JSON text from a paste: the last ```json fenced block if any, else the whole text trimmed. nil if empty.
    ///
    /// A bare ``` fence is accepted too when no ```json block exists. Other fenced languages are ignored, and a fence
    /// that is never closed runs to the end of the text.
    public static func extractJSON(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let blocks = fencedBlocks(in: trimmed)
        let usable = { (info: String) -> String? in
            blocks.last(where: { $0.info == info && !$0.content.isEmpty })?.content
        }
        if let content = usable("json") ?? usable("") { return Data(content.utf8) }
        return Data(trimmed.utf8)
    }

    /// Every ``` fenced block in `text` as (lower-cased language tag, trimmed content).
    private static func fencedBlocks(in text: String) -> [(info: String, content: String)] {
        var blocks: [(info: String, content: String)] = []
        var rest = Substring(text)
        while let open = rest.range(of: "```") {
            let afterOpen = rest[open.upperBound...]
            let lineEnd = afterOpen.firstIndex(of: "\n") ?? afterOpen.endIndex
            let firstLine = afterOpen[..<lineEnd].trimmingCharacters(in: .whitespaces)

            var info = firstLine.lowercased()
            var body = lineEnd == afterOpen.endIndex ? afterOpen[lineEnd...] : afterOpen[afterOpen.index(after: lineEnd)...]
            if firstLine.hasPrefix("{") || firstLine.hasPrefix("[") {
                // "```{ … }```" on one line: no language tag, the line itself is content.
                info = ""
                body = afterOpen
            } else if info.hasPrefix("json"), info.count > 4, let next = info.dropFirst(4).first, !next.isLetter {
                // "```json { … }```" on one line: skip the tag, the rest of the line is content.
                info = "json"
                if let tag = afterOpen.firstIndex(where: { $0 != " " && $0 != "\t" }) {
                    body = afterOpen[afterOpen.index(tag, offsetBy: 4)...]
                }
            }

            if let close = body.range(of: "```") {
                blocks.append((info: info, content: body[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)))
                rest = body[close.upperBound...]
            } else {
                blocks.append((info: info, content: body.trimmingCharacters(in: .whitespacesAndNewlines)))
                break
            }
        }
        return blocks
    }

    // MARK: - Decoding

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    /// Decodes plan JSON (raw or pasted text with a fence). Errors carry a field path.
    public static func decode(_ data: Data) throws(PlanImportError) -> PlanV1 {
        guard let json = extractJSON(from: String(decoding: data, as: UTF8.self)) else { throw .noJSON }
        // Read the version first, so a future schema reports "unsupported" rather than a field error.
        if let version = (try? JSONDecoder().decode(VersionProbe.self, from: json))?.schemaVersion, version != 1 {
            throw .unsupportedSchema(version)
        }
        do {
            return try JSONDecoder().decode(PlanV1.self, from: json)
        } catch let error as DecodingError {
            throw describe(error)
        } catch {
            throw .decoding(path: "plan", message: "\(error)")
        }
    }

    private static func describe(_ error: DecodingError) -> PlanImportError {
        switch error {
        case .keyNotFound(let key, let context):
            return .decoding(path: path(context.codingPath + [key]), message: "required field is missing")
        case .typeMismatch(let type, let context):
            return .decoding(path: path(context.codingPath), message: "expected \(typeDescription(type))")
        case .valueNotFound(let type, let context):
            return .decoding(path: path(context.codingPath), message: "is null but expected \(typeDescription(type))")
        case .dataCorrupted(let context):
            let message = context.debugDescription
            return .decoding(path: path(context.codingPath), message: message.isEmpty ? "is not valid JSON" : message)
        @unknown default:
            return .decoding(path: "plan", message: "\(error)")
        }
    }

    /// `[CodingKey]` → `habits[2].frequency`.
    private static func path(_ keys: [CodingKey]) -> String {
        var result = ""
        for key in keys {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result.isEmpty ? "plan" : result
    }

    private static func typeDescription(_ type: Any.Type) -> String {
        switch type {
        case is Int.Type: return "a whole number"
        case is Double.Type: return "a number"
        case is String.Type: return "text"
        case is Bool.Type: return "true or false"
        default:
            let name = String(describing: type)
            if name.hasPrefix("Array") { return "a list" }
            if name.hasPrefix("Dictionary") { return "an object" }
            return name
        }
    }

    // MARK: - Validation (§4.4 step 1)

    /// Every §4.4 validation failure, in document order. The UI shows the first 5.
    public static func validate(_ plan: PlanV1) -> [PlanIssue] {
        var issues: [PlanIssue] = []
        func add(_ path: String, _ message: String) { issues.append(PlanIssue(path: path, message: message)) }

        func checkDate(_ value: String?, _ path: String) {
            guard let value, LocalDay(value) == nil else { return }
            add(path, "\"\(value)\" is not YYYY-MM-DD")
        }
        func checkTime(_ value: String?, _ path: String) {
            guard let value, TimeOfDay.parse(value) == nil else { return }
            add(path, "\"\(value)\" is not HH:mm")
        }
        func checkWeekdays(_ values: [Int]?, _ path: String) {
            for value in values ?? [] where !(1...7).contains(value) { add(path, "\(value) is not 1–7") }
        }
        func checkDuplicateKeys(_ keys: [String], _ section: String) {
            var seen = Set<String>()
            for (index, key) in keys.enumerated() where !seen.insert(key).inserted {
                add("\(section)[\(index)].key", "duplicate key \"\(key)\"")
            }
        }
        func checkReference(_ key: String?, in known: Set<String>, _ path: String) {
            guard let key, !key.isEmpty, !known.contains(key) else { return }
            add(path, "unknown reference \"\(key)\"")
        }

        if plan.schemaVersion != 1 {
            add("schemaVersion", "\(plan.schemaVersion) is not supported (expected 1)")
        }

        // goal
        if let raw = PlanKeys.goalUUID(plan.goal.id).invalidText {
            add("goal.id", "\"\(raw)\" is not a UUID")
        }
        checkDate(plan.goal.deadline, "goal.deadline")

        let principleKeys = Set(plan.firstPrinciples.map(\.key))
        let systemKeys = Set(plan.systems.map(\.key))
        let objectiveKeys = Set(plan.objectives.map(\.key))

        // firstPrinciples
        checkDuplicateKeys(plan.firstPrinciples.map(\.key), "firstPrinciples")

        // systems
        checkDuplicateKeys(plan.systems.map(\.key), "systems")
        for (i, system) in plan.systems.enumerated() {
            let kind = system.kind.lowercased()
            if kind != "principle" && kind != "sustaining" {
                add("systems[\(i)].kind", "\"\(system.kind)\" is not principle or sustaining")
            }
            checkReference(system.firstPrinciple, in: principleKeys, "systems[\(i)].firstPrinciple")
        }
        let sustainingCount = plan.systems.filter { $0.kind.lowercased() == "sustaining" }.count
        if sustainingCount != 1 {
            add("systems", "needs exactly one sustaining system (found \(sustainingCount))")
        }

        // objectives
        checkDuplicateKeys(plan.objectives.map(\.key), "objectives")
        for (i, objective) in plan.objectives.enumerated() {
            if objective.estimatedDays < 1 {
                add("objectives[\(i)].estimatedDays", "\(objective.estimatedDays) is not at least 1")
            }
            for (j, key) in (objective.dependsOn ?? []).enumerated() {
                checkReference(key, in: objectiveKeys, "objectives[\(i)].dependsOn[\(j)]")
            }
            for (j, key) in (objective.systems ?? []).enumerated() {
                checkReference(key, in: systemKeys, "objectives[\(i)].systems[\(j)]")
            }
            checkDate(objective.deadline, "objectives[\(i)].deadline")
        }
        for cycle in dependencyCycles(plan.objectives) {
            add("objectives[\(cycle.index)].dependsOn", "cycle in dependsOn: \(cycle.keys.joined(separator: " → "))")
        }

        // steps
        checkDuplicateKeys(plan.steps.map(\.key), "steps")
        for (i, step) in plan.steps.enumerated() {
            checkReference(step.objective, in: objectiveKeys, "steps[\(i)].objective")
            checkDate(step.deadline, "steps[\(i)].deadline")
        }

        // habits
        checkDuplicateKeys(plan.habits.map(\.key), "habits")
        for (i, habit) in plan.habits.enumerated() {
            let base = "habits[\(i)]"
            checkReference(habit.system, in: systemKeys, "\(base).system")

            let kind = habit.kind.lowercased()
            if kind != "check" && kind != "count" {
                add("\(base).kind", "\"\(habit.kind)\" is not check or count")
            }
            if kind == "count" {
                if habit.target == nil { add("\(base).target", "required for count habits") }
                if habit.badDayTarget == nil { add("\(base).badDayTarget", "required for count habits") }
                if let target = habit.target, target < 1 { add("\(base).target", "\(target) is not at least 1") }
                if let bad = habit.badDayTarget {
                    if bad < 1 {
                        add("\(base).badDayTarget", "\(bad) is not at least 1")
                    } else if let target = habit.target, bad >= target {
                        add("\(base).badDayTarget", "\(bad) is not below target \(target)")
                    }
                }
            }

            let frequency = habit.frequency
            var scheduled: Int?
            switch frequency.type.lowercased() {
            case "daily":
                scheduled = 7
            case "weekdays":
                if let days = frequency.weekdays, !days.isEmpty {
                    checkWeekdays(days, "\(base).frequency.weekdays")
                    scheduled = Set(days.filter { (1...7).contains($0) }).count
                } else {
                    add("\(base).frequency.weekdays", "required for weekdays frequency")
                }
            case "perweek":
                if let times = frequency.timesPerWeek {
                    if (1...7).contains(times) { scheduled = times } else { add("\(base).frequency.timesPerWeek", "\(times) is not 1–7") }
                } else {
                    add("\(base).frequency.timesPerWeek", "required for perWeek frequency")
                }
                checkWeekdays(frequency.preferredWeekdays, "\(base).frequency.preferredWeekdays")
            default:
                add("\(base).frequency.type", "\"\(frequency.type)\" is not daily, weekdays or perWeek")
            }

            if let setPoint = habit.setPointPerWeek {
                if setPoint < 1 {
                    add("\(base).setPointPerWeek", "\(setPoint) is not at least 1")
                } else if let scheduled, setPoint > scheduled {
                    add("\(base).setPointPerWeek", "\(setPoint) is more than the \(scheduled) scheduled a week")
                }
            }
            checkTime(habit.reminderTime, "\(base).reminderTime")
            if let duration = habit.durationMinutes, duration < 1 {
                add("\(base).durationMinutes", "\(duration) is not at least 1")
            }
            if let priority = habit.priority, !(1...5).contains(priority) {
                add("\(base).priority", "\(priority) is not 1–5")
            }
        }

        // blocks
        checkDuplicateKeys(plan.blocks.map(\.key), "blocks")
        for (i, block) in plan.blocks.enumerated() {
            let base = "blocks[\(i)]"
            checkReference(block.system, in: systemKeys, "\(base).system")
            checkWeekdays(block.weekdays, "\(base).weekdays")
            checkDate(block.date, "\(base).date")
            if (block.weekdays ?? []).isEmpty && block.date == nil {
                add(base, "needs weekdays (repeating) or date (one-off)")
            }
            let duration = block.durationMinutes ?? 15
            if duration < 1 { add("\(base).durationMinutes", "\(duration) is not at least 1") }

            checkTime(block.startTime, "\(base).startTime")
            checkTime(block.windowStart, "\(base).windowStart")
            checkTime(block.windowEnd, "\(base).windowEnd")
            if let start = TimeOfDay.parse(block.startTime) {
                if let text = block.windowStart, let windowStart = TimeOfDay.parse(text), windowStart > start {
                    add("\(base).windowStart", "\"\(text)\" is after startTime \"\(block.startTime)\"")
                }
                if let text = block.windowEnd, let windowEnd = TimeOfDay.parse(text), windowEnd < start + duration {
                    add("\(base).windowEnd", "\"\(text)\" is before the block ends at \(TimeOfDay.format(start + duration))")
                }
            }
        }

        // reminders
        checkDuplicateKeys(plan.reminders.map(\.key), "reminders")
        for (i, reminder) in plan.reminders.enumerated() {
            let base = "reminders[\(i)]"
            checkReference(reminder.system, in: systemKeys, "\(base).system")
            checkWeekdays(reminder.weekdays, "\(base).weekdays")
            checkDate(reminder.date, "\(base).date")
            checkTime(reminder.time, "\(base).time")
            if (reminder.weekdays ?? []).isEmpty && reminder.date == nil {
                add(base, "needs date (one-off) or weekdays (repeating)")
            }
            if let priority = reminder.priority, !(1...5).contains(priority) {
                add("\(base).priority", "\(priority) is not 1–5")
            }
        }
        return issues
    }

    /// Loops in `dependsOn`, one per loop: the document index of its first member and the keys around it.
    private static func dependencyCycles(_ objectives: [PlanV1.ObjectiveSpec]) -> [(index: Int, keys: [String])] {
        var indexByKey: [String: Int] = [:]
        for (i, objective) in objectives.enumerated() where indexByKey[objective.key] == nil { indexByKey[objective.key] = i }
        enum State { case visiting, done }
        var state: [Int: State] = [:]
        var stack: [Int] = []
        var found: [(index: Int, keys: [String])] = []

        func visit(_ node: Int) {
            state[node] = .visiting
            stack.append(node)
            for key in objectives[node].dependsOn ?? [] {
                guard let next = indexByKey[key] else { continue }
                switch state[next] {
                case .none:
                    visit(next)
                case .visiting:
                    let loop = Array(stack[(stack.firstIndex(of: next) ?? 0)...])
                    let first = loop.min() ?? next
                    let rotated = Array(loop[(loop.firstIndex(of: first) ?? 0)...] + loop[..<(loop.firstIndex(of: first) ?? 0)])
                    let keys = (rotated + [rotated[0]]).map { objectives[$0].key }
                    if !found.contains(where: { $0.index == first && $0.keys == keys }) { found.append((index: first, keys: keys)) }
                case .done:
                    break
                }
            }
            stack.removeLast()
            state[node] = .done
        }
        for i in objectives.indices where state[i] == nil { visit(i) }
        return found.sorted { $0.index < $1.index }
    }

    // MARK: - Materialising (§4.4 steps 2–3)

    /// Maps a valid plan into a ChangeSet (§4.4 steps 2–3), including update mode, the Saturday move,
    /// one-off blocks as CalendarBlocks, and back-scheduled objective deadlines (§4.5).
    public static func materialise(_ plan: PlanV1, into snapshot: StoreSnapshot, today: LocalDay,
                                   settings: AppSettings) -> ImportResult {
        var materialiser = PlanMaterialiser(plan: plan, snapshot: snapshot, today: today, settings: settings)
        return materialiser.run()
    }
}
