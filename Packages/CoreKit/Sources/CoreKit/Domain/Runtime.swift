import Foundation

/// §3.13 — a busy stretch of time from Apple Calendar. Never stored.
public struct BusyInterval: Codable, Equatable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    /// The external event this came from; compared against `CalendarBlock.ignoredClashEventIDs` (§5.4).
    public var eventID: String?

    public init(start: Date, end: Date, eventID: String? = nil) {
        self.start = start; self.end = end; self.eventID = eventID
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// §3.13 — an event from any calendar except Goals. Never stored.
public struct ExternalEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var calendarColorHex: String
    public var isAllDay: Bool
    /// `EKEvent.availability == .free`; excluded from busy intervals (§5.2).
    public var isFree: Bool

    public init(id: String, title: String, start: Date, end: Date, calendarColorHex: String = "#A3ABB8",
                isAllDay: Bool = false, isFree: Bool = false) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.calendarColorHex = calendarColorHex; self.isAllDay = isAllDay; self.isFree = isFree
    }

    /// nil for all-day and free events.
    public var busyInterval: BusyInterval? {
        isAllDay || isFree ? nil : BusyInterval(start: start, end: end, eventID: id)
    }
}

public enum NotificationKind: String, Codable, Equatable, Sendable {
    case morning, habit, block, reminder, evening, checkIn, resign
}

/// §3.13 — one notification the app wants pending.
public struct PlannedNotification: Identifiable, Codable, Equatable, Sendable {
    /// §6.3 identifiers, e.g. `habit-{uuid}-YYYY-MM-DD`.
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var link: DeepLink
    public var kind: NotificationKind

    public init(id: String, fireDate: Date, title: String, body: String, link: DeepLink, kind: NotificationKind) {
        self.id = id; self.fireDate = fireDate; self.title = title; self.body = body; self.link = link; self.kind = kind
    }
}

public enum PermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined, granted, denied, restricted
}

/// `lockin://` links (§6.5). Encoded as its URL string.
public enum DeepLink: Codable, Equatable, Hashable, Sendable {
    case habit(UUID, LocalDay)
    case today
    case week
    case goal(UUID)
    case block(UUID)
    case settings

    public static let scheme = "lockin"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme, let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "today": self = .today
        case "week": self = .week
        case "settings": self = .settings
        case "goal":
            guard let raw = parts.first, let id = UUID(uuidString: raw) else { return nil }
            self = .goal(id)
        case "block":
            guard let raw = parts.first, let id = UUID(uuidString: raw) else { return nil }
            self = .block(id)
        case "habit":
            guard let raw = parts.first, let id = UUID(uuidString: raw),
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let dayText = query.first(where: { $0.name == "day" })?.value,
                  let day = LocalDay(dayText) else { return nil }
            self = .habit(id, day)
        default:
            return nil
        }
    }

    public var url: URL {
        let text: String
        switch self {
        case .habit(let id, let day): text = "lockin://habit/\(id.uuidString)?day=\(day.string)"
        case .today: text = "lockin://today"
        case .week: text = "lockin://week"
        case .goal(let id): text = "lockin://goal/\(id.uuidString)"
        case .block(let id): text = "lockin://block/\(id.uuidString)"
        case .settings: text = "lockin://settings"
        }
        return URL(string: text)!
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let url = URL(string: raw), let link = DeepLink(url: url) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(raw) is not a lockin:// link")
        }
        self = link
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.absoluteString)
    }
}
