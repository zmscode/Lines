import SearchBar
import SwiftUI

/// The drawing as a table, filling the window (⌘3): every element with its
/// type, paints, effects, animations and size. Sort by any column, search by
/// name, or filter to what's animated, what has effects, or what uses a
/// particular resource. Double-click a row to see it on the canvas.
struct OutlineView: View {
	var controller: CanvasController
	/// Room taken on the leading edge by the floating code panel.
	var leadingInset: CGFloat = 0

	enum Filter: String, CaseIterable, Identifiable {
		case all, shapes, text, groups, animated, effects, resources
		var id: String { rawValue }
		var title: String {
			switch self {
			case .all: String(localized: "All Elements")
			case .shapes: String(localized: "Shapes")
			case .text: String(localized: "Text")
			case .groups: String(localized: "Groups")
			case .animated: String(localized: "Animated")
			case .effects: String(localized: "With Effects")
			case .resources: String(localized: "Resources")
			}
		}
		var symbol: String {
			switch self {
			case .all: "square.stack"
			case .shapes: "square.on.circle"
			case .text: "textformat"
			case .groups: "folder"
			case .animated: "sparkles"
			case .effects: "camera.filters"
			case .resources: "shippingbox"
			}
		}
	}

	@State private var query = ""
	@AppStorage("outline.filter") private var filter: Filter = .all
	/// Only elements using this resource (by id).
	@State private var usesResource: String?
	@State private var sortOrder: [KeyPathComparator<OutlineRow>] = []
	@State private var selection: OutlineRow.ID?

	var body: some View {
		let rows = visibleRows
		VStack(spacing: 0) {
			bar(count: rows.count)
			Divider()
			Table(rows, selection: $selection, sortOrder: $sortOrder) {
				TableColumn("Name", value: \.name) { row in
					HStack(spacing: 6) {
						// Indented by depth while in document order.
						Color.clear.frame(width: sortOrder.isEmpty ? CGFloat(row.depth) * 14 : 0)
						LayerThumbnail(item: row.item, controller: controller)
						Text(row.name).lineLimit(1).truncationMode(.middle)
						if row.item.isHidden {
							Image(systemName: "eye.slash").font(.caption).foregroundStyle(
								.secondary)
						}
					}
				}
				.width(min: 160, ideal: 240)
				TableColumn("Type", value: \.typeName) { row in
					Text(row.typeName).foregroundStyle(.secondary)
				}
				.width(min: 70, ideal: 100)
				TableColumn("Fill", value: \.fillText) { row in
					paint(row.item.fill, row: row, attribute: "fill")
				}
				.width(min: 70, ideal: 120)
				TableColumn("Stroke", value: \.strokeText) { row in
					paint(
						row.item.prop("stroke"), row: row, attribute: "stroke",
						width: row.item.prop("stroke-width"))
				}
				.width(min: 70, ideal: 120)
				TableColumn("Effects", value: \.effectsText) { row in effects(row) }
					.width(min: 60, ideal: 120)
				TableColumn("Animations", value: \.animationCount) { row in animations(row) }
					.width(min: 60, ideal: 130)
				TableColumn("Size", value: \.area) { row in
					Text(row.sizeText).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
				}
				.width(min: 60, ideal: 100)
			}
			.contextMenu(forSelectionType: OutlineRow.ID.self) { ids in
				if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
					menu(for: row)
				}
			} primaryAction: { ids in
				// Double-click: see it on the canvas.
				if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
					controller.select(order: row.item.order)
					controller.layout = .canvas
				}
			}
			.overlay {
				if rows.isEmpty {
					ContentUnavailableView(
						controller.outline.isEmpty ? "No Elements" : "Nothing Matches",
						systemImage: filter.symbol,
						description: Text(
							controller.outline.isEmpty
								? "Elements in the drawing appear here."
								: "Try another search or filter."))
				}
			}
		}
		.padding(.leading, leadingInset)
		.background(.background)
		.onChange(of: selection) { _, id in
			if let id, let row = rows.first(where: { $0.id == id }),
				controller.selection?.order != row.item.order
			{
				controller.select(order: row.item.order)
			}
		}
		.onChange(of: controller.selection?.order, initial: true) { _, order in
			let path = controller.outline.first { $0.order == order }?.path
			if selection != path { selection = path }
		}
	}

	// MARK: Bar

	private func bar(count: Int) -> some View {
		HStack(spacing: 10) {
			SearchBar(text: $query, prompt: "Search names, types and colours")
				.searchBarScale(.small)
				.frame(maxWidth: 280)
			Picker("Show", selection: $filter) {
				ForEach(Filter.allCases) { f in
					Label(f.title, systemImage: f.symbol).tag(f)
				}
			}
			.fixedSize()
			.help("Show only some kinds of element")
			Menu {
				Button("Anything") { usesResource = nil }
				Divider()
				ForEach(ResourceInfo.all(in: controller.outline)) { resource in
					Button(
						resource.name,
						systemImage: InspectorView.symbol(for: resource.item.tag, isRoot: false)
					) {
						usesResource = resource.item.elementID
					}
				}
			} label: {
				Label(usesResource.map { "Uses \($0)" } ?? "Uses Any Resource", systemImage: "link")
			}
			.fixedSize()
			.help("Show only elements that use a particular gradient, clip, mask or filter")
			Spacer()
			Text("\(count) shown")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
			if !sortOrder.isEmpty {
				Button("Document Order") { sortOrder = [] }
					.controlSize(.small)
					.help("Back to the order elements appear in the file")
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
	}

	// MARK: Rows

	private var visibleRows: [OutlineRow] {
		let outline = controller.outline
		let animations = Dictionary(grouping: controller.animations) { $0.target?.order ?? -1 }
		var rows: [OutlineRow]
		if filter == .resources {
			rows = outline.filter { ResourceInfo.isResource($0.tag) }.map {
				OutlineRow(item: $0, depth: 0, animations: [])
			}
		} else {
			rows = LayersPanel.layerItems(outline)
				.filter {
					!AnimationTag.contains($0.tag)
						&& !["title", "desc", "metadata", "style", "script"].contains($0.tag)
				}
				.map {
					OutlineRow(item: $0, depth: $0.depth, animations: animations[$0.order] ?? [])
				}
		}
		rows = rows.filter { row in
			switch filter {
			case .all, .resources: true
			case .shapes:
				[
					"rect", "circle", "ellipse", "line", "path", "polygon", "polyline", "image",
					"use",
				].contains(row.item.tag)
			case .text: row.item.tag == "text"
			case .groups: row.item.tag == "g" || row.item.tag == "a"
			case .animated: !row.animations.isEmpty
			case .effects:
				row.item.references.contains {
					["clip-path", "mask", "filter"].contains($0.attribute)
				}
			}
		}
		if let id = usesResource {
			rows = rows.filter { $0.item.references.contains { $0.targetID == id } }
		}
		let q = query.trimmingCharacters(in: .whitespaces)
		if !q.isEmpty {
			rows = rows.compactMap { row in
				FuzzyMatch.best(
					q,
					in: [
						row.name, row.typeName, row.fillText, row.strokeText,
						row.item.elementID ?? "",
					]
				)
				.map { (row, $0) }
			}
			.sorted { $0.1 > $1.1 }
			.map(\.0)
		}
		return sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
	}

	// MARK: Cells

	@ViewBuilder
	private func paint(_ value: String?, row: OutlineRow, attribute: String, width: String? = nil)
		-> some View
	{
		if let ref = row.item.references.first(where: { $0.attribute == attribute }) {
			Label(ref.targetID, systemImage: "circle.lefthalf.filled")
				.foregroundStyle(.orange)
				.lineLimit(1)
		} else if let value, value != "none" {
			HStack(spacing: 5) {
				Circle()
					.fill(CSSColor.parse(value) ?? .gray)
					.overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
					.frame(width: 11, height: 11)
				Text(width.map { "\(value) · \($0)" } ?? value)
					.font(.callout.monospaced())
					.lineLimit(1)
			}
		} else {
			Text("—").foregroundStyle(.tertiary)
		}
	}

	@ViewBuilder
	private func effects(_ row: OutlineRow) -> some View {
		let refs = row.item.references.filter {
			["clip-path", "mask", "filter"].contains($0.attribute)
		}
		if refs.isEmpty {
			Text("—").foregroundStyle(.tertiary)
		} else {
			HStack(spacing: 4) {
				ForEach(refs, id: \.self) { ref in
					Text(ref.targetID)
						.font(.caption)
						.lineLimit(1)
						.padding(.horizontal, 5)
						.padding(.vertical, 1)
						.background(effectTint(ref.attribute).opacity(0.18), in: .capsule)
						.help("\(ref.attribute): \(ref.targetID)")
				}
			}
		}
	}

	private func effectTint(_ attribute: String) -> Color {
		switch attribute {
		case "clip-path": .teal
		case "mask": .purple
		default: .pink
		}
	}

	@ViewBuilder
	private func animations(_ row: OutlineRow) -> some View {
		if row.animations.isEmpty {
			Text("—").foregroundStyle(.tertiary)
		} else {
			let first = row.animations[0]
			let timing = first.duration.map { AnimationInfo.format(seconds: $0) } ?? ""
			let more = row.animations.count > 1 ? " +\(row.animations.count - 1)" : ""
			Label("\(first.property) \(timing)\(more)", systemImage: "sparkles")
				.foregroundStyle(.indigo)
				.lineLimit(1)
				.help(row.animations.map { "\($0.property): \($0.change)" }.joined(separator: "\n"))
		}
	}

	@ViewBuilder
	private func menu(for row: OutlineRow) -> some View {
		Button("Show on Canvas", systemImage: "scope") {
			controller.select(order: row.item.order)
			controller.layout = .canvas
		}
		Button("Show in Inspector", systemImage: "slider.horizontal.3") {
			controller.select(order: row.item.order)
			controller.showsInspector = true
		}
		Divider()
		Button(
			row.item.isHidden ? "Show" : "Hide",
			systemImage: row.item.isHidden ? "eye" : "eye.slash"
		) {
			controller.toggleHidden(order: row.item.order)
		}
		.disabled(!controller.isEditing)
		Menu("Add Animation") {
			ForEach(AnimationPreset.allCases) { preset in
				Button(preset.title, systemImage: preset.symbol) {
					controller.addAnimation(preset, toOrder: row.item.order)
				}
			}
		}
		.disabled(!controller.isEditing)
		Divider()
		Button("Delete", systemImage: "trash", role: .destructive) {
			controller.delete(order: row.item.order)
		}
		.disabled(!controller.isEditing)
	}
}

/// One element in the outline table, with sortable values.
struct OutlineRow: Identifiable {
	var item: OutlineItem
	var depth: Int
	var animations: [AnimationInfo]

	var id: String { item.path }
	var name: String { item.displayName }
	var typeName: String { InspectorView.elementName(for: item.tag) }
	var fillText: String { item.fill ?? "" }
	var strokeText: String { item.prop("stroke") ?? "" }
	var effectsText: String {
		item.references.filter { ["clip-path", "mask", "filter"].contains($0.attribute) }.map(
			\.targetID
		)
		.joined(separator: " ")
	}
	var animationCount: Int { animations.count }
	var area: Double { item.box.map { Double($0.width * $0.height) } ?? -1 }
	var sizeText: String {
		guard let b = item.box else { return "—" }
		return "\(ScrubField.format(b.width)) × \(ScrubField.format(b.height))"
	}
}
