import SwiftUI

/// The drawing's element tree, like the layer lists in Keynote, Sketch and
/// Figma. Top-level elements are the layers; groups disclose their contents.
///
/// Drag rows to reorder them or move them between groups (each group's
/// children are a reorderable collection), drag a row to another app to copy
/// it as SVG, or drop SVG files from the Finder to import them.
struct LayersSidebar: View {
	var controller: CanvasController

	@State private var expanded: Set<String> = []
	@State private var renaming: String?

	/// The collection ID for the root's children.
	static let rootCollection = ""

	private var tree: [LayerNode] { LayerNode.build(controller.outline) }

	private var selectedOrder: Binding<Int?> {
		Binding(
			get: { controller.hasElementSelection ? controller.selection?.order : nil },
			set: { order in
				if let order { controller.select(order: order) } else { controller.deselect() }
			}
		)
	}

	var body: some View {
		let tree = self.tree
		let index = LayerIndex(tree)
		List(selection: selectedOrder) {
			Section {
				ForEach(tree) { node in
					LayerTreeRow(
						node: node, controller: controller, expanded: $expanded, renaming: $renaming
					)
				}
				.reorderable(collectionID: Self.rootCollection)
			} header: {
				Text("Layers")
			} footer: {
				if controller.outlineTruncated {
					Text("Showing the first 5,000 elements.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.listStyle(.sidebar)
		.reorderContainer(for: LayerNode.self, in: String.self) { difference in
			apply(difference, index: index)
		}
		.dragContainer(for: LayerPayload.self) { path in
			index.nodes[path].map {
				[
					LayerPayload(
						id: path, order: $0.item.order, name: $0.item.displayName,
						controller: controller)
				]
			} ?? []
		}
		.dropDestination(for: URL.self) { urls, _ in
			importFiles(urls)
		}
		.onDeleteCommand {
			if controller.hasElementSelection { controller.deleteSelection() }
		}
		.onHover { inside in if !inside { controller.hover(order: nil) } }
		.overlay {
			if controller.outline.isEmpty {
				ContentUnavailableView(
					"No Elements", systemImage: "square.3.layers.3d",
					description: Text("Elements in the drawing appear here."))
			}
		}
		.safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
		.onChange(of: controller.selection?.order) { _, order in
			revealSelection(order)
		}
	}

	// MARK: Bottom bar

	private var bottomBar: some View {
		HStack(spacing: 2) {
			Menu {
				ForEach(ShapeKind.allCases) { kind in
					Button(kind.title, systemImage: kind.symbol) { controller.addShape(kind) }
				}
			} label: {
				Label("Add", systemImage: "plus")
			}
			.menuIndicator(.hidden)
			.help("Add a shape")

			Button("Group", systemImage: "square.on.square.dashed") { controller.groupSelection() }
				.disabled(!controller.hasElementSelection)
				.help("Group the selected element (⌥⌘G)")

			Spacer()

			Button("Delete", systemImage: "trash") { controller.deleteSelection() }
				.disabled(!controller.hasElementSelection)
				.help("Delete the selected element")
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.borderless)
		.controlSize(.large)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(alignment: .top) { Divider() }
	}

	// MARK: Reordering

	/// Applies a move from the list. The list shows the topmost element first,
	/// the reverse of document order, so "before X" in the list means "after X"
	/// in the file, and the end of a list means the start of that parent.
	private func apply(_ difference: ReorderDifference<String, String>, index: LayerIndex) {
		let sources = difference.sources.compactMap { index.nodes[$0]?.item.order }
		let parentPath = difference.destination.collectionID
		let parent = parentPath == Self.rootCollection ? 0 : index.nodes[parentPath]?.item.order
		guard !sources.isEmpty, let parent else { return }
		switch difference.destination.position {
		case .before(let path):
			controller.move(
				orders: sources, intoParent: parent, after: index.nodes[path]?.item.order)
		case .end:
			controller.move(orders: sources, intoParent: parent, after: nil)
		}
		if parentPath != Self.rootCollection { expanded.insert(parentPath) }
	}

	/// SVG files dropped from the Finder are added as groups.
	private func importFiles(_ urls: [URL]) {
		for url in urls where url.pathExtension.lowercased() == "svg" {
			guard let markup = try? String(contentsOf: url, encoding: .utf8) else { continue }
			controller.paste(markup: markup)
		}
	}

	/// Expands the groups containing the selected element so its row is visible.
	private func revealSelection(_ order: Int?) {
		guard let order, let item = controller.outline.first(where: { $0.order == order }) else {
			return
		}
		let parts = item.path.split(separator: ".")
		for length in stride(from: 1, to: parts.count, by: 1) {
			expanded.insert(parts.prefix(length).joined(separator: "."))
		}
	}
}
