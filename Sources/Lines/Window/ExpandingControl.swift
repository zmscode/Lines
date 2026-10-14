import SwiftUI

/// A single toolbar icon that expands in place to reveal related controls,
/// and collapses again when clicked (or with Escape).
struct ExpandingControl<Content: View>: View {
	var title: String
	var systemImage: String
	@Binding var isExpanded: Bool
	@ViewBuilder var content: Content

	var body: some View {
		HStack(spacing: 0) {
			Button(
				isExpanded ? "Hide \(title) Controls" : title,
				systemImage: isExpanded ? "chevron.backward" : systemImage
			) {
				withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
			}
			.help(isExpanded ? "Collapse" : title)
			if isExpanded {
				content
					.transition(.asymmetric(insertion: .push(from: .leading), removal: .opacity))
			}
		}
		.labelStyle(.iconOnly)
		.onExitCommand {
			if isExpanded { withAnimation(.snappy(duration: 0.25)) { isExpanded = false } }
		}
	}
}
