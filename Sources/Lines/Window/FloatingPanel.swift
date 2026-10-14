import SwiftUI

/// A panel that floats over the viewer on Liquid Glass, like the inspectors in
/// Freeform and Preview, instead of a sidebar that pushes the content aside.
struct FloatingPanel<Content: View>: View {
	var title: String?
	var close: () -> Void
	@ViewBuilder var content: Content

	var body: some View {
		VStack(spacing: 0) {
			if let title {
				HStack {
					Text(title)
						.font(.headline)
					Spacer()
					closeButton
				}
				.padding(.leading, 14)
				.padding(.trailing, 8)
				.padding(.top, 10)
				.padding(.bottom, 4)
			}
			content
				.frame(maxHeight: .infinity, alignment: .top)
		}
		.overlay(alignment: .topTrailing) {
			if title == nil {
				closeButton.padding(8)
			}
		}
		.frame(maxHeight: .infinity, alignment: .top)
		.floatingPanelChrome()
	}

	private var closeButton: some View {
		Button("Close", systemImage: "xmark", action: close)
			.buttonStyle(.icon(size: 24))
			.help("Close")
	}
}

extension View {
	/// The rounded Liquid Glass card every floating panel sits on.
	func floatingPanelChrome() -> some View {
		clipShape(.rect(cornerRadius: 18, style: .continuous))
			.glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
			.shadow(color: .black.opacity(0.18), radius: 16, y: 6)
	}
}
