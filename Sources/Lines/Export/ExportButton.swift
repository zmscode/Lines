import AppKit
import SwiftUI

/// The toolbar's export button: a popover of tiles, one per format, plus
/// copying, printing and sharing, instead of a plain menu.
struct ExportButton: View {
	var controller: CanvasController
	var document: SVGDocument

	@AppStorage("export.format") private var format: ExportFormat = .png
	@State private var isPresented = false
	@State private var copied = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			Label("Export", systemImage: "square.and.arrow.up")
		}
		.help("Export, print or share the drawing (⇧⌘E)")
		.popover(isPresented: $isPresented, arrowEdge: .bottom) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Export As")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				HStack(spacing: 8) {
					ForEach(ExportFormat.allCases) { option in
						FormatTile(format: option) {
							format = option
							isPresented = false
							controller.isExporting = true
						}
					}
				}
				Divider()
				HStack(spacing: 8) {
					ActionTile(
						title: copied ? "Copied" : "Copy SVG",
						symbol: copied ? "checkmark" : "doc.on.doc"
					) {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(document.text, forType: .string)
						withAnimation { copied = true }
						Task {
							try? await Task.sleep(for: .seconds(1.2))
							withAnimation { copied = false }
						}
					}
					ActionTile(title: "Print", symbol: "printer") {
						isPresented = false
						controller.printDrawing()
					}
					ShareLink(
						item: SharedDrawing(name: controller.documentName, controller: controller),
						preview: SharePreview(
							controller.documentName, image: Image(systemName: "photo"))
					) {
						TileLabel(title: "Share", symbol: "square.and.arrow.up")
					}
					.buttonStyle(TileButtonStyle())
					if let url = document.configuration?.fileURL {
						ShareLink(item: url) {
							TileLabel(title: "Share File", symbol: "doc")
						}
						.buttonStyle(TileButtonStyle())
					}
				}
			}
			.padding(14)
		}
	}
}

private struct FormatTile: View {
	var format: ExportFormat
	var action: () -> Void

	private var subtitle: String {
		switch format {
		case .svg: "Vector"
		case .png: "Transparent"
		case .jpeg: "Smallest"
		case .pdf: "Print-ready"
		}
	}

	private var tint: Color {
		switch format {
		case .svg: Brand.accent
		case .png: .blue
		case .jpeg: .green
		case .pdf: .red
		}
	}

	var body: some View {
		Button(action: action) {
			VStack(spacing: 6) {
				ZStack {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(tint.opacity(0.16))
					Text(format.title)
						.font(.system(size: 13, weight: .bold, design: .rounded))
						.foregroundStyle(tint)
				}
				.frame(width: 56, height: 44)
				Text(subtitle)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			.frame(width: 72)
			.padding(.vertical, 6)
		}
		.buttonStyle(TileButtonStyle())
		.help("Export as \(format.title)…")
	}
}

private struct ActionTile: View {
	var title: String
	var symbol: String
	var action: () -> Void

	var body: some View {
		Button(action: action) { TileLabel(title: title, symbol: symbol) }
			.buttonStyle(TileButtonStyle())
			.help(title)
	}
}

private struct TileLabel: View {
	var title: String
	var symbol: String

	var body: some View {
		VStack(spacing: 4) {
			Image(systemName: symbol)
				.font(.system(size: 15, weight: .medium))
				.frame(height: 20)
				.contentTransition(.symbolEffect(.replace))
			Text(title).font(.caption)
		}
		.frame(width: 72)
		.padding(.vertical, 6)
	}
}

/// A tile that tints on hover, like the app's icon buttons.
private struct TileButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		TileBody(configuration: configuration)
	}

	private struct TileBody: View {
		var configuration: ButtonStyleConfiguration
		@State private var isHovered = false

		var body: some View {
			configuration.label
				.background(
					configuration.isPressed
						? AnyShapeStyle(.quaternary.opacity(1.6))
						: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
					in: .rect(cornerRadius: 10, style: .continuous)
				)
				.contentShape(.rect)
				.onHover { isHovered = $0 }
		}
	}
}
