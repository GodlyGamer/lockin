import Foundation
import Observation

/// An `@Observable` in-memory `Store` for previews and tests.
@Observable
@MainActor
public final class InMemoryStore: Store {
    public private(set) var revision: Int = 0
    public var loadError: String?
    /// Set to make the next `apply` throw (to preview save errors).
    public var failNextApply = false
    private var data: StoreSnapshot

    public init(snapshot: StoreSnapshot = .empty) {
        self.data = snapshot
    }

    public struct SaveError: Error {}

    public func snapshot() -> StoreSnapshot { data }

    public func apply(_ changes: ChangeSet) throws {
        if failNextApply {
            failNextApply = false
            throw SaveError()
        }
        data = data.applying(changes)
        revision += 1
    }

    public func replaceAll(with snapshot: StoreSnapshot) throws {
        data = snapshot
        revision += 1
    }
}
