import Foundation

/// Plan keys (§3 `planKey`) and the stable keys generated for entities that have none (internal).
///
/// An entity made in the app has no `planKey`. When its goal is rebuilt as plan JSON (`PlanV1.init(goalID:snapshot:)`)
/// it gets `"{prefix}-{last 12 hex digits of its id}"`; the importer recognises the same key, so a check-in round trip
/// updates that entity instead of duplicating it.
enum PlanKeys {
    private static func generated(_ prefix: String, _ id: UUID) -> String {
        "\(prefix)-\(String(id.uuidString.suffix(12)).lowercased())"
    }

    static func principle(_ e: FirstPrinciple) -> String { e.planKey ?? generated("fp", e.id) }
    static func system(_ e: GoalSystem) -> String { e.planKey ?? generated("s", e.id) }
    static func objective(_ e: Objective) -> String { e.planKey ?? generated("o", e.id) }
    static func step(_ e: Step) -> String { e.planKey ?? generated("st", e.id) }
    static func habit(_ e: Habit) -> String { e.planKey ?? generated("h", e.id) }
    static func rule(_ e: BlockRule) -> String { e.planKey ?? generated("b", e.id) }
    /// One-off blocks have no `planKey` field, so their key is always generated.
    static func block(_ e: CalendarBlock) -> String { generated("b", e.id) }
    static func reminder(_ e: PlanReminder) -> String { e.planKey ?? generated("r", e.id) }

    /// `goal.id` from the plan: nil / "" / "null" mean "no id"; anything else must be a UUID.
    struct GoalID {
        var uuid: UUID?
        /// The text when it is present but not a UUID.
        var invalidText: String?
    }

    static func goalUUID(_ raw: String?) -> GoalID {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.lowercased() != "null" else { return GoalID(uuid: nil, invalidText: nil) }
        if let uuid = UUID(uuidString: text) { return GoalID(uuid: uuid, invalidText: nil) }
        return GoalID(uuid: nil, invalidText: text)
    }

    /// One key per id; a repeated key gets a suffix so a rebuilt plan never has duplicates.
    static func uniqueKeys<T>(_ items: [T], id: (T) -> UUID, key: (T) -> String) -> [UUID: String] {
        var used = Set<String>()
        var result: [UUID: String] = [:]
        for item in items {
            var candidate = key(item)
            if !used.insert(candidate).inserted {
                candidate += "-" + String(id(item).uuidString.suffix(12)).lowercased()
                used.insert(candidate)
            }
            result[id(item)] = candidate
        }
        return result
    }
}
