import Foundation
import SwiftFlow

/// A top-down tidy tree: each parent sits centered over its children, and a
/// long run of childless elements (a group of paths, say) wraps into rows
/// instead of stretching the graph sideways.
enum TidyTreeLayout {
	static let horizontalGap: CGFloat = 28
	static let levelGap: CGFloat = 64
	static let rowGap: CGFloat = 20
	static let wrapColumns = 4
	static let treeGap: CGFloat = 72

	static func positions(for items: [OutlineItem], size: (OutlineItem) -> CGSize) -> [String:
		XYPosition]
	{
		let visible = Dictionary(uniqueKeysWithValues: items.map { ($0.order, $0) })
		var children: [Int: [OutlineItem]] = [:]
		var roots: [OutlineItem] = []
		let parentsByOrder = Dictionary(uniqueKeysWithValues: items.map { ($0.order, $0.parent) })
		for item in items {
			// Attach to the nearest visible ancestor (some tags aren't shown).
			var parent = item.parent
			while parent != 0, visible[parent] == nil, let next = parentsByOrder[parent] {
				parent = next
			}
			if let p = visible[parent] {
				children[p.order, default: []].append(item)
			} else {
				roots.append(item)
			}
		}

		var sizes: [Int: CGSize] = [:]
		for item in items { sizes[item.order] = size(item) }
		var blocks: [Int: CGSize] = [:]

		func isLeaf(_ item: OutlineItem) -> Bool { (children[item.order] ?? []).isEmpty }
		func wraps(_ kids: [OutlineItem]) -> Bool {
			kids.count > wrapColumns && kids.allSatisfy(isLeaf)
		}

		func measure(_ item: OutlineItem) -> CGSize {
			let own = sizes[item.order]!
			let kids = children[item.order] ?? []
			guard !kids.isEmpty else {
				blocks[item.order] = own
				return own
			}
			let kidBlocks = kids.map(measure)
			var width: CGFloat
			var height: CGFloat
			if wraps(kids) {
				let columns = wrapColumns
				let cellW = kidBlocks.map(\.width).max()!
				let rows = (kids.count + columns - 1) / columns
				let rowHeights = stride(from: 0, to: kids.count, by: columns).map { start in
					kidBlocks[start..<min(start + columns, kids.count)].map(\.height).max()!
				}
				width = CGFloat(columns) * cellW + CGFloat(columns - 1) * horizontalGap
				height = rowHeights.reduce(0, +) + CGFloat(rows - 1) * rowGap
			} else {
				width =
					kidBlocks.map(\.width).reduce(0, +) + CGFloat(kids.count - 1) * horizontalGap
				height = kidBlocks.map(\.height).max()!
			}
			let block = CGSize(width: max(own.width, width), height: own.height + levelGap + height)
			blocks[item.order] = block
			return block
		}

		var result: [String: XYPosition] = [:]

		func place(_ item: OutlineItem, x: CGFloat, y: CGFloat) {
			let own = sizes[item.order]!
			let block = blocks[item.order]!
			result[item.path] = XYPosition(x: x + (block.width - own.width) / 2, y: y)
			let kids = children[item.order] ?? []
			guard !kids.isEmpty else { return }
			let top = y + own.height + levelGap
			if wraps(kids) {
				let cellW = kids.map { blocks[$0.order]!.width }.max()!
				let rowWidth =
					CGFloat(wrapColumns) * cellW + CGFloat(wrapColumns - 1) * horizontalGap
				var rowY = top
				for start in stride(from: 0, to: kids.count, by: wrapColumns) {
					let row = kids[start..<min(start + wrapColumns, kids.count)]
					var cx = x + (block.width - rowWidth) / 2
					for kid in row {
						place(kid, x: cx, y: rowY)
						cx += cellW + horizontalGap
					}
					rowY += row.map { blocks[$0.order]!.height }.max()! + rowGap
				}
			} else {
				let total =
					kids.map { blocks[$0.order]!.width }.reduce(0, +) + CGFloat(kids.count - 1)
					* horizontalGap
				var cx = x + (block.width - total) / 2
				for kid in kids {
					place(kid, x: cx, y: top)
					cx += blocks[kid.order]!.width + horizontalGap
				}
			}
		}

		var x: CGFloat = 0
		for root in roots {
			let block = measure(root)
			place(root, x: x, y: 0)
			x += block.width + treeGap
		}
		return result
	}
}
