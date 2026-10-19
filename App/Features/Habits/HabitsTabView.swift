import SwiftUI
import CoreKit

/// DESIGN.md §7.9. A tab root: the shell supplies the NavigationStack (bound to `router.habitsPath`).
struct HabitsTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @State private var showArchived = false

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let today = HabitEngine.logicalDay(for: Date())
        let model = HabitsListBuilder.build(snapshot: snapshot, showArchived: showArchived, today: today)
        let status = services.notifications.status
        let remindersOff = status == .denied || status == .restricted
        NightCanvas {
            Group {
                if model.isEmpty {
                    emptyState(remindersOff: remindersOff)
                } else {
                    habitList(model: model, today: today, remindersOff: remindersOff)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.habitEditor(nil))
                } label: {
                    Label("Add habit", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - List

    private var rowBackground: some View {
        Color.tileBottom.overlay(Color.white.opacity(0.03))
    }

    private func habitList(model: HabitsListModel, today: LocalDay, remindersOff: Bool) -> some View {
        List {
            Section {
                TitleText("Habits")
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            if remindersOff {
                Section {
                    PermissionBanner(title: "Reminders are off",
                                     body: "Habits still track, but nothing will nudge you.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            ForEach(model.sections, id: \.id) { section in
                Section {
                    ForEach(section.rows, id: \.id) { row in
                        habitRow(row, today: today)
                    }
                } header: {
                    Text(section.title)
                        .font(.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .textCase(nil)
                }
            }
            if model.archivedCount > 0 {
                Section {
                    Toggle("Show archived", isOn: $showArchived)
                        .listRowBackground(rowBackground)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }

    private func habitRow(_ row: HabitsRowModel, today: LocalDay) -> some View {
        let habit = row.habit
        return HabitRow(title: habit.title,
                        subtitle: row.subtitle,
                        mark: row.mark,
                        onTapMark: { router.sheet = .markHabit(habit.id, today) },
                        onTapRow: { router.push(.habitEditor(habit.id)) })
            .buttonStyle(.plain)
            .listRowBackground(rowBackground)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    setArchived(habit, archived: !habit.isArchived)
                } label: {
                    Label(habit.isArchived ? "Restore" : "Archive",
                          systemImage: habit.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
                .tint(Color.markMStroke)
            }
    }

    private func setArchived(_ habit: Habit, archived: Bool) {
        var updated = habit
        updated.isArchived = archived
        let services = self.services
        do {
            try services.store.apply(ChangeSet(upserts: [.habit(updated)]))
        } catch {
            router.toast = "Couldn't save. Try again."
            return
        }
        router.toast = archived ? "Archived. Past marks are kept." : "Restored."
        Task { await services.notifications.reschedule() }
    }

    // MARK: - Empty state

    private func emptyState(remindersOff: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TitleText("Habits")
                    .accessibilityAddTraits(.isHeader)
                if remindersOff {
                    PermissionBanner(title: "Reminders are off",
                                     body: "Habits still track, but nothing will nudge you.")
                }
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundStyle(Color.textTertiary)
                        .accessibilityHidden(true)
                    Text("Add your first habit")
                        .font(.tileTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Or build a goal and Claude will suggest them.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("Add habit") { router.push(.habitEditor(nil)) }
                            .buttonStyle(.borderedProminent)
                        Button("New goal") { router.sheet = .newGoal }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    NavigationStack { HabitsTabView() }
        .environment(AppServices.preview())
        .environment(Router())
}

#Preview("Empty") {
    NavigationStack { HabitsTabView() }
        .environment(AppServices(store: InMemoryStore(snapshot: StoreSnapshot()),
                                 calendar: FakeCalendarService(store: InMemoryStore()),
                                 notifications: FakeNotificationService(store: InMemoryStore(), status: .denied),
                                 backup: FakeBackupService(store: InMemoryStore()),
                                 signing: FixedSigningInfo(nil)))
        .environment(Router())
}
