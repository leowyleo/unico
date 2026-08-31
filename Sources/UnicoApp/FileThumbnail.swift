import AppKit
import SwiftUI
import QuickLookThumbnailing
import UnicoCore

// Generate only small previews, and cancel work when a recycled row changes or disappears.
struct FileThumbnail: NSViewRepresentable {
    let file: FileRecord
    @Environment(\.displayScale) private var scale

    final class Coordinator {
        var file: FileRecord?
        var scale: CGFloat = 0
        var request: QLThumbnailGenerator.Request?
        func cancel() {
            if let request { QLThumbnailGenerator.shared.cancel(request) }
            request = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.file != file || coordinator.scale != scale else { return }
        coordinator.cancel()
        coordinator.file = file
        coordinator.scale = scale
        view.image = NSWorkspace.shared.icon(forFile: file.url.path)
        let request = QLThumbnailGenerator.Request(fileAt: file.url, size: CGSize(width: 64, height: 64),
                                                   scale: scale, representationTypes: .all)
        coordinator.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak view, weak coordinator] result, _ in
            DispatchQueue.main.async {
                guard let coordinator, coordinator.request === request else { return }
                if let result { view?.image = result.nsImage }
                coordinator.request = nil
            }
        }
    }
    static func dismantleNSView(_ view: NSImageView, coordinator: Coordinator) {
        coordinator.cancel()
    }
}
