import SwiftUI
import CoreKit

struct TodayAccessoryView: View {
    var body: some View {
        Text("Today")
    }
}

#Preview {
    TodayAccessoryView()
        .environment(AppServices.preview())
        .environment(Router())
}
