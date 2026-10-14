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
			HStack(spacing: 4) {
				Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
					.font(.callout.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				ControlGroup {
					Button("Smaller Text", systemImage: "textformat.size.smaller") {
						SourceEditor.adjustFontSize(by: -1)
					}
					Button("Larger Text", systemImage: "textformat.size.larger") {
						SourceEditor.adjustFontSize(by: 1)
					}
				}
				.labelStyle(.iconOnly)
				.fixedSize()
				.help("Text size (pinch, or ⌘+ and ⌘− while editing)")
				Button("Format", systemImage: "text.alignleft") { controller.formatDocument() }
					.help("Re-indent the markup (⌃I)")
				Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
				{
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(document.text, forType: .string)
					withAnimation { copied = true }
					Task {
						try? await Task.sleep(for: .seconds(1.5))
						withAnimation { copied = false }
					}
				}
				.help("Copy all the source")
				.contentTransition(.symbolEffect(.replace))
			}
			.labelStyle(.titleAndIcon)
			.buttonStyle(.borderless)
			.controlSize(.small)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(.bar)
			.overlay(alignment: .bottom) { Divider() }
		}
	}
}
