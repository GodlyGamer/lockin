import CoreGraphics
import CoreKit
import EventKit
import Foundation
import Observation

// MARK: - Errors and small helpers (file-private)

/// A failure with a user-presentable message.
private struct CalSyncError: Error {
    let message: String
}

private func calMessage(for error: Error) -> String {
    if let known = error as? CalSyncError { return known.message }
    return error.localizedDescription
}

/// `Lock in` notes line parser: finds `id:{uuid}` in an event's notes (DESIGN.md §5.2).
private func calParseBlockID(from notes: String?) -> UUID? {
    guard let notes else { return nil }
    for line in notes.split(whereSeparator: { $0.isNewline }) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("id:") {
            let raw = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            if let id = UUID(uuidString: raw) { return id }
        }
    }
    return nil
}

private func calHexByte(_ value: CGFloat) -> String {
    let n = max(0, min(255, Int((value * 255).rounded())))
    let text = String(n, radix: 16, uppercase: true)
    return text.count == 1 ? "0" + text : text
}

/// `#RRGGBB` (sRGB) for a calendar colour; the neutral grey when the colour is missing.
private func calHexString(from color: CGColor?) -> String {
    let fallback = "#A3ABB8"
    guard let color else { return fallback }
    var resolved = color
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let converted = color.converted(to: space, intent: .defaultIntent, options: nil) {
        resolved = converted
    }
    guard let c = resolved.components, !c.isEmpty else { return fallback }
    let r = c[0]
    let g = c.count >= 3 ? c[1] : c[0]
    let b = c.count >= 3 ? c[2] : c[0]
    return "#" + calHexByte(r) + calHexByte(g) + calHexByte(b)
}

/// Working copy of the blocks during one sync; applied to the store in a single change set at the end.
private struct CalSyncDraft {
    var blocks: [UUID: CalendarBlock] = [:]
    var order: [UUID] = []
    var original: [UUID: CalendarBlock] = [:]
    var report = SyncReport()
    var firstError: String?
    /// Cancelled one-off blocks whose event is gone; deleted from the store after a successful commit.
    var prunable: [UUID] = []

    init(snapshot: StoreSnapshot) {
        for block in snapshot.blocks where blocks[block.id] == nil {
            blocks[block.id] = block
            original[block.id] = block
            order.append(block.id)
        }
    }

    func orderedBlocks() -> [CalendarBlock] {
        order.compactMap { blocks[$0] }
    }

    mutating func add(_ block: CalendarBlock) {
        if blocks[block.id] == nil { order.append(block.id) }
        blocks[block.id] = block
    }

    mutating func noteError(_ error: Error) {
        if firstError == nil { firstError = calMessage(for: error) }
    }

    /// The Goals calendar was just created or adopted: nothing in it has been verified, so forget what we
    /// believed was pushed (future blocks only) and let the push step rewrite them.
    mutating func forgetPushedState(now: Date) {
        for id in order {
            guard var block = blocks[id], block.end > now else { continue }
            guard block.ekEventIdentifier != nil || block.ekExternalIdentifier != nil || block.lastSyncedAt != nil else { continue }
            block.ekEventIdentifier = nil
            block.ekExternalIdentifier = nil
            block.lastSyncedAt = nil
            blocks[id] = block
        }
    }
}

private struct CalSavedEvent {
    let blockID: UUID
    let event: EKEvent
}

/// The Goals calendar plus its events in the sync window, indexed for matching.
private final class CalGoalsContext {
    let calendar: EKCalendar
    let calendarID: String
    let events: [EKEvent]
    var byIdentifier: [String: EKEvent] = [:]
    var byBlockID: [UUID: [EKEvent]] = [:]
    var removed = Set<ObjectIdentifier>()
    var claimed: [UUID: ObjectIdentifier] = [:]
    var saved: [CalSavedEvent] = []
    var didRemove = false

    init(calendar: EKCalendar, events: [EKEvent]) {
        self.calendar = calendar
        self.calendarID = calendar.calendarIdentifier
        self.events = events
        for event in events {
            if let identifier = event.eventIdentifier, byIdentifier[identifier] == nil {
                byIdentifier[identifier] = event
            }
            if let blockID = calParseBlockID(from: event.notes) {
                byBlockID[blockID, default: []].append(event)
            }
        }
    }
}

// MARK: - Service

/// Two-way pairing with Apple Calendar through EventKit (DESIGN.md §5).
///
/// - Reads every calendar except the app's own "Goals" calendar (busy intervals and the Calendar tab).
/// - Writes goal blocks to "Goals" as individual events (never recurrence rules).
/// - Pulls time/title changes and deletions made in Apple Calendar back into the blocks (Apple wins).
///
/// App-side edits to the time of an already-pushed block must go through `move(blockID:to:)`, which pushes
/// immediately; a direct store edit would be overwritten by the next pull.
@Observable
@MainActor
final class EventKitCalendarService: CalendarServicing {
    private(set) var status: PermissionStatus

    private let appStore: any Store
    private let notifications: any NotificationServicing

    @ObservationIgnored private var eventStore = EKEventStore()
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var waiters: [CheckedContinuation<SyncReport, Never>] = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastOwnWrite = Date.distantPast
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?

    private static let goalsTitle = "Goals"
    private static let horizonDays: Double = 14
    /// Changes arriving this soon after our own commit are echoes of it.
    private static let ownWriteQuietPeriod: TimeInterval = 1.5
    private static let debounceSeconds: Double = 1

    init(store: any Store, notifications: any NotificationServicing) {
        self.appStore = store
        self.notifications = notifications
        self.status = Self.mapStatus(EKEventStore.authorizationStatus(for: .event))
        startObservingStoreChanges()
    }

    // MARK: Permission

    private static func mapStatus(_ raw: EKAuthorizationStatus) -> PermissionStatus {
        switch raw {
        case .fullAccess: return .granted
        case .writeOnly, .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func refreshStatus() {
        status = Self.mapStatus(EKEventStore.authorizationStatus(for: .event))
    }

    private var isAccessGranted: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> PermissionStatus {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = await Self.requestFullAccess()
            // A store created before access was granted can keep returning nothing; start a fresh one.
            eventStore = EKEventStore()
        }
        refreshStatus()
        if status == .granted {
            Task { _ = await self.sync() }
        }
        return status
    }

    private nonisolated static func requestFullAccess() async -> Bool {
        let freshStore = EKEventStore()
        do {
            return try await freshStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    // MARK: Change observation

    private func startObservingStoreChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.eventStoreDidChange()
            }
        }
    }

    private func eventStoreDidChange() {
        refreshStatus()
        guard status == .granted else { return }
        if isSyncing || Date().timeIntervalSince(lastOwnWrite) < Self.ownWriteQuietPeriod { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounceSeconds))
            guard !Task.isCancelled, let self else { return }
            _ = await self.sync()
        }
    }

    // MARK: Reading

    private func fetchEvents(in range: DateInterval, excluding goalsID: String?) -> [EKEvent] {
        let calendars = eventStore.calendars(for: .event).filter { $0.calendarIdentifier != goalsID }
        return fetchEvents(in: range, calendars: calendars)
    }

    private func fetchEvents(in range: DateInterval, calendars: [EKCalendar]) -> [EKEvent] {
        guard !calendars.isEmpty, range.end > range.start else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        return eventStore.events(matching: predicate)
    }

    /// Unique per occurrence: recurring events share one `eventIdentifier`, so their start is appended.
    private func occurrenceID(for event: EKEvent, start: Date) -> String {
        let base = event.eventIdentifier ?? "event"
        if event.hasRecurrenceRules || event.isDetached {
            return "\(base)#\(Int(start.timeIntervalSince1970))"
        }
        return base
    }

    private func readExternalEvents(in range: DateInterval, excludingCalendarID goalsID: String?) -> [ExternalEvent] {
        var colours: [String: String] = [:]
        var result: [ExternalEvent] = []
        for event in fetchEvents(in: range, excluding: goalsID) {
            if event.status == .canceled { continue }
            guard let start = event.startDate, let end = event.endDate else { continue }
            let calendarID = event.calendar?.calendarIdentifier ?? ""
            let hex: String
            if let cached = colours[calendarID] {
                hex = cached
            } else {
                hex = calHexString(from: event.calendar?.cgColor)
                colours[calendarID] = hex
            }
            let rawTitle = event.title ?? ""
            result.append(ExternalEvent(
                id: occurrenceID(for: event, start: start),
                title: rawTitle.isEmpty ? "(No title)" : rawTitle,
                start: start,
                end: end,
                calendarColorHex: hex,
                isAllDay: event.isAllDay,
                isFree: event.availability == .free
            ))
        }
        return result.sorted { $0.start < $1.start }
    }

    func busyIntervals(in range: DateInterval) async -> [BusyInterval] {
        guard isAccessGranted else { return [] }
        let goalsID = appStore.snapshot().settings.goalsCalendarIdentifier
        return readExternalEvents(in: range, excludingCalendarID: goalsID).compactMap(\.busyInterval)
    }

    func externalEvents(in range: DateInterval) async -> [ExternalEvent] {
        guard isAccessGranted else { return [] }
        let goalsID = appStore.snapshot().settings.goalsCalendarIdentifier
        return readExternalEvents(in: range, excludingCalendarID: goalsID)
    }

    // MARK: Goals calendar (DESIGN.md §5.3)

    private func makeGoalsCalendar() throws -> EKCalendar {
        var sources: [EKSource] = []
        if let fallback = eventStore.defaultCalendarForNewEvents, fallback.allowsContentModifications,
           let source = fallback.source {
            sources.append(source)
        }
        if let local = eventStore.sources.first(where: { $0.sourceType == .local }) {
            sources.append(local)
        }
        var lastError: Error?
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = Self.goalsTitle
            calendar.cgColor = CGColor(srgbRed: 61.0 / 255.0, green: 107.0 / 255.0, blue: 1.0, alpha: 1.0)
            calendar.source = source
            do {
                try eventStore.saveCalendar(calendar, commit: true)
                return calendar
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw CalSyncError(message: "No calendar account lets Lock in create the Goals calendar.")
    }

    /// The Goals calendar, creating it (or adopting an existing one named "Goals" when no identifier is
    /// stored) if needed. `isFresh` means nothing about its contents has been verified yet.
    private func ensureGoalsCalendar(identifier: String?) throws -> (calendar: EKCalendar, isFresh: Bool) {
        if let identifier, let existing = eventStore.calendar(withIdentifier: identifier), existing.allowsContentModifications {
            return (existing, false)
        }
        if identifier == nil,
           let adopted = eventStore.calendars(for: .event).first(where: { $0.title == Self.goalsTitle && $0.allowsContentModifications }) {
            return (adopted, true)
        }
        let created = try makeGoalsCalendar()
        return (created, true)
    }

    // MARK: Event matching and writing (DESIGN.md §5.2)

    private func goalsEvent(for block: CalendarBlock, context: CalGoalsContext) -> EKEvent? {
        if let identifier = block.ekEventIdentifier, let event = context.byIdentifier[identifier],
           !context.removed.contains(ObjectIdentifier(event)) {
            return event
        }
        if let candidates = context.byBlockID[block.id],
           let live = candidates.first(where: { !context.removed.contains(ObjectIdentifier($0)) }) {
            return live
        }
        if let identifier = block.ekEventIdentifier, let event = eventStore.event(withIdentifier: identifier),
           event.calendar?.calendarIdentifier == context.calendarID {
            return event
        }
        return nil
    }

    private static func notes(for block: CalendarBlock, goalTitles: [UUID: String]) -> String {
        var head = "Lock in"
        if let goalID = block.goalID, let title = goalTitles[goalID] {
            head = "Lock in · \(title)"
        }
        return "\(head)\nid:\(block.id.uuidString)"
    }

    private func configure(_ event: EKEvent, for block: CalendarBlock, goalTitles: [UUID: String]) {
        event.title = block.title
        event.startDate = block.start
        event.endDate = block.end
        event.notes = Self.notes(for: block, goalTitles: goalTitles)
        event.url = DeepLink.block(block.id).url
    }

    private func eventNeedsUpdate(_ event: EKEvent, for block: CalendarBlock) -> Bool {
        guard let start = event.startDate, let end = event.endDate else { return true }
        if abs(start.timeIntervalSince(block.start)) >= 1 || abs(end.timeIntervalSince(block.end)) >= 1 { return true }
        if (event.title ?? "") != block.title { return true }
        if calParseBlockID(from: event.notes) != block.id { return true }
        let expected = DeepLink.block(block.id).url.absoluteString.lowercased()
        if event.url?.absoluteString.lowercased() != expected { return true }
        return false
    }

    // MARK: Sync (DESIGN.md §5.5)

    func sync() async -> SyncReport {
        if isSyncing {
            rerunRequested = true
            return await withCheckedContinuation { (continuation: CheckedContinuation<SyncReport, Never>) in
                waiters.append(continuation)
            }
        }
        isSyncing = true
        var report = await performSync()
        while rerunRequested {
            rerunRequested = false
            report = await performSync()
        }
        isSyncing = false
        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume(returning: report) }
        return report
    }

    private func performSync() async -> SyncReport {
        refreshStatus()
        let now = Date()
        let snapshot = appStore.snapshot()
        var settings = snapshot.settings
        var draft = CalSyncDraft(snapshot: snapshot)
        let goalTitles = Dictionary(snapshot.goals.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let horizon = now.addingTimeInterval(Self.horizonDays * 86_400)
        let granted = status == .granted
        var busy: [BusyInterval] = []
        var context: CalGoalsContext?
        var freshCalendar = false

        // 1. Read external events (and open the Goals calendar). Skipped when access is off.
        if granted {
            do {
                let ensured = try ensureGoalsCalendar(identifier: settings.goalsCalendarIdentifier)
                freshCalendar = ensured.isFresh
                settings.goalsCalendarIdentifier = ensured.calendar.calendarIdentifier
                let window = DateInterval(start: now.addingTimeInterval(-86_400), end: horizon.addingTimeInterval(86_400))
                context = CalGoalsContext(calendar: ensured.calendar,
                                          events: fetchEvents(in: window, calendars: [ensured.calendar]))
                if freshCalendar { draft.forgetPushedState(now: now) }
            } catch {
                draft.noteError(error)
            }
            // Read far enough ahead for the 7-day slot search of blocks near the horizon.
            let readRange = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(22 * 86_400))
            busy = readExternalEvents(in: readRange, excludingCalendarID: settings.goalsCalendarIdentifier)
                .compactMap(\.busyInterval)
        }

        // 2. Pull Goals calendar changes.
        if let context {
            pull(&draft, context: context, freshCalendar: freshCalendar, now: now)
        }

        // 3. Materialise rules.
        let created = ScheduleEngine.materialise(rules: snapshot.blockRules, existing: draft.orderedBlocks(),
                                                 from: LocalDay(now), days: 14, settings: settings,
                                                 systems: snapshot.systems)
        for block in created { draft.add(block) }
        draft.report.created = created.count

        // 4. Detect clashes and suggest slots (needs busy data, so not when access is off).
        if granted {
            let checked = ScheduleEngine.detectClashes(blocks: draft.orderedBlocks(), busy: busy,
                                                       settings: settings, now: now)
            for block in checked where draft.blocks[block.id] != nil {
                draft.blocks[block.id] = block
            }
            let rulesByID = Dictionary(snapshot.blockRules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let allBlocks = draft.orderedBlocks()
            for id in draft.order {
                guard var block = draft.blocks[id], block.status == .clash else { continue }
                let rule = block.ruleID.flatMap { rulesByID[$0] }
                let others = allBlocks.filter { $0.id != id }
                block.suggestedStart = ScheduleEngine.suggestSlot(for: block, rule: rule, busy: busy,
                                                                  blocks: others, settings: settings)
                draft.blocks[id] = block
            }
        }

        // 5. Push blocks, delete events of cancelled blocks, then commit once.
        var committed = true
        if let context {
            push(&draft, context: context, goalTitles: goalTitles, now: now, horizon: horizon)
            removeStale(&draft, context: context, now: now, allowOrphanRemoval: appStore.loadError == nil)
            if !context.saved.isEmpty || context.didRemove {
                do {
                    try eventStore.commit()
                    lastOwnWrite = Date()
                } catch {
                    draft.noteError(error)
                    eventStore.reset()
                    committed = false
                }
            }
            if committed {
                let stamp = Date()
                for saved in context.saved {
                    guard var block = draft.blocks[saved.blockID] else { continue }
                    block.ekEventIdentifier = saved.event.eventIdentifier
                    block.ekExternalIdentifier = saved.event.calendarItemExternalIdentifier
                    block.lastSyncedAt = stamp
                    draft.blocks[saved.blockID] = block
                }
            }
        }

        // One store.apply with everything.
        let pruned: Set<UUID> = committed ? Set(draft.prunable) : []
        var changes = ChangeSet()
        for id in draft.order {
            guard !pruned.contains(id), let block = draft.blocks[id] else { continue }
            if draft.original[id] != block { changes.upserts.append(.block(block)) }
        }
        for id in pruned where draft.original[id] != nil {
            changes.deletes.append(EntityRef(.block, id))
        }
        if settings != snapshot.settings {
            changes.upserts.append(.settings(settings))
        }
        if !changes.isEmpty {
            do {
                try appStore.apply(changes)
            } catch {
                draft.noteError(error)
            }
        }

        draft.report.clashes = draft.blocks.values.filter { $0.status == .clash && $0.end > now }.count
        draft.report.error = draft.firstError

        // 6. Always reschedule notifications, also when calendar access is off.
        await notifications.reschedule()
        return draft.report
    }

    /// Step 2: Apple Calendar wins for start/end, title and deletion of a block's event.
    private func pull(_ draft: inout CalSyncDraft, context: CalGoalsContext, freshCalendar: Bool, now: Date) {
        for id in draft.order {
            guard var block = draft.blocks[id],
                  block.status == .scheduled || block.status == .clash,
                  block.end > now else { continue }
            let wasPushed = block.lastSyncedAt != nil
            guard let event = goalsEvent(for: block, context: context) else {
                if wasPushed && !freshCalendar {
                    block.status = .cancelled
                    block.suggestedStart = nil
                    block.ekEventIdentifier = nil
                    block.ekExternalIdentifier = nil
                    draft.blocks[id] = block
                    draft.report.cancelled += 1
                }
                continue
            }
            if let identifier = event.eventIdentifier, block.ekEventIdentifier != identifier {
                block.ekEventIdentifier = identifier
            }
            if wasPushed {
                var changed = false
                if let start = event.startDate, let end = event.endDate,
                   abs(start.timeIntervalSince(block.start)) >= 1 || abs(end.timeIntervalSince(block.end)) >= 1 {
                    block.start = start
                    block.end = end
                    block.suggestedStart = nil
                    changed = true
                }
                if let title = event.title, !title.isEmpty, title != block.title {
                    block.title = title
                    changed = true
                }
                if changed { draft.report.updated += 1 }
            }
            draft.blocks[id] = block
        }
    }

    /// Step 5a: create or update one event per scheduled/clash block from now to +14 days.
    private func push(_ draft: inout CalSyncDraft, context: CalGoalsContext, goalTitles: [UUID: String],
                      now: Date, horizon: Date) {
        for id in draft.order {
            guard var block = draft.blocks[id],
                  block.status == .scheduled || block.status == .clash,
                  block.end > now, block.start < horizon else { continue }
            do {
                if let event = goalsEvent(for: block, context: context) {
                    context.claimed[id] = ObjectIdentifier(event)
                    if eventNeedsUpdate(event, for: block) {
                        configure(event, for: block, goalTitles: goalTitles)
                        try eventStore.save(event, span: .thisEvent, commit: false)
                        context.saved.append(CalSavedEvent(blockID: id, event: event))
                    } else {
                        var changed = false
                        if let identifier = event.eventIdentifier, block.ekEventIdentifier != identifier {
                            block.ekEventIdentifier = identifier
                            changed = true
                        }
                        if block.lastSyncedAt == nil {
                            block.lastSyncedAt = Date()
                            changed = true
                        }
                        if changed { draft.blocks[id] = block }
                    }
                } else {
                    let event = EKEvent(eventStore: eventStore)
                    event.calendar = context.calendar
                    event.isAllDay = false
                    event.alarms = nil
                    configure(event, for: block, goalTitles: goalTitles)
                    try eventStore.save(event, span: .thisEvent, commit: false)
                    context.claimed[id] = ObjectIdentifier(event)
                    context.saved.append(CalSavedEvent(blockID: id, event: event))
                }
            } catch {
                draft.noteError(error)
            }
        }
    }

    /// Step 5b: delete events of cancelled blocks, duplicates, and events whose block no longer exists.
    /// Events that end in the past are never touched.
    private func removeStale(_ draft: inout CalSyncDraft, context: CalGoalsContext, now: Date, allowOrphanRemoval: Bool) {
        for id in draft.order {
            guard var block = draft.blocks[id], block.status == .cancelled, block.end > now else { continue }
            var eventGone = true
            if let event = goalsEvent(for: block, context: context) {
                do {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    context.removed.insert(ObjectIdentifier(event))
                    context.didRemove = true
                    draft.report.cancelled += 1
                } catch {
                    draft.noteError(error)
                    eventGone = false
                }
            }
            if eventGone {
                if block.ekEventIdentifier != nil || block.ekExternalIdentifier != nil {
                    block.ekEventIdentifier = nil
                    block.ekExternalIdentifier = nil
                    draft.blocks[id] = block
                }
                if block.ruleID == nil { draft.prunable.append(id) }
            }
        }

        guard allowOrphanRemoval else { return }
        for event in context.events {
            let key = ObjectIdentifier(event)
            guard !context.removed.contains(key),
                  let blockID = calParseBlockID(from: event.notes),
                  let end = event.endDate, end > now else { continue }
            var shouldRemove = false
            if let owner = draft.blocks[blockID] {
                if owner.status == .scheduled || owner.status == .clash,
                   let claimed = context.claimed[blockID], claimed != key {
                    shouldRemove = true
                }
            } else {
                shouldRemove = true
            }
            guard shouldRemove else { continue }
            do {
                try eventStore.remove(event, span: .thisEvent, commit: false)
                context.removed.insert(key)
                context.didRemove = true
                draft.report.cancelled += 1
            } catch {
                draft.noteError(error)
            }
        }
    }

    // MARK: Move

    func move(blockID: UUID, to start: Date) async throws {
        let snapshot = appStore.snapshot()
        guard let original = snapshot.block(blockID) else {
            throw CalSyncError(message: "That block no longer exists.")
        }
        var block = original
        let duration = block.end.timeIntervalSince(block.start)
        block.start = start
        block.end = start.addingTimeInterval(duration)
        block.status = .scheduled
        block.suggestedStart = nil
        try appStore.apply(ChangeSet(upserts: [.block(block)]))

        refreshStatus()
        if status == .granted {
            do {
                try pushMoved(&block, snapshot: snapshot, oldStart: original.start)
            } catch {
                // Keep the store and Apple Calendar in agreement: undo the move.
                try? appStore.apply(ChangeSet(upserts: [.block(original)]))
                await notifications.reschedule()
                throw error
            }
        }
        await notifications.reschedule()
    }

    /// Re-checks clashes for the moved block, writes its event immediately, and stores the result.
    private func pushMoved(_ block: inout CalendarBlock, snapshot: StoreSnapshot, oldStart: Date) throws {
        var settings = snapshot.settings
        let ensured = try ensureGoalsCalendar(identifier: settings.goalsCalendarIdentifier)
        settings.goalsCalendarIdentifier = ensured.calendar.calendarIdentifier

        let busyRange = DateInterval(start: block.start.addingTimeInterval(-86_400),
                                     end: block.start.addingTimeInterval(9 * 86_400))
        let busy = readExternalEvents(in: busyRange, excludingCalendarID: ensured.calendar.calendarIdentifier)
            .compactMap(\.busyInterval)
        let checked = ScheduleEngine.detectClashes(blocks: [block], busy: busy, settings: settings, now: Date())
        if let updated = checked.first(where: { $0.id == block.id }) { block = updated }
        if block.status == .clash {
            let rule = block.ruleID.flatMap { snapshot.blockRule($0) }
            let others = snapshot.blocks.filter { $0.id != block.id }
            block.suggestedStart = ScheduleEngine.suggestSlot(for: block, rule: rule, busy: busy,
                                                              blocks: others, settings: settings)
        }

        let lower = min(oldStart, block.start).addingTimeInterval(-86_400)
        let upper = max(oldStart, block.start).addingTimeInterval(2 * 86_400)
        let context = CalGoalsContext(calendar: ensured.calendar,
                                      events: fetchEvents(in: DateInterval(start: lower, end: upper),
                                                          calendars: [ensured.calendar]))
        let goalTitles = Dictionary(snapshot.goals.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var target: EKEvent?
        if let existing = goalsEvent(for: block, context: context) {
            target = existing
        } else if block.end > Date(), block.start < Date().addingTimeInterval(Self.horizonDays * 86_400) {
            let event = EKEvent(eventStore: eventStore)
            event.calendar = ensured.calendar
            event.isAllDay = false
            event.alarms = nil
            target = event
        }
        if let event = target {
            configure(event, for: block, goalTitles: goalTitles)
            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                try eventStore.commit()
            } catch {
                eventStore.reset()
                throw error
            }
            lastOwnWrite = Date()
            block.ekEventIdentifier = event.eventIdentifier
            block.ekExternalIdentifier = event.calendarItemExternalIdentifier
            block.lastSyncedAt = Date()
        }

        var changes = ChangeSet(upserts: [.block(block)])
        if settings != snapshot.settings { changes.upserts.append(.settings(settings)) }
        try appStore.apply(changes)
    }
}
