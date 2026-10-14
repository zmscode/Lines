import AppKit
import SwiftUI

/// The inspector panel: friendly controls for the selected element (or the
/// document when nothing is selected), with the raw attributes tucked away.
struct InspectorView: View {
	var controller: CanvasController

	var body: some View {
		if let selection = controller.selection {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					if selection.isRoot {
						DocumentInspector(selection: selection, controller: controller)
					} else {
						ElementInspector(selection: selection, controller: controller)
					}
					AllAttributes(selection: selection, controller: controller)
				}
				.padding(.horizontal, 14)
				.padding(.top, 14)
				.padding(.bottom, 18)
			}
			.id(selection.path)
		} else {
			ContentUnavailableView(
				"Nothing to Inspect", systemImage: "square.dashed",
				description: Text("Fix the errors in the source to inspect the drawing.")
			)
		}
	}
}

// MARK: - Element

private struct ElementInspector: View {
	var selection: SelectionInfo
	var controller: CanvasController

	@AppStorage("inspector.lockAspect") private var lockAspect = false

	private var tag: String { selection.tag }
	private var hidden: Bool { selection.value("display") == "none" }

	var body: some View {
		header
		quickActions
		if AnimationTag.contains(tag) {
			AnimationCard(selection: selection, controller: controller)
		} else {
			if let bounds = selection.bounds { geometry(bounds) }
			appearance
			if tag == "text" { TextCard(selection: selection, controller: controller) }
			ElementAnimationsCard(selection: selection, controller: controller)
		}
	}

	// MARK: Header

	private var header: some View {
		HStack(spacing: 12) {
			IconTile(symbol: InspectorView.symbol(for: tag, isRoot: false), tint: tint)
			VStack(alignment: .leading, spacing: 2) {
				NameField(selection: selection, controller: controller)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.padding(.trailing, 24)  // clear of the panel's close button
	}

	private var tint: Color {
		for attribute in ["fill", "stroke"] {
			if let value = selection.value(attribute), value != "none",
				let c = CSSColor.parse(value)
			{
				return c
			}
		}
		return .accentColor
	}

	private var subtitle: String {
		var parts = [InspectorView.elementName(for: tag)]
		if let b = selection.bounds {
			parts.append("\(ScrubField.format(b.width)) × \(ScrubField.format(b.height))")
		}
		if tag == "polygon" || tag == "polyline", let points = selection.value("points") {
			let count = points.split(whereSeparator: { $0 == " " || $0 == "," }).count / 2
			parts.append("\(count) points")
		}
		return parts.joined(separator: " · ")
	}

	private var quickActions: some View {
		HStack(spacing: 6) {
			action("Duplicate", "plus.square.on.square") { controller.duplicateSelection() }
			action("Bring Forward", "square.2.layers.3d.top.filled") {
				controller.reorder(.forward)
			}
			action("Send Backward", "square.2.layers.3d.bottom.filled") {
				controller.reorder(.backward)
			}
			action(hidden ? "Show" : "Hide", hidden ? "eye.slash" : "eye") {
				controller.toggleHidden(order: selection.order)
			}
			action("Select Enclosing Group", "arrow.up.square") { controller.selectParent() }
			Spacer(minLength: 0)
			action("Delete", "trash", role: .destructive) { controller.deleteSelection() }
		}
	}

	private func action(
		_ title: String, _ symbol: String, role: ButtonRole? = nil, perform: @escaping () -> Void
	) -> some View {
		Button(title, systemImage: symbol, role: role, action: perform)
			.buttonStyle(.icon(size: 30))
			.help(title)
	}

	// MARK: Geometry

	private func geometry(_ b: CGRect) -> some View {
		InspectorCard(title: "Position & Size") {
			Grid(horizontalSpacing: 8, verticalSpacing: 8) {
				GridRow {
					ScrubField(label: "X", value: b.minX) { controller.setBounds(x: $0) }
					ScrubField(label: "Y", value: b.minY) { controller.setBounds(y: $0) }
				}
				GridRow {
					ScrubField(label: "W", value: b.width, range: 0.01...1_000_000) { w in
						let h = lockAspect && b.width > 0 ? b.height * w / b.width : nil
						controller.setBounds(width: w, height: h)
					}
					ScrubField(label: "H", value: b.height, range: 0.01...1_000_000) { h in
						let w = lockAspect && b.height > 0 ? b.width * h / b.height : nil
						controller.setBounds(width: w, height: h)
					}
				}
			}
			HStack(spacing: 8) {
				ScrubField(
					label: "Rotation", systemImage: "rotate.right", value: selection.rotation,
					unit: "°",
					range: -360...360
				) { controller.setRotation($0) }
				Button("Rotate Left 90°", systemImage: "rotate.left") {
					controller.setRotation(selection.rotation - 90)
				}
				.help("Rotate Left 90°")
				Button("Rotate Right 90°", systemImage: "rotate.right") {
					controller.setRotation(selection.rotation + 90)
				}
				.help("Rotate Right 90°")
				Button(
					lockAspect ? "Unlock Aspect Ratio" : "Lock Aspect Ratio",
					systemImage: lockAspect ? "lock.fill" : "lock.open"
				) { lockAspect.toggle() }
				.buttonStyle(.icon(size: 28, selected: lockAspect))
				.help(lockAspect ? "Unlock Aspect Ratio" : "Lock Aspect Ratio")
			}
			.buttonStyle(.icon(size: 28))
		}
	}

	// MARK: Appearance

	private var appearance: some View {
		InspectorCard(title: "Appearance") {
			PaintRow(title: "Fill", attribute: "fill", selection: selection, controller: controller)
			PaintRow(
				title: "Stroke", attribute: "stroke", selection: selection, controller: controller)
			if let stroke = selection.value("stroke"), stroke != "none" {
				labelled("Stroke Width") {
					ScrubField(
						label: "Width", systemImage: "lineweight",
						value: selection.value("stroke-width").flatMap(Double.init) ?? 1,
						range: 0...10_000, step: 0.5
					) {
						controller.setAttribute(
							"stroke-width", ScrubField.format($0), coalesce: true)
					}
				}
			}
			if tag == "rect" {
				labelled("Corner Radius") {
					ScrubField(
						label: "Radius", systemImage: "app",
						value: selection.value("rx").flatMap(Double.init) ?? 0, range: 0...100_000
					) { controller.setAttribute("rx", ScrubField.format($0), coalesce: true) }
				}
			}
			OpacitySlider(
				value: selection.value("opacity").flatMap(Double.init) ?? 1, controller: controller)
		}
	}

	private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		HStack {
			Text(title).foregroundStyle(.secondary)
			Spacer()
			content().frame(width: 116)
		}
	}
}

/// A fill or stroke: the colour well, what it's set to, and add/remove.
private struct PaintRow: View {
	var title: String
	var attribute: String
	var selection: SelectionInfo
	var controller: CanvasController

	var body: some View {
		let value = selection.value(attribute) ?? (attribute == "fill" ? "black" : "none")
		let opacity = selection.value(attribute + "-opacity").flatMap(Double.init) ?? 1
		HStack(spacing: 10) {
			ColourWell(
				title: title, value: value, opacity: opacity, documentColours: documentColours,
				onPick: { hex, alpha in
					controller.setPaint(attribute, color: hex, opacity: alpha, coalesce: true)
				},
				onNone: { controller.setAttribute(attribute, "none") }
			)
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
				Text(describe(value, opacity: opacity))
					.font(.caption.monospaced())
					.foregroundStyle(.secondary)
			}
			Spacer()
			if value == "none" {
				Button("Add \(title)", systemImage: "plus.circle") {
					controller.setPaint(
						attribute, color: attribute == "fill" ? "#0a84ff" : "#1c1c1e", opacity: 1,
						coalesce: false)
					if attribute == "stroke", selection.value("stroke-width") == nil {
						controller.setAttribute("stroke-width", "2")
					}
				}
				.help("Add \(title.lowercased())")
			} else {
				Button("Remove \(title)", systemImage: "minus.circle") {
					controller.setAttribute(attribute, "none")
				}
				.help("Remove \(title.lowercased())")
			}
		}
		.buttonStyle(.icon(size: 26))
	}

	private func describe(_ value: String, opacity: Double) -> String {
		if value == "none" { return "None" }
		if value.hasPrefix("url(") { return "Gradient or pattern" }
		let hex = CSSColor.parse(value).map(CSSColor.hex)?.uppercased() ?? value
		return opacity < 1 ? "\(hex) · \(Int((opacity * 100).rounded()))%" : hex
	}

	private var documentColours: [String] { DocumentColours.of(controller, limit: 16) }
}

/// The element's name (its `id`), editable in place.
private struct NameField: View {
	var selection: SelectionInfo
	var controller: CanvasController
	@State private var draft = ""
	@FocusState private var focused: Bool

	var body: some View {
		TextField(
			"Name", text: $draft, prompt: Text(InspectorView.elementName(for: selection.tag))
		)
		.textFieldStyle(.plain)
		.font(.title3.weight(.semibold))
		.focused($focused)
		.onAppear { draft = selection.value("id") ?? "" }
		.onSubmit(commit)
		.onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
		.help("Name (the element’s id)")
	}

	private func commit() {
		guard draft != (selection.value("id") ?? "") else { return }
		controller.rename(order: selection.order, to: draft)
	}
}

private struct OpacitySlider: View {
	var value: Double
	var controller: CanvasController

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "circle.lefthalf.filled")
				.foregroundStyle(.secondary)
			Slider(
				value: Binding(
					get: { value },
					set: { new in
						let rounded = (new * 100).rounded() / 100
						controller.setAttribute(
							"opacity", ScrubField.format(rounded), coalesce: true)
					}
				), in: 0...1)
			Text(value, format: .percent.precision(.fractionLength(0)))
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .trailing)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Opacity")
	}
}

private struct IconTile: View {
	var symbol: String
	var tint: Color

	var body: some View {
		Image(systemName: symbol)
			.font(.title2)
			.foregroundStyle(tint)
			.frame(width: 44, height: 44)
			.background(tint.opacity(0.18), in: .rect(cornerRadius: 10, style: .continuous))
			.accessibilityHidden(true)
	}
}

enum DocumentColours {
	/// Distinct plain colours used for fills in the drawing.
	@MainActor
	static func of(_ controller: CanvasController, limit: Int) -> [String] {
		var seen = Set<String>()
		return controller.outline.compactMap { item -> String? in
			guard let fill = item.fill, fill != "none", let colour = CSSColor.parse(fill) else {
				return nil
			}
			let hex = CSSColor.hex(colour)
			return seen.insert(hex).inserted ? hex : nil
		}
		.prefix(limit).map { $0 }
	}
}

// MARK: - Text

private struct TextCard: View {
	var selection: SelectionInfo
	var controller: CanvasController

	private static let families: [(name: String, value: String)] = [
		("System", "-apple-system, Helvetica, sans-serif"),
		("Helvetica", "Helvetica, Arial, sans-serif"),
		("Avenir Next", "Avenir Next, sans-serif"),
		("Futura", "Futura, sans-serif"),
		("Georgia", "Georgia, serif"),
		("Times", "Times New Roman, serif"),
		("Menlo", "Menlo, monospace"),
		("Courier", "Courier New, monospace"),
	]
	private static let weights: [(name: String, value: String)] = [
		("Light", "300"), ("Regular", "400"), ("Medium", "500"), ("Semibold", "600"),
		("Bold", "700"),
	]

	var body: some View {
		InspectorCard(title: "Text") {
			AttributeField(title: "Text", value: selection.textContent ?? "", axis: .vertical) {
				controller.setTextContent($0)
			}
			.labelsHidden()
			.textFieldStyle(.roundedBorder)

			HStack(spacing: 8) {
				Menu(familyName) {
					ForEach(Self.families, id: \.value) { family in
						Button(family.name) { controller.setAttribute("font-family", family.value) }
					}
				}
				.fixedSize()
				.help("Font")
				ScrubField(
					label: "Size", systemImage: "textformat.size", value: fontSize,
					range: 1...10_000
				) { controller.setAttribute("font-size", ScrubField.format($0), coalesce: true) }
			}

			HStack(spacing: 8) {
				Picker(
					"Weight",
					selection: Binding(
						get: { selection.value("font-weight") ?? "400" },
						set: { controller.setAttribute("font-weight", $0) })
				) {
					ForEach(Self.weights, id: \.value) { Text($0.name).tag($0.value) }
				}
				.labelsHidden()
				.fixedSize()
				.help("Weight")

				Picker(
					"Alignment",
					selection: Binding(
						get: { selection.value("text-anchor") ?? "start" },
						set: { controller.setAttribute("text-anchor", $0) })
				) {
					Image(systemName: "text.alignleft").tag("start")
					Image(systemName: "text.aligncenter").tag("middle")
					Image(systemName: "text.alignright").tag("end")
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.help("Alignment: left, centre or right")
			}
		}
	}

	private var fontSize: Double {
		selection.value("font-size").flatMap { Double($0.replacingOccurrences(of: "px", with: "")) }
			?? 16
	}

	private var familyName: String {
		let value = selection.value("font-family") ?? ""
		if let known = Self.families.first(where: { $0.value == value }) { return known.name }
		return value.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
			?? "System"
	}
}

// MARK: - Document

private struct DocumentInspector: View {
	var selection: SelectionInfo
	var controller: CanvasController

	@AppStorage("inspector.lockAspect") private var lockAspect = false

	private var width: Double? { selection.value("width").flatMap(Self.number) ?? viewBox[safe: 2] }
	private var height: Double? {
		selection.value("height").flatMap(Self.number) ?? viewBox[safe: 3]
	}
	private var viewBox: [Double] {
		(selection.value("viewBox") ?? "")
			.split(whereSeparator: { $0 == " " || $0 == "," })
			.compactMap { Double($0) }
	}

	var body: some View {
		HStack(spacing: 12) {
			IconTile(symbol: "doc.richtext", tint: .accentColor)
			VStack(alignment: .leading, spacing: 2) {
				Text(controller.documentName)
					.font(.title3.weight(.semibold))
					.lineLimit(1)
				Text(summary).font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(.trailing, 24)

		InspectorCard(title: "Canvas") {
			Grid(horizontalSpacing: 8, verticalSpacing: 8) {
				GridRow {
					ScrubField(label: "W", value: width, range: 1...100_000) { w in
						setSize(width: w, height: lockAspect ? aspect.map { w / $0 } : nil)
					}
					ScrubField(label: "H", value: height, range: 1...100_000) { h in
						setSize(width: lockAspect ? aspect.map { h * $0 } : nil, height: h)
					}
				}
			}
			HStack {
				Button(
					lockAspect ? "Unlock Aspect Ratio" : "Lock Aspect Ratio",
					systemImage: lockAspect ? "lock.fill" : "lock.open"
				) { lockAspect.toggle() }
				.buttonStyle(.icon(size: 28, selected: lockAspect))
				.help(lockAspect ? "Unlock Aspect Ratio" : "Lock Aspect Ratio")
				Spacer()
				Button("Fit to Content", systemImage: "arrow.down.right.and.arrow.up.left") {
					controller.fitViewBoxToContent()
				}
				.help("Set the viewBox to the drawing’s bounds")
				.buttonStyle(.borderless)
				.controlSize(.small)
			}
			AttributeField(
				title: "View Box", value: selection.value("viewBox") ?? "", prompt: "None"
			) {
				$0.isEmpty
					? controller.removeAttribute("viewBox") : controller.setAttribute("viewBox", $0)
			}
			.textFieldStyle(.roundedBorder)
		}

		let colours = DocumentColours.of(controller, limit: 24)
		if !colours.isEmpty {
			InspectorCard(title: "Colours") {
				LazyVGrid(
					columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8),
					spacing: 8
				) {
					ForEach(colours, id: \.self) { hex in
						Swatch(colour: CSSColor.parse(hex), opacity: 1, isNone: false)
							.frame(width: 24, height: 24)
							.help(hex.uppercased())
					}
				}
			}
		}
	}

	private var aspect: Double? {
		guard let width, let height, height > 0 else { return nil }
		return width / height
	}

	private func setSize(width w: Double?, height h: Double?) {
		if let w { controller.setAttribute("width", ScrubField.format(w), coalesce: true) }
		if let h { controller.setAttribute("height", ScrubField.format(h), coalesce: true) }
	}

	private var summary: String {
		let count = controller.outline.count
		let bytes = Int64(controller.document?.text.utf8.count ?? 0)
		return
			"\(count) element\(count == 1 ? "" : "s") · \(bytes.formatted(.byteCount(style: .file)))"
	}

	static func number(_ s: String) -> Double? {
		Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "px ")))
	}
}

// MARK: - All attributes

private struct AllAttributes: View {
	var selection: SelectionInfo
	var controller: CanvasController
	@AppStorage("inspector.showsAttributes") private var expanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// A full-width header you can click anywhere on, not just the chevron.
			Button {
				withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
			} label: {
				HStack(spacing: 6) {
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.bold))
						.rotationEffect(.degrees(expanded ? 90 : 0))
					Text("All Attributes")
					Text("\(selection.attributes.count)")
						.foregroundStyle(.tertiary)
					Spacer()
				}
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
				.padding(.vertical, 6)
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.help(expanded ? "Hide the raw attributes" : "Show and edit the raw attributes")
			.accessibilityLabel("All Attributes")
			.accessibilityValue(expanded ? "Expanded" : "Collapsed")

			if expanded {
				attributeList
					.transition(.opacity.combined(with: .move(edge: .top)))
			}
		}
	}

	private var attributeList: some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(selection.attributes) { attribute in
				HStack(spacing: 6) {
					Text(attribute.name)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
						.frame(width: 84, alignment: .leading)
						.lineLimit(1)
						.truncationMode(.middle)
						.help(attribute.name)
					AttributeField(title: attribute.name, value: attribute.value) {
						controller.setAttribute(attribute.name, $0)
					}
					.labelsHidden()
					.textFieldStyle(.roundedBorder)
					.font(.caption.monospaced())
					Button("Remove \(attribute.name)", systemImage: "minus.circle") {
						controller.removeAttribute(attribute.name)
					}
					.buttonStyle(.icon(size: 24))
					.help("Remove \(attribute.name)")
				}
			}
			NewAttributeRow(controller: controller)
		}
		.padding(.top, 8)
	}
}

extension Array {
	subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
