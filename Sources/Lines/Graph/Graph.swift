import SwiftFlow
import SwiftUI

/// How the graph is arranged.
enum GraphLayoutMode: String, CaseIterable, Identifiable {
	/// Definitions on the left feeding the elements that use them, like a
	/// node editor; nesting is hidden.
	case flow
	/// The document's nesting as a tree.
	case tree
	var id: String { rawValue }
	var title: String { self == .flow ? "Flow" : "Tree" }
	var symbol: String {
		self == .flow ? "point.3.filled.connected.trianglepath.dotted" : "list.bullet.indent"
	}
	var help: String {
		self == .flow
			? "Flow: left to right by dependency; unconnected elements wait below"
			: "Tree: the document’s nesting, top-down; select a node to see what it references"
	}
}

struct GraphNodeData: Equatable, Sendable {
	enum Kind: Equatable, Sendable {
		case element, group, paint, clip, mask, filter, symbol, container, animation
	}

	/// A child shown inside a node: a gradient stop or a filter primitive.
	struct Part: Equatable, Sendable, Identifiable {
		var order: Int
		var tag: String
		var props: [String: String]
		var id: Int { order }
	}

	var order: Int
	var tag: String
	var name: String
	var elementID: String?
	var kind: Kind
	var inputs: [String]
	var connected: Set<String>
	var isHidden: Bool
	/// The element's own attribute values (paints, widths, timings…).
	var props: [String: String] = [:]
	/// Gradient stops or filter primitives.
	var parts: [Part] = []
	var hasAnimations = false
	/// How many elements point at this definition.
	var usedBy = 0
	/// Names of the elements using this definition, or that an animation animates.
	var users: [String] = []
	/// The names of the shapes inside a clip path or mask.
	var contents: [String] = []

	struct InfoRow: Hashable, Sendable {
		var label: String
		var value: String
	}

	/// What a definition is and does, shown under its header.
	var infoRows: [InfoRow] {
		guard [.paint, .clip, .mask, .filter, .symbol].contains(kind) else { return [] }
		var rows: [InfoRow] = []
		let fitsShape = { (name: String) in
			props[name] == "userSpaceOnUse" ? "drawing units" : "fits each shape"
		}
		switch tag {
		case "linearGradient":
			let n = { (k: String, d: Double) in
				props[k].flatMap { Double($0.replacingOccurrences(of: "%", with: "")) } ?? d
			}
			let angle = atan2(n("y2", 0) - n("y1", 0), n("x2", 1) - n("x1", 0)) * 180 / .pi
			rows.append(InfoRow(label: "type", value: "linear · \(Int(angle.rounded()))°"))
			rows.append(InfoRow(label: "spread", value: props["spreadMethod"] ?? "pad"))
			rows.append(InfoRow(label: "units", value: fitsShape("gradientUnits")))
		case "radialGradient":
			rows.append(InfoRow(label: "type", value: "radial · r \(props["r"] ?? "50%")"))
			rows.append(InfoRow(label: "spread", value: props["spreadMethod"] ?? "pad"))
			rows.append(InfoRow(label: "units", value: fitsShape("gradientUnits")))
		case "pattern":
			rows.append(
				InfoRow(
					label: "tile", value: "\(props["width"] ?? "?") × \(props["height"] ?? "?")"))
			rows.append(
				InfoRow(
					label: "units",
					value: props["patternUnits"] == "userSpaceOnUse"
						? "drawing units" : "fits each shape"))
		case "clipPath", "mask":
			let shown = contents.prefix(3).joined(separator: ", ")
			let more = contents.count > 3 ? " +\(contents.count - 3)" : ""
			rows.append(
				InfoRow(label: "shapes", value: contents.isEmpty ? "none yet" : shown + more))
			// Clip paths default to drawing units; masks' contents too.
			let unitsKey = tag == "mask" ? "maskContentUnits" : "clipPathUnits"
			rows.append(
				InfoRow(
					label: "units",
					value: props[unitsKey] == "objectBoundingBox"
						? "fits each shape" : "drawing units"))
		case "filter":
			if let w = props["width"], let h = props["height"] {
				rows.append(InfoRow(label: "region", value: "\(w) × \(h)"))
			}
		case "symbol", "marker":
			rows.append(InfoRow(label: "viewBox", value: props["viewBox"] ?? "none"))
		default: break
		}
		rows.append(
			InfoRow(
				label: "used by",
				value: usedBy == 0
					? "nothing yet" : usedBy == 1 ? "1 element" : "\(usedBy) elements"))
		return rows
	}

	/// The attribute that applies this definition to a shape.
	var applyAttribute: String? {
		switch kind {
		case .paint: "fill"
		case .clip: "clip-path"
		case .mask: "mask"
		case .filter: "filter"
		default: nil
		}
	}

	/// Only things other elements can point at get an output pin.
	var hasOutput: Bool { [.paint, .clip, .mask, .filter, .symbol].contains(kind) }

	/// Value rows shown below the inputs on shapes.
	var valueRows: [String] {
		switch kind {
		case .element:
			var rows: [String] = []
			if inputs.contains("stroke") { rows.append("stroke-width") }
			rows.append("opacity")
			return rows
		case .group: return ["opacity"]
		default: return []
		}
	}
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
	/// Reference pairs (source path → target path), for the flow layout.
	var referencePairs: [(source: String, target: String)] = []
	private var kinds: [String: GraphNodeData.Kind] = [:]
	private var partsByOrder: [Int: [GraphNodeData.Part]] = [:]
	private var animated: Set<Int> = []
	private var usage: [String: Int] = [:]
	private var userNames: [String: [String]] = [:]
	private var parentNames: [Int: String] = [:]
	private var contentsByOrder: [Int: [String]] = [:]

	var nodeIDs: [String] { items.map(\.path) }

	/// Whether any shown definition is unused (nothing points at it).
	var hasUnusedDefinitions: Bool {
		items.contains { item in
			[.paint, .clip, .mask, .filter, .symbol].contains(Self.kind(for: item.tag))
				&& data(for: item).usedBy == 0
		}
	}

	/// - Parameters:
	///   - outline: the elements to show as nodes.
	///   - all: the whole outline, for stops and primitives shown inside nodes.
	///   - showsNesting: draw parent → child edges (the tree layout).
	init(outline: [OutlineItem], all: [OutlineItem], showsNesting: Bool) {
		items = outline
		let byOrder = Dictionary(uniqueKeysWithValues: all.map { ($0.order, $0) })
		let shown = Set(outline.map(\.order))
		let byID = Dictionary(
			all.compactMap { item in item.elementID.map { ($0, item) } },
			uniquingKeysWith: { first, _ in first })

		for item in all where item.tag == "stop" || item.tag.hasPrefix("fe") {
			partsByOrder[item.parent, default: []].append(
				GraphNodeData.Part(order: item.order, tag: item.tag, props: item.props))
		}
		for item in all where AnimationTag.contains(item.tag) { animated.insert(item.parent) }
		for item in all {
			for ref in item.references {
				usage[ref.targetID, default: 0] += 1
				userNames[ref.targetID, default: []].append(item.displayName)
			}
			if AnimationTag.contains(item.tag), let parent = byOrder[item.parent] {
				parentNames[item.order] = parent.displayName
			}
			if let parent = byOrder[item.parent], parent.tag == "clipPath" || parent.tag == "mask" {
				contentsByOrder[parent.order, default: []].append(item.displayName)
			}
		}

		for item in outline {
			orders[item.path] = item.order
			kinds[item.path] = Self.kind(for: item.tag)
			if let parent = byOrder[item.parent], shown.contains(parent.order) {
				let isAnimation = AnimationTag.contains(item.tag)
				if isAnimation {
					// Animations hang off the right of what they animate, in every layout.
					edges.append(
						FlowEdge(
							id: "a:\(item.path)", source: parent.path, target: item.path,
							sourceHandle: "animations", targetHandle: "animated", type: .default,
							deletable: false, focusable: false,
							style: EdgeStyle(strokeColor: .indigo, strokeWidth: 1.5, opacity: 0.7)
						))
				} else if showsNesting {
					edges.append(
						FlowEdge(
							id: "h:\(item.path)", source: parent.path, target: item.path,
							sourceHandle: "children", targetHandle: "parent", type: .smoothstep,
							deletable: false, focusable: false,
							style: EdgeStyle(
								strokeColor: .secondary, strokeWidth: 1.25, opacity: 0.6)
						))
				}
			}
			for ref in item.references {
				guard let target = byID[ref.targetID], shown.contains(target.order) else {
					continue
				}
				let id = "r:\(item.path):\(ref.attribute)"
				references[id] = ReferenceEdge(order: item.order, attribute: ref.attribute)
				referencePairs.append((target.path, item.path))
				edges.append(
					FlowEdge(
						id: id, source: target.path, target: item.path,
						sourceHandle: "ref",
						targetHandle: Self.inputs(for: item.tag).contains(ref.attribute)
							? ref.attribute : "parent",
						// The flow layout is about references, so they're bold and
						// moving; in the tree they recede behind the nesting.
						type: .default, animated: !showsNesting,
						style: EdgeStyle(
							strokeColor: Self.color(for: ref.attribute),
							strokeWidth: showsNesting ? 1.5 : 2.25,
							opacity: showsNesting ? 0.45 : 1)
					))
			}
		}
	}

	func data(for item: OutlineItem) -> GraphNodeData {
		GraphNodeData(
			order: item.order, tag: item.tag, name: item.displayName, elementID: item.elementID,
			kind: Self.kind(for: item.tag), inputs: Self.inputs(for: item.tag),
			connected: Set(item.references.map(\.attribute)), isHidden: item.isHidden,
			props: item.props, parts: partsByOrder[item.order] ?? [],
			hasAnimations: animated.contains(item.order),
			usedBy: item.elementID.flatMap { usage[$0] } ?? 0,
			users: AnimationTag.contains(item.tag)
				? parentNames[item.order].map { [$0] } ?? []
				: item.elementID.flatMap { userNames[$0] } ?? [],
			contents: contentsByOrder[item.order] ?? []
		)
	}

	func nodes(positions: [String: XYPosition], selected: String?) -> [Node<GraphNodeData>] {
		items.enumerated().map { index, item in
			let data = data(for: item)
			let size = GraphNodeView.size(for: data)
			return Node(
				id: item.path,
				position: positions[item.path]
					?? XYPosition(x: CGFloat(index % 6) * 240, y: CGFloat(index / 6) * 160),
				data: data, selected: item.path == selected,
				width: size.width, height: size.height
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
		case _ where AnimationTag.contains(tag): .animation
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
