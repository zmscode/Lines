import SwiftUI

/// Edits a gradient's stops and direction: shown when a gradient is selected,
/// and under Fill or Stroke when a shape is painted with one.
struct GradientEditor: View {
	var gradient: OutlineItem
	var controller: CanvasController

	private var stops: [OutlineItem] {
		controller.outline.filter { $0.parent == gradient.order && $0.tag == "stop" }
	}

	private var isLinear: Bool { gradient.tag == "linearGradient" }
	private var usesBoundingBox: Bool { gradient.prop("gradientUnits") != "userSpaceOnUse" }

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			strip
			ForEach(Array(stops.enumerated()), id: \.element.order) { index, stop in
				StopRow(
					stop: stop, index: index, canDelete: stops.count > 2, controller: controller)
			}
			HStack {
				Button("Add Stop", systemImage: "plus") {
					controller.addStop(toGradient: gradient.order)
				}
				Spacer()
				Button("Reverse", systemImage: "arrow.left.arrow.right") { reverse() }
					.help("Swap the stops end to end")
			}
			.controlSize(.small)
			Divider()
			if isLinear && usesBoundingBox {
				// Quick directions, then the exact angle.
				HStack(spacing: 2) {
					Text("Direction").foregroundStyle(.secondary)
					Spacer()
					ForEach([0.0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { degrees in
						Button("\(Int(degrees))°", systemImage: "arrow.right") { setAngle(degrees) }
							.labelStyle(.iconOnly)
							.rotationEffect(.degrees(degrees))
							.buttonStyle(.icon(size: 20, selected: Int(angle) == Int(degrees)))
							.help("\(Int(degrees))°")
					}
				}
				Text("Or drag the handles on the shape in the canvas.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			if isLinear {
				if usesBoundingBox {
					row("Angle") {
						ScrubField(
							label: "Angle", systemImage: "angle", value: angle, unit: "°",
							range: -360...360
						) { setAngle($0) }
					}
				} else {
					coordinates(["x1", "y1", "x2", "y2"])
				}
			} else {
				// The focal point only when it's set; the handles move the centre.
				coordinates(
					["cx", "cy", "r"]
						+ (gradient.prop("fx") != nil || gradient.prop("fy") != nil
							? ["fx", "fy"] : []))
			}
			row("Spread") {
				Picker("Spread", selection: spread) {
					Text("Pad").tag("pad")
					Text("Reflect").tag("reflect")
					Text("Repeat").tag("repeat")
				}
				.labelsHidden()
			}
		}
	}

	/// The gradient as it looks, from its stops.
	private var strip: some View {
		let colours = stops.map { stop in
			Gradient.Stop(
				color: (CSSColor.parse(Self.colour(of: stop)) ?? .black)
					.opacity(Double(stop.prop("stop-opacity") ?? "") ?? 1),
				location: Self.offset(of: stop))
		}
		return RoundedRectangle(cornerRadius: 6, style: .continuous)
			.fill(
				colours.isEmpty
					? AnyShapeStyle(.quaternary)
					: AnyShapeStyle(
						LinearGradient(stops: colours, startPoint: .leading, endPoint: .trailing))
			)
			.frame(height: 22)
			.overlay {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.strokeBorder(.separator, lineWidth: 0.5)
			}
			.accessibilityHidden(true)
	}

	private func coordinates(_ names: [String]) -> some View {
		Grid(horizontalSpacing: 8, verticalSpacing: 8) {
			ForEach(Array(stride(from: 0, to: names.count, by: 2)), id: \.self) { i in
				GridRow {
					ForEach(names[i..<min(i + 2, names.count)], id: \.self) { name in
						ScrubField(
							label: name.uppercased(),
							value: gradient.prop(name).flatMap(Self.number),
							range: -100_000...100_000, step: usesBoundingBox ? 0.01 : 1
						) {
							controller.setAttribute(
								name, ScrubField.format($0), onOrder: gradient.order,
								coalesce: true)
						}
					}
				}
			}
		}
	}

	private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		HStack {
			Text(title).foregroundStyle(.secondary)
			Spacer()
			content().frame(width: 130)
		}
	}

	// MARK: Values

	/// Degrees clockwise from left-to-right, from x1/y1 → x2/y2.
	private var angle: Double {
		let p = { (n: String, d: Double) in gradient.prop(n).flatMap(Self.number) ?? d }
		let dx = p("x2", 1) - p("x1", 0)
		let dy = p("y2", 0) - p("y1", 0)
		return (atan2(dy, dx) * 180 / .pi).rounded()
	}

	private func setAngle(_ degrees: Double) {
		let r = degrees * .pi / 180
		let values = [
			("x1", 0.5 - cos(r) / 2), ("y1", 0.5 - sin(r) / 2),
			("x2", 0.5 + cos(r) / 2), ("y2", 0.5 + sin(r) / 2),
		]
		for (name, v) in values {
			controller.setAttribute(
				name, ScrubField.format((v * 1000).rounded() / 1000), onOrder: gradient.order,
				coalesce: true)
		}
	}

	private var spread: Binding<String> {
		Binding(
			get: { gradient.prop("spreadMethod") ?? "pad" },
			set: {
				controller.setAttribute(
					"spreadMethod", $0 == "pad" ? nil : $0, onOrder: gradient.order)
			})
	}

	private func reverse() {
		for stop in stops {
			let flipped = 1 - Self.offset(of: stop)
			controller.setAttribute(
				"offset", ScrubField.format((flipped * 1000).rounded() / 1000),
				onOrder: stop.order)
		}
	}

	static func number(_ s: String) -> Double? {
		let t = s.trimmingCharacters(in: .whitespaces)
		if t.hasSuffix("%") { return Double(t.dropLast()).map { $0 / 100 } }
		return Double(t)
	}

	static func offset(of stop: OutlineItem) -> Double {
		min(max(stop.prop("offset").flatMap(number) ?? 0, 0), 1)
	}

	/// A stop's colour, from its attribute or its style.
	static func colour(of stop: OutlineItem) -> String {
		if let c = stop.prop("stop-color") { return c }
		if let style = stop.prop("style"),
			let m = style.firstMatch(of: #/stop-color\s*:\s*([^;]+)/#)
		{
			return String(m.1).trimmingCharacters(in: .whitespaces)
		}
		return "#000000"
	}
}

private struct StopRow: View {
	var stop: OutlineItem
	var index: Int
	var canDelete: Bool
	var controller: CanvasController

	var body: some View {
		HStack(spacing: 8) {
			ColourWell(
				title: "Stop \(index + 1)", value: GradientEditor.colour(of: stop),
				opacity: Double(stop.prop("stop-opacity") ?? "") ?? 1,
				documentColours: DocumentColours.of(controller, limit: 16),
				onPick: { hex, alpha in
					controller.setAttribute(
						"stop-color", hex, onOrder: stop.order, coalesce: true)
					controller.setAttribute(
						"stop-opacity", alpha >= 0.999 ? nil : ScrubField.format(alpha),
						onOrder: stop.order, coalesce: true)
				},
				onNone: {
					controller.setAttribute("stop-opacity", "0", onOrder: stop.order)
				}
			)
			Slider(
				value: Binding(
					get: { GradientEditor.offset(of: stop) },
					set: {
						controller.setAttribute(
							"offset", ScrubField.format(($0 * 100).rounded() / 100),
							onOrder: stop.order, coalesce: true)
					}), in: 0...1
			)
			.controlSize(.small)
			.help("Where this colour sits along the gradient")
			Text("\(Int((GradientEditor.offset(of: stop) * 100).rounded()))%")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(width: 34, alignment: .trailing)
			Button("Remove Stop", systemImage: "minus.circle") {
				controller.delete(order: stop.order)
			}
			.buttonStyle(.icon(size: 22))
			.disabled(!canDelete)
			.help(canDelete ? "Remove this stop" : "A gradient needs at least two stops")
		}
	}
}

/// Edits a mask or clip path: the shapes it's made of, adding more, and (for
/// masks) whether each shows or hides what's under it.
struct MaskEditor: View {
	var definition: OutlineItem
	var controller: CanvasController

	private var isMask: Bool { definition.tag == "mask" }

	private var shapes: [OutlineItem] {
		controller.outline.filter { $0.parent == definition.order }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(
				isMask
					? "White areas show what's masked, black areas hide it, greys fade it."
					: "Only what's inside these shapes is drawn."
			)
			.font(.caption)
			.foregroundStyle(.secondary)
			// Editing on the canvas is the easy way: drag and resize the shapes
			// right over the element they cut.
			Button {
				controller.editOnCanvas(definition: definition.order)
			} label: {
				Label("Edit Shapes on Canvas", systemImage: "hand.draw")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
			.disabled(shapes.isEmpty || !controller.isEditing)
			.help(
				"Show the shapes over the element, to move and resize them directly (Esc when done)"
			)
			ForEach(shapes) { shape in
				HStack(spacing: 8) {
					Image(systemName: InspectorView.symbol(for: shape.tag, isRoot: false))
						.foregroundStyle(.secondary)
						.frame(width: 18)
					Text(shape.displayName)
						.lineLimit(1)
						.truncationMode(.middle)
						.layoutPriority(1)
						.help(shape.displayName)
					Spacer(minLength: 4)
					if isMask {
						// A swatch of the shape's mask colour: white shows, black hides.
						let shows = reveal(shape)
						Button {
							shows.wrappedValue.toggle()
						} label: {
							HStack(spacing: 4) {
								Circle()
									.fill(shows.wrappedValue ? Color.white : Color.black)
									.overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
									.frame(width: 12, height: 12)
								Text(shows.wrappedValue ? "Shows" : "Hides")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 6)
							.padding(.vertical, 3)
							.background(.quaternary, in: .capsule)
						}
						.buttonStyle(.plain)
						.fixedSize()
						.help(
							shows.wrappedValue
								? "White: shows what's under this shape. Click to hide it instead."
								: "Black: hides what's under this shape. Click to show it instead.")
					}
					Button("Edit Shape", systemImage: "arrow.right.circle") {
						controller.select(order: shape.order)
					}
					.buttonStyle(.icon(size: 22))
					.help("Select this shape to edit it")
					Button("Remove Shape", systemImage: "minus.circle") {
						controller.delete(order: shape.order)
					}
					.buttonStyle(.icon(size: 22))
					.help("Remove this shape")
				}
			}
			HStack {
				Menu {
					MaskShapeMenu(definition: definition.order, controller: controller)
				} label: {
					Label("Add Shape", systemImage: "plus")
				}
				.fixedSize()
				Spacer()
				if isMask {
					Button("Invert", systemImage: "circle.righthalf.filled") {
						controller.invertMask(order: definition.order)
					}
					.help("Swap white and black, so what's shown is hidden")
				}
			}
			.controlSize(.small)
		}
	}

	private func reveal(_ shape: OutlineItem) -> Binding<Bool> {
		Binding(
			get: {
				let fill = (shape.prop("fill") ?? shape.fill ?? "black").lowercased()
				return ["white", "#fff", "#ffffff"].contains(fill)
			},
			set: {
				controller.setAttribute("fill", $0 ? "white" : "black", onOrder: shape.order)
			})
	}
}

/// The inspector card for a selected gradient, mask or clip path.
struct DefinitionCard: View {
	var item: OutlineItem
	var controller: CanvasController

	var body: some View {
		switch item.tag {
		case "linearGradient", "radialGradient":
			InspectorCard(title: "Gradient") {
				GradientEditor(gradient: item, controller: controller)
			}
		case "mask":
			InspectorCard(title: "Mask") { MaskEditor(definition: item, controller: controller) }
		case "clipPath":
			InspectorCard(title: "Clip Path") {
				MaskEditor(definition: item, controller: controller)
			}
		default:
			EmptyView()
		}
	}

	static func handles(_ tag: String) -> Bool {
		["linearGradient", "radialGradient", "mask", "clipPath"].contains(tag)
	}
}

/// Shapes a clip path or mask can be made of.
enum MaskShape: String, CaseIterable, Identifiable {
	case rect, roundedRect, circle, ellipse, triangle, hexagon, star, text, selection
	var id: String { rawValue }

	var title: String {
		switch self {
		case .rect: "Rectangle"
		case .roundedRect: "Rounded Rectangle"
		case .circle: "Circle"
		case .ellipse: "Ellipse"
		case .triangle: "Triangle"
		case .hexagon: "Hexagon"
		case .star: "Star"
		case .text: "Text"
		case .selection: "Copy of Selection"
		}
	}

	var symbol: String {
		switch self {
		case .rect: "rectangle"
		case .roundedRect: "app"
		case .circle: "circle"
		case .ellipse: "oval"
		case .triangle: "triangle"
		case .hexagon: "hexagon"
		case .star: "star"
		case .text: "textformat"
		case .selection: "square.on.square"
		}
	}
}

/// The Add Shape items for a clip path or mask.
struct MaskShapeMenu: View {
	var definition: Int
	var controller: CanvasController

	var body: some View {
		ForEach(MaskShape.allCases.filter { $0 != .selection }) { shape in
			Button(shape.title, systemImage: shape.symbol) {
				controller.addShape(shape.rawValue, toDefinition: definition)
			}
		}
		Divider()
		Button(MaskShape.selection.title, systemImage: MaskShape.selection.symbol) {
			controller.addShape(MaskShape.selection.rawValue, toDefinition: definition)
		}
		.disabled(!controller.hasElementSelection || controller.selection?.order == definition)
		.help("Use a copy of the selected element's shape")
	}
}
