import SwiftUI
import UIKit

/// §7 / §8.5 `PermissionBanner(title:body:)`: the one shared permission-denied component. Solid, fill `#FFFFFF` 6%.
/// Its "Open Settings" button opens `UIApplication.openSettingsURLString`.
struct PermissionBanner: View {
    let title: String
    let detail: String

    @Environment(\.openURL) private var openURL

    init(title: String, body: String) {
        self.title = title
        self.detail = body
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            Image(systemName: "hand.raised")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(title)
                        .font(.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cobaltText)
                        .frame(minHeight: Sizing.minTouchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.top, Spacing.s12)
        .padding(.bottom, Spacing.s4)
        .background {
            RoundedRectangle.continuous(Radius.banner)
                .fill(Color.bannerFill)
        }
    }
}

#Preview("PermissionBanner") {
    NightCanvas {
        VStack(spacing: Spacing.s12) {
            PermissionBanner(
                title: "Calendar access is off",
                body: "Turn it on so plans fit your timetable."
            )
            PermissionBanner(
                title: "Reminders are off",
                body: "Habits still track, but nothing will nudge you."
            )
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
