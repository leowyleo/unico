import SwiftUI

extension View {
    /// Monterey keeps the native list background and selection behavior.
    /// Ventura and newer can blend lists with Unico's custom surfaces.
    @ViewBuilder
    func compatibleScrollBackground() -> some View {
        if #available(macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
