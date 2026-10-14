import SwiftUI

/// Filters, clip paths and masks on the selected element: pick an existing
/// definition, make a new one fitted to the element, or remove it. A filter's
/// main parameters (blur radius, shadow offset…) edit in place.
struct EffectsCard: View {
	var selection: SelectionInfo
	var controller: CanvasController

	private struct Slot {
		var title: String
		var attribute: String
		var tag: String
		var symbol: String
		var new: [CanvasController.Definition]
	}

	private var slots: [Slot] {
		var slots = [
			Slot(
				title: "Filter", attribute: "filter", tag: "filter", symbol: "camera.filters",
				new: [.blur, .shadow]),
			Slot(
				title: "Clip", attribute: "clip-path", tag: "clipPath", symbol: "scissors",
				new: [.clipPath]),
			Slot(
				title: "Mask", attribute: "mask", tag: "mask", symbol: "theatermasks", new: [.mask]),
		]
		if selection.tag == "svg" || selection.tag == "defs" { slots.removeAll() }
		return slots
	}

	var body: some View {
		if !slots.isEmpty {
			InspectorCard(title: "Effects") {
				ForEach(slots, id: \.attribute) { slot in
					row(slot)
					if slot.attribute == "filter", let filter = referenced(slot) {
						FilterParameters(filter: filter, controller: controller)
					}
					if slot.attribute != "filter", let definition = referenced(slot) {
						MaskEditor(definition: definition, controller: controller)
							.padding(.leading, 22)
					}
				}
			}
		}
	}

	private func row(_ slot: Slot) -> some View {
		let current = referenced(slot)
		return HStack(spacing: 6) {
			Label(slot.title, systemImage: slot.symbol)
				.foregroundStyle(.secondary)
			Spacer()
			Menu {
				Button("None") {
					controller.setAttribute(slot.attribute, nil, onOrder: selection.order)
				}
				let existing = definitions(slot)
				if !existing.isEmpty {
					Divider()
					ForEach(existing) { item in
						Button(item.elementID ?? item.displayName) {
							controller.setAttribute(
								slot.attribute, "url(#\(item.elementID ?? ""))",
								onOrder: selection.order)
						}
					}
				}
				Divider()
				ForEach(slot.new) { kind in
					Button("New \(kind.title)", systemImage: kind.symbol) {
						controller.addDefinition(kind, applyingTo: selection.order)
					}
				}
			} label: {
				Text(current.map { $0.elementID ?? $0.displayName } ?? "None")
					.lineLimit(1)
			}
			.fixedSize()
			.help("Choose the \(slot.title.lowercased()) applied to this element")
			Button("Edit \(slot.title)", systemImage: "arrow.right.circle") {
				if let current { controller.select(order: current.order) }
			}
			.buttonStyle(.icon(size: 22))
			.disabled(current == nil)
			.help(current == nil ? "No \(slot.title.lowercased()) to edit" : "Select it to edit")
		}
	}

	/// The definition this slot points at, from `url(#id)`.
	private func referenced(_ slot: Slot) -> OutlineItem? {
		guard let value = selection.value(slot.attribute),
			let match = value.firstMatch(of: #/url\(\s*['"]?#([^'")\s]+)/#)
		else { return nil }
		let id = String(match.1)
		return controller.outline.first { $0.elementID == id }
	}

	private func definitions(_ slot: Slot) -> [OutlineItem] {
		controller.outline.filter { $0.tag == slot.tag && $0.elementID != nil }
	}
}

/// The main settings of each primitive in a filter.
private struct FilterParameters: View {
	var filter: OutlineItem
	var controller: CanvasController

	private var primitives: [OutlineItem] {
		controller.outline.filter { $0.parent == filter.order && $0.tag.hasPrefix("fe") }
	}

	var body: some View {
		ForEach(primitives) { primitive in
			ForEach(Self.parameters(for: primitive.tag), id: \.name) { parameter in
				HStack {
					Text(parameter.title)
						.foregroundStyle(.secondary)
						.padding(.leading, 22)
					Spacer()
					ScrubField(
						label: parameter.title, systemImage: parameter.symbol,
						value: primitive.prop(parameter.name).flatMap {
							Double($0.split(separator: " ").first ?? "")
						} ?? parameter.fallback,
						range: parameter.range, step: parameter.step
					) {
						controller.setAttribute(
							parameter.name, ScrubField.format($0), onOrder: primitive.order,
							coalesce: true)
					}
					.frame(width: 116)
				}
			}
		}
	}

	struct Parameter {
		var name: String
		var title: String
		var symbol: String
		var fallback: Double
		var range: ClosedRange<Double>
		var step: Double
	}

	static func parameters(for tag: String) -> [Parameter] {
		let blur = Parameter(
			name: "stdDeviation", title: "Blur", symbol: "drop", fallback: 0, range: 0...500,
			step: 0.5)
		switch tag {
		case "feGaussianBlur": return [blur]
		case "feDropShadow":
			return [
				Parameter(
					name: "dx", title: "Offset X", symbol: "arrow.left.and.right", fallback: 2,
					range: -1000...1000, step: 0.5),
				Parameter(
					name: "dy", title: "Offset Y", symbol: "arrow.up.and.down", fallback: 2,
					range: -1000...1000, step: 0.5),
				blur,
				Parameter(
					name: "flood-opacity", title: "Opacity", symbol: "circle.lefthalf.filled",
					fallback: 1, range: 0...1, step: 0.05),
			]
		case "feOffset":
			return [
				Parameter(
					name: "dx", title: "Offset X", symbol: "arrow.left.and.right", fallback: 0,
					range: -1000...1000, step: 0.5),
				Parameter(
					name: "dy", title: "Offset Y", symbol: "arrow.up.and.down", fallback: 0,
					range: -1000...1000, step: 0.5),
			]
		case "feMorphology":
			return [
				Parameter(
					name: "radius", title: "Radius", symbol: "circle.dashed", fallback: 0,
					range: 0...200, step: 0.5)
			]
		default: return []
		}
	}
}
