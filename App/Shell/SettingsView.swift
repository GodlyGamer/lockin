import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreKit

/// Settings (DESIGN.md §7.11), pushed from Goals. Every editable `AppSettings` field is here and every change is
/// saved at once: `store.apply`, then `notifications.reschedule()` (F14). `maxNotificationsPerDay` is read-only.
///
/// This outer view only reads the store, so it re-renders on every change; the form lives in
/// `ShellSettingsContent`, which keeps a local copy of the settings so that Steppers and pickers stay responsive.
struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        ShellSettingsContent(initial: snapshot.settings,
                             lastSync: snapshot.blocks.compactMap(\.lastSyncedAt).max())
    }
}

// MARK: - Content

private struct ShellSettingsContent: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    /// The stored settings as of the last render. Used for the fields that services write (calendar id,
    /// backup folder, last backup), never for the fields edited here.
    private let initial: AppSettings
    private let lastSync: Date?

    /// The editable copy. Saved on every change by merging only the editable fields into the live stored settings,
    /// so a service writing `lastBackupAt` meanwhile is never overwritten.
    @State private var draft: AppSettings
    @State private var refreshTick = 0
    @State private var signingExpiry: Date?
    @State private var pendingCount: Int?
    @State private var isSyncing = false
    @State private var importPurpose: ShellImportPurpose = .folder
    @State private var showImporter = false
    @State private var restoreURL: URL?
    @State private var showRestoreAlert = false

    init(initial: AppSettings, lastSync: Date?) {
        self.initial = initial
        self.lastSync = lastSync
        _draft = State(initialValue: initial)
    }

    var body: some View {
        let _ = refreshTick

        NightCanvas {
            Form {
                timesSection
                bestHoursSection
                planningSection
                calendarSection
                notificationsSection
                backupSection
                signingSection
                claudeSection
                diagnosticsSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(LockInFormat.titled("Settings"))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importPurpose.contentTypes) { result in
            handleImport(result)
        }
        .alert("Replace everything in the app with this backup?", isPresented: $showRestoreAlert) {
            Button("Replace", role: .destructive) {
                if let url = restoreURL { restore(from: url) }
                restoreURL = nil
            }
            Button("Cancel", role: .cancel) {
                restoreURL = nil
            }
        } message: {
            Text("Your current goals, habits and marks will be replaced. This can't be undone.")
        }
        .onChange(of: draft) { _, edited in
            save(edited)
        }
        .task {
            signingExpiry = services.signing.expiryDate()
            pendingCount = await services.notifications.pendingCount()
        }
    }

    private var rowFill: Color { Color.white.opacity(0.06) }

    // MARK: Sections

    private var timesSection: some View {
        Section("Times") {
            ShellTimeRow("Morning, Mon to Fri", minutes: $draft.morningTimeWeekday)
            ShellTimeRow("Morning, Sat and Sun", minutes: $draft.morningTimeWeekend)
            ShellTimeRow("Evening tick-off", minutes: $draft.eveningTime)
            Picker("Check-in day", selection: $draft.checkInWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(ShellWeekday.name(day)).tag(day)
                }
            }
            ShellTimeRow("Check-in time", minutes: $draft.checkInTime)
        }
        .listRowBackground(rowFill)
    }

    private var bestHoursSection: some View {
        Section {
            NavigationLink {
                ShellBestHoursScreen(windows: $draft.bestHours)
            } label: {
                LabeledContent("Best hours", value: "\(draft.bestHours.count) windows")
            }
        } footer: {
            Text("Goal blocks and nudges land inside these hours.")
        }
        .listRowBackground(rowFill)
    }

    private var planningSection: some View {
        Section {
            Toggle("Saturday off for goal work", isOn: $draft.saturdayOff)
            Stepper("Travel buffer: \(draft.travelBufferMinutes) min",
                    value: $draft.travelBufferMinutes, in: 0...60, step: 5)
        } header: {
            Text("Planning")
        } footer: {
            Text("Physical habits are still allowed on Saturdays.")
        }
        .listRowBackground(rowFill)
    }

    private var calendarSection: some View {
        let status = services.calendar.status
        return Section("Calendar") {
            LabeledContent("Access", value: ShellSettingsText.access(status))
            if status == .notDetermined {
                Button("Allow calendar access") { askForCalendar() }
            }
            if status == .denied || status == .restricted {
                PermissionBanner(title: "Calendar access is off",
                                 body: "Turn it on so plans fit your timetable.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            LabeledContent("Goals calendar",
                           value: initial.goalsCalendarIdentifier == nil ? "Not created" : "Goals")
        }
        .listRowBackground(rowFill)
    }

    private var notificationsSection: some View {
        let status = services.notifications.status
        return Section {
            LabeledContent("Access", value: ShellSettingsText.access(status))
            if status == .notDetermined {
                Button("Allow reminders") { askForNotifications() }
            }
            if status == .denied || status == .restricted {
                PermissionBanner(title: "Reminders are off",
                                 body: "Habits still track, but nothing will nudge you.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            LabeledContent("Notifications a day", value: "\(initial.maxNotificationsPerDay)")
            Stepper("Timed nudges a day: \(draft.maxTimedNudgesPerDay)",
                    value: $draft.maxTimedNudgesPerDay, in: 0...4)
        } header: {
            Text("Notifications")
        } footer: {
            Text("The morning plan and the evening tick-off always count, so 6 a day at most.")
        }
        .listRowBackground(rowFill)
    }

    private var backupSection: some View {
        Section {
            LabeledContent("Folder", value: services.backup.folderName ?? "None")
            LabeledContent("Last backup", value: initial.lastBackupAt.map { LockInFormat.dayMonthTime($0) } ?? "Never")
            Button("Choose folder") {
                importPurpose = .folder
                showImporter = true
            }
            Button("Back up now") { backUpNow() }
            Button("Restore from file…") {
                importPurpose = .restore
                showImporter = true
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup is saved after each weekly check-in.")
        }
        .listRowBackground(rowFill)
    }

    private var signingSection: some View {
        Section {
            if let signingExpiry {
                Text("App expires \(LockInFormat.dayMonthTime(signingExpiry))")
            } else {
                LabeledContent("App expires", value: "Unknown")
            }
        } header: {
            Text("Signing")
        } footer: {
            Text("Re-sign with Sideloadly before then, using the same Apple ID, so your data stays.")
        }
        .listRowBackground(rowFill)
    }

    private var claudeSection: some View {
        Section {
            Button("Copy prompt add-on") { copyPromptAddOn() }
        } header: {
            Text("Claude")
        } footer: {
            Text("Paste it at the end of your goal-system prompt so plans finish with importable JSON.")
        }
        .listRowBackground(rowFill)
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            LabeledContent("Pending notifications", value: pendingCount.map { String($0) } ?? "…")
            LabeledContent("Last sync", value: lastSync.map { LockInFormat.dayMonthTime($0) } ?? "Never")
            Button(isSyncing ? "Syncing…" : "Sync now") { syncNow() }
                .disabled(isSyncing)
            LabeledContent("Version", value: ShellSettingsText.versionAndBuild)
        }
        .listRowBackground(rowFill)
    }

    // MARK: Saving

    private func save(_ edited: AppSettings) {
        let current = services.store.snapshot().settings
        let merged = shellMergingEditableFields(of: edited, into: current)
        guard merged != current else { return }
        do {
            try services.store.apply(ChangeSet(upserts: [.settings(merged)]))
        } catch {
            router.toast = "Couldn't save. Try again."
            return
        }
        let notifications = services.notifications
        Task {
            await notifications.reschedule()
            pendingCount = await notifications.pendingCount()
        }
    }

    // MARK: Permissions

    private func askForCalendar() {
        let calendar = services.calendar
        Task {
            _ = await calendar.requestAccess()
            refreshTick += 1
        }
    }

    private func askForNotifications() {
        let notifications = services.notifications
        Task {
            _ = await notifications.requestAccess()
            refreshTick += 1
        }
    }

    // MARK: Backup

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                router.toast = "Couldn't open that file."
            }
        case .success(let url):
            switch importPurpose {
            case .folder:
                useFolder(url)
            case .restore:
                restoreURL = url
                // Let the picker finish dismissing before the alert comes up.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    showRestoreAlert = true
                }
            }
        }
    }

    private func useFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try services.backup.setFolder(url)
            router.toast = "Backup folder set"
        } catch {
            router.toast = "Couldn't use that folder. Pick another one."
        }
        refreshTick += 1
    }

    private func backUpNow() {
        guard services.backup.folderName != nil else {
            router.toast = "Choose a backup folder first."
            return
        }
        do {
            let url = try services.backup.backUpNow()
            router.toast = "Backed up to \(url.lastPathComponent)"
        } catch {
            router.toast = "Backup failed. Try choosing the folder again."
        }
        refreshTick += 1
    }

    /// Restore replaces the whole store; then sync (which also reschedules) so blocks and reminders match.
    private func restore(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try services.backup.restore(from: url)
        } catch {
            router.toast = (error as? BackupError)?.message ?? "Couldn't restore that file."
            return
        }
        // Show the restored values (a no-op save follows, because nothing differs from the store).
        draft = shellMergingEditableFields(of: services.store.snapshot().settings, into: draft)
        let calendar = services.calendar
        let notifications = services.notifications
        Task {
            _ = await calendar.sync()
            pendingCount = await notifications.pendingCount()
            router.toast = "Backup restored"
        }
    }

    // MARK: Claude and diagnostics

    private func copyPromptAddOn() {
        UIPasteboard.general.string = PromptBuilder.promptAddOn
        router.toast = "Prompt add-on copied"
    }

    private func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        let calendar = services.calendar
        let notifications = services.notifications
        Task {
            let report = await calendar.sync()
            pendingCount = await notifications.pendingCount()
            isSyncing = false
            router.toast = report.error ?? "Synced"
        }
    }
}

// MARK: - Helpers

/// Why the file importer is open.
private enum ShellImportPurpose {
    case folder, restore

    var contentTypes: [UTType] {
        switch self {
        case .folder: [.folder]
        case .restore: [.json]
        }
    }
}

private enum ShellSettingsText {
    static func access(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "On"
        case .denied: "Off"
        case .notDetermined: "Not asked yet"
        case .restricted: "Restricted"
        }
    }

    /// "1.0 (1)" from the bundle.
    static var versionAndBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Copies the fields Settings edits from `edited` onto `base`. Leaves `maxNotificationsPerDay` (read-only) and the
/// fields services write (calendar id, backup bookmark, last backup, onboarding) as they are in `base`.
private func shellMergingEditableFields(of edited: AppSettings, into base: AppSettings) -> AppSettings {
    var result = base
    result.morningTimeWeekday = edited.morningTimeWeekday
    result.morningTimeWeekend = edited.morningTimeWeekend
    result.eveningTime = edited.eveningTime
    result.checkInWeekday = edited.checkInWeekday
    result.checkInTime = edited.checkInTime
    result.maxTimedNudgesPerDay = edited.maxTimedNudgesPerDay
    result.bestHours = edited.bestHours
    result.saturdayOff = edited.saturdayOff
    result.travelBufferMinutes = edited.travelBufferMinutes
    return result
}

/// The best-hours list, pushed from Settings.
private struct ShellBestHoursScreen: View {
    @Binding var windows: [TimeWindow]

    var body: some View {
        NightCanvas {
            List {
                ShellBestHoursSections(windows: $windows)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Best hours")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppServices.preview())
    .environment(Router())
    .preferredColorScheme(.dark)
}
