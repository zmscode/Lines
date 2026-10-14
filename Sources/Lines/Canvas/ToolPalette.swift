import AppKit
import SwiftUI

/// The tools palette: a vertical strip on the canvas like Photoshop's.
/// Pick a shape tool and drag on the canvas to draw; slots with variants
/// remember the last one used, and their corner arrow lists the others.
struct ToolPalette: View {
	var controller: CanvasController

	static let buttonSize: CGFloat = 34
	static let width: CGFloat = buttonSize + 12

	/// The variant each multi-tool slot shows, by slot index.
	@State private var chosen: [Int: CanvasTool] = [:]

	var body: some View {
		VStack(spacing: 2) {
			ForEach(Array(CanvasTool.groups.enumerated()), id: \.offset) { index, group in
				slot(index, group)
				if index == 1 { divider }  // navigation tools, then drawing tools
			}
			divider
			PaletteButton(
				title: "Image", symbol: "photo.badge.plus", help: "Place an image…",
				isSelected: false
			) {
				chooseImage()
			}
			divider
			BackgroundPill()
		}
		.padding(6)
		.glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
		.shadow(color: .black.opacity(0.14), radius: 10, y: 4)
		.onChange(of: controller.tool) { _, tool in
			// Keep the slot showing whichever variant was picked (by key or menu).
			if let index = CanvasTool.groups.firstIndex(where: { $0.contains(tool) }) {
				chosen[index] = tool
			}
		}
	}

	private var divider: some View {
		Divider().frame(width: Self.buttonSize - 10).padding(.vertical, 3)
	}

	@ViewBuilder
	private func slot(_ index: Int, _ group: [CanvasTool]) -> some View {
		let current = chosen[index] ?? group[0]
		let isSelected = group.contains(controller.tool)
		PaletteButton(
			title: current.title, symbol: current.symbol, help: help(for: current),
			isSelected: isSelected, hasVariants: group.count > 1
		) {
			controller.setTool(current)
		}
		.contextMenu {
			if group.count > 1 {
				ForEach(group) { tool in
					Button(tool.title, systemImage: tool.symbol) {
						chosen[index] = tool
						controller.setTool(tool)
					}
				}
			}
		}
		.overlay(alignment: .bottomTrailing) {
			if group.count > 1 {
				Menu {
					ForEach(group) { tool in
						Button(tool.title, systemImage: tool.symbol) {
							chosen[index] = tool
							controller.setTool(tool)
						}
					}
				} label: {
					Image(systemName: "arrowtriangle.down.right.fill")
						.font(.system(size: 6))
						.foregroundStyle(.secondary)
						.frame(width: 12, height: 12)
						.contentShape(.rect)
				}
				.menuStyle(.button)
				.buttonStyle(.plain)
				.menuIndicator(.hidden)
				.fixedSize()
				.help("More \(group[0].title.lowercased()) tools")
			}
		}
	}

	private func help(for tool: CanvasTool) -> String {
		let action: String
		switch tool {
		case .select: action = "Select and move elements"
		case .hand: action = "Pan the canvas"
		case .text: action = "Click to add text"
		default: action = "Drag to draw a \(tool.title.lowercased()) (Shift keeps it even)"
		}
		return tool.key.map { "\(tool.title) (\($0)) — \(action)" } ?? "\(tool.title) — \(action)"
	}

	private func chooseImage() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .heic, .svg]
		panel.message = "Choose an image to place in the drawing."
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

/// One square tool button, highlighted when its tool is active.
private struct PaletteButton: View {
	var title: String
	var symbol: String
	var help: String
	var isSelected: Bool
	var hasVariants = false
	var action: () -> Void

	@State private var isHovered = false

	var body: some View {
		Button(action: action) {
			Image(systemName: symbol)
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
				.frame(width: ToolPalette.buttonSize, height: ToolPalette.buttonSize)
				.background(
					isSelected
						? AnyShapeStyle(.tint.opacity(0.18))
						: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
					in: .rect(cornerRadius: 8, style: .continuous)
				)
				.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		.help(help)
		.accessibilityLabel(title)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
}
