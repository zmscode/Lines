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

/// One animation in the drawing, read from the outline for the timeline:
/// a SMIL element, or a CSS animation running on an element.
struct AnimationInfo: Identifiable {
	/// The animation element; for a CSS animation, the element it runs on.
	var item: OutlineItem
	var target: OutlineItem?
	var css: OutlineItem.CSSAnimation? = nil
	var cssIndex = 0

	var id: String { css == nil ? item.path : "\(item.path)#css\(cssIndex)" }
	/// What to select for this animation.
	var order: Int { item.order }
	/// CSS animations play and scrub, but their timing is edited in the stylesheet.
	var isCSS: Bool { css != nil }

	var symbol: String {
		isCSS ? "wand.and.sparkles" : InspectorView.symbol(for: item.tag, isRoot: false)
	}

	/// What's animated: an attribute, a transform type, a motion path, or a keyframes name.
	var property: String {
		if let css {
			return css.properties.isEmpty
				? css.name : css.properties.map(Self.cssName).joined(separator: ", ")
		}
		switch item.tag {
		case "animateTransform": return item.prop("type").map { "transform: \($0)" } ?? "transform"
		case "animateMotion": return "motion path"
		default: return item.prop("attributeName") ?? "?"
		}
	}

	var begin: Double {
		if let css { return css.delay }
		return AnimationInfo.seconds(item.prop("begin")) ?? 0
	}
	var duration: Double? {
		if let css { return css.duration }
		return AnimationInfo.seconds(item.prop("dur"))
	}
	var repeatsForever: Bool {
		if let css { return css.iterations == nil }
		return item.prop("repeatCount") == "indefinite" || item.prop("repeatDur") == "indefinite"
	}
	var repeatCount: Double? {
		if let css { return css.iterations }
		return item.prop("repeatCount").flatMap(Double.init)
	}

	/// When the animation (one pass, or all its repeats) ends.
	var end: Double { begin + (duration ?? 0) * (repeatsForever ? 1 : (repeatCount ?? 1)) }

	/// "1 → 0", the values list, or a CSS animation's easing, for summaries.
	var change: String {
		if let css { return "@keyframes \(css.name)" }
		if let values = item.prop("values") {
			return values.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
				.joined(separator: " → ")
		}
		let from = item.prop("from") ?? "…"
		let to = item.prop("to") ?? item.prop("by") ?? "…"
		return "\(from) → \(to)"
	}

	var name: String { target.map(\.displayName) ?? "Animation" }

	/// "strokeDashoffset" → "stroke-dashoffset", as written in CSS.
	static func cssName(_ property: String) -> String {
		property.replacing(#/[A-Z]/#) { "-" + $0.output.lowercased() }
	}

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

	/// Every animation in the outline, with the element it animates: SMIL
	/// elements (their parent, or the element their `href` names) and CSS
	/// animations.
	static func all(in outline: [OutlineItem]) -> [AnimationInfo] {
		let byOrder = Dictionary(uniqueKeysWithValues: outline.map { ($0.order, $0) })
		let byID = Dictionary(
			outline.compactMap { item in item.elementID.map { ($0, item) } },
			uniquingKeysWith: { first, _ in first })
		var result: [AnimationInfo] = []
		for item in outline {
			if AnimationTag.contains(item.tag) {
				let href = (item.prop("href") ?? item.prop("xlink:href"))
					.flatMap { $0.hasPrefix("#") ? String($0.dropFirst()) : nil }
				let target = href.flatMap { byID[$0] } ?? byOrder[item.parent]
				result.append(AnimationInfo(item: item, target: target))
			}
			for (index, css) in item.cssAnimations.enumerated() {
				result.append(AnimationInfo(item: item, target: item, css: css, cssIndex: index))
			}
		}
		return result
	}
}
