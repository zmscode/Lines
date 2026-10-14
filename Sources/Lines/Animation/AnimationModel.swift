import Foundation

/// SMIL animation elements Lines understands.
enum AnimationTag {
	static let all: Set<String> = ["animate", "animateTransform", "animateMotion", "set"]
	static func contains(_ tag: String) -> Bool { all.contains(tag) }
}

/// Presets the timeline and inspector can add to an element.
enum AnimationPreset: String, CaseIterable, Identifiable {
	case fade, fadeIn, spin, slide, colour, draw
	var id: String { rawValue }

	var title: String {
		switch self {
		case .fade: "Fade (Loop)"
		case .fadeIn: "Fade In"
		case .spin: "Spin"
		case .slide: "Slide"
		case .colour: "Colour Cycle"
		case .draw: "Draw (Stroke)"
		}
	}

	var symbol: String {
		switch self {
		case .fade: "circle.lefthalf.filled"
		case .fadeIn: "sun.max"
		case .spin: "arrow.trianglehead.2.clockwise.rotate.90"
		case .slide: "arrow.left.and.right"
		case .colour: "paintpalette"
		case .draw: "scribble.variable"
		}
	}
}

/// One animation in the drawing, read from the outline for the timeline.
struct AnimationInfo: Identifiable {
	var item: OutlineItem
	var target: OutlineItem?

	var id: String { item.path }
	var order: Int { item.order }

	/// What's animated: an attribute, a transform type, or a motion path.
	var property: String {
		switch item.tag {
		case "animateTransform": item.prop("type").map { "transform: \($0)" } ?? "transform"
		case "animateMotion": "motion path"
		default: item.prop("attributeName") ?? "?"
		}
	}

	var begin: Double { AnimationInfo.seconds(item.prop("begin")) ?? 0 }
	var duration: Double? { AnimationInfo.seconds(item.prop("dur")) }
	var repeatsForever: Bool {
		item.prop("repeatCount") == "indefinite" || item.prop("repeatDur") == "indefinite"
	}
	var repeatCount: Double? { item.prop("repeatCount").flatMap(Double.init) }

	/// When the animation (one pass, or all its repeats) ends.
	var end: Double { begin + (duration ?? 0) * (repeatsForever ? 1 : (repeatCount ?? 1)) }

	/// "1 → 0", or the values list, for summaries.
	var change: String {
		if let values = item.prop("values") {
			return values.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
				.joined(separator: " → ")
		}
		let from = item.prop("from") ?? "…"
		let to = item.prop("to") ?? item.prop("by") ?? "…"
		return "\(from) → \(to)"
	}

	var name: String { target.map(\.displayName) ?? "Animation" }

	/// SMIL clock values: "2s", "500ms", "1.5", "0:01.5". nil for "indefinite" or unparseable.
	static func seconds(_ value: String?) -> Double? {
		guard var v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v != "indefinite"
		else { return nil }
		if v.contains(";") { v = String(v.split(separator: ";")[0]) }
		if v.hasSuffix("ms") { return Double(v.dropLast(2)).map { $0 / 1000 } }
		if v.hasSuffix("min") { return Double(v.dropLast(3)).map { $0 * 60 } }
		if v.hasSuffix("h") { return Double(v.dropLast()).map { $0 * 3600 } }
		if v.hasSuffix("s") { return Double(v.dropLast()) }
		if v.contains(":") {
			return v.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
		}
		return Double(v)
	}

	static func format(seconds: Double) -> String {
		seconds < 10 ? String(format: "%.2fs", seconds) : String(format: "%.1fs", seconds)
	}

	/// Every animation in the outline, with the element it animates.
	static func all(in outline: [OutlineItem]) -> [AnimationInfo] {
		let byOrder = Dictionary(uniqueKeysWithValues: outline.map { ($0.order, $0) })
		return outline.filter { AnimationTag.contains($0.tag) }.map {
			AnimationInfo(item: $0, target: byOrder[$0.parent])
		}
	}
}
