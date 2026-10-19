import Foundation

public enum BackupError: Error, Equatable, Sendable {
    /// `format` isn't "lockin-backup", or the file isn't JSON.
    case notABackup
    /// "This backup is from a newer version of the app."
    case newerVersion(Int)

    public var message: String {
        switch self {
        case .notABackup: "This file isn't a Lock in backup."
        case .newerVersion: "This backup is from a newer version of the app."
        }
    }
}

/// Appendix D backup files.
public enum BackupCodec {
    public static let format = "lockin-backup"
    public static let schemaVersion = 1
    /// ISO-8601 with milliseconds, so round trips keep sub-second times (to the millisecond).
    private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private struct Envelope: Codable {
        var format: String
        var schemaVersion: Int
        var exportedAt: Date
        var appVersion: String
        var data: StoreSnapshot
    }

    private struct Header: Decodable {
        var format: String
        var schemaVersion: Int
    }

    public static func encode(_ snapshot: StoreSnapshot, exportedAt: Date = Date(), appVersion: String = "1.0 (1)") -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(iso8601))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelope = Envelope(format: format, schemaVersion: schemaVersion, exportedAt: exportedAt,
                                appVersion: appVersion, data: snapshot)
        return (try? encoder.encode(envelope)) ?? Data()
    }

    public static func decode(_ data: Data) throws(BackupError) -> StoreSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? iso8601.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) is not ISO-8601")
        }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw .notABackup
        }
        guard header.schemaVersion <= schemaVersion else { throw .newerVersion(header.schemaVersion) }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw .notABackup }
        return envelope.data
    }

    /// `lockin-backup-YYYY-MM-DD.json`
    public static func fileName(for day: LocalDay) -> String { "lockin-backup-\(day.string).json" }
    public static let latestFileName = "lockin-backup-latest.json"

    /// The day in a dated backup file name, or nil for any other name (only these files are ever pruned).
    public static func day(fromFileName name: String) -> LocalDay? {
        guard name.hasPrefix("lockin-backup-"), name.hasSuffix(".json") else { return nil }
        let middle = name.dropFirst("lockin-backup-".count).dropLast(".json".count)
        return LocalDay(String(middle))
    }
}
