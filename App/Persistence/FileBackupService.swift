import Foundation
import CoreKit

/// Why a backup or restore could not run. Messages are written to be shown as they are.
nonisolated enum PersistenceBackupError: LocalizedError {
    /// No backup folder has been chosen yet.
    case noFolder
    /// A folder was chosen, but it cannot be reached any more (deleted, or its drive is gone).
    case folderUnavailable
    case notAFolder
    case encodeFailed
    case writeFailed(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noFolder:
            "No backup folder chosen. Choose a folder in Settings."
        case .folderUnavailable:
            "The backup folder can't be reached. Choose it again in Settings."
        case .notAFolder:
            "That isn't a folder. Choose a folder for backups."
        case .encodeFailed:
            "Couldn't create the backup file."
        case .writeFailed(let file, let reason):
            "Couldn't write \(file): \(reason)"
        }
    }
}

/// JSON backups in a folder the user picked in Files (DESIGN.md §9.3, Appendix D).
///
/// The folder is remembered as a security-scoped bookmark inside `AppSettings.backupFolderBookmark` (saved through the
/// store, so it travels with the rest of the settings). Each backup writes `lockin-backup-YYYY-MM-DD.json` and a copy
/// named `lockin-backup-latest.json`, then deletes dated files older than 8 weeks. Sync and reschedule after a restore are
/// the caller's job (Settings).
@MainActor
final class FileBackupService: BackupServicing {
    private let store: any Store
    /// The folder name last resolved for a bookmark, so `folderName` (read while rendering) doesn't resolve it every time.
    private var cachedName: (bookmark: Data, name: String)?

    init(store: any Store) {
        self.store = store
    }

    // MARK: - BackupServicing

    /// The chosen folder's name, or nil when none is chosen or it cannot be reached.
    var folderName: String? {
        guard let bookmark = store.snapshot().settings.backupFolderBookmark else { return nil }
        if let cachedName, cachedName.bookmark == bookmark {
            return cachedName.name
        }
        guard let resolved = try? resolveFolder(bookmark) else { return nil }
        let name = resolved.url.lastPathComponent
        cachedName = (bookmark, name)
        return name
    }

    /// Remembers `url` (a folder from the system file picker) as the backup folder.
    func setFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == false {
            throw PersistenceBackupError.notAFolder
        }
        let bookmark: Data
        do {
            // iOS has no `.withSecurityScope`; a bookmark of a URL from the picker already carries its access.
            bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw PersistenceBackupError.folderUnavailable
        }
        var settings = store.snapshot().settings
        settings.backupFolderBookmark = bookmark
        try store.apply(ChangeSet(upserts: [.settings(settings)]))
        cachedName = (bookmark, url.lastPathComponent)
    }

    /// Writes today's backup and the "latest" copy, prunes old ones, records `lastBackupAt`. Returns the dated file.
    func backUpNow() throws -> URL {
        let snapshot = store.snapshot()
        guard let bookmark = snapshot.settings.backupFolderBookmark else {
            throw PersistenceBackupError.noFolder
        }
        let resolved = try resolveFolder(bookmark)
        let folder = resolved.url
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing { folder.stopAccessingSecurityScopedResource() }
        }

        let now = Date()
        let today = LocalDay(now)
        let data = BackupCodec.encode(snapshot, exportedAt: now, appVersion: FileBackupService.appVersion)
        guard !data.isEmpty else { throw PersistenceBackupError.encodeFailed }

        let datedURL = folder.appendingPathComponent(BackupCodec.fileName(for: today))
        let latestURL = folder.appendingPathComponent(BackupCodec.latestFileName)
        try write(data, to: datedURL)
        try write(data, to: latestURL)
        prune(in: folder, today: today)

        var settings = store.snapshot().settings
        settings.lastBackupAt = now
        if resolved.isStale,
           let fresh = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.backupFolderBookmark = fresh
        }
        try store.apply(ChangeSet(upserts: [.settings(settings)]))
        return datedURL
    }

    /// Replaces everything in the store with the backup at `url`. Throws `BackupError` for a file that isn't a
    /// backup or is from a newer app version.
    func restore(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let data = try readData(at: url)
        var snapshot = try BackupCodec.decode(data)
        // The backup folder is a choice made on this install; a bookmark inside the file came from another one.
        if let current = store.snapshot().settings.backupFolderBookmark {
            snapshot.settings.backupFolderBookmark = current
        }
        try store.replaceAll(with: snapshot)
    }

    // MARK: - Files

    /// "1.0 (1)", the format Appendix D wants in `appVersion`.
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func resolveFolder(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            throw PersistenceBackupError.folderUnavailable
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PersistenceBackupError.writeFailed(file: url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    /// Reads through a file coordinator, which makes iCloud Drive download a file that is only a placeholder here.
    private func readData(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let result {
            return try result.get()
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            if let coordinationError { throw coordinationError }
            throw error
        }
    }

    /// Deletes dated backups older than 8 weeks. Only `lockin-backup-YYYY-MM-DD.json` names qualify; failures are ignored.
    private func prune(in folder: URL, today: LocalDay) {
        let cutoff = today.adding(days: -56)
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in urls {
            guard let day = BackupCodec.day(fromFileName: url.lastPathComponent), day < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
