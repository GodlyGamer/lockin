import SwiftUI
import CoreKit

/// Conflict sheet (DESIGN.md §5.4): "{event} now overlaps {block}", the suggested slot, and Move / Keep /
/// Pick another time. Nothing moves without a tap.
struct ConflictSheet: View {
    let blockID: UUID

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var overlapping: [ExternalEvent] = []
    @State private var loaded = false
    @State private var isPicking = false
    @State private var pickedStart = Date()
    @State private var moveFeedback = 0
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let block = snapshot.block(blockID)
        NavigationStack {
            Group {
                if let block {
                    content(block)
                } else {
                    ContentUnavailableView("Block not found", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("Clash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .haptic(.blockMoved, trigger: moveFeedback)
        .task(id: block?.start) {
            await loadOverlap()
        }
    }

    private func content(_ block: CalendarBlock) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(headline(for: block))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Block", "\(LockInFormat.dayMonth(block.day)), \(CalFormat.timeRange(block.start, block.end))")
                    ForEach(overlapping) { event in
                        detailRow("Event", "\(event.title), \(CalFormat.timeRange(event.start, event.end))")
                    }
                    if let suggested = block.suggestedStart {
                        let end = suggested.addingTimeInterval(block.end.timeIntervalSince(block.start))
                        detailRow("Suggested",
                                  "\(LockInFormat.dayMonth(LocalDay(suggested))), \(CalFormat.timeRange(suggested, end))")
                    } else {
                        detailRow("Suggested", "No free slot this week")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 10) {
                    Button {
                        Task { await moveToSuggestion(block) }
                    } label: {
                        Text("Move").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(block.suggestedStart == nil || isBusy)

                    Button {
                        Task { await keep(block) }
                    } label: {
                        Text("Keep").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isBusy)

                    Button {
                        pickedStart = block.suggestedStart ?? block.start
                        withAnimation { isPicking.toggle() }
                    } label: {
                        Text("Pick another time").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isBusy)
                }

                if isPicking {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("New start", selection: $pickedStart, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, Calendar.lockIn.timeZone)
                        Button {
                            Task { await move(block, to: pickedStart) }
                        } label: {
                            Text("Move here").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isBusy)
                    }
                    .padding(16)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(Color.emberText)
                }
            }
            .padding(16)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headline(for block: CalendarBlock) -> String {
        if let first = overlapping.first {
            let base = "\(first.title) now overlaps \(block.title)"
            let more = overlapping.count - 1
            return more > 0 ? "\(base) (and \(more) more)" : base
        }
        if loaded && block.status != .clash {
            return "\(block.title) no longer clashes"
        }
        return "\(block.title) overlaps a calendar event"
    }

    // MARK: Data

    /// The external events that overlap the block, using the same travel buffer as the clash check.
    private func loadOverlap() async {
        let snapshot = services.store.snapshot()
        guard let block = snapshot.block(blockID) else {
            overlapping = []
            loaded = true
            return
        }
        let buffer = TimeInterval(snapshot.settings.travelBufferMinutes * 60)
        let range = DateInterval(start: block.start.addingTimeInterval(-buffer - 3600),
                                 end: block.end.addingTimeInterval(buffer + 3600))
        let found = await services.calendar.externalEvents(in: range)
        overlapping = found.filter { event in
            !event.isAllDay && !event.isFree
                && !block.ignoredClashEventIDs.contains(event.id)
                && event.start.addingTimeInterval(-buffer) < block.end
                && event.end.addingTimeInterval(buffer) > block.start
        }
        loaded = true
    }

    // MARK: Actions

    private func moveToSuggestion(_ block: CalendarBlock) async {
        guard let target = block.suggestedStart else { return }
        await move(block, to: target)
    }

    private func move(_ block: CalendarBlock, to start: Date) async {
        isBusy = true
        errorText = nil
        do {
            try await services.calendar.move(blockID: block.id, to: CalFormat.wholeMinute(start))
            moveFeedback += 1
            // Let the haptic play before the sheet goes away.
            try? await Task.sleep(for: .milliseconds(200))
            isBusy = false
            dismiss()
        } catch {
            errorText = "Couldn't move the block. Try again."
            isBusy = false
        }
    }

    /// Keep: ignore every event it overlaps now and go back to Scheduled.
    private func keep(_ block: CalendarBlock) async {
        isBusy = true
        var updated = block
        for event in overlapping where !updated.ignoredClashEventIDs.contains(event.id) {
            updated.ignoredClashEventIDs.append(event.id)
        }
        updated.status = .scheduled
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
}

#Preview {
    let services = calPreviewServices()
    let clash = services.store.snapshot().blocks.first { $0.status == .clash }
    return ConflictSheet(blockID: clash?.id ?? UUID())
        .environment(services)
        .environment(Router())
        .preferredColorScheme(.dark)
}
