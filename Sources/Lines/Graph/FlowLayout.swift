import Foundation
import SwiftFlow

/// A left-to-right dependency layout, unlike the tree's nesting view.
///
/// Nodes are ranked by what they depend on: a gradient another gradient
/// inherits from sits left of it, definitions sit left of the shapes that use
/// them, a `<use>` sits right of what it draws, and animations sit right of
/// what they animate. Each column is ordered to keep lines from crossing.
/// Elements with no connections are set aside in a compact grid below.
enum FlowLayout {
	static let columnGap: CGFloat = 140
	static let rowGap: CGFloat = 18
	static let gridGap: CGFloat = 24
	static let sectionGap: CGFloat = 96

	static func positions(
		for items: [OutlineItem], references: [(source: String, target: String)],
		size: (OutlineItem) -> CGSize
	) -> [String: XYPosition] {
		let byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0) })
		let byOrder = Dictionary(uniqueKeysWithValues: items.map { ($0.order, $0) })

		// Dependencies: references, plus element → its animations.
		var pairs = references.filter { byPath[$0.source] != nil && byPath[$0.target] != nil }
		for item in items where AnimationTag.contains(item.tag) {
			if let parent = byOrder[item.parent] { pairs.append((parent.path, item.path)) }
		}
		var successors: [String: [String]] = [:]
		var predecessors: [String: [String]] = [:]
		for (s, t) in pairs where s != t {
			successors[s, default: []].append(t)
			predecessors[t, default: []].append(s)
		}
		let connected = items.filter { successors[$0.path] != nil || predecessors[$0.path] != nil }
		let loose = items.filter { successors[$0.path] == nil && predecessors[$0.path] == nil }

		var result: [String: XYPosition] = [:]

		// Rank: the longest chain of dependencies leading in (cycles are cut).
		var rank: [String: Int] = [:]
		func rankOf(_ path: String, _ visiting: inout Set<String>) -> Int {
			if let r = rank[path] { return r }
			guard visiting.insert(path).inserted else { return 0 }
			let r =
				(predecessors[path] ?? []).map { rankOf($0, &visiting) + 1 }.max() ?? 0
			visiting.remove(path)
			rank[path] = r
			return r
		}
		for item in connected {
			var visiting = Set<String>()
			_ = rankOf(item.path, &visiting)
		}

		// Columns in document order, then reordered by the average position of
		// neighbours, sweeping right and left a few times.
		let columnCount = (rank.values.max() ?? -1) + 1
		var columns: [[String]] = Array(repeating: [], count: columnCount)
		for item in connected { columns[rank[item.path] ?? 0].append(item.path) }
		func index(in column: [String]) -> [String: Int] {
			Dictionary(uniqueKeysWithValues: column.enumerated().map { ($1, $0) })
		}
		func barycentre(_ neighbours: [String], _ positions: [String: Int]) -> Double? {
			let found = neighbours.compactMap { positions[$0] }
			return found.isEmpty ? nil : Double(found.reduce(0, +)) / Double(found.count)
		}
		for _ in 0..<4 {
			for c in columns.indices.dropFirst() {
				let left = index(in: columns[c - 1])
				let mine = index(in: columns[c])
				columns[c].sort {
					(barycentre(predecessors[$0] ?? [], left) ?? Double(mine[$0]!))
						< (barycentre(predecessors[$1] ?? [], left) ?? Double(mine[$1]!))
				}
			}
			for c in columns.indices.reversed().dropFirst() {
				let right = index(in: columns[c + 1])
				let mine = index(in: columns[c])
				columns[c].sort {
					(barycentre(successors[$0] ?? [], right) ?? Double(mine[$0]!))
						< (barycentre(successors[$1] ?? [], right) ?? Double(mine[$1]!))
				}
			}
		}

		// Place columns left to right; each node as near its neighbours'
		// height as it can get without overlapping.
		var x: CGFloat = 0
		var centreY: [String: CGFloat] = [:]
		var bottom: CGFloat = 0
		for column in columns {
			let nodes = column.compactMap { byPath[$0] }
			var wanted: [(OutlineItem, CGFloat)] = []
			var fallback: CGFloat = 0
			for item in nodes {
				let ys = (predecessors[item.path] ?? []).compactMap { centreY[$0] }
				let h = size(item).height
				let y = ys.isEmpty ? fallback + h / 2 : ys.reduce(0, +) / CGFloat(ys.count)
				wanted.append((item, y))
				fallback = max(fallback, y + h / 2 + rowGap)
			}
			stack(wanted, x: x, size: size, into: &result)
			for item in nodes {
				let p = result[item.path]!
				let s = size(item)
				centreY[item.path] = p.y + s.height / 2
				bottom = max(bottom, p.y + s.height)
			}
			x += (nodes.map { size($0).width }.max() ?? 0) + columnGap
		}

		// Everything else in a grid below, in document order.
		let top = connected.isEmpty ? 0 : bottom + sectionGap
		let cellWidth = (loose.map { size($0).width }.max() ?? 220) + gridGap
		let perRow = max(3, min(6, columnCount + 1))
		var rowTop = top
		for row in stride(from: 0, to: loose.count, by: perRow) {
			let slice = loose[row..<min(row + perRow, loose.count)]
			for (i, item) in slice.enumerated() {
				result[item.path] = XYPosition(x: CGFloat(i) * cellWidth, y: rowTop)
			}
			rowTop += (slice.map { size($0).height }.max() ?? 0) + gridGap
		}
		return result
	}

	/// Places items in one column as near their wanted centre as possible
	/// without overlapping, top to bottom.
	private static func stack(
		_ wanted: [(OutlineItem, CGFloat)], x: CGFloat, size: (OutlineItem) -> CGSize,
		into result: inout [String: XYPosition]
	) {
		var bottom = -CGFloat.infinity
		for (item, centre) in wanted {
			let h = size(item).height
			let top = max(centre - h / 2, bottom + rowGap)
			result[item.path] = XYPosition(x: x, y: top)
			bottom = top + h
		}
	}

	static func isDefinition(_ tag: String) -> Bool {
		[.paint, .clip, .mask, .filter, .symbol].contains(Graph.kind(for: tag))
	}
}
