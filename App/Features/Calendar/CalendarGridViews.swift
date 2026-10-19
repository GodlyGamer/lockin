import SwiftUI
import CoreKit

// The Week/Day grid (DESIGN.md §5.1). Calendar cells and blocks are solid content: no glass, no Material.

/// Remembers where a touch landed so a long press can be turned into a time.
/// A class on purpose: updating it never re-renders the grid.
final class CalPressTracker {
    var y: CGFloat = 0
}

/// One horizontally paged page: the header, the all-day strip and the vertically scrolling grid.
struct CalPageView: View {
    let days: [LocalDay]
    let hourHeight: CGFloat
    let snapshot: StoreSnapshot
    let events: [ExternalEvent]
    let onRefresh: @MainActor () async -> Void

    @Environment(Router.self) private var router

    var body: some View {
        let now = Date()
        let today = LocalDay(now)
        VStack(spacing: 0) {
            CalHeaderRow(days: days, today: today)
            CalAllDayStrip(days: days, events: events)
            ScrollViewReader { proxy in
                ScrollView {
                    CalGrid(days: days, today: today, hourHeight: hourHeight, snapshot: snapshot, events: events,
                            onOpen: { item in open(item) },
                            onLongPress: { date in router.sheet = .newBlock(date) })
                }
                .refreshable { await onRefresh() }
                .onAppear {
                    proxy.scrollTo("hour-\(initialHour(today: today, now: now))", anchor: .top)
                }
            }
        }
    }

    private func initialHour(today: LocalDay, now: Date) -> Int {
        guard days.contains(today) else { return 7 }
        let hour = TimeOfDay.minutes(of: now) / 60
        return min(max(CalMetrics.firstHour, hour - 1), CalMetrics.lastHour - 1)
    }

    private func open(_ item: CalItem) {
        switch item.kind {
        case .event:
            break
        case .block(let block):
            router.sheet = block.status == .clash ? .conflict(block.id) : .block(block.id)
        case .habit(let habit, let day):
            router.sheet = .markHabit(habit.id, day)
        }
    }
}

// MARK: - Header

struct CalHeaderRow: View {
    let days: [LocalDay]
    let today: LocalDay

    var body: some View {
        if days.count == 1, let day = days.first {
            HStack {
                Text(LockInFormat.dayMonth(day))
                    .font(.headline)
                    .foregroundStyle(day == today ? Color.cobaltText : Color.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let first = days.first, let last = days.last {
                    Text("\(LockInFormat.shortDayMonth(first)) – \(LockInFormat.shortDayMonth(last))")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, 16)
                }
                HStack(spacing: 0) {
                    Color.clear.frame(width: CalMetrics.gutterWidth, height: 1)
                    ForEach(days, id: \.self) { day in
                        CalDayHeaderCell(day: day, isToday: day == today)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct CalDayHeaderCell: View {
    let day: LocalDay
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(LockInFormat.weekdayLetters[day.weekday - 1])
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text("\(day.day)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Color.white : Color.textPrimary)
                .frame(minWidth: 28, minHeight: 28)
                .background(isToday ? Color.cobalt : Color.clear, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isToday ? "Today, \(LockInFormat.dayMonth(day))" : LockInFormat.dayMonth(day))
    }
}

// MARK: - All-day strip

struct CalAllDayStrip: View {
    let days: [LocalDay]
    let events: [ExternalEvent]

    var body: some View {
        let perDay: [[ExternalEvent]] = days.map { CalLayout.allDayEvents(on: $0, in: events) }
        if perDay.contains(where: { !$0.isEmpty }) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("All day")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: CalMetrics.gutterWidth, height: 16)
                    ForEach(0..<perDay.count, id: \.self) { index in
                        VStack(spacing: 2) {
                            ForEach(Array(perDay[index].prefix(2))) { event in
                                CalAllDayChip(event: event)
                            }
                            if perDay[index].count > 2 {
                                Text("+\(perDay[index].count - 2)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.horizontal, 1)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
                Rectangle().fill(Color.rowSeparator).frame(height: 1)
            }
        }
    }
}

private struct CalAllDayChip: View {
    let event: ExternalEvent

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(hex: event.calendarColorHex)).frame(width: 3)
            Text(event.title)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 3)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .background(Color.eventFill)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All day, \(event.title)")
    }
}

// MARK: - Grid

struct CalGrid: View {
    let days: [LocalDay]
    let today: LocalDay
    let hourHeight: CGFloat
    let snapshot: StoreSnapshot
    let events: [ExternalEvent]
    let onOpen: @MainActor (CalItem) -> Void
    let onLongPress: @MainActor (Date) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CalGutter(hourHeight: hourHeight)
            ForEach(days, id: \.self) { day in
                CalDayColumn(
                    day: day,
                    isToday: day == today,
                    showsOff: snapshot.settings.saturdayOff && day.weekday == 6,
                    hourHeight: hourHeight,
                    placed: CalLayout.place(CalLayout.items(for: day, snapshot: snapshot, events: events),
                                            day: day, hourHeight: hourHeight),
                    snapshot: snapshot,
                    onOpen: onOpen,
                    onLongPress: onLongPress
                )
            }
        }
        .padding(.top, 10)
        // Room to scroll the last hours clear of the tab bar; the grid extends under it.
        .padding(.bottom, 96)
    }
}

private struct CalGutter: View {
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalMetrics.firstHour..<CalMetrics.lastHour, id: \.self) { hour in
                Text(CalFormat.hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    .frame(height: hourHeight, alignment: .top)
                    .id("hour-\(hour)")
                    .offset(y: -7)
            }
        }
        .frame(width: CalMetrics.gutterWidth)
        .accessibilityHidden(true)
    }
}

private struct CalHourLines: Shape {
    let hours: Int
    let hourHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for hour in 0...hours {
            let y = CGFloat(hour) * hourHeight
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct CalDayColumn: View {
    let day: LocalDay
    let isToday: Bool
    let showsOff: Bool
    let hourHeight: CGFloat
    let placed: [CalPlacedItem]
    let snapshot: StoreSnapshot
    let onOpen: @MainActor (CalItem) -> Void
    let onLongPress: @MainActor (Date) -> Void

    @State private var tracker = CalPressTracker()

    private var gridHeight: CGFloat { CGFloat(CalMetrics.hourCount) * hourHeight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsOff {
                Rectangle()
                    .fill(Color.white.opacity(0.03))
                    .allowsHitTesting(false)
            }
            CalHourLines(hours: CalMetrics.hourCount, hourHeight: hourHeight)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                .allowsHitTesting(false)
            if showsOff {
                Text("Off")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 2)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(placed) { entry in
                        let laneWidth = (geometry.size.width - 4) / CGFloat(entry.laneCount)
                        CalItemView(entry: entry, snapshot: snapshot, onOpen: onOpen)
                            .frame(width: max(8, laneWidth - 1), height: entry.height)
                            .offset(x: 2 + CGFloat(entry.lane) * laneWidth, y: entry.top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in tracker.y = value.startLocation.y }
                    )
                    .onLongPressGesture(minimumDuration: 0.5) { handleLongPress() }
                    .accessibilityHidden(true)
            }
            if isToday {
                CalNowLine(hourHeight: hourHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: gridHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LockInFormat.dayMonth(day))
    }

    /// Press time rounded down to 15 minutes.
    private func handleLongPress() {
        let minutes = CalMetrics.firstHour * 60 + Int((tracker.y / hourHeight) * 60)
        let rounded = min(max(0, (minutes / 15) * 15), 24 * 60 - 15)
        onLongPress(day.date(minutes: rounded))
    }
}

/// The current time: a 1 pt cobalt line with a 6 pt dot.
private struct CalNowLine: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let minutes = TimeOfDay.minutes(of: context.date)
            let first = CalMetrics.firstHour * 60
            if minutes >= first && minutes < CalMetrics.lastHour * 60 {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.cobalt)
                        .frame(height: 1)
                    Circle()
                        .fill(Color.cobalt)
                        .frame(width: 6, height: 6)
                        .offset(x: -3, y: -2.5)
                }
                .offset(y: CGFloat(minutes - first) / 60 * hourHeight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Items

private struct CalItemView: View {
    let entry: CalPlacedItem
    let snapshot: StoreSnapshot
    let onOpen: @MainActor (CalItem) -> Void

    var body: some View {
        switch entry.item.kind {
        case .event(let event):
            CalEventCell(event: event, height: entry.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(event.title), \(CalFormat.timeRange(event.start, event.end))")
        case .block(let block):
            Button {
                onOpen(entry.item)
            } label: {
                CalBlockCell(block: block, height: entry.height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(blockLabel(block))
        case .habit(let habit, let day):
            Button {
                onOpen(entry.item)
            } label: {
                CalHabitChip(habit: habit,
                             mark: HabitEngine.mark(for: habit, on: day, logs: snapshot.logs, now: Date()))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.title), reminder \(LockInFormat.time(habit.reminderTime ?? 0))")
        }
    }

    private func blockLabel(_ block: CalendarBlock) -> String {
        let base = "\(block.title), \(CalFormat.timeRange(block.start, block.end))"
        switch block.status {
        case .clash: return "Clash, \(base)"
        case .done: return "Done, \(base)"
        case .scheduled, .cancelled: return base
        }
    }
}

/// External event: fill `#23252B`, 3 pt leading bar in the calendar colour, title in textSecondary at 12 pt.
private struct CalEventCell: View {
    let event: ExternalEvent
    let height: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Color(hex: event.calendarColorHex)).frame(width: 3)
            Text(event.title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(max(1, Int((height - 4) / 15)))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.eventFill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Goal block: fill `#182553`, 3 pt cobalt bar, title in textPrimary. Clash: 1.5 pt ember border and a "Clash" chip.
/// Done: fill `#1E2026`, title in textSecondary.
private struct CalBlockCell: View {
    let block: CalendarBlock
    let height: CGFloat

    private var isClash: Bool { block.status == .clash }
    private var isDone: Bool { block.status == .done }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isDone ? Color.markMStroke : Color.cobalt)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if isClash {
                    Text("Clash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.emberText)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.ember.opacity(0.18), in: Capsule())
                }
                Text(block.title)
                    .font(.caption)
                    .foregroundStyle(isDone ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(max(1, Int((height - 4) / 15) - (isClash ? 1 : 0)))
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isDone ? Color(hex: "#1E2026") : Color.blockFill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if isClash {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.ember, lineWidth: 1.5)
            }
        }
    }
}

/// Timed habit: a 20 pt chip with a 1 pt `#4A505B` outline, at its reminder time.
private struct CalHabitChip: View {
    let habit: Habit
    let mark: Mark?

    var body: some View {
        HStack(spacing: 4) {
            dot
            Text(habit.title)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.canvas.opacity(0.7), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.markMStroke, lineWidth: 1)
        }
    }

    @ViewBuilder private var dot: some View {
        switch mark {
        case .D?:
            Circle().fill(Color.cobalt).frame(width: 8, height: 8)
        case .B?:
            Circle().fill(Color.markB).frame(width: 8, height: 8)
        case .M?:
            Circle().strokeBorder(Color.markMStroke, lineWidth: 1.5).frame(width: 8, height: 8)
        case nil:
            Circle().strokeBorder(Color.textTertiary, lineWidth: 1).frame(width: 8, height: 8)
        }
    }
}

#Preview("Week page") {
    let services = calPreviewServices()
    return CalPageView(days: Week(containing: .today).days, hourHeight: CalMetrics.weekHourHeight,
                       snapshot: services.store.snapshot(), events: SampleData.timetable(), onRefresh: {})
        .environment(services)
        .environment(Router())
        .preferredColorScheme(.dark)
}
