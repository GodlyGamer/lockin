import SwiftUI
import CoreKit

struct HabitMarkSheet: View {
    let habitID: UUID
    let day: LocalDay

    init(habitID: UUID, day: LocalDay) {
        self.habitID = habitID
        self.day = day
    }

    var body: some View {
        Text("Mark sheet")
    }
}

#Preview {
    HabitMarkSheet(habitID: SampleData.liftHabitID, day: HabitEngine.logicalDay(for: .now))
        .environment(AppServices.preview())
        .environment(Router())
}
