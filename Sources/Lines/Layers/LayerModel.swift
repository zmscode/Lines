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

/// A layer dragged out of the list. Other apps receive its SVG markup.
struct LayerPayload: Transferable, Identifiable {
	var id: String  // the row's path, matching the reorderable rows' IDs
	var order: Int
	var name: String
	var controller: CanvasController

	static var transferRepresentation: some TransferRepresentation {
		DataRepresentation(exportedContentType: .svg) { payload in
			Data(await payload.markup().utf8)
		}
		DataRepresentation(exportedContentType: .plainText) { payload in
			Data(await payload.markup().utf8)
		}
		.suggestedFileName { $0.name + ".svg" }
	}

	@MainActor private func markup() async -> String {
		let element = await controller.markup(order: order) ?? ""
		return
			"<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">\(element)</svg>"
	}
}
