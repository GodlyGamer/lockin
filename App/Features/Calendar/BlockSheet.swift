import SwiftUI
import CoreKit

/// Block sheet (DESIGN.md §5.1): title, goal and time, with Done, Move and Delete.
struct BlockSheet: View {
    let blockID: UUID

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var isMoving = false
    @State private var newStart = Date()
    @State private var confirmDelete = false
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        NavigationStack {
            Group {
                if let block = snapshot.block(blockID) {
                    detail(block, snapshot: snapshot)
                } else {
                    ContentUnavailableView("Block not found", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func detail(_ block: CalendarBlock, snapshot: StoreSnapshot) -> some View {
        List {
            Section {
                Text(LockInFormat.titled(block.title))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.vertical, 4)
                LabeledContent("Goal", value: goalName(block, snapshot: snapshot))
                LabeledContent("When", value: whenText(block))
                LabeledContent("Status", value: statusText(block.status))
            }

            if block.status == .clash {
                Section {
                    Button("Resolve clash") { router.sheet = .conflict(block.id) }
                }
            }

            Section {
                if block.status == .done {
                    Button("Mark not done") { Task { await setStatus(.scheduled, for: block) } }
                } else {
                    Button("Done") { Task { await setStatus(.done, for: block) } }
                }
                Button("Move") {
                    newStart = block.start
                    withAnimation { isMoving.toggle() }
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
            }

            if isMoving {
                Section("New start") {
                    DatePicker("Start", selection: $newStart, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Calendar.lockIn.timeZone)
                    Button("Move block") { Task { await move(block) } }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(Color.emberText)
                }
            }
        }
        .disabled(isBusy)
        .confirmationDialog("Delete this block?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await setStatus(.cancelled, for: block) } }
            Button("Keep", role: .cancel) {}
        }
    }

    // MARK: Text

    private func goalName(_ block: CalendarBlock, snapshot: StoreSnapshot) -> String {
        if let goalID = block.goalID, let goal = snapshot.goal(goalID) { return goal.title }
        if let systemID = block.systemID, let system = snapshot.system(systemID) { return system.title }
        return "None"
    }

    private func whenText(_ block: CalendarBlock) -> String {
        "\(LockInFormat.dayMonth(block.day)), \(CalFormat.timeRange(block.start, block.end))"
    }

    private func statusText(_ status: BlockStatus) -> String {
        switch status {
        case .scheduled: "Scheduled"
        case .clash: "Clash"
        case .done: "Done"
        case .cancelled: "Deleted"
        }
    }

    // MARK: Actions

    /// Done, undo Done and Delete (a cancelled block's Apple Calendar event is removed by the sync).
    private func setStatus(_ status: BlockStatus, for block: CalendarBlock) async {
        isBusy = true
        var updated = block
        updated.status = status
        updated.suggestedStart = nil
        do {
            try services.store.apply(ChangeSet(upserts: [.block(updated)]))
        } catch {
            errorText = "Couldn't save. Try again."
            isBusy = false
            return
        }
        let report = await services.calendar.sync()
        if report.error != nil {
            router.toast = "Calendar didn't sync. Pull to retry."
        }
        isBusy = false
        dismiss()
    }

    private func move(_ block: CalendarBlock) async {
        isBusy = true
        errorText = nil
        do {
            try await services.calendar.move(blockID: block.id, to: CalFormat.wholeMinute(newStart))
            isBusy = false
            dismiss()
        } catch {
            errorText = "Couldn't move the block. Try again."
            isBusy = false
        }
    }
}

#Preview {
    let services = calPreviewServices()
    return BlockSheet(blockID: services.store.snapshot().blocks.first?.id ?? UUID())
        .environment(services)
        .environment(Router())
        .preferredColorScheme(.dark)
}
