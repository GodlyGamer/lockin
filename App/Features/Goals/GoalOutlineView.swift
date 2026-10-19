import SwiftUI
import CoreKit

struct GoalOutlineView: View {
    let goalID: UUID

    var body: some View {
        Text("Goal outline")
    }
}

#Preview {
    NavigationStack { GoalOutlineView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
