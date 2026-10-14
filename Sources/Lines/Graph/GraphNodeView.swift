import SwiftFlow
import SwiftUI

/// A node in the element graph: a header, then the element's inputs and
/// values. Values can be clicked to edit them in place.
struct GraphNodeView: View {
	var node: Node<GraphNodeData>
	var controller: CanvasController? = nil

	static let width: CGFloat = 220
	static let headerHeight: CGFloat = 44
	static let rowHeight: CGFloat = 22

	static func size(for data: GraphNodeData) -> CGSize {
		var h = headerHeight
		let rows =
			data.inputs.count + data.valueRows.count + partRows(data) + animationRows(data)
			+ data.infoRows.count
		if rows > 0 { h += CGFloat(rows) * rowHeight + 10 }
		if data.kind == .paint, !data.parts.isEmpty { h += 26 }  // the gradient strip
		return CGSize(width: width, height: h)
	}

	private static func partRows(_ data: GraphNodeData) -> Int {
		switch data.kind {
		case .paint: data.parts.isEmpty ? 0 : 1
		case .filter: data.parts.count
		default: 0
		}
	}

	private static func animationRows(_ data: GraphNodeData) -> Int {
		data.kind == .animation ? 4 : 0
	}

	var body: some View {
		let data = node.data
		VStack(alignment: .leading, spacing: 0) {
			header(data)
			if Self.size(for: data).height > Self.headerHeight {
				Divider()
				VStack(alignment: .leading, spacing: 0) {
					switch data.kind {
					case .paint: gradientRows(data)
					case .filter: filterRows(data)
					case .animation: animationRows(data)
					default:
						ForEach(data.inputs, id: \.self) { inputRow($0, data: data) }
						ForEach(data.valueRows, id: \.self) { valueRow($0, data: data) }
					}
					ForEach(data.infoRows, id: \.self) { info in
						HStack(spacing: 6) {
							Text(info.label).font(.caption.monospaced()).foregroundStyle(.secondary)
							Spacer(minLength: 4)
							Text(info.value)
								.font(.caption)
								.foregroundStyle(
									info.label == "used by" && data.usedBy == 0
										? AnyShapeStyle(.orange) : AnyShapeStyle(.primary)
								)
								.lineLimit(1)
								.truncationMode(.middle)
						}
						.frame(height: Self.rowHeight)
						.padding(.horizontal, 10)
						.help("\(info.label): \(info.value)")
					}
				}
				.padding(.vertical, 5)
			}
		}
		.frame(width: Self.width, alignment: .leading)
		.frame(height: Self.size(for: data).height, alignment: .top)
		.background(.background, in: .rect(cornerRadius: 10, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(
					node.selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
					lineWidth: node.selected ? 2 : 1)
		}
		// Hidden anchors for structure and animation lines; they can't start drags.
		.overlay(alignment: .top) {
			Handle(
				nodeId: node.id, id: "parent", type: .target, position: .top, isConnectable: false
			)
			.offset(y: -6)
			.opacity(0)
		}
		.overlay(alignment: .bottom) {
			Handle(
				nodeId: node.id, id: "children", type: .source, position: .bottom,
				isConnectable: false
			)
			.offset(y: 6)
			.opacity(0)
		}
		.overlay(alignment: .leading) {
			if data.kind == .animation {
				Handle(
					nodeId: node.id, id: "animated", type: .target, position: .left,
					color: .indigo, isConnectable: false
				)
				.offset(x: -6)
			}
		}
		.overlay(alignment: .trailing) {
			if data.hasOutput {
				Handle(nodeId: node.id, id: "ref", type: .source, position: .right, color: tint)
					.offset(x: 6)
					.help(
						"Drag to an input to use this \(InspectorView.elementName(for: data.tag).lowercased())"
					)
			} else if data.hasAnimations {
				Handle(
					nodeId: node.id, id: "animations", type: .source, position: .right,
					color: .indigo, isConnectable: false
				)
				.offset(x: 6)
			}
		}
		.contextMenu { menu(data) }
		.modifier(NodeHoverPreview(data: data, controller: controller))
		.shadow(color: .black.opacity(0.08), radius: 3, y: 1)
		.opacity(data.isHidden ? 0.6 : 1)
	}

	// MARK: Header

	private func header(_ data: GraphNodeData) -> some View {
		HStack(spacing: 8) {
			Image(systemName: InspectorView.symbol(for: data.tag, isRoot: false))
				.foregroundStyle(tint)
				.frame(width: 18)
			VStack(alignment: .leading, spacing: 0) {
				Text(data.name).font(.callout.weight(.semibold)).lineLimit(1)
				Text("<\(data.tag)>").font(.caption.monospaced()).foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
			if data.isHidden {
				Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 10)
		.frame(height: Self.headerHeight)
	}

	// MARK: Rows

	/// An input port with its current value.
	private func inputRow(_ input: String, data: GraphNodeData) -> some View {
		HStack(spacing: 6) {
			Handle(
				nodeId: node.id, id: input, type: .target, position: .left,
				color: data.connected.contains(input) ? Graph.color(for: input) : .gray,
				// Inputs only receive: connections start from an output.
				isConnectable: false
			)
			.offset(x: -6)
			Text(input).font(.caption.monospaced()).foregroundStyle(.secondary)
			Spacer(minLength: 4)
			let value = data.props[input]
			if input == "fill" || input == "stroke" {
				NodeValue(
					kind: .colour, value: value ?? (input == "fill" ? "black" : "none"),
					label: input.capitalized
				) { new in
					edit(input, new, on: data.order)
				}
			} else if let value, let id = Self.referencedID(value) {
				Text("→ \(id)").font(.caption.monospaced()).foregroundStyle(Graph.color(for: input))
					.lineLimit(1)
			}
		}
		.frame(height: Self.rowHeight)
		.padding(.trailing, 8)
	}

	/// A numeric attribute (stroke width, opacity) with an editor.
	private func valueRow(_ name: String, data: GraphNodeData) -> some View {
		HStack(spacing: 6) {
			Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
			Spacer(minLength: 4)
			NodeValue(
				kind: name == "opacity" ? .fraction : .number,
				value: data.props[name] ?? (name == "opacity" ? "1" : "1"), label: name
			) { new in
				edit(name, new, on: data.order)
			}
		}
		.frame(height: Self.rowHeight)
		.padding(.horizontal, 10)
	}

	/// The gradient as a strip, then each stop's colour, editable.
	@ViewBuilder
	private func gradientRows(_ data: GraphNodeData) -> some View {
		let colours = data.parts.map { CSSColor.parse(Self.stopColour($0)) ?? .black }
		RoundedRectangle(cornerRadius: 5, style: .continuous)
			.fill(
				LinearGradient(
					colors: colours.count > 1 ? colours : colours + colours,
					startPoint: .leading, endPoint: .trailing)
			)
			.overlay {
				RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator)
			}
			.frame(height: 16)
			.padding(.horizontal, 10)
			.padding(.bottom, 10)
		if !data.parts.isEmpty {
			HStack(spacing: 6) {
				Text("stops").font(.caption.monospaced()).foregroundStyle(.secondary)
				Spacer(minLength: 4)
				ForEach(data.parts) { stop in
					NodeValue(
						kind: .colour, value: Self.stopColour(stop), label: "Stop", compact: true
					) {
						new in
						edit("stop-color", new, on: stop.order)
					}
				}
			}
			.frame(height: Self.rowHeight)
			.padding(.horizontal, 10)
		}
	}

	/// Each filter effect with its main amount, editable.
	private func filterRows(_ data: GraphNodeData) -> some View {
		ForEach(data.parts) { part in
			HStack(spacing: 6) {
				Text(Self.effectName(part.tag)).font(.caption.weight(.medium))
					.padding(.horizontal, 6).padding(.vertical, 1)
					.background(tint.opacity(0.18), in: .capsule)
				Spacer(minLength: 4)
				if let (name, value) = Self.mainParameter(of: part) {
					Text(name).font(.caption2.monospaced()).foregroundStyle(.tertiary)
					NodeValue(kind: .number, value: value, label: name) { new in
						edit(name, new, on: part.order)
					}
				}
			}
			.frame(height: Self.rowHeight)
			.padding(.horizontal, 10)
		}
	}

	/// What an animation changes, and its timing, editable.
	@ViewBuilder
	private func animationRows(_ data: GraphNodeData) -> some View {
		let p = data.props
		let property =
			data.tag == "animateTransform"
			? (p["type"] ?? "transform") : (p["attributeName"] ?? "—")
		row(
			"animates",
			NodeValue(kind: .text, value: property, label: "Property") { new in
				edit(data.tag == "animateTransform" ? "type" : "attributeName", new, on: data.order)
			})
		let usesValues = p["values"] != nil
		row(
			usesValues ? "values" : "to",
			NodeValue(
				kind: .text, value: usesValues ? p["values"]! : (p["to"] ?? ""),
				label: usesValues ? "Values" : "To"
			) { new in
				edit(usesValues ? "values" : "to", new, on: data.order)
			})
		row(
			"duration",
			NodeValue(kind: .text, value: p["dur"] ?? "", label: "Duration") { new in
				edit("dur", new, on: data.order)
			})
		row(
			"repeat",
			NodeValue(
				kind: .text, value: p["repeatCount"] ?? "once",
				label: "Repeat (a count or indefinite)"
			) { new in
				edit("repeatCount", new == "once" ? nil : new, on: data.order)
			})
	}

	private func row(_ title: String, _ value: NodeValue) -> some View {
		HStack(spacing: 6) {
			Text(title).font(.caption.monospaced()).foregroundStyle(.secondary)
			Spacer(minLength: 4)
			value
		}
		.frame(height: Self.rowHeight)
		.padding(.horizontal, 10)
	}

	private func edit(_ name: String, _ value: String?, on order: Int) {
		controller?.setAttribute(name, value, onOrder: order, coalesce: true)
	}

	// MARK: Menu

	@ViewBuilder
	private func menu(_ data: GraphNodeData) -> some View {
		if let controller {
			Button("Show on Canvas", systemImage: "photo") {
				controller.select(order: data.order)
				controller.layout = .canvas
			}
			if data.kind == .element || data.kind == .group {
				Menu("Add Animation") {
					ForEach(AnimationPreset.allCases) { preset in
						Button(preset.title, systemImage: preset.symbol) {
							controller.addAnimation(preset, toOrder: data.order)
						}
					}
				}
			}
			if let attribute = data.applyAttribute {
				Button("Apply to Selection", systemImage: "wand.and.stars") {
					if let s = controller.selection, !s.isRoot, s.order != data.order {
						controller.setReference(
							order: s.order, attribute: attribute, targetOrder: data.order)
					} else {
						NSSound.beep()
					}
				}
				.disabled(!controller.hasElementSelection)
			}
			Button("Edit in Inspector", systemImage: "slider.horizontal.3") {
				controller.select(order: data.order)
				controller.showsInspector = true
			}
			Button("Remove Its References", systemImage: "link") {
				controller.removeAllReferences(order: data.order)
			}
			.disabled(data.connected.isEmpty)
			Divider()
			Button("Delete", systemImage: "trash", role: .destructive) {
				controller.delete(order: data.order)
			}
		}
	}

	// MARK: Helpers

	private var tint: Color {
		switch node.data.kind {
		case .paint: .orange
		case .clip: .teal
		case .mask: .purple
		case .filter: .pink
		case .symbol, .animation: .indigo
		case .group, .container: .secondary
		case .element: .accentColor
		}
	}

	static func referencedID(_ value: String) -> String? {
		guard let range = value.range(of: #"#([^)'"\s]+)"#, options: .regularExpression) else {
			return nil
		}
		return String(value[range].dropFirst())
	}

	static func stopColour(_ stop: GraphNodeData.Part) -> String {
		if let c = stop.props["stop-color"] { return c }
		// stop-color can also live in the style attribute.
		if let style = stop.props["style"],
			let range = style.range(of: #"stop-color\s*:\s*([^;]+)"#, options: .regularExpression)
		{
			return String(style[range].split(separator: ":")[1]).trimmingCharacters(
				in: .whitespaces)
		}
		return "#000000"
	}

	/// The one number worth showing for each filter effect.
	static func mainParameter(of part: GraphNodeData.Part) -> (String, String)? {
		let keys: [String] =
			switch part.tag {
			case "feGaussianBlur": ["stdDeviation"]
			case "feDropShadow": ["stdDeviation", "dy"]
			case "feOffset": ["dy", "dx"]
			case "feMorphology": ["radius"]
			case "feTurbulence": ["baseFrequency"]
			case "feDisplacementMap": ["scale"]
			case "feFlood": ["flood-opacity"]
			default: []
			}
		for key in keys {
			if let v = part.props[key] { return (key, v) }
		}
		return keys.first.map { ($0, "0") }
	}

	static func effectName(_ primitive: String) -> String {
		switch primitive {
		case "feGaussianBlur": "Blur"
		case "feDropShadow": "Shadow"
		case "feOffset": "Offset"
		case "feColorMatrix": "Colour"
		case "feFlood": "Flood"
		case "feBlend": "Blend"
		case "feComposite": "Composite"
		case "feMerge": "Merge"
		case "feMorphology": "Morphology"
		case "feTurbulence": "Noise"
		case "feDisplacementMap": "Displace"
		default: String(primitive.dropFirst(2))
		}
	}
}

/// A value in a node; click it to edit in a popover.
struct NodeValue: View {
	enum Kind { case colour, number, fraction, text }

	var kind: Kind
	var value: String
	var label: String
	var compact = false
	var onChange: (String?) -> Void

	@State private var isEditing = false
	@State private var draft = ""

	var body: some View {
		Button {
			draft = value
			isEditing = true
		} label: {
			HStack(spacing: 4) {
				if kind == .colour {
					Swatch(colour: CSSColor.parse(value), opacity: 1, isNone: value == "none")
						.frame(width: compact ? 16 : 14, height: compact ? 16 : 14)
				}
				if !compact {
					Text(display)
						.font(.caption.monospaced())
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
			.padding(.horizontal, compact ? 0 : 5)
			.padding(.vertical, 1)
			.background(
				compact ? AnyShapeStyle(.clear) : AnyShapeStyle(.fill.tertiary),
				in: .rect(cornerRadius: 4)
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.frame(maxWidth: 110, alignment: .trailing)
		.help("\(label): \(value) — click to change")
		.popover(isPresented: $isEditing, arrowEdge: .trailing) { editor }
	}

	private var display: String {
		switch kind {
		case .colour:
			if value == "none" { return "none" }
			if value.hasPrefix("url(") {
				return GraphNodeView.referencedID(value).map { "→ \($0)" } ?? value
			}
			return CSSColor.parse(value).map(CSSColor.hex)?.uppercased() ?? value
		case .fraction:
			return Double(value).map { "\(Int(($0 * 100).rounded()))%" } ?? value
		default:
			return value
		}
	}

	@ViewBuilder
	private var editor: some View {
		switch kind {
		case .colour:
			ColourPickerPopover(
				initial: CSSColor.parse(value) ?? .black, opacity: 1, documentColours: [],
				onPick: { hex, _ in onChange(hex) },
				onNone: {
					onChange("none")
					isEditing = false
				})
		case .number, .fraction:
			VStack(alignment: .leading, spacing: 8) {
				Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
				ScrubField(
					label: label, systemImage: "slider.horizontal.3", value: Double(value) ?? 0,
					range: kind == .fraction ? 0...1 : -100_000...100_000,
					step: kind == .fraction ? 0.01 : 0.5
				) { onChange(ScrubField.format($0)) }
				.frame(width: 160)
				if kind == .fraction {
					Slider(
						value: Binding(
							get: { Double(value) ?? 1 },
							set: { onChange(ScrubField.format(($0 * 100).rounded() / 100)) }),
						in: 0...1)
				}
			}
			.padding(12)
		case .text:
			VStack(alignment: .leading, spacing: 8) {
				Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
				TextField(label, text: $draft)
					.textFieldStyle(.roundedBorder)
					.font(.body.monospaced())
					.frame(width: 220)
					.onSubmit {
						onChange(draft.isEmpty ? nil : draft)
						isEditing = false
					}
				Text("Press Return to apply").font(.caption2).foregroundStyle(.tertiary)
			}
			.padding(12)
		}
	}
}

/// After a short hover, a popover shows what the node does: the element on
/// its own, or a sample shape using the definition, with a sentence about it.
private struct NodeHoverPreview: ViewModifier {
	var data: GraphNodeData
	var controller: CanvasController?

	@State private var isShown = false
	@State private var image: NSImage?
	@State private var task: Task<Void, Never>?

	func body(content: Content) -> some View {
		content
			.onHover { inside in
				task?.cancel()
				if inside {
					task = Task { @MainActor in
						try? await Task.sleep(for: .milliseconds(650))
						guard !Task.isCancelled, let controller else { return }
						image = await controller.previewImage(order: data.order)
						guard !Task.isCancelled else { return }
						isShown = true
					}
				} else {
					isShown = false
				}
			}
			.popover(isPresented: $isShown, arrowEdge: .trailing) {
				VStack(alignment: .leading, spacing: 8) {
					if let image {
						Image(nsImage: image)
							.resizable()
							.interpolation(.high)
							.aspectRatio(contentMode: .fit)
							.frame(maxWidth: 200, maxHeight: 140)
							.frame(maxWidth: .infinity)
							.padding(8)
							.background(
								PreviewBacking(),
								in: .rect(cornerRadius: 8, style: .continuous))
					}
					Text(data.name).font(.headline)
					Text(NodeDescription.of(data))
						.font(.callout)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				.frame(width: 232)
				.padding(12)
			}
	}
}

/// A plain-language sentence about what a node does.
enum NodeDescription {
	static func of(_ data: GraphNodeData) -> String {
		let used =
			data.usedBy == 0
			? "Nothing uses it yet — drag from its output to a shape's input."
			: "Used by \(data.usedBy) element\(data.usedBy == 1 ? "" : "s")."
		switch data.tag {
		case "linearGradient":
			return "Paints a straight blend through \(data.parts.count) colours. \(used)"
		case "radialGradient":
			return
				"Paints a blend outward from a centre through \(data.parts.count) colours. \(used)"
		case "pattern":
			return "Paints shapes with a repeating tile. \(used)"
		case "clipPath":
			return "Draws only what falls inside its shapes; the rest is cut away. \(used)"
		case "mask":
			return
				"Shows what's under its white areas, hides it under black, and fades it under grey. \(used)"
		case "filter":
			let effects = data.parts.map { GraphNodeView.effectName($0.tag).lowercased() }
			return
				"Applies \(effects.isEmpty ? "no effects yet" : effects.joined(separator: ", then ")) to what uses it. \(used)"
		case "symbol", "marker":
			return "A reusable drawing, shown wherever a <use> points at it. \(used)"
		case "use":
			return "Draws another element again here."
		case _ where AnimationTag.contains(data.tag):
			let p = data.props
			let what = p["attributeName"] ?? p["type"] ?? "its shape"
			let repeats = p["repeatCount"] == "indefinite" ? ", forever" : ""
			return "Animates \(what) over \(p["dur"] ?? "?")\(repeats)."
		case "g":
			return "A group: moves, hides and styles its contents together."
		default:
			var parts = ["A \(InspectorView.elementName(for: data.tag).lowercased())"]
			if let fill = data.props["fill"] { parts.append("filled with \(fill)") }
			if let stroke = data.props["stroke"], stroke != "none" {
				parts.append("outlined in \(stroke)")
			}
			return parts.joined(separator: ", ") + "."
		}
	}
}

/// A soft backing behind previews, so light and transparent parts read.
private struct PreviewBacking: ShapeStyle {
	func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
		Color.gray.opacity(0.12)
	}
}
