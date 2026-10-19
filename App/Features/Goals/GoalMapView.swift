import SwiftUI
import CoreKit

struct GoalMapView: View {
    let goalID: UUID

    var body: some View {
        Text("Goal map")
    }
}

#Preview {
    NavigationStack { GoalMapView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
