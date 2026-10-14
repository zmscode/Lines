import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	/// A layer dragged within Lines; the payload is the layer's path.
	static let linesLayer = UTType(exportedAs: "com.zms.lines.layer")
}

/// The drawing's elements as stacked cards, topmost first, one level at a
/// time: a group's card shows what's inside it, and opens to its own level,
/// with a breadcrumb back out. Resources sit in a strip below.
///
/// Drag a card to move it: a line above or below shows where it lands, a
/// highlighted group means "inside", and a breadcrumb means "into that
/// level". Dragging a card into another app copies it as SVG, and SVG files
/// dropped from the Finder are imported.
struct LayersPanel: View {
	var controller: CanvasController
	/// The panel's width: wide enough, the details sit beside the layers.
	@Binding var width: Double

	static let narrowWidth: Double = 300
	static let wideWidth: Double = 680
	/// From this width the details column shows.
	static let detailsWidth: Double = 520
	private var isWide: Bool { width >= Self.detailsWidth }

	/// The group whose contents are showing (its path); nil for the drawing.
	@State private var level: String?
	@State private var renaming: String?
	@State private var dragging: String?
	/// A resource being dragged onto a layer, to apply it.
	@State private var draggingResource: ResourceInfo?
	@State private var dropTarget: DropTarget?
	@State private var crumbTarget: String?
	@State private var filesTargeted = false
	@State private var filter = LayerFilter()

	struct DropTarget: Equatable {
		enum Zone { case above, below, inside }
		var path: String
		var zone: Zone
	}

	/// One card.
	struct Row: Identifiable {
		var node: LayerNode
		/// Where it is, when the filter lists cards from every level.
		var location: String?
		var id: String { node.id }
		var isGroup: Bool { !node.children.isEmpty || node.item.tag == "g" }
		var height: CGFloat {
			(isGroup && !node.children.isEmpty) || location != nil
				? LayersPanel.tallCardHeight : LayersPanel.cardHeight
		}
	}

	static let cardHeight: CGFloat = 60
	static let tallCardHeight: CGFloat = 80

	var body: some View {
		if isWide {
			HStack(spacing: 0) {
				// Half and half: the layers, and what applies to the selected one.
				layers.frame(maxWidth: .infinity)
				Divider()
				LayerDetails(controller: controller) { kind in filter.kinds = [kind] }
					.frame(maxWidth: .infinity)
			}
		} else {
			layers
		}
	}

	/// Elements that animate, or that SMIL animations target.
	static func animatedOrders(_ outline: [OutlineItem]) -> Set<Int> {
		Set(
			outline.filter { AnimationTag.contains($0.tag) }.map(\.parent)
				+ outline.filter { !$0.cssAnimations.isEmpty }.map(\.order))
	}

	@ViewBuilder
	private var layers: some View {
		let tree = LayerNode.build(Self.layerItems(controller.outline))
		let index = LayerIndex(tree)
		let animated = Self.animatedOrders(controller.outline)
		let current = level.flatMap { index.nodes[$0] }
		let rows =
			filter.isActive
			? matching(tree, index: index, animated: animated)
			: (current?.children ?? tree).map { Row(node: $0) }
		VStack(spacing: 0) {
			if !controller.outline.isEmpty {
				HStack(spacing: 0) {
					LayerFilterBar(
						filter: $filter, resources: ResourceInfo.all(in: controller.outline),
						matchCount: rows.count)
					detailsToggle
				}
				if !filter.isActive && current != nil {
					breadcrumb(current: current, index: index)
				}
			}
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(spacing: 6) {
						ForEach(rows) { row in
							LayerCard(
								row: row, controller: controller, renaming: $renaming,
								dropZone: dropTarget?.path == row.id ? dropTarget?.zone : nil,
								isAnimated: animated.contains(row.node.item.order),
								open: { open(row.node.id) },
								showResourceUsers: { filter.resourceID = $0 }
							)
							.id(row.id)
							.onDrag {
								dragging = row.id
								draggingResource = nil
								return provider(for: row)
							}
							.onDrop(
								of: [.linesLayer],
								delegate: RowDropDelegate(
									row: row, index: index, dragging: $dragging,
									draggingResource: $draggingResource,
									target: $dropTarget,
									perform: perform,
									apply: { resource in
										guard let attribute = resource.kind.attribute else {
											return
										}
										controller.setReference(
											order: row.node.item.order, attribute: attribute,
											targetOrder: resource.order)
									})
							)
						}
					}
					.padding(.horizontal, 8)
					.padding(.vertical, 6)
				}
				.onChange(of: controller.selection?.order) { _, order in
					if let path = reveal(order, index: index) {
						withAnimation { proxy.scrollTo(path, anchor: .center) }
					}
				}
			}
			.overlay {
				if controller.outline.isEmpty {
					ContentUnavailableView(
						"No Elements", systemImage: "square.3.layers.3d",
						description: Text("Elements in the drawing appear here."))
				} else if filter.isActive && rows.isEmpty {
					ContentUnavailableView {
						Label("No Matches", systemImage: "magnifyingglass")
					} actions: {
						Button("Clear Filter") { filter.clear() }
					}
				} else if rows.isEmpty {
					ContentUnavailableView(
						"Empty Group", systemImage: "folder",
						description: Text("Drag layers onto the breadcrumb to move them here."))
				}
			}
			.overlay {
				if filesTargeted {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.strokeBorder(.tint, lineWidth: 2)
						.padding(4)
				}
			}
			.dropDestination(for: URL.self) { urls, _ in
				importFiles(urls)
				return true
			} isTargeted: {
				filesTargeted = $0
			}

			if !controller.outline.isEmpty {
				ResourceStrip(controller: controller, draggingResource: $draggingResource)
			}
			if !isWide {
				bottomBar
			}
		}
		.onHover { inside in if !inside { controller.hover(order: nil) } }
		.onDeleteCommand {
			if controller.hasElementSelection { controller.deleteSelection() }
		}
	}

	private var detailsToggle: some View {
		Button(isWide ? "Hide Details" : "Show Details", systemImage: "sidebar.right") {
			withAnimation(.snappy(duration: 0.25)) {
				width = isWide ? Self.narrowWidth : Self.wideWidth
			}
		}
		.buttonStyle(.icon(size: 26, selected: isWide))
		.padding(.trailing, 8)
		.padding(.top, 4)
		.help(
			isWide
				? "Hide the details column"
				: "Show what applies to the selected layer, beside the layers")
	}

	// MARK: Levels

	/// "Drawing › Leaves › Stem": click to go back out, or drop a card on one
	/// to move it into that level (on top).
	private func breadcrumb(current: LayerNode?, index: LayerIndex) -> some View {
		let components = current?.id.split(separator: ".") ?? []
		let parts: [LayerNode] = components.indices.compactMap {
			index.nodes[components.prefix($0 + 1).joined(separator: ".")]
		}
		return ScrollView(.horizontal) {
			HStack(spacing: 2) {
				Button("Back", systemImage: "chevron.backward") {
					withAnimation(.snappy(duration: 0.2)) {
						level = parts.dropLast().last?.id
					}
				}
				.buttonStyle(.icon(size: 22))
				.help("Back out of \(current?.item.displayName ?? "this group")")
				crumb(title: String(localized: "Drawing"), path: nil, order: 0, index: index)
				ForEach(parts, id: \.id) { node in
					Image(systemName: "chevron.forward")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.tertiary)
					crumb(
						title: node.item.displayName, path: node.id, order: node.item.order,
						index: index)
				}
			}
			.padding(.horizontal, 8)
		}
		.scrollIndicators(.never)
		.frame(height: 30)
	}

	private func crumb(title: String, path: String?, order: Int, index: LayerIndex) -> some View {
		let key = path ?? ""
		return Button(title) {
			withAnimation(.snappy(duration: 0.2)) { level = path }
		}
		.buttonStyle(.plain)
		.font(.callout.weight(path == level ? .semibold : .regular))
		.foregroundStyle(path == level ? .primary : .secondary)
		.lineLimit(1)
		.padding(.horizontal, 6)
		.padding(.vertical, 3)
		.background(
			crumbTarget == key ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
			in: .capsule
		)
		.help(path == level ? "Showing \(title)" : "Show \(title)")
		.onDrop(
			of: [.linesLayer],
			isTargeted: Binding(
				get: { crumbTarget == key },
				set: { crumbTarget = $0 ? key : (crumbTarget == key ? nil : crumbTarget) }
			)
		) { _ in
			defer { dragging = nil }
			guard let dragging, let source = index.nodes[dragging]?.item.order,
				dragging != path, !(path ?? "").hasPrefix(dragging + ".")
			else { return false }
			// On top: after the level's last child.
			let siblings = path.flatMap { index.nodes[$0]?.children } ?? []
			let top =
				path == nil
				? controller.outline.last(where: { $0.parent == 0 })?.order
				: siblings.first?.item.order
			controller.move(orders: [source], intoParent: order, after: top)
			return true
		}
	}

	private func open(_ path: String) {
		withAnimation(.snappy(duration: 0.2)) {
			filter.clear()
			level = path
		}
	}

	/// Shows the level holding the selected element; returns its card.
	private func reveal(_ order: Int?, index: LayerIndex) -> String? {
		guard !filter.isActive, let order,
			let item = controller.outline.first(where: { $0.order == order }),
			index.nodes[item.path] != nil
		else { return nil }
		let parent = item.path.split(separator: ".").dropLast().joined(separator: ".")
		let target = parent.isEmpty ? nil : parent
		if target != level {
			withAnimation(.snappy(duration: 0.2)) { level = target }
		}
		return item.path
	}

	// MARK: Tree

	/// The drawing's elements without <defs>, resources (which have their own
	/// strip) and what sits inside them.
	static func layerItems(_ outline: [OutlineItem]) -> [OutlineItem] {
		var hidden = Set<Int>()
		for item in outline {
			if hidden.contains(item.parent) || item.tag == "defs"
				|| ResourceInfo.isResource(item.tag)
			{
				hidden.insert(item.order)
			}
		}
		return outline.filter { !hidden.contains($0.order) }
	}

	/// Every card the filter matches, from every level, with where each is.
	private func matching(_ nodes: [LayerNode], index: LayerIndex, animated: Set<Int>) -> [Row] {
		var rows: [Row] = []
		func walk(_ nodes: [LayerNode], trail: [String]) {
			for node in nodes {
				if filter.matches(node.item, animated: animated) {
					rows.append(
						Row(
							node: node,
							location: trail.isEmpty
								? String(localized: "Drawing")
								: trail.joined(separator: " › ")))
				}
				walk(node.children, trail: trail + [node.item.displayName])
			}
		}
		walk(nodes, trail: [])
		return rows
	}

	// MARK: Drag and drop

	private func provider(for row: Row) -> NSItemProvider {
		let provider = NSItemProvider()
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.linesLayer.identifier, visibility: .ownProcess
		) {
			completion in
			completion(Data(row.id.utf8), nil)
			return nil
		}
		// Other apps get the element as a standalone SVG.
		let controller = controller
		let order = row.node.item.order
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.svg.identifier, visibility: .all
		) {
			completion in
			Task { @MainActor in
				let element = await controller.markup(order: order) ?? ""
				let svg =
					"<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">\(element)</svg>"
				completion(Data(svg.utf8), nil)
			}
			return nil
		}
		provider.suggestedName = row.node.item.displayName
		return provider
	}

	/// The list is topmost-first, the reverse of document order: dropping
	/// above a row puts the layer after it in the file, and below means before.
	private func perform(_ path: String, onto target: DropTarget, index: LayerIndex) {
		guard let source = index.nodes[path]?.item.order,
			let destination = index.nodes[target.path]?.item.order
		else { return }
		switch target.zone {
		case .above: controller.move(orders: [source], relativeTo: destination, position: .after)
		case .below: controller.move(orders: [source], relativeTo: destination, position: .before)
		case .inside:
			controller.move(orders: [source], relativeTo: destination, position: .inside)
		}
	}

	/// SVG files dropped from the Finder are added as groups.
	private func importFiles(_ urls: [URL]) {
		for url in urls where url.pathExtension.lowercased() == "svg" {
			guard let markup = try? String(contentsOf: url, encoding: .utf8) else { continue }
			controller.paste(markup: markup)
		}
	}

	// MARK: Bottom bar

	/// Group, Duplicate and Delete, in the narrow panel; the wide one leaves
	/// them to the context menu.
	private var bottomBar: some View {
		HStack(spacing: 2) {
			Button("Group", systemImage: "square.on.square.dashed") { controller.groupSelection() }
				.help("Group the selected element (⌥⌘G)")
			Button("Duplicate", systemImage: "plus.square.on.square") {
				controller.duplicateSelection()
			}
			.help("Duplicate (⌘D)")
			Spacer()
			Button("Delete", systemImage: "trash") { controller.deleteSelection() }
				.help("Delete the selected element")
		}
		.disabled(!controller.isEditing || !controller.hasElementSelection)
		.buttonStyle(.icon(size: 28))
		.padding(.horizontal, 8)
		.padding(.vertical, 8)
		.overlay(alignment: .top) { Divider().opacity(0.6) }
	}
}

/// Works out where a dragged layer would land as the pointer moves over a row.
private struct RowDropDelegate: DropDelegate {
	var row: LayersPanel.Row
	var index: LayerIndex
	@Binding var dragging: String?
	@Binding var draggingResource: ResourceInfo?
	@Binding var target: LayersPanel.DropTarget?
	var perform: (String, LayersPanel.DropTarget, LayerIndex) -> Void
	var apply: (ResourceInfo) -> Void

	/// A resource can land on drawn elements (and groups, for clips, masks, filters).
	private var acceptsResource: Bool {
		guard let resource = draggingResource, resource.kind.attribute != nil else { return false }
		let tag = row.node.item.tag
		if resource.kind == .gradient || resource.kind == .pattern {
			return [
				"rect", "circle", "ellipse", "path", "polygon", "polyline", "text", "line", "g",
			]
			.contains(tag)
		}
		return !AnimationTag.contains(tag)
	}

	private var isGroup: Bool { row.node.item.tag == "g" || !row.node.children.isEmpty }

	func validateDrop(info: DropInfo) -> Bool {
		if draggingResource != nil { return acceptsResource }
		guard let dragging else { return false }
		// Never into itself or its own descendants.
		return row.id != dragging && !row.id.hasPrefix(dragging + ".")
	}

	func dropEntered(info: DropInfo) { update(info) }

	func dropUpdated(info: DropInfo) -> DropProposal? {
		update(info)
		return DropProposal(operation: .move)
	}

	func dropExited(info: DropInfo) {
		if target?.path == row.id { target = nil }
	}

	func performDrop(info: DropInfo) -> Bool {
		defer {
			target = nil
			dragging = nil
		}
		if let resource = draggingResource {
			draggingResource = nil
			guard acceptsResource else { return false }
			apply(resource)
			return true
		}
		guard let dragging, let target, validateDrop(info: info) else { return false }
		perform(dragging, target, index)
		return true
	}

	private func update(_ info: DropInfo) {
		guard validateDrop(info: info) else {
			target = nil
			return
		}
		// A resource applies to the whole row.
		if draggingResource != nil {
			let next = LayersPanel.DropTarget(path: row.id, zone: .inside)
			if target != next { target = next }
			return
		}
		let y = info.location.y / row.height
		let zone: LayersPanel.DropTarget.Zone =
			isGroup ? (y < 0.3 ? .above : y > 0.7 ? .below : .inside) : (y < 0.5 ? .above : .below)
		let next = LayersPanel.DropTarget(path: row.id, zone: zone)
		if target != next { target = next }
	}
}

// MARK: - Card

private struct LayerCard: View {
	var row: LayersPanel.Row
	var controller: CanvasController
	@Binding var renaming: String?
	var dropZone: LayersPanel.DropTarget.Zone?
	var isAnimated = false
	/// Shows the group's own level.
	var open: () -> Void
	/// Filters the panel to what uses a resource, by its id.
	var showResourceUsers: (String) -> Void = { _ in }

	@State private var isHovered = false
	@State private var draft = ""
	@FocusState private var nameFocused: Bool

	private var item: OutlineItem { row.node.item }
	private var isGroup: Bool { row.isGroup }
	private var isSelected: Bool {
		controller.hasElementSelection && controller.selection?.order == item.order
	}
	private var isRenaming: Bool { renaming == item.id }

	private var kind: String {
		let name = InspectorView.elementName(for: item.tag)
		let count = row.node.children.count
		if isGroup { return count == 1 ? "\(name) · 1 item" : "\(name) · \(count) items" }
		if let box = item.box {
			return
				"\(name) · \(Double(box.width).formatted(.number.precision(.fractionLength(0)))) × \(Double(box.height).formatted(.number.precision(.fractionLength(0))))"
		}
		return name
	}

	var body: some View {
		HStack(spacing: 10) {
			LayerThumbnail(item: item, controller: controller, size: 44)

			VStack(alignment: .leading, spacing: 3) {
				name
				HStack(spacing: 6) {
					Text(kind)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
					LayerBadges(item: item, isAnimated: isAnimated, controller: controller)
				}
				if let location = row.location {
					Label(location, systemImage: "folder")
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.lineLimit(1)
						.truncationMode(.head)
				} else if !row.node.children.isEmpty {
					childStrip
				}
			}

			Spacer(minLength: 4)

			Button(
				item.isHidden ? "Show" : "Hide", systemImage: item.isHidden ? "eye.slash" : "eye"
			) {
				controller.toggleHidden(order: item.order)
			}
			.buttonStyle(.icon(size: 22))
			.opacity((isHovered && controller.isEditing) || item.isHidden ? 1 : 0)
			.disabled(!controller.isEditing)
			.help(item.isHidden ? "Show Element" : "Hide Element")

			if !row.node.children.isEmpty {
				Button("Open", systemImage: "chevron.forward", action: open)
					.buttonStyle(.icon(size: 22))
					.help("Show what's inside \(item.displayName)")
			}
		}
		.padding(.horizontal, 8)
		.frame(height: row.height)
		.background {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(cardFill)
		}
		.overlay {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(
					dropZone == .inside
						? AnyShapeStyle(.tint)
						: isSelected
							? AnyShapeStyle(.tint.opacity(0.7))
							: AnyShapeStyle(.separator.opacity(0.5)),
					lineWidth: dropZone == .inside ? 2 : 1)
		}
		.overlay(alignment: dropZone == .below ? .bottom : .top) {
			if dropZone == .above || dropZone == .below {
				Capsule().fill(.tint).frame(height: 3)
					.padding(.horizontal, 6)
					.offset(y: dropZone == .above ? -4 : 4)
			}
		}
		.opacity(item.isHidden ? 0.6 : 1)
		.contentShape(.rect)
		.onTapGesture { controller.select(order: item.order) }
		.onHover { hovering in
			isHovered = hovering
			controller.hover(order: hovering ? item.order : nil)
		}
		.contextMenu { menu.disabled(!controller.isEditing) }
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(item.displayName), \(kind)")
		.accessibilityValue(item.isHidden ? "Hidden" : "")
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.accessibilityAction { controller.select(order: item.order) }
		.accessibilityAction(named: item.isHidden ? "Show" : "Hide") {
			controller.toggleHidden(order: item.order)
		}
		.accessibilityAction(named: "Rename") { renaming = item.id }
		.accessibilityAction(named: "Open") { if !row.node.children.isEmpty { open() } }
	}

	/// The group's contents, small; click to open it.
	private var childStrip: some View {
		let shown = row.node.children.prefix(6)
		return Button(action: open) {
			HStack(spacing: 3) {
				ForEach(Array(shown), id: \.id) { child in
					LayerThumbnail(item: child.item, controller: controller, size: 18)
				}
				if row.node.children.count > shown.count {
					Text("+\(row.node.children.count - shown.count)")
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.help("Show what's inside \(item.displayName)")
	}

	@ViewBuilder
	private var name: some View {
		if isRenaming {
			TextField("Name", text: $draft)
				.textFieldStyle(.roundedBorder)
				.controlSize(.small)
				.focused($nameFocused)
				.onSubmit(finishRename)
				.onExitCommand { renaming = nil }
				.onChange(of: nameFocused) { _, focused in if !focused { finishRename() } }
				.onAppear {
					draft = item.elementID ?? ""
					nameFocused = true
				}
		} else {
			Text(item.displayName)
				.font(.callout.weight(.medium))
				.lineLimit(1)
				.truncationMode(.middle)
				.simultaneousGesture(
					TapGesture(count: 2).onEnded {
						if controller.isEditing { renaming = item.id }
					}
				)
				.help(item.displayName)
		}
	}

	private var cardFill: AnyShapeStyle {
		if isSelected { return AnyShapeStyle(.tint.opacity(0.16)) }
		if isHovered { return AnyShapeStyle(.quaternary) }
		return AnyShapeStyle(.quaternary.opacity(0.45))
	}

	@ViewBuilder
	private var menu: some View {
		Button("Rename", systemImage: "pencil") { renaming = item.id }
		Button(item.isHidden ? "Show" : "Hide", systemImage: item.isHidden ? "eye" : "eye.slash") {
			controller.toggleHidden(order: item.order)
		}
		Divider()
		Button("Duplicate", systemImage: "plus.square.on.square") {
			controller.select(order: item.order)
			controller.duplicateSelection()
		}
		Button("Group", systemImage: "square.on.square.dashed") {
			controller.select(order: item.order)
			controller.groupSelection()
		}
		if isGroup {
			Button("Ungroup") {
				controller.select(order: item.order)
				controller.ungroupSelection()
			}
		}
		Divider()
		Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") {
			controller.select(order: item.order)
			controller.reorder(.front)
		}
		Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
			controller.select(order: item.order)
			controller.reorder(.forward)
		}
		Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
			controller.select(order: item.order)
			controller.reorder(.backward)
		}
		Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") {
			controller.select(order: item.order)
			controller.reorder(.back)
		}
		let used = Array(Set(item.references.map(\.targetID))).sorted()
		if !used.isEmpty {
			Divider()
			ForEach(used, id: \.self) { id in
				Button("Show Everything Using \(id)", systemImage: "line.3.horizontal.decrease") {
					showResourceUsers(id)
				}
			}
		}
		Divider()
		Button("Copy", systemImage: "doc.on.doc") {
			Task {
				guard let markup = await controller.markup(order: item.order) else { return }
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(markup, forType: .string)
			}
		}
		Button("Delete", systemImage: "trash", role: .destructive) {
			controller.delete(order: item.order)
		}
	}

	private func finishRename() {
		guard isRenaming else { return }
		if draft != (item.elementID ?? "") { controller.rename(order: item.order, to: draft) }
		renaming = nil
	}

}
