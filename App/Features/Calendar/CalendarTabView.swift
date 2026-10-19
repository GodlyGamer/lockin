import SwiftUI
import CoreKit

/// The Calendar tab (DESIGN.md §5.1, §7.8). Stub: filled in by a later commit.
struct CalendarTabView: View {
    var body: some View {
        Text("Calendar")
    }
}

#Preview {
    NavigationStack { CalendarTabView() }
        .environment(AppServices.preview())
        .environment(Router())
}
