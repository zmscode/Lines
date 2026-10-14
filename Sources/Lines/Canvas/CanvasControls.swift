import SwiftUI

/// Round zoom buttons floating at the canvas's bottom right. The tools
/// palette is on the left and the minimap (drawn by the canvas page) at the
/// bottom left.
struct CanvasControls: View {
	var controller: CanvasController

	var body: some View {
		ZStack {
			ZoomButtons(controller: controller)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		}
		.padding(12)
	}
}

private struct ZoomButtons: View {
	var controller: CanvasController

	var body: some View {
		FloatingStrip {
			button("Zoom In", "plus.magnifyingglass", help: "Zoom In (⌘+)") {
				controller.zoom(by: 1.25)
			}
			button("Zoom Out", "minus.magnifyingglass", help: "Zoom Out (⌘−)") {
				controller.zoom(by: 0.8)
			}
			StripDivider()
			button(
				controller.isFitted ? "Actual Size" : "Zoom to Fit",
				controller.isFitted
					? "1.magnifyingglass" : "arrow.up.left.and.down.right.magnifyingglass",
				help: controller.isFitted ? "Actual Size (⌘0)" : "Zoom to Fit (⌘9)"
			) {
				if controller.isFitted { controller.setZoom(1) } else { controller.zoomToFit() }
			}
		}
	}

	private func button(
		_ title: String, _ symbol: String, help: String, action: @escaping () -> Void
	) -> some View {
		Button(title, systemImage: symbol, action: action)
			.buttonStyle(.icon(size: ToolPalette.buttonSize))
			.help(help)
	}
}

/// The canvas background swatch at the foot of the tools palette, like the
/// colour swatches at the bottom of Photoshop's toolbar.
struct BackgroundPill: View {
	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.customColourKey) private var customColour = "#f2a65a"
	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			Label {
				Text("Canvas Background")
			} icon: {
				BackgroundSwatch(background: background, customColour: customColour)
					.frame(width: 18, height: 18)
			}
		}
		.buttonStyle(.icon(size: ToolPalette.buttonSize))
		.help("Canvas background: \(background.title)")
		.accessibilityLabel("Canvas background")
		.accessibilityValue(background.title)
		.popover(isPresented: $isPresented, arrowEdge: .trailing) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Background").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
				HStack(spacing: 10) {
					ForEach(CanvasBackground.swatches) { option in
						Button {
							background = option
						} label: {
							BackgroundSwatch(background: option, customColour: customColour)
								.frame(width: 26, height: 26)
								.overlay {
									Circle().strokeBorder(
										background == option
											? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
										lineWidth: 2
									)
									.padding(-4)
								}
						}
						.buttonStyle(.plain)
						.help(option.title)
						.accessibilityLabel(option.title)
						.accessibilityAddTraits(background == option ? .isSelected : [])
					}
				}
				if background == .custom {
					ColourPickerPopover(
						initial: CSSColor.parse(customColour) ?? .orange, opacity: 1,
						documentColours: [],
						onPick: { hex, _ in customColour = hex }, onNone: {}, allowsNone: false
					)
					.padding(-14)
				}
			}
			.padding(14)
		}
	}
}

/// A round sample of a canvas background.
struct BackgroundSwatch: View {
	var background: CanvasBackground
	var customColour: String

	var body: some View {
		ZStack {
			switch background {
			case .checkerboard, .transparent:
				Swatch(colour: nil, opacity: 1, isNone: false, showsSlash: false)
			case .white: Color.white
			case .grey: Color(white: 0.56)
			case .black: Color.black
			case .custom: CSSColor.parse(customColour) ?? .orange
			case .window: Color(nsColor: .windowBackgroundColor)
			}
		}
		.clipShape(.circle)
		.overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
	}
}
