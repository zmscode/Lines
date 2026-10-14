import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	/// A layer dragged within Lines; the payload is the layer's path.
	static let linesLayer = UTType(exportedAs: "com.zms.lines.layer")
}

/// The drawing's elements, topmost first, with what applies to each attached
/// beneath it — its clip, mask, filter, gradient or pattern paint, and its
/// animations — the way Affinity and Illustrator show clips and masks under
/// what they affect, rather than off in <defs>. The Resources tab holds the
/// whole library, used or not.
///
/// Drag a row to move it: a line above or below shows where it lands, and a
/// highlighted group means "inside". Drag an attachment (or a resource) onto
/// another row to apply it there too. Dragging a row into another app copies
/// it as SVG, and SVG files dropped from the Finder are imported.
struct LayersPanel: View {
	var controller: CanvasController

	enum Tab: String { case layers, resources }

	@AppStorage("layers.tab") private var tab: Tab = .layers
	@State private var expanded: Set<String> = []
	@State private var renaming: String?
	@State private var dragging: String?
	/// A resource being dragged onto a layer, to apply it, and how.
	@State private var draggingResource: ResourceInfo?
	@State private var draggingAttribute: String?
	@State private var dropTarget: DropTarget?
	@State private var filesTargeted = false
	@State private var filter = LayerFilter()

	struct DropTarget: Equatable {
		enum Zone { case above, below, inside }
		var path: String
		var zone: Zone
	}

	/// An element's row.
	struct Row: Identifiable {
		var node: LayerNode
		var depth: Int
		/// Where it is, when the filter lists matches from every level.
		var location: String?
		var id: String { node.id }
		var height: CGFloat { LayersPanel.rowHeight }
	}

	/// One line of the list: an element, or something applied to the one above.
	enum Line: Identifiable {
		case element(Row, attachments: [Attachment])
		case attachment(Attachment, depth: Int)

		var id: String {
			switch self {
			case .element(let row, _): row.id
			case .attachment(let a, _): a.id
			}
		}
	}

	static let rowHeight: CGFloat = 30
	static let attachmentHeight: CGFloat = 24

	var body: some View {
		let outline = controller.outline
		let resources = ResourceInfo.all(in: outline)
		VStack(spacing: 0) {
			Picker("Show", selection: $tab) {
				Text("Layers").tag(Tab.layers)
				Text("Resources (\(resources.count))").tag(Tab.resources)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.padding(.horizontal, 10)
			.padding(.top, 2)
			.padding(.bottom, 4)

			switch tab {
			case .layers: layers(resources: resources)
			case .resources:
				ResourcesList(
					controller: controller, resources: resources,
					showUser: { order in
						tab = .layers
						controller.select(order: order)
					})
			}
		}
		.onHover { inside in if !inside { controller.hover(order: nil) } }
		.onDeleteCommand {
			if controller.hasElementSelection { controller.deleteSelection() }
		}
	}

	// MARK: Layers

	@ViewBuilder
	private func layers(resources: [ResourceInfo]) -> some View {
		let outline = controller.outline
		let tree = LayerNode.build(Self.layerItems(outline))
		let index = LayerIndex(tree)
		let attachments = Attachment.all(
			in: outline, resources: resources, animations: controller.animations)
		let lines =
			filter.isActive
			? matching(tree, attachments: attachments)
			: flatten(tree, attachments: attachments)
		if !outline.isEmpty {
			LayerFilterBar(
				filter: $filter, resources: resources,
				matchCount: lines.count(where: { if case .element = $0 { true } else { false } }))
		}
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(spacing: 0) {
					ForEach(lines) { line in
						switch line {
						case .element(let row, let attached):
							elementRow(row, attached: attached, index: index)
						case .attachment(let attachment, let depth):
							AttachmentRow(
								attachment: attachment, depth: depth, controller: controller
							)
							.onDrag {
								guard case .resource(let resource, let attribute) = attachment.kind
								else { return NSItemProvider() }
								dragging = nil
								draggingResource = resource
								draggingAttribute = attribute
								return ResourcesList.provider(for: resource)
							}
						}
					}
				}
				.padding(.horizontal, 6)
				.padding(.vertical, 4)
			}
			.onChange(of: controller.selection?.order) { _, order in
				if let path = revealSelection(order) {
					withAnimation { proxy.scrollTo(path, anchor: .center) }
				}
			}
		}
		.overlay {
			if outline.isEmpty {
				ContentUnavailableView(
					"No Elements", systemImage: "square.3.layers.3d",
					description: Text("Elements in the drawing appear here."))
			} else if filter.isActive && lines.isEmpty {
				ContentUnavailableView {
					Label("No Matches", systemImage: "magnifyingglass")
				} actions: {
					Button("Clear Filter") { filter.clear() }
				}
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
	}

	private func elementRow(_ row: Row, attached: [Attachment], index: LayerIndex) -> some View {
		let hasChildren = !row.node.children.isEmpty || !attached.isEmpty
		return LayerRow(
			row: row, attachments: attached, controller: controller,
			hasChildren: hasChildren,
			isExpanded: hasChildren && (filter.isActive ? false : expanded.contains(row.id)),
			toggleExpanded: { toggle(row.id) }, renaming: $renaming,
			dropZone: dropTarget?.path == row.id ? dropTarget?.zone : nil,
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
					guard let attribute = draggingAttribute ?? resource.kind.attribute else {
						return
					}
					draggingAttribute = nil
					controller.setReference(
						order: row.node.item.order, attribute: attribute,
						targetOrder: resource.order)
					expanded.insert(row.id)
				})
		)
	}

	// MARK: Tree

	/// The drawing's elements without <defs>, resources (in their own tab),
	/// animations (attached to what they animate) and what sits inside them.
	static func layerItems(_ outline: [OutlineItem]) -> [OutlineItem] {
		var hidden = Set<Int>()
		for item in outline {
			if hidden.contains(item.parent) || item.tag == "defs"
				|| ResourceInfo.isResource(item.tag) || AnimationTag.contains(item.tag)
			{
				hidden.insert(item.order)
			}
		}
		return outline.filter { !hidden.contains($0.order) }
	}

	/// Each element, then (when open) what applies to it, then its children.
	private func flatten(
		_ nodes: [LayerNode], depth: Int = 0, attachments: [Int: [Attachment]]
	) -> [Line] {
		nodes.flatMap { node -> [Line] in
			let attached = attachments[node.item.order] ?? []
			var lines: [Line] = [.element(Row(node: node, depth: depth), attachments: attached)]
			guard expanded.contains(node.id) else { return lines }
			lines += attached.map { .attachment($0, depth: depth + 1) }
			lines += flatten(node.children, depth: depth + 1, attachments: attachments)
			return lines
		}
	}

	/// Every element the filter matches, from every level, with where it is.
	private func matching(_ nodes: [LayerNode], attachments: [Int: [Attachment]]) -> [Line] {
		let animated = Self.animatedOrders(controller.outline)
		var lines: [Line] = []
		func walk(_ nodes: [LayerNode], trail: [String]) {
			for node in nodes {
				if filter.matches(node.item, animated: animated) {
					lines.append(
						.element(
							Row(
								node: node, depth: 0,
								location: trail.isEmpty
									? String(localized: "Drawing")
									: trail.joined(separator: " › ")),
							attachments: attachments[node.item.order] ?? []))
				}
				walk(node.children, trail: trail + [node.item.displayName])
			}
		}
		walk(nodes, trail: [])
		return lines
	}

	/// Elements that animate, or that SMIL animations target.
	static func animatedOrders(_ outline: [OutlineItem]) -> Set<Int> {
		Set(AnimationInfo.all(in: outline).compactMap { $0.target?.order })
	}

	private func toggle(_ path: String) {
		withAnimation(.snappy(duration: 0.2)) {
			if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
		}
	}

	/// Opens the groups containing the selected element; returns its row.
	private func revealSelection(_ order: Int?) -> String? {
		guard let order, let item = controller.outline.first(where: { $0.order == order }),
			Self.layerItems(controller.outline).contains(where: { $0.order == order })
		else { return nil }
		if tab != .layers { return nil }
		let parts = item.path.split(separator: ".")
		for length in stride(from: 1, to: parts.count, by: 1) {
			expanded.insert(parts.prefix(length).joined(separator: "."))
		}
		return item.path
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

// MARK: - Element row

private struct LayerRow: View {
	var row: LayersPanel.Row
	var attachments: [Attachment]
	var controller: CanvasController
	var hasChildren: Bool
	var isExpanded: Bool
	var toggleExpanded: () -> Void
	@Binding var renaming: String?
	var dropZone: LayersPanel.DropTarget.Zone?
	/// Filters the panel to what uses a resource, by its id.
	var showResourceUsers: (String) -> Void = { _ in }

	@State private var isHovered = false
	@State private var draft = ""
	@FocusState private var nameFocused: Bool

	private var item: OutlineItem { row.node.item }
	private var isGroup: Bool { !row.node.children.isEmpty || item.tag == "g" }
	private var isSelected: Bool {
		controller.hasElementSelection && controller.selection?.order == item.order
	}
	private var isRenaming: Bool { renaming == item.id }

	var body: some View {
		HStack(spacing: 5) {
			Color.clear.frame(width: CGFloat(row.depth) * 16)

			Button(action: toggleExpanded) {
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.bold))
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.foregroundStyle(.secondary)
					.frame(width: 12, height: 20)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.opacity(hasChildren && row.location == nil ? 1 : 0)
			.disabled(!hasChildren || row.location != nil)
			.help(isExpanded ? "Collapse" : "Show what's inside and what applies to it")
			.accessibilityLabel(isExpanded ? "Collapse" : "Expand")

			LayerThumbnail(item: item, controller: controller, size: 22)

			VStack(alignment: .leading, spacing: 0) {
				name
				if let location = row.location {
					Text(location)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.lineLimit(1)
						.truncationMode(.head)
				}
			}

			Spacer(minLength: 4)

			// What applies, at a glance while closed; open the row for the details.
			if !isExpanded {
				HStack(spacing: 3) {
					ForEach(Array(attachments.prefix(5).enumerated()), id: \.offset) { _, a in
						Image(systemName: a.symbol)
							.font(.system(size: 9, weight: .semibold))
							.foregroundStyle(a.tint)
							.help(a.summary)
					}
				}
				.accessibilityHidden(true)
			}
			PaintDots(item: item)

			Text(InspectorView.elementName(for: item.tag))
				.font(.caption)
				.foregroundStyle(.tertiary)
				.lineLimit(1)

			Button(
				item.isHidden ? "Show" : "Hide", systemImage: item.isHidden ? "eye.slash" : "eye"
			) {
				controller.toggleHidden(order: item.order)
			}
			.buttonStyle(.icon(size: 22))
			.opacity((isHovered && controller.isEditing) || item.isHidden ? 1 : 0)
			.disabled(!controller.isEditing)
			.help(item.isHidden ? "Show Element" : "Hide Element")
		}
		.padding(.horizontal, 6)
		.frame(height: row.location == nil ? LayersPanel.rowHeight : LayersPanel.rowHeight + 8)
		.background {
			RoundedRectangle(cornerRadius: 6, style: .continuous)
				.fill(rowFill)
		}
		.overlay {
			if dropZone == .inside {
				RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(
					.tint, lineWidth: 2)
			}
		}
		.overlay(alignment: dropZone == .below ? .bottom : .top) {
			if dropZone == .above || dropZone == .below {
				Capsule().fill(.tint).frame(height: 3)
					.padding(.leading, CGFloat(row.depth) * 16 + 20)
					.offset(y: dropZone == .above ? -2 : 2)
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
		.accessibilityLabel("\(item.displayName), \(InspectorView.elementName(for: item.tag))")
		.accessibilityValue(
			([item.isHidden ? String(localized: "Hidden") : nil] + attachments.map(\.summary))
				.compactMap { $0 }.joined(separator: "; ")
		)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.accessibilityAction { controller.select(order: item.order) }
		.accessibilityAction(named: item.isHidden ? "Show" : "Hide") {
			controller.toggleHidden(order: item.order)
		}
		.accessibilityAction(named: "Rename") { renaming = item.id }
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
				.lineLimit(1)
				.truncationMode(.middle)
				.fontWeight(isGroup ? .medium : .regular)
				.simultaneousGesture(
					TapGesture(count: 2).onEnded {
						if controller.isEditing { renaming = item.id }
					}
				)
				.help(item.displayName)
		}
	}

	private var rowFill: AnyShapeStyle {
		if isSelected { return AnyShapeStyle(.tint.opacity(0.2)) }
		if isHovered { return AnyShapeStyle(.quaternary) }
		return AnyShapeStyle(.clear)
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
