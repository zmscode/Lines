import AppKit
import SwiftUI

/// Something defined once and used by reference: a gradient, pattern, clip
/// path, mask, filter or symbol. The Layers panel lists these under
/// Resources, with who uses each.
struct ResourceInfo: Identifiable, Equatable {
	enum Kind: Equatable {
		case gradient, pattern, clip, mask, filter, symbol

		init?(tag: String) {
			switch tag {
			case "linearGradient", "radialGradient": self = .gradient
			case "pattern": self = .pattern
			case "clipPath": self = .clip
			case "mask": self = .mask
			case "filter": self = .filter
			case "symbol", "marker": self = .symbol
			default: return nil
			}
		}

		/// The attribute that applies it to a shape (symbols are placed with <use>).
		var attribute: String? {
			switch self {
			case .gradient, .pattern: "fill"
			case .clip: "clip-path"
			case .mask: "mask"
			case .filter: "filter"
			case .symbol: nil
			}
		}

		var tint: Color {
			switch self {
			case .gradient, .pattern: .orange
			case .clip: .teal
			case .mask: .purple
			case .filter: .pink
			case .symbol: .indigo
			}
		}
	}

	var item: OutlineItem
	var kind: Kind
	/// Elements pointing at it.
	var users: [OutlineItem]
	/// Gradient stops or filter primitives.
	var parts: [OutlineItem]
	/// The shapes inside a clip path or mask.
	var contents: [OutlineItem]

	var id: String { item.path }
	var order: Int { item.order }
	var name: String { item.elementID ?? item.displayName }
	var isUnused: Bool { users.isEmpty }

	static func isResource(_ tag: String) -> Bool { Kind(tag: tag) != nil }

	/// Every resource in the drawing, in document order.
	static func all(in outline: [OutlineItem]) -> [ResourceInfo] {
		var users: [String: [OutlineItem]] = [:]
		var children: [Int: [OutlineItem]] = [:]
		for item in outline {
			for ref in item.references { users[ref.targetID, default: []].append(item) }
			children[item.parent, default: []].append(item)
		}
		return outline.compactMap { item in
			guard let kind = Kind(tag: item.tag) else { return nil }
			let kids = children[item.order] ?? []
			return ResourceInfo(
				item: item, kind: kind,
				users: item.elementID.flatMap { users[$0] } ?? [],
				parts: kids.filter { $0.tag == "stop" || $0.tag.hasPrefix("fe") },
				contents: kind == .clip || kind == .mask ? kids : [])
		}
	}

	/// A stop's colour, from its attribute or its style.
	static func stopColour(_ stop: OutlineItem) -> String {
		if let c = stop.prop("stop-color") { return c }
		if let style = stop.prop("style"),
			let m = style.firstMatch(of: #/stop-color\s*:\s*([^;]+)/#)
		{
			return String(m.1).trimmingCharacters(in: .whitespaces)
		}
		return "#000000"
	}

	static func effectName(_ primitive: String) -> String {
		switch primitive {
		case "feGaussianBlur": "Blur"
		case "feDropShadow": "Shadow"
		case "feOffset": "Offset"
		case "feColorMatrix": "Colour"
		case "feFlood": "Flood"
		case "feBlend": "Blend"
		case "feComposite": "Composite"
		case "feMerge": "Merge"
		case "feMorphology": "Morphology"
		case "feTurbulence": "Noise"
		case "feDisplacementMap": "Displace"
		default: String(primitive.dropFirst(2))
		}
	}

	/// What it does to this drawing, in a sentence, then how to read its preview.
	var summary: String {
		let names = Self.list(users.map(\.displayName))
		let p = item.props
		let sentence: String
		switch item.tag {
		case "linearGradient", "radialGradient":
			let colours = parts.map { ColourName.of(Self.stopColour($0)) }
			let blend =
				colours.count >= 2
				? "from \(colours.first!) to \(colours.last!)"
					+ (colours.count > 2
						? " through \(Self.list(Array(colours.dropFirst().dropLast())))" : "")
				: "of \(colours.first ?? "one colour")"
			let shape =
				item.tag == "radialGradient"
				? "a blend outward from the centre" : "a straight blend"
			let spread =
				switch p["spreadMethod"] {
				case "repeat": ", repeating past its edge"
				case "reflect": ", mirrored past its edge"
				default: ""
				}
			sentence = "Fills \(names) with \(shape) \(blend)\(spread)."
		case "pattern":
			sentence =
				"Fills \(names) with a repeating \(p["width"] ?? "?")×\(p["height"] ?? "?") tile."
		case "clipPath":
			let shapes = contents.isEmpty ? "no shapes yet" : Self.list(contents.map(\.displayName))
			sentence = "Cuts \(names) to the outline of \(shapes): only the parts inside are drawn."
		case "mask":
			let shapes = contents.isEmpty ? "no shapes yet" : Self.list(contents.map(\.displayName))
			sentence =
				"Masks \(names) with \(shapes): where they're white it shows, black hides it, grey fades it."
		case "filter":
			let effects = parts.map(Self.effect)
			let what = effects.isEmpty ? "No effects yet" : Self.list(effects)
			sentence = "\(what.prefix(1).uppercased() + what.dropFirst()), on \(names)."
		default:
			sentence = "A reusable drawing, placed wherever \(names) points at it."
		}
		return isUnused
			? sentence.replacingOccurrences(of: " nothing", with: " shapes")
				+ " Nothing uses it yet: the preview shows it on a sample shape. Drag it onto a layer to use it."
			: sentence + " Left: without it. Right: with it — the dashed box marks the change."
	}

	private static func effect(_ part: OutlineItem) -> String {
		let p = part.props
		switch part.tag {
		case "feGaussianBlur": return "blurs by \(p["stdDeviation"] ?? "0")"
		case "feDropShadow":
			return
				"adds a shadow offset \(p["dx"] ?? "2"), \(p["dy"] ?? "2") with a \(p["stdDeviation"] ?? "2") blur"
		case "feOffset": return "shifts by \(p["dx"] ?? "0"), \(p["dy"] ?? "0")"
		case "feColorMatrix": return "changes colours (\(p["type"] ?? "matrix"))"
		case "feMorphology":
			return "\(p["operator"] == "dilate" ? "thickens" : "thins") by \(p["radius"] ?? "0")"
		case "feTurbulence": return "adds noise"
		case "feFlood": return "fills with \(ColourName.of(p["flood-color"] ?? "#000000"))"
		default: return effectName(part.tag).lowercased()
		}
	}

	/// "a", "a and b", "a, b and 2 more".
	static func list(_ names: [String]) -> String {
		switch names.count {
		case 0: "nothing"
		case 1: names[0]
		case 2: "\(names[0]) and \(names[1])"
		case 3: "\(names[0]), \(names[1]) and \(names[2])"
		default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
		}
	}
}

/// Plain names for colours, for sentences: "pink", "dark blue".
enum ColourName {
	static func of(_ value: String) -> String {
		let v = value.trimmingCharacters(in: .whitespaces).lowercased()
		if v == "none" || v == "transparent" { return "nothing" }
		guard let colour = CSSColor.parse(v), let ns = NSColor(colour).usingColorSpace(.sRGB) else {
			return v
		}
		var h: CGFloat = 0
		var s: CGFloat = 0
		var b: CGFloat = 0
		var a: CGFloat = 0
		ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
		if b < 0.12 { return "black" }
		if s < 0.12 {
			return b > 0.9 ? "white" : b > 0.6 ? "light grey" : b > 0.3 ? "grey" : "dark grey"
		}
		let name: String =
			switch h * 360 {
			case ..<15, 345...: "red"
			case ..<40: "orange"
			case ..<65: "yellow"
			case ..<160: "green"
			case ..<195: "teal"
			case ..<250: "blue"
			case ..<290: "purple"
			default: "pink"
			}
		if b < 0.4 { return "dark \(name)" }
		if s < 0.4 && b > 0.8 { return "pale \(name)" }
		return name
	}
}

/// How a resource changes the drawing: its users without and with it (the
/// rest dimmed, the change outlined), or a sample when nothing uses it.
struct ImpactPreviewCard: View {
	var order: Int
	var title: String
	var symbol: String
	var summary: String
	var controller: CanvasController

	@State private var pictures: [(label: String, image: NSImage)] = []
	@State private var isLoading = true

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Label(title, systemImage: symbol).font(.headline).lineLimit(1)
			if isLoading {
				ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
			} else if !pictures.isEmpty {
				HStack(alignment: .top, spacing: 8) {
					ForEach(Array(pictures.enumerated()), id: \.offset) { index, picture in
						if index > 0 && pictures.count == 2 {
							Image(systemName: "arrow.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
								.frame(height: 120)
						}
						VStack(spacing: 4) {
							Image(nsImage: picture.image)
								.resizable()
								.interpolation(.high)
								.aspectRatio(contentMode: .fit)
								.frame(maxWidth: pictures.count > 2 ? 96 : 140, maxHeight: 120)
								.background(
									Color.gray.opacity(0.12),
									in: .rect(cornerRadius: 8, style: .continuous))
							Text(picture.label)
								.font(.caption)
								.foregroundStyle(
									picture.label == "With"
										? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
						}
					}
				}
				.frame(maxWidth: .infinity)
			}
			Text(summary)
				.font(.callout)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(14)
		.frame(width: 340)
		.task(id: order) {
			isLoading = true
			pictures = await controller.impactPreview(order: order)
			isLoading = false
		}
	}
}
