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
    /// The JSON text from a paste: the last ```json fenced block if any, else the whole text trimmed. nil if empty.
    public static func extractJSON(from text: String) -> Data? {
        // M1: implement (Appendix A decoding rules).
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Data(trimmed.utf8)
    }

    /// Decodes plan JSON (raw or pasted text with a fence). Errors carry a field path.
    public static func decode(_ data: Data) throws(PlanImportError) -> PlanV1 {
        // M1: implement (fence extraction, DecodingError → path, schemaVersion check).
        do {
            return try JSONDecoder().decode(PlanV1.self, from: data)
        } catch {
            throw .decoding(path: "plan", message: "\(error)")
        }
    }

    /// Every §4.4 validation failure, in document order. The UI shows the first 5.
    public static func validate(_ plan: PlanV1) -> [PlanIssue] {
        // M1: implement (§4.4 step 1).
        []
    }

    /// Maps a valid plan into a ChangeSet (§4.4 steps 2–3), including update mode, the Saturday move,
    /// one-off blocks as CalendarBlocks, and back-scheduled objective deadlines (§4.5).
    public static func materialise(_ plan: PlanV1, into snapshot: StoreSnapshot, today: LocalDay,
                                   settings: AppSettings) -> ImportResult {
        // M1: implement (§4.4).
        ImportResult(goalID: UUID(), changes: ChangeSet(), summary: ImportSummary(goalTitle: plan.goal.title))
    }
}
