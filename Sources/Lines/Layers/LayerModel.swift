import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct LayerNode: Identifiable {
	var item: OutlineItem
	var children: [LayerNode]
	var id: String { item.path }

	static func build(_ items: [OutlineItem]) -> [LayerNode] {
		var childrenByParent: [Int: [OutlineItem]] = [:]
		for item in items { childrenByParent[item.parent, default: []].append(item) }
		// Topmost first, like every layer list: the last element in the file draws on top.
		func make(_ item: OutlineItem) -> LayerNode {
			LayerNode(
				item: item, children: (childrenByParent[item.order] ?? []).reversed().map(make))
		}
		return (childrenByParent[0] ?? []).reversed().map(make)
	}
}

/// Looks up nodes by path for the reorder and drag callbacks.
struct LayerIndex {
	var nodes: [String: LayerNode] = [:]

	init(_ tree: [LayerNode]) {
		func add(_ node: LayerNode) {
			nodes[node.id] = node
			node.children.forEach(add)
		}
		tree.forEach(add)
	}
}
