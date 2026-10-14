import SwiftFlow
import SwiftUI

struct GraphNodeData: Equatable, Sendable {
	enum Kind: Equatable, Sendable {
		case element, group, paint, clip, mask, filter, symbol, container
	}

	var order: Int
	var tag: String
	var name: String
	var elementID: String?
	var kind: Kind
	var inputs: [String]
	var connected: Set<String>
	var isHidden: Bool

	/// Gradient stop colours, or a filter's effects.
	var preview: [String]? = nil

	/// Only things other elements can point at get an output pin.
	var hasOutput: Bool { [.paint, .clip, .mask, .filter, .symbol].contains(kind) }
}

struct Graph {
	struct ReferenceEdge {
		var order: Int
		var attribute: String
	}

	var items: [OutlineItem]
	var orders: [String: Int] = [:]  // node id (path) → element order
	var references: [String: ReferenceEdge] = [:]  // edge id → the attribute it represents
	var edges: [FlowEdge<EmptyEdgeData>] = []
	private var kinds: [String: GraphNodeData.Kind] = [:]

	var nodeIDs: [String] { items.map(\.path) }

	init(outline: [OutlineItem]) {
		items = outline
		let byOrder = Dictionary(uniqueKeysWithValues: outline.map { ($0.order, $0) })
		let byID = Dictionary(
			outline.compactMap { item in item.elementID.map { ($0, item) } },
			uniquingKeysWith: { first, _ in first })
		for item in outline {
			orders[item.path] = item.order
			kinds[item.path] = Self.kind(for: item.tag)
			if let parent = byOrder[item.parent] {
				edges.append(
					FlowEdge(
						id: "h:\(item.path)", source: parent.path, target: item.path,
						sourceHandle: "children", targetHandle: "parent", type: .straight,
						deletable: false, focusable: false,
						style: EdgeStyle(strokeColor: .secondary, strokeWidth: 1, opacity: 0.45)
					))
			}
			for ref in item.references {
				guard let target = byID[ref.targetID] else { continue }
				let id = "r:\(item.path):\(ref.attribute)"
				references[id] = ReferenceEdge(order: item.order, attribute: ref.attribute)
				edges.append(
					FlowEdge(
						id: id, source: target.path, target: item.path,
						sourceHandle: "ref",
						targetHandle: Self.inputs(for: item.tag).contains(ref.attribute)
							? ref.attribute : "parent",
						type: .default, animated: true,
						style: EdgeStyle(
							strokeColor: Self.color(for: ref.attribute), strokeWidth: 2)
					))
			}
		}
	}

	func data(for item: OutlineItem) -> GraphNodeData {
		GraphNodeData(
			order: item.order, tag: item.tag, name: item.displayName, elementID: item.elementID,
			kind: Self.kind(for: item.tag), inputs: Self.inputs(for: item.tag),
			connected: Set(item.references.map(\.attribute)), isHidden: item.isHidden,
			preview: item.preview
		)
	}

	func nodes(positions: [String: XYPosition], selected: String?) -> [Node<GraphNodeData>] {
		items.enumerated().map { index, item in
			let data = data(for: item)
			return Node(
				id: item.path,
				position: positions[item.path]
					?? XYPosition(x: CGFloat(index % 6) * 240, y: CGFloat(index / 6) * 160),
				data: data, selected: item.path == selected,
				width: GraphNodeView.size(for: data).width,
				height: GraphNodeView.size(for: data).height
			)
		}
	}

	/// Only reference outputs can connect, and only to inputs that accept that kind of element.
	func isValid(_ connection: Connection) -> Bool {
		guard connection.sourceHandle == "ref", let attribute = connection.targetHandle,
			connection.source != connection.target,
			let kind = kinds[connection.source],
			let targetTag = items.first(where: { $0.path == connection.target })?.tag,
			Self.inputs(for: targetTag).contains(attribute)
		else { return false }
		switch attribute {
		case "fill", "stroke": return kind == .paint
		case "clip-path": return kind == .clip
		case "mask": return kind == .mask
		case "filter": return kind == .filter
		case "href": return true
		default: return false
		}
	}

	static func kind(for tag: String) -> GraphNodeData.Kind {
		switch tag {
		case "linearGradient", "radialGradient", "pattern": .paint
		case "clipPath": .clip
		case "mask": .mask
		case "filter": .filter
		case "symbol", "marker": .symbol
		case "g", "a", "switch": .group
		case "defs", "svg": .container
		default: .element
		}
	}

	static func inputs(for tag: String) -> [String] {
		switch tag {
		case "rect", "circle", "ellipse", "path", "polygon", "polyline", "text":
			["fill", "stroke", "clip-path", "mask", "filter"]
		case "line": ["stroke", "clip-path", "mask", "filter"]
		case "g", "image", "a": ["clip-path", "mask", "filter"]
		case "use": ["href", "clip-path", "mask", "filter"]
		default: []
		}
	}

	static func color(for attribute: String) -> Color {
		switch attribute {
		case "fill", "stroke": .orange
		case "clip-path": .teal
		case "mask": .purple
		case "filter": .pink
		default: .accentColor
		}
	}
}
