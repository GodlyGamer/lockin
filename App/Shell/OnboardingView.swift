import SwiftUI
import UniformTypeIdentifiers
import CoreKit

/// First-launch onboarding (DESIGN.md §7.1), shown by `RootTabView` as a full-screen cover until
/// `onboardingDone` is set. Six pages. Each system prompt follows an explanation page; a denied permission just
/// continues to the next page.
struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    @State private var page: ShellOnboardingPage = .welcome
    @State private var bestHours: [TimeWindow] = AppSettings.defaultBestHours
    @State private var isAsking = false
    @State private var showFolderPicker = false
    @State private var folderName: String?
    @State private var folderProblem: String?

    var body: some View {
        @Bindable var router = router

        NightCanvas {
            VStack(spacing: 0) {
                topBar
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(page)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        // The cover hides the root toast, so the cover shows its own.
        .toast(text: $router.toast)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            handleFolder(result)
        }
        .task {
            bestHours = services.store.snapshot().settings.bestHours
            folderName = services.backup.folderName
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            ShellPageDots(count: ShellOnboardingPage.allCases.count, index: page.rawValue)
            HStack {
                if page != .welcome {
                    Button("Back") { goBack() }
                        .foregroundStyle(Color.cobaltText)
                }
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome:
            ShellOnboardingInfoPage(
                symbol: "scope",
                title: "Lock in",
                message: "Habits, goals and your calendar in one place. Claude plans the system. This app keeps you on it."
            ) {
                Button("Start") { advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

        case .notifications:
            ShellOnboardingInfoPage(
                symbol: "bell.badge",
                title: "Reminders",
                message: "Up to 6 a day: a morning plan, a few timed nudges, an evening tick-off."
            ) {
                Button("Allow reminders") { askForNotifications() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isAsking)
                Button("Not now") { advance() }
                    .foregroundStyle(Color.textSecondary)
                    .disabled(isAsking)
            }

        case .calendar:
            ShellOnboardingInfoPage(
                symbol: "calendar.badge.clock",
                title: "Calendar",
                message: "Reads your calendars to find free time. Writes only to a new Goals calendar."
            ) {
                Button("Connect calendar") { askForCalendar() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isAsking)
                Button("Not now") { advance() }
                    .foregroundStyle(Color.textSecondary)
                    .disabled(isAsking)
            }

        case .bestHours:
            bestHoursPage

        case .backup:
            ShellOnboardingInfoPage(
                symbol: "externaldrive",
                title: "Backups",
                message: "After each weekly check-in the app saves a backup file to a folder you choose, so a re-install never loses your goals."
            ) {
                if let folderName {
                    Label(folderName, systemImage: "checkmark.circle")
                        .foregroundStyle(Color.cobaltText)
                }
                if let folderProblem {
                    Text(folderProblem)
                        .font(.footnote)
                        .foregroundStyle(Color.emberText)
                        .multilineTextAlignment(.center)
                }
                if folderName == nil {
                    Button("Choose folder") { showFolderPicker = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Later") { advance() }
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Button("Continue") { advance() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }

        case .tip:
            ShellOnboardingInfoPage(
                symbol: "eye.slash",
                title: "One tip",
                message: "In Apple Calendar, tap Calendars and untick Goals. Your blocks stay in this app's Calendar tab."
            ) {
                Button("Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var bestHoursPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                TitleText("Best hours")
                Text("Goal blocks and nudges land inside these hours. You can change them any time in Settings.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            List {
                ShellBestHoursSections(windows: $bestHours)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            Button("Continue") { saveBestHoursAndAdvance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 16)
        }
    }

    // MARK: Actions

    private func advance() {
        if let next = page.next { page = next }
    }

    private func goBack() {
        if let previous = page.previous { page = previous }
    }

    private func askForNotifications() {
        guard !isAsking else { return }
        isAsking = true
        Task {
            _ = await services.notifications.requestAccess()
            isAsking = false
            advance()
        }
    }

    private func askForCalendar() {
        guard !isAsking else { return }
        isAsking = true
        Task {
            _ = await services.calendar.requestAccess()
            isAsking = false
            advance()
        }
    }

    private func saveBestHoursAndAdvance() {
        var settings = services.store.snapshot().settings
        settings.bestHours = bestHours
        do {
            try services.store.apply(ChangeSet(upserts: [.settings(settings)]))
            advance()
        } catch {
            router.toast = "Couldn't save. Try again."
        }
    }

    private func handleFolder(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                try services.backup.setFolder(url)
                folderName = services.backup.folderName ?? url.lastPathComponent
                folderProblem = nil
            } catch {
                folderProblem = "Couldn't use that folder. Pick another one or choose Later."
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                folderProblem = "Couldn't open that folder. Pick another one or choose Later."
            }
        }
    }

    /// Sets `onboardingDone` (the cover closes when the store changes), then runs a first sync, which also
    /// schedules the first reminders.
    private func finish() {
        var settings = services.store.snapshot().settings
        settings.bestHours = bestHours
        settings.onboardingDone = true
        do {
            try services.store.apply(ChangeSet(upserts: [.settings(settings)]))
        } catch {
            router.toast = "Couldn't save. Try again."
            return
        }
        let calendar = services.calendar
        Task {
            _ = await calendar.sync()
        }
    }
}

/// The six pages, in order.
private enum ShellOnboardingPage: Int, CaseIterable {
    case welcome, notifications, calendar, bestHours, backup, tip

    var next: ShellOnboardingPage? { ShellOnboardingPage(rawValue: rawValue + 1) }
    var previous: ShellOnboardingPage? { ShellOnboardingPage(rawValue: rawValue - 1) }
}

/// A centred icon, title, message and a stack of buttons.
private struct ShellOnboardingInfoPage<Actions: View>: View {
    private let symbol: String
    private let title: String
    private let message: String
    private let actions: Actions

    init(symbol: String, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.cobaltText)
                .accessibilityHidden(true)
            TitleText(title)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                actions
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

/// Page indicator: a row of dots, the current one longer and cobalt.
private struct ShellPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Color.cobalt : Color.white.opacity(0.18))
                    .frame(width: dot == index ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

#Preview {
    OnboardingView()
        .environment(AppServices.preview())
        .environment(Router())
        .preferredColorScheme(.dark)
}
