import SwiftUI
import CoreKit

struct HabitEditorView: View {
    let habitID: UUID?

    init(habitID: UUID?) {
        self.habitID = habitID
    }

    var body: some View {
        Text("Habit editor")
    }
}

#Preview {
    NavigationStack { HabitEditorView(habitID: nil) }
        .environment(AppServices.preview())
        .environment(Router())
}
