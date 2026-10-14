import SwiftUI

/// What the Layers panel is narrowed to: a fuzzy search over names, types and
/// colours, kinds of element, and what uses a particular resource.
struct LayerFilter: Equatable {
	enum Kind: String, CaseIterable, Identifiable {
		case shapes, text, groups, images, animated, effects, hidden

		var id: String { rawValue }

		var title: LocalizedStringKey {
			switch self {
			case .shapes: "Shapes"
			case .text: "Text"
			case .groups: "Groups"
			case .images: "Images"
			case .animated: "Animated"
			case .effects: "With Effects"
			case .hidden: "Hidden"
			}
		}

		var symbol: String {
			switch self {
			case .shapes: "square.on.circle"
			case .text: "textformat"
			case .groups: "folder"
			case .images: "photo"
			case .animated: "sparkles"
			case .effects: "camera.filters"
			case .hidden: "eye.slash"
			}
		}
	}

	var query = ""
	var kinds: Set<Kind> = []
	/// Only elements using this resource (its `id`).
	var resourceID: String?

	var isActive: Bool {
		!query.trimmingCharacters(in: .whitespaces).isEmpty || !kinds.isEmpty || resourceID != nil
	}

	/// Kind and resource filters, without the search text.
	var narrowsKinds: Bool { !kinds.isEmpty || resourceID != nil }

	mutating func clear() { self = LayerFilter() }

	private static let shapeTags: Set = [
		"rect", "circle", "ellipse", "line", "polyline", "polygon", "path",
	]
	private static let textTags: Set = ["text", "tspan", "textPath"]

	/// Whether the element itself passes; `animated` holds the orders of animated elements.
	func matches(_ item: OutlineItem, animated: Set<Int>) -> Bool {
		if let resourceID, !item.references.contains(where: { $0.targetID == resourceID }) {
			return false
		}
		if !kinds.isEmpty {
			// Kinds of element widen each other; the rest narrow.
			let types = kinds.intersection([.shapes, .text, .groups, .images])
			if !types.isEmpty && !types.contains(where: { isKind(item, $0) }) { return false }
			if kinds.contains(.animated) && !animated.contains(item.order) { return false }
			if kinds.contains(.effects)
				&& !item.references.contains(where: {
					["filter", "clip-path", "mask"].contains($0.attribute)
				})
			{
				return false
			}
			if kinds.contains(.hidden) && !item.isHidden { return false }
		}
		let q = query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return true }
		return FuzzyMatch.best(q, in: Self.searchText(item)) != nil
	}

	private func isKind(_ item: OutlineItem, _ kind: Kind) -> Bool {
		switch kind {
		case .shapes: Self.shapeTags.contains(item.tag)
		case .text: Self.textTags.contains(item.tag)
		case .groups: item.tag == "g" || item.tag == "a" || item.tag == "svg"
		case .images: item.tag == "image" || item.tag == "use"
		default: false
		}
	}

	/// The names, type and colours an element can be found by.
	private static func searchText(_ item: OutlineItem) -> [String] {
		var texts = [item.displayName, item.tag, InspectorView.elementName(for: item.tag)]
		if let id = item.elementID { texts.append(id) }
		for paint in [item.fill, item.prop("fill"), item.prop("stroke")].compactMap({ $0 })
		where paint != "none" && !paint.hasPrefix("url(") {
			texts.append(paint)
			texts.append(ColourName.of(paint))
		}
		texts += item.references.map(\.targetID)
		return texts
	}
}

/// The search field and filter menu at the top of the Layers panel.
struct LayerFilterBar: View {
	@Binding var filter: LayerFilter
	var resources: [ResourceInfo]
	var matchCount: Int

	@FocusState private var isFocused: Bool

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			TextField("Filter", text: $filter.query)
				.textFieldStyle(.plain)
				.focused($isFocused)
				.onExitCommand {
					filter.query = ""
					isFocused = false
				}
				.help("Find layers by name, type or colour")
			if filter.isActive {
				Text("\(matchCount)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
					.accessibilityLabel("\(matchCount) matches")
				Button("Clear Filter", systemImage: "xmark.circle.fill") { filter.clear() }
					.buttonStyle(.plain)
					.labelStyle(.iconOnly)
					.foregroundStyle(.secondary)
					.help("Clear the search and filters")
			}
			filterMenu
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7, style: .continuous))
		.padding(.horizontal, 8)
		.padding(.top, 6)
		.padding(.bottom, 2)
	}

	private var filterMenu: some View {
		Menu {
			Section("Show") {
				ForEach(LayerFilter.Kind.allCases) { kind in
					Toggle(isOn: binding(kind)) { Label(kind.title, systemImage: kind.symbol) }
				}
			}
			let usable = resources.filter { !$0.isUnused && $0.item.elementID != nil }
			if !usable.isEmpty {
				Section("Using") {
					ForEach(usable) { resource in
						Toggle(
							isOn: Binding(
								get: { filter.resourceID == resource.item.elementID },
								set: { filter.resourceID = $0 ? resource.item.elementID : nil })
						) {
							Text(resource.name)
						}
					}
				}
			}
			if filter.narrowsKinds {
				Divider()
				Button("Show All") {
					filter.kinds = []
					filter.resourceID = nil
				}
			}
		} label: {
			Image(
				systemName: filter.narrowsKinds
					? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
			)
			.foregroundStyle(filter.narrowsKinds ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
		}
		.menuStyle(.button)
		.buttonStyle(.plain)
		.menuIndicator(.hidden)
		.fixedSize()
		.help("Filter by kind, or by what uses a resource")
		.accessibilityLabel("Filters")
	}

	private func binding(_ kind: LayerFilter.Kind) -> Binding<Bool> {
		Binding(
			get: { filter.kinds.contains(kind) },
			set: { on in
				if on { filter.kinds.insert(kind) } else { filter.kinds.remove(kind) }
			})
	}
}
