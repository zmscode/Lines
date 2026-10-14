import AppKit
import SwiftUI

/// Makes the window see-through behind the canvas for the Transparent background.
struct WindowTransparency: NSViewRepresentable {
	var isTransparent: Bool

	func makeNSView(context: Context) -> NSView { NSView() }

	func updateNSView(_ view: NSView, context: Context) {
		DispatchQueue.main.async {
			guard let window = view.window else { return }
			window.isOpaque = !isTransparent
			window.backgroundColor = isTransparent ? .clear : .windowBackgroundColor
			// See-through, but still an ordinary window that others can cover.
			window.level = .normal
		}
	}
}
