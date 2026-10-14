import AppKit
import SwiftUI

/// The source editor with a small header for formatting and copying.
struct CodePanel: View {
	var document: SVGDocument
	var controller: CanvasController
	var fontSize: Double
	var wrapsLines: Bool
	var theme: SyntaxTheme

	@State private var copied = false

	var body: some View {
		SourceEditor(
			document: document, controller: controller, fontSize: fontSize,
			wrapsLines: wrapsLines, theme: theme
		)
		.safeAreaInset(edge: .top, spacing: 0) {
			// The same round glass buttons as the canvas, on the editor's own
			// background, so the header reads as part of the editor.
			HStack(spacing: 8) {
				Text("Source")
					.font(.headline)
					.foregroundStyle(.secondary)
				Spacer()
				GlassEffectContainer(spacing: 6) {
					HStack(spacing: 6) {
						button("Smaller Text", "textformat.size.smaller", help: "Smaller text (⌘−)")
						{
							SourceEditor.adjustFontSize(by: -1)
						}
						button("Larger Text", "textformat.size.larger", help: "Larger text (⌘+)") {
							SourceEditor.adjustFontSize(by: 1)
						}
						button("Format", "text.alignleft", help: "Re-indent the markup (⌃I)") {
							controller.formatDocument()
						}
						button(
							copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc",
							help: copied ? "Copied" : "Copy all the source"
						) {
							NSPasteboard.general.clearContents()
							NSPasteboard.general.setString(document.text, forType: .string)
							withAnimation { copied = true }
							Task {
								try? await Task.sleep(for: .seconds(1.5))
								withAnimation { copied = false }
							}
						}
						.contentTransition(.symbolEffect(.replace))
					}
				}
			}
			.padding(.leading, 14)
			.padding(.trailing, 10)
			.padding(.vertical, 8)
			.background(Color(nsColor: theme.background))
		}
	}

	private func button(
		_ title: String, _ symbol: String, help: String, action: @escaping () -> Void
	) -> some View {
		Button(title, systemImage: symbol, action: action)
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.help(help)
	}
}
