import SwiftUI

/// Controls that float over the canvas, so the toolbar can stay minimal:
/// a background pill at the top left and round zoom buttons at the bottom
/// right. The minimap (drawn by the canvas page) sits at the bottom left.
struct CanvasControls: View {
	var controller: CanvasController

	var body: some View {
		ZStack {
			BackgroundPill()
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			ZoomButtons(controller: controller)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		}
		.padding(12)
	}
}

private struct ZoomButtons: View {
	var controller: CanvasController

	var body: some View {
		GlassEffectContainer(spacing: 8) {
			VStack(spacing: 8) {
				button("Zoom In", "plus.magnifyingglass") { controller.zoom(by: 1.25) }
				button("Zoom Out", "minus.magnifyingglass") { controller.zoom(by: 0.8) }
				button(
					controller.isFitted ? "Actual Size" : "Zoom to Fit",
					controller.isFitted ? "1.magnifyingglass" : "arrow.counterclockwise"
				) {
					if controller.isFitted { controller.setZoom(1) } else { controller.zoomToFit() }
				}
			}
		}
	}

	private func button(_ title: String, _ symbol: String, action: @escaping () -> Void)
		-> some View
	{
		Button(title, systemImage: symbol, action: action)
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.controlSize(.large)
			.help(title)
	}
}

/// Shows the current canvas background; click to switch between the quick
/// choices or pick a custom colour.
private struct BackgroundPill: View {
	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.customColourKey) private var customColour = "#f2a65a"
	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			HStack(spacing: 6) {
				BackgroundSwatch(background: background, customColour: customColour)
					.frame(width: 16, height: 16)
				Image(systemName: "chevron.down")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.glass)
		.help("Canvas background: \(background.title)")
		.accessibilityLabel("Canvas background")
		.accessibilityValue(background.title)
		.popover(isPresented: $isPresented, arrowEdge: .bottom) {
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
