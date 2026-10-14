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

	@State private var positions: [String: XYPosition] = [:]
	@State private var movedByHand: Set<String> = []
	@State private var layoutKey: [String] = []
	@State private var needsFit = true
	@StateObject private var flow = SwiftFlowInstance()

	private static let hiddenTags: Set<String> = [
		"stop", "tspan", "title", "desc", "metadata", "style", "script",
	]
	private static let nodeLimit = 300

	var body: some View {
		let graph = Graph(outline: visibleItems)
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
			GraphNodeView(node: node)
		} overlay: {
			Background(variant: .dots, color: .secondary.opacity(0.35))
			Controls()
			MiniMap(selectedNodeColor: .accentColor)
		}
		.background(GraphNavigation(flow: flow))
		.overlay(alignment: .topTrailing) {
			Button("Tidy Up", systemImage: "wand.and.rays") {
				movedByHand.removeAll()
				relayout(graph, force: true)
			}
			.help("Arrange the graph automatically")
			.padding(12)
		}
		.overlay {
			if visibleItems.isEmpty {
				ContentUnavailableView(
					"No Elements", systemImage: "point.3.connected.trianglepath.dotted",
					description: Text("Elements and the references between them appear here."))
			}
		}
		.onAppear { relayout(graph, force: true) }
		.onChange(of: graph.nodeIDs) { _, _ in relayout(graph, force: false) }
		.onChange(of: flow.viewSize) { _, _ in fitIfNeeded(graph) }
	}

	// MARK: Data

	/// Large drawings show their top levels plus anything involved in a reference.
	private var visibleItems: [OutlineItem] {
		let items = controller.outline.filter { !Self.hiddenTags.contains($0.tag) }
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
		let tidy = TidyTreeLayout.positions(for: graph.items) {
			GraphNodeView.size(for: graph.data(for: $0))
		}
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
		guard needsFit, flow.viewSize.width > 1, flow.viewSize.height > 1, !graph.items.isEmpty
		else { return }
		needsFit = false
		let nodes = graph.nodes(positions: positions, selected: nil)
		let sizes = Dictionary(
			uniqueKeysWithValues: nodes.map { ($0.id, GraphNodeView.size(for: $0.data)) })
		flow.fitView(
			nodes: nodes, nodeSizes: sizes,
			options: FitViewOptions(padding: 48, maxZoom: 1, duration: 0.25))
	}

	// MARK: Changes

	private func handleNodeChanges(_ changes: [NodeChange<GraphNodeData>]) {
		for change in changes {
			if case .position(let id, let position) = change {
				positions[id] = position
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
