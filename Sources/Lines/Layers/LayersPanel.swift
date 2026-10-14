import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	/// A layer dragged within Lines; the payload is the layer's path.
	static let linesLayer = UTType(exportedAs: "com.zms.lines.layer")
}

/// The drawing's element tree, topmost first like every layer list.
///
/// Drag a row to move it: a line above or below a row shows where it lands,
/// and a highlighted group means "inside". Dragging a row into another app
/// copies it as SVG, and SVG files dropped from the Finder are imported.
struct LayersPanel: View {
	var controller: CanvasController

	@State private var expanded: Set<String> = []
	@State private var renaming: String?
	@State private var dragging: String?
	@State private var dropTarget: DropTarget?
	@State private var filesTargeted = false

	struct DropTarget: Equatable {
		enum Zone { case above, below, inside }
		var path: String
		var zone: Zone
	}

	/// One visible row of the flattened tree.
	struct Row: Identifiable {
		var node: LayerNode
		var depth: Int
		var id: String { node.id }
	}

	static let rowHeight: CGFloat = 28

	var body: some View {
		let tree = LayerNode.build(controller.outline)
		let index = LayerIndex(tree)
		let rows = flatten(tree)
		VStack(spacing: 0) {
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(spacing: 1) {
						ForEach(rows) { row in
							LayerRowView(
								row: row, controller: controller,
								isExpanded: expanded.contains(row.id),
								toggleExpanded: { toggle(row.id) }, renaming: $renaming,
								dropZone: dropTarget?.path == row.id ? dropTarget?.zone : nil
							)
							.id(row.id)
							.onDrag {
								dragging = row.id
								return provider(for: row)
							}
							.onDrop(
								of: [.linesLayer],
								delegate: RowDropDelegate(
									row: row, index: index, dragging: $dragging,
									target: $dropTarget,
									perform: perform)
							)
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
				if controller.outline.isEmpty {
					ContentUnavailableView(
						"No Elements", systemImage: "square.3.layers.3d",
						description: Text("Elements in the drawing appear here."))
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

			bottomBar
				.disabled(!controller.isEditing)
		}
		.onHover { inside in if !inside { controller.hover(order: nil) } }
		.onDeleteCommand {
			if controller.hasElementSelection { controller.deleteSelection() }
		}
	}

	// MARK: Tree

	private func flatten(_ nodes: [LayerNode], depth: Int = 0) -> [Row] {
		nodes.flatMap { node -> [Row] in
			let row = Row(node: node, depth: depth)
			guard expanded.contains(node.id) else { return [row] }
			return [row] + flatten(node.children, depth: depth + 1)
		}
	}

	private func toggle(_ path: String) {
		withAnimation(.snappy(duration: 0.2)) {
			if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
		}
	}

	/// Expands the groups containing the selected element; returns its row.
	private func revealSelection(_ order: Int?) -> String? {
		guard let order, let item = controller.outline.first(where: { $0.order == order }) else {
			return nil
		}
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
			expanded.insert(target.path)
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

	private var bottomBar: some View {
		HStack(spacing: 2) {
			Button("Group", systemImage: "square.on.square.dashed") { controller.groupSelection() }
				.disabled(!controller.hasElementSelection)
				.help("Group the selected element (⌥⌘G)")
			Button("Duplicate", systemImage: "plus.square.on.square") {
				controller.duplicateSelection()
			}
			.disabled(!controller.hasElementSelection)
			.help("Duplicate (⌘D)")
			Spacer()
			Button("Delete", systemImage: "trash") { controller.deleteSelection() }
				.disabled(!controller.hasElementSelection)
				.help("Delete the selected element")
		}
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
	@Binding var target: LayersPanel.DropTarget?
	var perform: (String, LayersPanel.DropTarget, LayerIndex) -> Void

	private var isGroup: Bool { row.node.item.tag == "g" || !row.node.children.isEmpty }

	func validateDrop(info: DropInfo) -> Bool {
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
		guard let dragging, let target, validateDrop(info: info) else { return false }
		perform(dragging, target, index)
		return true
	}

	private func update(_ info: DropInfo) {
		guard validateDrop(info: info) else {
			target = nil
			return
		}
		let y = info.location.y / LayersPanel.rowHeight
		let zone: LayersPanel.DropTarget.Zone =
			isGroup ? (y < 0.3 ? .above : y > 0.7 ? .below : .inside) : (y < 0.5 ? .above : .below)
		let next = LayersPanel.DropTarget(path: row.id, zone: zone)
		if target != next { target = next }
	}
}

// MARK: - Row

private struct LayerRowView: View {
	var row: LayersPanel.Row
	var controller: CanvasController
	var isExpanded: Bool
	var toggleExpanded: () -> Void
	@Binding var renaming: String?
	var dropZone: LayersPanel.DropTarget.Zone?

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
		HStack(spacing: 4) {
			Color.clear.frame(width: CGFloat(row.depth) * 14)

			Button(action: toggleExpanded) {
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.bold))
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.foregroundStyle(.secondary)
					.frame(width: 14, height: 20)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.opacity(row.node.children.isEmpty ? 0 : 1)
			.disabled(row.node.children.isEmpty)
			.help(isExpanded ? "Collapse" : "Expand")
			.accessibilityLabel(isExpanded ? "Collapse" : "Expand")

			Image(systemName: InspectorView.symbol(for: item.tag, isRoot: false))
				.foregroundStyle(swatch)
				.frame(width: 18)

			name

			Spacer(minLength: 4)

			if !item.references.isEmpty {
				Image(systemName: "link")
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.help(
						"Uses "
							+ item.references.map { "#\($0.targetID) (\($0.attribute))" }.joined(
								separator: ", "))
			}

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
		.frame(height: LayersPanel.rowHeight)
		.background {
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.fill(rowFill)
		}
		.overlay {
			if dropZone == .inside {
				RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(
					.tint, lineWidth: 2)
			}
		}
		.overlay(alignment: dropZone == .below ? .bottom : .top) {
			if dropZone == .above || dropZone == .below {
				Capsule().fill(.tint).frame(height: 3)
					.padding(.leading, CGFloat(row.depth) * 14 + 24)
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
		.accessibilityValue(item.isHidden ? "Hidden" : "")
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
				.foregroundStyle(.primary)
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

	/// Tints the icon with the element's fill when it's a plain colour.
	private var swatch: AnyShapeStyle {
		if isSelected { return AnyShapeStyle(.tint) }
		if let fill = item.fill, fill != "none", let colour = CSSColor.parse(fill) {
			return AnyShapeStyle(colour)
		}
		return AnyShapeStyle(.secondary)
	}
}
