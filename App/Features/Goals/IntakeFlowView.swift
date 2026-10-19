import SwiftUI
import CoreKit

struct IntakeFlowView: View {
    var body: some View {
        Text("Intake")
    }
}

#Preview {
    IntakeFlowView()
        .environment(AppServices.preview())
        .environment(Router())
}
