import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Insert popover: a grid of shapes like Keynote's shape picker, plus
/// lines, text, groups and images. New elements land in the middle of the
/// drawing (inside the selected group, if any) and are selected.
struct InsertPalette: View {
	var controller: CanvasController
	var dismiss: () -> Void

	@State private var hovered: ShapeKind?

	private let columns = Array(repeating: GridItem(.fixed(72), spacing: 8), count: 4)

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			section("Shapes", kinds: ShapeKind.allCases.filter { $0.section == 0 })
			section("Lines", kinds: ShapeKind.allCases.filter { $0.section == 1 })
			VStack(alignment: .leading, spacing: 8) {
				header("Other")
				LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
					ForEach(ShapeKind.allCases.filter { $0.section == 2 }) { tile($0) }
					imageTile
				}
			}
		}
		.padding(14)
	}

	private func section(_ title: String, kinds: [ShapeKind]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			header(title)
			LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
				ForEach(kinds) { tile($0) }
			}
		}
	}

	private func header(_ title: String) -> some View {
		Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
	}

	private func tile(_ kind: ShapeKind) -> some View {
		PaletteTile(title: kind.title, systemImage: kind.symbol, filled: kind.section == 0) {
			controller.addShape(kind)
			dismiss()
		}
	}

	private var imageTile: some View {
		PaletteTile(title: "Image…", systemImage: "photo.badge.plus", filled: false) {
			dismiss()
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .heic, .svg]
			panel.message = "Choose an image to embed in the drawing."
			let pick: (NSApplication.ModalResponse) -> Void = { response in
				if response == .OK, let url = panel.url { controller.addImage(from: url) }
			}
			if let window = controller.webView?.window {
				panel.beginSheetModal(for: window, completionHandler: pick)
			} else {
				pick(panel.runModal())
			}
		}
	}
}

private struct PaletteTile: View {
	var title: String
	var systemImage: String
	var filled: Bool
	var action: () -> Void

	@State private var isHovered = false

	var body: some View {
		Button(action: action) {
			VStack(spacing: 6) {
				Image(systemName: filled ? systemImage + ".fill" : systemImage)
					.font(.system(size: 24, weight: .regular))
					.symbolRenderingMode(.hierarchical)
					.foregroundStyle(.tint)
					.frame(height: 30)
				Text(title)
					.font(.caption2)
					.lineLimit(2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
			}
			.frame(width: 72, height: 70)
			.background(
				isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
				in: .rect(cornerRadius: 10, style: .continuous)
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		.help("Insert \(title.lowercased())")
		.accessibilityLabel("Insert \(title)")
	}
}
