import SwiftUI

extension View {
    /// §8.5 `.toast(text:)`: a solid capsule at the top, shown while `text` is non-nil and cleared to nil after
    /// 2.5 s (setting a new message restarts the timer). Tapping it dismisses it. VoiceOver announces the message.
    /// Apply it once near the root: `.toast(text: $router.toast)`.
    func toast(text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var text: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: Binding<String?>) {
        _text = text
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ZStack {
                if let message = text {
                    ToastCapsule(message: message)
                        .transition(Motion.toastTransition(reduceMotion: reduceMotion))
                        .onTapGesture { text = nil }
                        .task(id: message) {
                            AccessibilityNotification.Announcement(message).post()
                            try? await Task.sleep(for: .seconds(Motion.toastVisibleSeconds))
                            if !Task.isCancelled, text == message {
                                text = nil
                            }
                        }
                }
            }
            .animation(Motion.animation(.toast, reduceMotion: reduceMotion), value: text)
        }
    }
}

private struct ToastCapsule: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.s20)
            .padding(.vertical, Spacing.s12)
            .background {
                Capsule()
                    .fill(Color.toastFill)
                    .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.tileStroke, lineWidth: 1)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s8)
    }
}

private struct ToastPreviewHost: View {
    @State private var message: String? = "Week saved"

    var body: some View {
        NightCanvas {
            Button("Show a toast") {
                message = "Copied. Open Claude and paste it into your goal-system project."
            }
        }
        .toast(text: $message)
    }
}

#Preview("Toast") {
    ToastPreviewHost()
        .preferredColorScheme(.dark)
}
