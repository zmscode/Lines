import Foundation
import SwiftFlow

/// A left-to-right node-editor layout. Definitions (gradients, clip paths,
/// masks, filters) sit in a column on the left, each beside the elements that
/// use it; elements run down the middle in document order, indented by
/// nesting; animations sit on the right beside what they animate. Reference
/// lines then run left to right with few crossings.
enum FlowLayout {
	static let columnGap: CGFloat = 120
	static let rowGap: CGFloat = 18
	static let indent: CGFloat = 18

	static func positions(
		for items: [OutlineItem], references: [(source: String, target: String)],
		size: (OutlineItem) -> CGSize
	) -> [String: XYPosition] {
		let definitions = items.filter { isDefinition($0.tag) }
		let animations = items.filter { AnimationTag.contains($0.tag) }
		let elements = items.filter { !isDefinition($0.tag) && !AnimationTag.contains($0.tag) }
		let byOrder = Dictionary(uniqueKeysWithValues: items.map { ($0.order, $0) })

		var result: [String: XYPosition] = [:]
		let defWidth = definitions.map { size($0).width }.max() ?? 0
		let mainX = definitions.isEmpty ? 0 : defWidth + columnGap

		// Elements: document order, indented by depth (relative to the shallowest).
		let minDepth = elements.map(\.depth).min() ?? 0
		var y: CGFloat = 0
		var centreY: [String: CGFloat] = [:]
		var mainRight: CGFloat = mainX
		for item in elements {
			let s = size(item)
			let x = mainX + CGFloat(min(item.depth - minDepth, 5)) * indent
			result[item.path] = XYPosition(x: x, y: y)
			centreY[item.path] = y + s.height / 2
			mainRight = max(mainRight, x + s.width)
			y += s.height + rowGap
		}

		// Definitions: at the average height of the elements that use them.
		let targets = Dictionary(grouping: references, by: \.source)
		let wantedY: [(OutlineItem, CGFloat)] = definitions.enumerated().map { index, item in
			let ys = (targets[item.path] ?? []).compactMap { centreY[$0.target] }
			let fallback = y + CGFloat(index) * 60  // unused ones go below
			return (item, ys.isEmpty ? fallback : ys.reduce(0, +) / CGFloat(ys.count))
		}
		stack(wantedY, x: 0, size: size, into: &result)

		// Animations: beside the element they animate.
		let animX = mainRight + columnGap
		let animWanted: [(OutlineItem, CGFloat)] = animations.map { item in
			let parent = byOrder[item.parent]
			let wanted = parent.flatMap { centreY[$0.path] } ?? y
			return (item, wanted)
		}
		stack(animWanted, x: animX, size: size, into: &result)
		return result
	}

	/// Places items in one column as near their wanted centre as possible
	/// without overlapping, top to bottom.
	private static func stack(
		_ wanted: [(OutlineItem, CGFloat)], x: CGFloat, size: (OutlineItem) -> CGSize,
		into result: inout [String: XYPosition]
	) {
		var bottom = -CGFloat.infinity
		for (item, centre) in wanted.sorted(by: { $0.1 < $1.1 }) {
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
