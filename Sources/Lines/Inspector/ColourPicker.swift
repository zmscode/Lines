import AppKit
import ColourPickerMaker
import SwiftUI

/// A swatch that opens Lines' colour picker in a popover, in place of the
/// system colour panel.
struct ColourWell: View {
	var title: String
	var value: String?
	var opacity: Double
	var documentColours: [String]
	var onPick: (_ hex: String, _ opacity: Double) -> Void
	var onNone: () -> Void

	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			Swatch(colour: CSSColor.parse(value), opacity: opacity, isNone: value == "none")
				.frame(width: 38, height: 22)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(title)
		.accessibilityValue(value ?? "Default")
		.help("Choose \(title.lowercased()) colour")
		.popover(isPresented: $isPresented, arrowEdge: .leading) {
			ColourPickerPopover(
				initial: CSSColor.parse(value) ?? .black, opacity: opacity,
				documentColours: documentColours, onPick: onPick,
				onNone: {
					onNone()
					isPresented = false
				}
			)
		}
	}
}

/// Hue × saturation canvas, brightness and opacity sliders (from
/// ColourPickerMaker), a hex field, and the colours already in the drawing.
struct ColourPickerPopover: View {
	var documentColours: [String]
	var onPick: (_ hex: String, _ opacity: Double) -> Void
	var onNone: () -> Void
	var allowsNone = true

	@State private var values: ColourModel.HSBAValues
	@State private var hexDraft: String
	@FocusState private var hexFocused: Bool

	private let width: CGFloat = 232

	init(
		initial: Color, opacity: Double, documentColours: [String],
		onPick: @escaping (String, Double) -> Void, onNone: @escaping () -> Void,
		allowsNone: Bool = true
	) {
		let c = NSColor(initial).usingColorSpace(.sRGB) ?? .black
		_values = State(
			initialValue: (
				Double(c.hueComponent), Double(c.saturationComponent),
				Double(c.brightnessComponent), opacity
			))
		_hexDraft = State(initialValue: CSSColor.hex(initial).dropFirst().uppercased())
		self.documentColours = documentColours
		self.onPick = onPick
		self.onNone = onNone
		self.allowsNone = allowsNone
	}

	private var binding: Binding<ColourModel.HSBAValues> {
		Binding(
			get: { values },
			set: { new in
				values = new
				hexDraft = String(hex.dropFirst()).uppercased()
				onPick(hex, new.alpha)
			})
	}

	private var colour: Color {
		Color(hue: values.hue, saturation: values.saturation, brightness: values.brightness)
	}

	private var hex: String { CSSColor.hex(colour) }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HSBACanvasView(data: HSBAData(values: binding, parameters: (.hue, .saturation)))
				.frame(width: width, height: width)
				.clipShape(.rect(cornerRadius: 10, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
						.separator, lineWidth: 0.5)
				}
				.accessibilityLabel("Hue and saturation")

			sliderRow("Brightness", parameter: .brightness)
			sliderRow("Opacity", parameter: .alpha)

			HStack(spacing: 8) {
				Swatch(colour: colour, opacity: values.alpha, isNone: false)
					.frame(width: 30, height: 22)
				TextField("Hex", text: $hexDraft, prompt: Text("RRGGBB"))
					.textFieldStyle(.roundedBorder)
					.font(.body.monospaced())
					.focused($hexFocused)
					.onSubmit(applyHex)
					.onChange(of: hexFocused) { _, focused in if !focused { applyHex() } }
				Text(values.alpha, format: .percent.precision(.fractionLength(0)))
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.frame(width: 40, alignment: .trailing)
			}

			if !documentColours.isEmpty {
				VStack(alignment: .leading, spacing: 6) {
					Text("In This Drawing")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					LazyVGrid(
						columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8),
						spacing: 6
					) {
						ForEach(documentColours, id: \.self) { css in
							Button {
								if let c = CSSColor.parse(css) { set(c) }
							} label: {
								Swatch(colour: CSSColor.parse(css), opacity: 1, isNone: false)
									.frame(width: 22, height: 22)
							}
							.buttonStyle(.plain)
							.help(css)
						}
					}
				}
			}

			if allowsNone {
				Divider()

				Button("No Colour", systemImage: "circle.slash", action: onNone)
					.buttonStyle(.borderless)
			}
		}
		.padding(14)
		.frame(width: width + 28)
	}

	private func sliderRow(_ title: String, parameter: Parameter) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title).font(.caption).foregroundStyle(.secondary)
			HSBASliderView(
				data: HSBASliderData(
					values: binding, parameter: parameter, orientation: .horizontal),
				thickness: 16, length: width
			)
			.frame(width: width, height: 20)
			.accessibilityLabel(title)
		}
	}

	private func applyHex() {
		if let c = CSSColor.parse(
			"#" + hexDraft.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
		{
			set(c)
		} else {
			hexDraft = String(hex.dropFirst()).uppercased()
		}
	}

	private func set(_ c: Color) {
		let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
		binding.wrappedValue = (
			Double(ns.hueComponent), Double(ns.saturationComponent),
			Double(ns.brightnessComponent), values.alpha
		)
	}
}

/// A colour sample over a checkerboard, with a slash for "none".
struct Swatch: View {
	var colour: Color?
	var opacity: Double
	var isNone: Bool
	/// Whether a missing colour is drawn with the "none" slash.
	var showsSlash = true

	var body: some View {
		ZStack {
			TransparencyCheckerboardView(tileSize: 5, colour1: .white, colour2: Color(white: 0.82))
			if let colour, !isNone {
				colour.opacity(opacity)
			}
			if isNone || (colour == nil && showsSlash) {
				GeometryReader { geo in
					Path { p in
						p.move(to: CGPoint(x: geo.size.width, y: 0))
						p.addLine(to: CGPoint(x: 0, y: geo.size.height))
					}
					.stroke(.red, lineWidth: 1.5)
				}
			}
		}
		.clipShape(.rect(cornerRadius: 5, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
				.separator, lineWidth: 1)
		}
	}
}
