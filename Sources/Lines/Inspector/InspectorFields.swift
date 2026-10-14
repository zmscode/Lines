import SwiftUI

/// A text field that commits when you press Return or move focus away,
/// mirroring how inspector fields behave in Keynote and Pages.
struct AttributeField: View {
	var title: String
	var value: String
	var prompt: String? = nil
	var axis: Axis = .horizontal
	var monospacedTitle = false
	var commit: (String) -> Void

	@State private var draft = ""
	@FocusState private var focused: Bool

	var body: some View {
		TextField(text: $draft, prompt: prompt.map { Text($0) }, axis: axis) {
			Text(title).font(monospacedTitle ? .body.monospaced() : .body)
		}
		.focused($focused)
		.onAppear { draft = value }
		.onChange(of: value) { _, new in if !focused { draft = new } }
		.onChange(of: focused) { _, isFocused in if !isFocused { send() } }
		.onSubmit(send)
	}

	private func send() {
		if draft != value { commit(draft) }
	}
}

/// A compact labeled numeric field for the geometry grid.
struct NumberField: View {
	var name: String
	var value: String
	var commit: (String) -> Void

	@State private var draft = ""
	@FocusState private var focused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			TextField(name, text: $draft, prompt: Text("—"))
				.labelsHidden()
				.textFieldStyle(.roundedBorder)
				.monospacedDigit()
				.multilineTextAlignment(.trailing)
				.focused($focused)
				.onSubmit(send)
				.onAppear { draft = value }
				.onChange(of: value) { _, new in if !focused { draft = new } }
				.onChange(of: focused) { _, isFocused in if !isFocused { send() } }
			Text(Self.label(name))
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
		}
	}

	private func send() {
		if draft != value { commit(draft) }
	}

	static func label(_ name: String) -> String {
		switch name {
		case "x", "cx", "x1": "X"
		case "y", "cy", "y1": "Y"
		case "x2": "X2"
		case "y2": "Y2"
		case "r": "Radius"
		case "rx": "Radius X"
		case "ry": "Radius Y"
		case "font-size": "Size"
		default: name.prefix(1).uppercased() + name.dropFirst()
		}
	}
}

struct PaintRow: View {
	var title: String
	var value: String?
	var opacity: String?
	var controller: CanvasController
	var attribute: String

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 8) {
				AttributeField(
					title: title, value: value ?? "", prompt: attribute == "fill" ? "Black" : "None"
				) {
					$0.isEmpty
						? controller.removeAttribute(attribute)
						: controller.setAttribute(attribute, $0)
				}
				.labelsHidden()
				.frame(maxWidth: 110)
				ColourWell(
					title: title, value: value ?? (attribute == "fill" ? "black" : "none"),
					opacity: opacity.flatMap(Double.init) ?? 1,
					documentColours: documentColours,
					onPick: { hex, alpha in
						controller.setPaint(attribute, color: hex, opacity: alpha, coalesce: true)
					},
					onNone: { controller.setAttribute(attribute, "none") }
				)
			}
		}
	}

	/// Distinct plain colours used for fills in the drawing.
	private var documentColours: [String] {
		var seen = Set<String>()
		return controller.outline.compactMap { item -> String? in
			guard let fill = item.fill, let colour = CSSColor.parse(fill), fill != "none" else {
				return nil
			}
			let hex = CSSColor.hex(colour)
			return seen.insert(hex).inserted ? hex : nil
		}
		.prefix(16)
		.map { $0 }
	}
}

struct OpacityRow: View {
	var value: String?
	var controller: CanvasController

	var body: some View {
		let opacity = value.flatMap(Double.init) ?? 1
		LabeledContent("Opacity") {
			HStack {
				Slider(
					value: Binding(
						get: { opacity },
						set: {
							controller.setAttribute(
								"opacity", String(format: "%.2f", $0), coalesce: true)
						}
					), in: 0...1)
				Text(opacity, format: .percent.precision(.fractionLength(0)))
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.frame(width: 40, alignment: .trailing)
			}
		}
	}
}

struct NewAttributeRow: View {
	var controller: CanvasController
	@State private var name = ""
	@State private var value = ""
	@FocusState private var nameFocused: Bool

	var body: some View {
		HStack {
			TextField("Name", text: $name, prompt: Text("New attribute"))
				.labelsHidden()
				.focused($nameFocused)
				.font(.body.monospaced())
			TextField("Value", text: $value, prompt: Text("Value"))
				.labelsHidden()
				.onSubmit(add)
			Button("Add Attribute", systemImage: "plus.circle.fill", action: add)
				.labelStyle(.iconOnly)
				.buttonStyle(.borderless)
				.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
		}
	}

	private func add() {
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return }
		controller.setAttribute(trimmed, value)
		name = ""
		value = ""
		nameFocused = true
	}
}
