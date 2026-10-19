import SwiftUI
import CoreKit

struct GoalsDashboardView: View {
    var body: some View {
        Text("Goals")
    }
}

#Preview {
    NavigationStack { GoalsDashboardView() }
        .environment(AppServices.preview())
        .environment(Router())
}
