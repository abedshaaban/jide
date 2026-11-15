import SwiftUI
import UIKit

/// Hardware-keyboard input for one screen (Mac, or a keyboard attached to the phone).
/// It holds first responder itself: on the Mac a full-screen cover has none until the window is
/// re-activated, so SwiftUI's `keyboardShortcut` and `onKeyPress` stay dead after opening it.
struct KeyCatcher: UIViewRepresentable {
    /// Off while something else needs the keyboard (a sheet with text fields).
    var isActive = true
    /// Return true when the key was used.
    var onKey: (UIKey) -> Bool

    func makeUIView(context: Context) -> CatcherView { CatcherView() }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
        view.isActive = isActive
        view.claim()
    }

    final class CatcherView: UIView {
        var onKey: ((UIKey) -> Bool)?
        var isActive = true

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            claim()
        }

        func claim() {
            // Next run loop: during an update or presentation the view cannot take first responder yet.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive, self.window != nil, !self.isFirstResponder else { return }
                self.becomeFirstResponder()
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var used = false
            for press in presses {
                if let key = press.key, onKey?(key) == true { used = true }
            }
            if !used { super.pressesBegan(presses, with: event) }
        }
    }
}
