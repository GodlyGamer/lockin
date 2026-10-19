import SwiftUI
import CoreKit

struct TodaySheet: View {
    var body: some View {
        Text("Today sheet")
    }
}

#Preview {
    TodaySheet()
        .environment(AppServices.preview())
        .environment(Router())
}
