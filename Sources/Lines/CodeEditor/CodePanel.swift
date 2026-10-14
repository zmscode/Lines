import AppKit
import SwiftUI

/// The source editor with a small header for formatting and copying.
struct CodePanel: View {
	var document: SVGDocument
	var controller: CanvasController
	var fontSize: Double
	var wrapsLines: Bool
	var theme: SyntaxTheme
	var fontName = ""

	@State private var copied = false

	var close: () -> Void = {}

	var body: some View {
		VStack(spacing: 0) {
			// The floating panels' header: title, icon buttons, close.
			HStack(spacing: 2) {
				Text("Source")
					.font(.headline)
				Spacer()
				button("Smaller Text", "textformat.size.smaller", help: "Smaller text (⌘−)") {
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
				Button("Close", systemImage: "xmark", action: close)
					.buttonStyle(.icon(size: 24))
					.help("Hide Code (⌘2)")
					.padding(.leading, 4)
			}
			.padding(.leading, 14)
			.padding(.trailing, 8)
			.padding(.top, 10)
			.padding(.bottom, 6)

			SourceEditor(
				document: document, controller: controller, fontSize: fontSize,
				wrapsLines: wrapsLines, theme: theme, fontName: fontName
			)
			.clipShape(.rect(cornerRadius: 12, style: .continuous))
			.padding([.horizontal, .bottom], 6)
		}
		.floatingPanelChrome()
	}

	private func button(
		_ title: String, _ symbol: String, help: String, action: @escaping () -> Void
	) -> some View {
		Button(title, systemImage: symbol, action: action)
			.buttonStyle(.icon(size: 26))
			.help(help)
	}
}
