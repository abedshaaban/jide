import SwiftUI

extension View {
    /// Keeps content at a comfortable width and centers it in the wide Mac window. No effect on iPhone.
    func readableWidth(_ max: CGFloat = 640) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
    }
}
