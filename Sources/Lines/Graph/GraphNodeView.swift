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
		// The border sits behind the content, so the input handles on the
		// edge stay on top of the selection highlight.
		.background {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(.background)
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
			if let controller { PreviewButton(order: data.order, controller: controller) }
		}
		.padding(.leading, 10)
		.padding(.trailing, 6)
		.frame(height: Self.headerHeight)
	}

	// MARK: Rows

	/// An input port with its current value.
	private func inputRow(_ input: String, data: GraphNodeData) -> some View {
		HStack(spacing: 6) {
			let isTarget =
				controller?.validConnectionTargets.contains("\(node.id):\(input)") ?? false
			Handle(
				nodeId: node.id, id: input, type: .target, position: .left,
				color: data.connected.contains(input) || isTarget ? Graph.color(for: input) : .gray,
				// Inputs only receive: connections start from an output.
				isConnectable: false
			)
			// While an output is being connected, inputs that accept it glow.
			.overlay {
				if isTarget {
					Circle()
						.strokeBorder(Graph.color(for: input), lineWidth: 2)
						.frame(width: 20, height: 20)
						.shadow(color: Graph.color(for: input).opacity(0.8), radius: 4)
						.allowsHitTesting(false)
				}
			}
			.offset(x: -6)
			.animation(.easeOut(duration: 0.15), value: isTarget)
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
			if data.kind == .clip || data.kind == .mask {
				Menu("Add Shape") {
					MaskShapeMenu(definition: data.order, controller: controller)
				}
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

/// A node's preview button: hover it to see how the node changes the
/// drawing (see `NodeImpactCard`); click to keep the preview up.
private struct PreviewButton: View {
	var order: Int
	var controller: CanvasController

	private var isPinned: Bool { controller.pinnedPreviewNode == order }

	var body: some View {
		Button(isPinned ? "Hide Preview" : "Preview", systemImage: isPinned ? "eye.fill" : "eye") {
			controller.pinnedPreviewNode = isPinned ? nil : order
		}
		.buttonStyle(.icon(size: 26, selected: isPinned))
		.onHover { inside in
			if inside {
				controller.hoveredNode = order
			} else if controller.hoveredNode == order {
				controller.hoveredNode = nil
			}
		}
		.help(
			isPinned
				? "Hide the preview"
				: "Hover to preview how this changes the drawing; click to keep it open")
	}
}

/// How a hovered node changes the drawing: the shapes using a definition
/// without and with it, an animation's frames, or an element in place, with
/// the rest of the drawing dimmed and the affected area outlined.
struct NodeImpactCard: View {
	var data: GraphNodeData
	var controller: CanvasController

	@State private var pictures: [(label: String, image: NSImage)] = []
	@State private var isLoading = true

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				Image(systemName: InspectorView.symbol(for: data.tag, isRoot: false))
					.foregroundStyle(.tint)
				Text(data.name).font(.headline).lineLimit(1)
				Spacer()
				if controller.pinnedPreviewNode == data.order {
					Button("Close Preview", systemImage: "xmark") {
						controller.pinnedPreviewNode = nil
					}
					.buttonStyle(.icon(size: 22))
					.help("Close")
				}
			}
			if isLoading {
				ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
			} else if !pictures.isEmpty {
				HStack(alignment: .top, spacing: 8) {
					ForEach(Array(pictures.enumerated()), id: \.offset) { index, picture in
						if index > 0 && pictures.count == 2 {
							Image(systemName: "arrow.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
								.frame(height: 130)
						}
						VStack(spacing: 4) {
							Image(nsImage: picture.image)
								.resizable()
								.interpolation(.high)
								.aspectRatio(contentMode: .fit)
								.frame(maxWidth: pictures.count > 2 ? 104 : 150, maxHeight: 130)
								.background(
									Color.gray.opacity(0.12),
									in: .rect(cornerRadius: 8, style: .continuous))
							Text(picture.label)
								.font(.caption)
								.foregroundStyle(
									picture.label == "With"
										? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
						}
					}
				}
				.frame(maxWidth: .infinity)
			}
			Text(NodeDescription.of(data))
				.font(.callout)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(14)
		.frame(width: 360)
		.floatingPanelChrome()
		.task(id: data) {
			isLoading = true
			pictures = await controller.impactPreview(order: data.order)
			isLoading = false
		}
		.allowsHitTesting(controller.pinnedPreviewNode == data.order)
	}
}

/// A plain-language sentence about what a node does.
enum NodeDescription {
	/// What the node does to this drawing, then what the pictures show.
	static func of(_ data: GraphNodeData) -> String {
		let users = list(data.users)
		let p = data.props
		switch data.tag {
		case "linearGradient", "radialGradient":
			let colours = data.parts.map { ColourName.of(GraphNodeView.stopColour($0)) }
			let blend =
				colours.count >= 2
				? "from \(colours.first!) to \(colours.last!)"
					+ (colours.count > 2
						? " through \(list(Array(colours.dropFirst().dropLast())))" : "")
				: "of \(colours.first ?? "one colour")"
			let kind =
				data.tag == "radialGradient"
				? "a blend outward from the centre" : "a straight blend"
			let spread =
				switch p["spreadMethod"] {
				case "repeat": ", repeating past its edge"
				case "reflect": ", mirrored past its edge"
				default: ""
				}
			return uses(data, "Fills \(users) with \(kind) \(blend)\(spread).")
		case "pattern":
			return uses(
				data,
				"Fills \(users) with a repeating \(p["width"] ?? "?")×\(p["height"] ?? "?") tile.")
		case "clipPath":
			let shapes = data.contents.isEmpty ? "no shapes yet" : list(data.contents)
			return uses(
				data,
				"Cuts \(users) to the outline of \(shapes): only the parts inside are drawn, the rest disappears."
			)
		case "mask":
			let shapes = data.contents.isEmpty ? "no shapes yet" : list(data.contents)
			return uses(
				data,
				"Masks \(users) with \(shapes): where they're white it shows, black hides it, grey fades it."
			)
		case "filter":
			let effects = data.parts.map(effect)
			let what = effects.isEmpty ? "No effects yet" : list(effects).capitalizedFirst
			return uses(data, "\(what), on \(users).")
		case "symbol", "marker":
			return uses(data, "A reusable drawing, placed wherever \(users) points at it.")
		case "use":
			return
				"Draws another element again here. The picture shows where it sits in the drawing."
		case _ where AnimationTag.contains(data.tag):
			let target = data.users.first ?? "its element"
			let property =
				data.tag == "animateTransform"
				? (p["type"].map { "\($0)" } ?? "transform")
				: data.tag == "animateMotion"
					? "position along a path" : (p["attributeName"] ?? "a value")
			var change = ""
			if let values = p["values"] {
				let list = values.split(separator: ";").map {
					$0.trimmingCharacters(in: .whitespaces)
				}
				change = list.count > 1 ? " through \(list.joined(separator: " → "))" : ""
			} else if let to = p["to"] {
				change = p["from"].map { " from \($0) to \(to)" } ?? " to \(to)"
			}
			let timing = p["dur"].map { " over \($0)" } ?? ""
			let repeats =
				p["repeatCount"] == "indefinite"
				? ", forever" : p["repeatCount"].map { ", \($0) times" } ?? ""
			return
				"Animates \(target)'s \(property)\(change)\(timing)\(repeats). The pictures show the start, middle and end of one pass."
		case "g":
			return
				"A group: moves, hides and styles its contents together. The picture shows where it sits in the drawing."
		default:
			var parts = ["\(data.name): a \(InspectorView.elementName(for: data.tag).lowercased())"]
			if let fill = p["fill"] { parts.append("filled with \(paint(fill))") }
			if let stroke = p["stroke"], stroke != "none" {
				parts.append("outlined in \(paint(stroke))")
			}
			return parts.joined(separator: ", ")
				+ ". The picture shows where it sits in the drawing, the rest dimmed."
		}
	}

	/// The definition's sentence, then usage and how to read the pictures.
	private static func uses(_ data: GraphNodeData, _ sentence: String) -> String {
		data.usedBy == 0
			? sentence.replacingOccurrences(of: " nothing", with: " shapes")
				+ " Nothing uses it yet: the picture shows it on a sample shape. Drag from its output to a shape's input to use it."
			: sentence + " Left: without it. Right: with it — the dashed box marks the change."
	}

	private static func effect(_ part: GraphNodeData.Part) -> String {
		let p = part.props
		switch part.tag {
		case "feGaussianBlur": return "blurs by \(p["stdDeviation"] ?? "0")"
		case "feDropShadow":
			return
				"adds a shadow offset \(p["dx"] ?? "2"), \(p["dy"] ?? "2") with a \(p["stdDeviation"] ?? "2") blur"
		case "feOffset": return "shifts by \(p["dx"] ?? "0"), \(p["dy"] ?? "0")"
		case "feColorMatrix": return "changes colours (\(p["type"] ?? "matrix"))"
		case "feMorphology":
			return "\(p["operator"] == "dilate" ? "thickens" : "thins") by \(p["radius"] ?? "0")"
		case "feTurbulence": return "adds noise"
		case "feFlood": return "fills with \(ColourName.of(p["flood-color"] ?? "#000000"))"
		default: return GraphNodeView.effectName(part.tag).lowercased()
		}
	}

	private static func paint(_ value: String) -> String {
		if let id = GraphNodeView.referencedID(value) { return id }
		return "\(ColourName.of(value)) (\(value))"
	}

	/// "a", "a and b", "a, b and 2 more".
	static func list(_ names: [String]) -> String {
		switch names.count {
		case 0: return "nothing"
		case 1: return names[0]
		case 2: return "\(names[0]) and \(names[1])"
		case 3: return "\(names[0]), \(names[1]) and \(names[2])"
		default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
		}
	}
}

/// Plain names for colours, for sentences: "pink", "dark blue".
enum ColourName {
	static func of(_ value: String) -> String {
		let v = value.trimmingCharacters(in: .whitespaces).lowercased()
		if v == "none" || v == "transparent" { return "nothing" }
		guard let colour = CSSColor.parse(v),
			let ns = NSColor(colour).usingColorSpace(.sRGB)
		else { return v }
		var h: CGFloat = 0
		var s: CGFloat = 0
		var b: CGFloat = 0
		var a: CGFloat = 0
		ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
		if b < 0.12 { return "black" }
		if s < 0.12 {
			return b > 0.9 ? "white" : b > 0.6 ? "light grey" : b > 0.3 ? "grey" : "dark grey"
		}
		let hue = h * 360
		let name: String =
			switch hue {
			case ..<15, 345...: "red"
			case ..<40: "orange"
			case ..<65: "yellow"
			case ..<160: "green"
			case ..<195: "teal"
			case ..<250: "blue"
			case ..<290: "purple"
			default: "pink"
			}
		if b < 0.4 { return "dark \(name)" }
		if s < 0.4 && b > 0.8 { return "pale \(name)" }
		return name
	}
}

extension String {
	fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// A soft backing behind previews, so light and transparent parts read.
private struct PreviewBacking: ShapeStyle {
	func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
		Color.gray.opacity(0.12)
	}
}
