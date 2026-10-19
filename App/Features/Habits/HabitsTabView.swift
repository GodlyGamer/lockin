import SwiftUI
import CoreKit

struct HabitsTabView: View {
    var body: some View {
        Text("Habits")
    }
}

#Preview {
    NavigationStack { HabitsTabView() }
        .environment(AppServices.preview())
        .environment(Router())
}
