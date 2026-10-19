import SwiftUI
import CoreKit

struct WeekTabView: View {
    var body: some View {
        Text("Week")
    }
}

#Preview {
    NavigationStack { WeekTabView() }
        .environment(AppServices.preview())
        .environment(Router())
}
