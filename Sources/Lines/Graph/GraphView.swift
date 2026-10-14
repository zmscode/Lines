import SwiftFlow
import SwiftUI

/// A node editor for the drawing's structure.
///
/// Each element is a node. Gray edges show nesting; colored edges are
/// references — a gradient used as a fill, a clipping path, a mask, a filter,
/// or the element a `<use>` instance draws. Dragging from an element's
/// output (on the right) to another element's input sets that reference, and
/// deleting an edge removes it.
struct GraphView: View {
	var controller: CanvasController
	/// Room taken on the leading edge by the floating code panel.
	var leadingInset: CGFloat = 0

	@State private var positions: [String: XYPosition] = [:]
	@State private var movedByHand: Set<String> = []
	@State private var layoutKey: [String] = []
	@State private var needsFit = true
	/// Hidden until the first fit, so the graph appears in place instead of
	/// sliding in from SwiftFlow's default viewport at the top left.
	@State private var hasFitted = false
	@StateObject private var flow = SwiftFlowInstance()
	@AppStorage("graph.layout") private var mode: GraphLayoutMode = .flow
	@State private var chosen: [String: Int] = [:]

	/// Shift-dragged nodes snap to this grid, which the background dots show.
	static let snapGrid: CGFloat = 24

	private static let hiddenTags: Set<String> = [
		"stop", "tspan", "title", "desc", "metadata", "style", "script",
	]
	/// Filter primitives and gradient stops are shown inside their parent's
	/// node. The flow layout also leaves out containers like `<defs>`.
	private func isShown(_ item: OutlineItem) -> Bool {
		!Self.hiddenTags.contains(item.tag) && !item.tag.hasPrefix("fe")
			&& !(mode == .flow && Graph.kind(for: item.tag) == .container)
	}
	private static let nodeLimit = 300

	var body: some View {
		let graph = Graph(
			outline: visibleItems, all: controller.outline, showsNesting: mode == .tree)
		SwiftFlow(
			nodes: graph.nodes(positions: positions, selected: selectedPath),
			edges: graph.edges,
			onNodesChange: handleNodeChanges,
			onEdgesChange: { changes in handleEdgeChanges(changes, graph: graph) },
			onConnect: { connect($0, graph: graph) },
			// Scrolling zooms and the middle button pans; GraphNavigation handles
			// both ahead of SwiftFlow so they match the canvas.
			panOnScroll: false,
			zoomOnScroll: false,
			zoomOnDoubleClick: false,
			selectNodesOnDrag: true,
			connectionLineType: .default,
			colorMode: .system,
			isValidConnection: { graph.isValid($0) },
			onNodesDelete: { nodes in
				// Delete from the end of the document first so earlier indices stay valid.
				for node in nodes.sorted(by: { $0.data.order > $1.data.order }) {
					controller.delete(order: node.data.order)
				}
			},
			onNodeClick: { node in controller.select(order: node.data.order) },
			onNodeDoubleClick: { node in
				controller.select(order: node.data.order)
				controller.layout = .canvas
			},
			swiftFlowInstance: flow
		) { node in
			GraphNodeView(node: node, controller: controller)
		} overlay: {
			Background(variant: .dots, color: .secondary.opacity(0.35), gap: Self.snapGrid)
			MiniMap(
				nodeColor: .secondary.opacity(0.45), selectedNodeColor: Brand.accent,
				nodeBorderRadius: 2, width: 168, height: 112, position: .bottomLeft
			)
			.floating(accent: Brand.accent)
		}
		.background(GraphNavigation(flow: flow))
		.overlay(alignment: .topLeading) {
			// A vertical palette in the same place and style as the canvas's tools.
			FloatingStrip {
				PaletteSlot(
					id: "graph.add",
					options: CanvasController.Definition.allCases.map { kind in
						PaletteOption(
							title: "Add \(kind.title)", symbol: kind.symbol,
							help: "Add a \(kind.title.lowercased()), then connect it to a shape"
						) { controller.addDefinition(kind) }
					}, chosen: $chosen, isSelected: false)
				StripDivider()
				ForEach(GraphLayoutMode.allCases) { option in
					Button(option.title, systemImage: option.symbol) {
						mode = option
						movedByHand.removeAll()
						relayout(graph, force: true)
					}
					.buttonStyle(.icon(size: ToolPalette.buttonSize, selected: mode == option))
					.help(option.help)
				}
				StripDivider()
				Button("Tidy Up", systemImage: "wand.and.rays") {
					movedByHand.removeAll()
					relayout(graph, force: true)
				}
				.buttonStyle(.icon(size: ToolPalette.buttonSize))
				.help("Arrange the graph automatically")
				Button("Select on Canvas", systemImage: "scope") {
					controller.layout = .canvas
				}
				.buttonStyle(.icon(size: ToolPalette.buttonSize))
				.disabled(!controller.hasElementSelection)
				.help("Show the selected node's element on the canvas")
			}
			.padding(12)
			.padding(.leading, leadingInset)
		}
		.overlay(alignment: .bottomTrailing) {
			// The same zoom strip as the canvas.
			FloatingStrip {
				Button("Zoom In", systemImage: "plus.magnifyingglass") { flow.zoomIn() }
					.buttonStyle(.icon)
					.help("Zoom In")
				Button("Zoom Out", systemImage: "minus.magnifyingglass") { flow.zoomOut() }
					.buttonStyle(.icon)
					.help("Zoom Out")
				StripDivider()
				Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
					needsFit = true
					fitIfNeeded(graph)
				}
				.buttonStyle(.icon)
				.help("Zoom to Fit")
			}
			.padding(12)
		}
		.overlay {
			if visibleItems.isEmpty {
				ContentUnavailableView(
					"No Elements", systemImage: "point.3.connected.trianglepath.dotted",
					description: Text("Elements and the references between them appear here."))
			}
		}
		.opacity(hasFitted ? 1 : 0)
		.onAppear { relayout(graph, force: true) }
		.onChange(of: graph.nodeIDs) { _, _ in relayout(graph, force: false) }
		.onChange(of: flow.viewSize) { _, _ in fitIfNeeded(graph) }
	}

	// MARK: Data

	/// Large drawings show their top levels plus anything involved in a reference.
	private var visibleItems: [OutlineItem] {
		let items = controller.outline.filter(isShown)
		guard items.count > Self.nodeLimit else { return items }
		let referenced = Set(items.flatMap { $0.references.map(\.targetID) })
		return Array(
			items.filter { item in
				item.depth <= 1 || !item.references.isEmpty
					|| item.elementID.map(referenced.contains) == true
			}.prefix(Self.nodeLimit))
	}

	private var selectedPath: String? {
		guard let order = controller.selection?.order, controller.hasElementSelection else {
			return nil
		}
		return controller.outline.first { $0.order == order }?.path
	}

	// MARK: Layout

	/// Lays the graph out as a tidy tree. New nodes are placed; nodes someone
	/// moved by hand stay put unless they choose Tidy Up.
	private func relayout(_ graph: Graph, force: Bool) {
		guard force || graph.nodeIDs != layoutKey else { return }
		let firstLayout = layoutKey.isEmpty
		layoutKey = graph.nodeIDs
		let size = { (item: OutlineItem) in GraphNodeView.size(for: graph.data(for: item)) }
		let tidy =
			mode == .flow
			? FlowLayout.positions(for: graph.items, references: graph.referencePairs, size: size)
			: TidyTreeLayout.positions(for: graph.items, size: size)
		var laidOut = positions
		for (id, position) in tidy where force || !movedByHand.contains(id) {
			laidOut[id] = position
		}
		positions = laidOut
		if force || firstLayout {
			needsFit = true
			fitIfNeeded(graph)
		}
	}

	/// Frames the graph once SwiftFlow knows its size; until then the fit waits.
	private func fitIfNeeded(_ graph: Graph) {
		if graph.items.isEmpty {
			hasFitted = true
			return
		}
		guard needsFit, flow.viewSize.width > 1, flow.viewSize.height > 1 else { return }
		needsFit = false
		let nodes = graph.nodes(positions: positions, selected: nil)
		let sizes = Dictionary(
			uniqueKeysWithValues: nodes.map { ($0.id, GraphNodeView.size(for: $0.data)) })
		// The first fit is instant; later ones (Tidy Up) animate.
		flow.fitView(
			nodes: nodes, nodeSizes: sizes,
			options: FitViewOptions(padding: 48, maxZoom: 1, duration: hasFitted ? 0.25 : nil))
		if !hasFitted {
			DispatchQueue.main.async {
				withAnimation(.easeOut(duration: 0.15)) { hasFitted = true }
			}
		}
	}

	// MARK: Changes

	private func handleNodeChanges(_ changes: [NodeChange<GraphNodeData>]) {
		for change in changes {
			if case .position(let id, let position) = change {
				// Holding Shift snaps to the grid.
				let g = Self.snapGrid
				positions[id] =
					NSEvent.modifierFlags.contains(.shift)
					? XYPosition(
						x: (position.x / g).rounded() * g, y: (position.y / g).rounded() * g)
					: position
				movedByHand.insert(id)
			}
		}
	}

	private func handleEdgeChanges(_ changes: [EdgeChange<EmptyEdgeData>], graph: Graph) {
		for change in changes {
			guard case .remove(let id) = change, let ref = graph.references[id] else { continue }
			controller.removeReference(order: ref.order, attribute: ref.attribute)
		}
	}

	private func connect(_ connection: Connection, graph: Graph) {
		guard graph.isValid(connection),
			let source = graph.orders[connection.source],
			let target = graph.orders[connection.target],
			let attribute = connection.targetHandle
		else { return }
		controller.setReference(order: target, attribute: attribute, targetOrder: source)
	}
}
