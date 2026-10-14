import Foundation
import SwiftFlow

/// A top-down tidy tree: each parent sits centered over its children, and a
/// long run of childless elements (a group of paths, say) wraps into rows
/// instead of stretching the graph sideways.
enum TidyTreeLayout {
	static let horizontalGap: CGFloat = 28
	static let levelGap: CGFloat = 64
	static let rowGap: CGFloat = 20
	/// Rows of siblings wrap past about four nodes' width.
	static let maxRowWidth: CGFloat = 1000
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

		/// Sibling subtrees go left to right, wrapping into rows past `width`
		/// so a wide level becomes a compact block instead of a long strip.
		struct Rows {
			var rows: [[Int]] = []  // indices into the siblings
			var size: CGSize = .zero
		}
		func wrap(_ sizes: [CGSize], width: CGFloat) -> Rows {
			var result = Rows()
			var row: [Int] = []
			var rowWidth: CGFloat = 0
			var rowHeights: [CGFloat] = []
			var widest: CGFloat = 0
			func close() {
				guard !row.isEmpty else { return }
				result.rows.append(row)
				rowHeights.append(row.map { sizes[$0].height }.max()!)
				widest = max(widest, rowWidth)
				row = []
				rowWidth = 0
			}
			for (i, s) in sizes.enumerated() {
				let added = row.isEmpty ? s.width : rowWidth + horizontalGap + s.width
				if !row.isEmpty && added > width { close() }
				rowWidth = row.isEmpty ? s.width : rowWidth + horizontalGap + s.width
				row.append(i)
			}
			close()
			result.size = CGSize(
				width: widest,
				height: rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * rowGap)
			return result
		}
		/// Wide enough for a few nodes, or for the widest subtree.
		func rowLimit(_ sizes: [CGSize], minimum: CGFloat) -> CGFloat {
			max(minimum, sizes.map(\.width).max() ?? 0)
		}
		func isLeaf(_ item: OutlineItem) -> Bool { (children[item.order] ?? []).isEmpty }
		/// Children wrap only when they're all leaves; subtrees stay in one
		/// row, so lines from a parent never pass through a row above.
		func childLimit(_ kids: [OutlineItem], _ kidBlocks: [CGSize]) -> CGFloat {
			kids.allSatisfy(isLeaf) ? rowLimit(kidBlocks, minimum: maxRowWidth) : .infinity
		}

		func measure(_ item: OutlineItem) -> CGSize {
			let own = sizes[item.order]!
			let kids = children[item.order] ?? []
			guard !kids.isEmpty else {
				blocks[item.order] = own
				return own
			}
			let kidBlocks = kids.map(measure)
			let laid = wrap(kidBlocks, width: childLimit(kids, kidBlocks))
			let block = CGSize(
				width: max(own.width, laid.size.width),
				height: own.height + levelGap + laid.size.height)
			blocks[item.order] = block
			return block
		}

		var result: [String: XYPosition] = [:]

		/// Places rows of sibling blocks, each row centred in `width`.
		func placeRows(
			_ kids: [OutlineItem], x: CGFloat, y: CGFloat, width: CGFloat, limit: CGFloat,
			gap: CGFloat = rowGap
		) {
			let kidBlocks = kids.map { blocks[$0.order]! }
			let laid = wrap(kidBlocks, width: limit)
			var rowY = y
			for row in laid.rows {
				let rowWidth =
					row.map { kidBlocks[$0].width }.reduce(0, +) + CGFloat(row.count - 1)
					* horizontalGap
				var cx = x + (width - rowWidth) / 2
				for i in row {
					place(kids[i], x: cx, y: rowY)
					cx += kidBlocks[i].width + horizontalGap
				}
				rowY += row.map { kidBlocks[$0].height }.max()! + gap
			}
		}

		func place(_ item: OutlineItem, x: CGFloat, y: CGFloat) {
			let own = sizes[item.order]!
			let block = blocks[item.order]!
			result[item.path] = XYPosition(x: x + (block.width - own.width) / 2, y: y)
			let kids = children[item.order] ?? []
			guard !kids.isEmpty else { return }
			let kidBlocks = kids.map { blocks[$0.order]! }
			placeRows(
				kids, x: x, y: y + own.height + levelGap, width: block.width,
				limit: childLimit(kids, kidBlocks))
		}

		// The top level wraps too, aiming for a landscape block overall.
		let rootBlocks = roots.map(measure)
		let area = rootBlocks.map { $0.width * $0.height }.reduce(0, +)
		let limit = rowLimit(rootBlocks, minimum: max(maxRowWidth, (area * 1.8).squareRoot()))
		let laid = wrap(rootBlocks, width: limit)
		// Top-level rows have no parent lines, so they can sit further apart.
		placeRows(roots, x: 0, y: 0, width: laid.size.width, limit: limit, gap: treeGap)
		return result
	}
}
