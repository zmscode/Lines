import AppKit
import SwiftUI

/// Colours from the app icon: a graphite tile with an orange curve's handles.
/// The accent is a slightly muted version of the icon's orange, so it reads as an
/// accent rather than a highlighter.
enum Brand {
	/// The icon's orange, between its gradient's two stops. Brighter in dark mode.
	static let accent = Color(
		nsColor: NSColor(name: "LinesAccent") { appearance in
			appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
				? NSColor(srgbRed: 0.941, green: 0.569, blue: 0.341, alpha: 1)  // #F09157
				: NSColor(srgbRed: 0.851, green: 0.459, blue: 0.247, alpha: 1)  // #D9753F
		})

}
