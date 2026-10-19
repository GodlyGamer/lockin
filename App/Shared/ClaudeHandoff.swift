import UIKit

/// "Send to Claude" (§4.3 steps 2–3): copy the prompt, try to open the Claude app, else show the fallback toast.
enum ClaudeHandoff {
    static let fallbackToast = "Copied. Open Claude and paste it into your goal-system project."

    static func send(_ prompt: String, router: Router) async {
        UIPasteboard.general.string = prompt
        guard let url = URL(string: "claude://") else {
            router.toast = fallbackToast
            return
        }
        let opened = await UIApplication.shared.open(url)
        if !opened {
            router.toast = fallbackToast
        }
    }
}
