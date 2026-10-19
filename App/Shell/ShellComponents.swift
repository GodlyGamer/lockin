import SwiftUI
import CoreKit

// Small building blocks shared by OnboardingView and SettingsView: a time-of-day row and the best-hours editor.
// Everything here is `Shell…`-prefixed or private (one Swift module for the whole app).

/// Minutes-after-midnight <-> `Date` for `DatePicker`.
enum ShellTime {
    /// A winter day, so "07:30" is always 450 minutes after midnight (no clock-change day).
    private static let referenceDay = LocalDay(year: 2001, month: 1, day: 15)

    static func date(minutes: Int) -> Date {
        referenceDay.date(minutes: min(max(minutes, 0), 1439))
    }

    static func minutes(of date: Date) -> Int {
        TimeOfDay.minutes(of: date)
    }
}

/// Weekday names for ISO weekdays 1…7.
enum ShellWeekday {
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func name(_ weekday: Int) -> String {
        names.indices.contains(weekday - 1) ? names[weekday - 1] : "Day \(weekday)"
    }
}

/// A `DatePicker` (hours and minutes) over an `Int` of minutes after midnight, shown in the app's time zone.
struct ShellTimeRow: View {
    private let title: String
    @Binding private var minutes: Int
    @State private var date: Date

    init(_ title: String, minutes: Binding<Int>) {
        self.title = title
        _minutes = minutes
        _date = State(initialValue: ShellTime.date(minutes: minutes.wrappedValue))
    }

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
            .environment(\.calendar, Calendar.lockIn)
            .environment(\.timeZone, Calendar.lockIn.timeZone)
            .onChange(of: date) { _, newDate in
                let value = ShellTime.minutes(of: newDate)
                if value != minutes { minutes = value }
            }
            .onChange(of: minutes) { _, newMinutes in
                if newMinutes != ShellTime.minutes(of: date) { date = ShellTime.date(minutes: newMinutes) }
            }
    }
}

/// The best-hours editor (§3.12, §7.1 page 4, §7.11): one `Section` per weekday, each with its windows and an
/// "Add window" button. Put it inside a `List` or `Form`.
struct ShellBestHoursSections: View {
    @Binding var windows: [TimeWindow]

    var body: some View {
        ForEach(1...7, id: \.self) { day in
            Section(ShellWeekday.name(day)) {
                ForEach(indices(on: day), id: \.self) { index in
                    if windows.indices.contains(index) {
                        ShellWindowRow(window: windows[index]) { updated in
                            if windows.indices.contains(index) { windows[index] = updated }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { remove(at: index) }
                        }
                    }
                }
                Button {
                    windows.append(TimeWindow(weekday: day, start: 540, end: 660))
                } label: {
                    Label("Add window", systemImage: "plus")
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
    }

    private func indices(on day: Int) -> [Int] {
        windows.indices.filter { windows[$0].weekday == day }
    }

    private func remove(at index: Int) {
        if windows.indices.contains(index) { windows.remove(at: index) }
    }
}

/// One window: start and end pickers. Keeps the end after the start (30 minutes apart when they collide).
private struct ShellWindowRow: View {
    private let window: TimeWindow
    private let onChange: (TimeWindow) -> Void
    @State private var draft: TimeWindow

    init(window: TimeWindow, onChange: @escaping (TimeWindow) -> Void) {
        self.window = window
        self.onChange = onChange
        _draft = State(initialValue: window)
    }

    var body: some View {
        HStack(spacing: 12) {
            ShellTimeRow("Start", minutes: $draft.start)
                .labelsHidden()
            Text("to")
                .foregroundStyle(Color.textSecondary)
            ShellTimeRow("End", minutes: $draft.end)
                .labelsHidden()
            Spacer(minLength: 0)
        }
        .onChange(of: draft.start) { _, start in
            if draft.end <= start { draft.end = min(start + 30, 1440) }
        }
        .onChange(of: draft.end) { _, end in
            if end <= draft.start { draft.start = max(end - 30, 0) }
        }
        .onChange(of: draft) { _, newDraft in
            if newDraft != window { onChange(newDraft) }
        }
        .onChange(of: window) { _, newWindow in
            if newWindow != draft { draft = newWindow }
        }
    }
}
