import SwiftUI

/// The wide Layers panel's second column: the selected element drawn large,
/// and in plain words what it is, how it's painted, and everything that
/// changes how it's drawn — its own clips, masks, filters and animations, and
/// those it picks up from the groups it's in. With nothing selected, what the
/// drawing is made of.
struct LayerDetails: View {
	var controller: CanvasController
	/// Narrows the layers to a kind of element.
	var showKind: (LayerFilter.Kind) -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				if controller.hasElementSelection, let order = controller.selection?.order,
					let item = controller.outline.first(where: { $0.order == order })
				{
					ElementDetails(item: item, controller: controller)
				} else {
					DrawingSummary(controller: controller, showKind: showKind)
				}
			}
			.padding(14)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

// MARK: - Element

private struct ElementDetails: View {
	var item: OutlineItem
	var controller: CanvasController

	private var outline: [OutlineItem] { controller.outline }

	var body: some View {
		let byOrder = Dictionary(uniqueKeysWithValues: outline.map { ($0.order, $0) })
		let ancestors = Self.ancestors(of: item, in: byOrder)
		let resources = ResourceInfo.all(in: outline)
		let resourceByID = Dictionary(
			resources.compactMap { r in r.item.elementID.map { ($0, r) } },
			uniquingKeysWith: { first, _ in first })

		header
		LargePreview(item: item, controller: controller)

		if let resource = resources.first(where: { $0.order == item.order }) {
			DetailSection(title: "What It Does") {
				Text(resource.sentence).fixedSize(horizontal: false, vertical: true)
			}
			DetailSection(title: resource.isUnused ? "Not Used Yet" : "Used By") {
				if resource.isUnused {
					Text("Drag it from Resources onto a layer to use it.")
						.foregroundStyle(.secondary)
				}
				ForEach(resource.users, id: \.order) { user in
					DetailLine(
						symbol: InspectorView.symbol(for: user.tag, isRoot: false),
						tint: resource.kind.tint, text: Text(user.displayName),
						action: { controller.select(order: user.order) })
				}
			}
		} else {
			DetailSection(title: "Paint") {
				Lines(paintLines(ancestors: ancestors, resources: resourceByID))
			}
			DetailSection(title: "What Applies to It") {
				let lines = effectLines(ancestors: ancestors, resources: resourceByID)
				if lines.isEmpty {
					Text("Nothing else changes how it's drawn.").foregroundStyle(.secondary)
				}
				Lines(lines)
			}
			let animations = animationLines(ancestors: ancestors)
			if !animations.isEmpty {
				DetailSection(title: "Movement") { Lines(animations) }
			}
		}

		let children = outline.filter { $0.parent == item.order && !AnimationTag.contains($0.tag) }
		if !children.isEmpty {
			DetailSection(title: "Inside It") {
				Text(Self.contents(of: item, in: outline))
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				ForEach(children.prefix(12), id: \.order) { child in
					DetailLine(
						symbol: InspectorView.symbol(for: child.tag, isRoot: false),
						tint: .secondary, text: Text(child.displayName),
						action: { controller.select(order: child.order) })
				}
				if children.count > 12 {
					Text("and \(children.count - 12) more").foregroundStyle(.secondary)
				}
			}
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(item.displayName)
				.font(.title3.weight(.semibold))
				.lineLimit(2)
			HStack(spacing: 6) {
				Text(InspectorView.elementName(for: item.tag))
				if let id = item.elementID, item.label != id {
					Text("#\(id)").font(.callout.monospaced())
				}
				if item.isHidden {
					Label("Hidden", systemImage: "eye.slash").labelStyle(.titleAndIcon)
				}
			}
			.foregroundStyle(.secondary)
			if let box = item.box {
				Text(
					"\(Self.number(box.width)) × \(Self.number(box.height)), at \(Self.number(box.minX)), \(Self.number(box.minY))"
				)
				.font(.callout.monospacedDigit())
				.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: Paint

	private func paintLines(
		ancestors: [OutlineItem], resources: [String: ResourceInfo]
	) -> [DetailLine] {
		var lines: [DetailLine] = []
		for (attribute, title) in [("fill", "Fill"), ("stroke", "Stroke")] {
			let own = item.prop(attribute)
			let source = own == nil ? ancestors.first { $0.prop(attribute) != nil } : nil
			let value = own ?? source?.prop(attribute)
			var text: Text
			var tint: AnyShapeStyle = AnyShapeStyle(.secondary)
			var action: (() -> Void)?
			switch value {
			case nil:
				text =
					attribute == "fill"
					? Text("\(title): black, the default") : Text("\(title): none")
			case "none", "transparent":
				text = Text("\(title): none")
			case let v? where v.hasPrefix("url("):
				let id = Self.referencedID(v)
				if let resource = resources[id] {
					text = Text("\(title): \(Text("“\(resource.name)”").bold()), \(resource.what)")
					tint = AnyShapeStyle(resource.kind.tint)
					action = { controller.select(order: resource.order) }
				} else {
					text = Text("\(title): “\(id)”, which isn't defined, so nothing is drawn")
				}
			case let v?:
				text = Text("\(title): \(ColourName.of(v)) \(Text(v).font(.callout.monospaced()))")
				if let colour = CSSColor.parse(v) { tint = AnyShapeStyle(colour) }
			}
			if attribute == "stroke", let value, value != "none" {
				let width =
					item.prop("stroke-width")
					?? ancestors.first { $0.prop("stroke-width") != nil }?.prop("stroke-width")
					?? "1"
				text = Text("\(text), \(width) wide")
			}
			if let source {
				text = Text("\(text), from \(Text(source.displayName).bold())")
				action = action ?? { controller.select(order: source.order) }
			}
			lines.append(
				DetailLine(
					symbol: attribute == "fill" ? "drop.fill" : "pencil.tip",
					tint: tint, text: text, action: action))
		}
		for (attribute, what) in [
			("opacity", "Drawn at"), ("fill-opacity", "Fill at"), ("stroke-opacity", "Stroke at"),
		] {
			if let value = item.prop(attribute), let percent = Self.percent(value), percent < 100 {
				lines.append(
					DetailLine(
						symbol: "circle.lefthalf.filled", tint: .secondary,
						text: Text("\(what) \(percent)% opacity")))
			}
		}
		return lines
	}

	// MARK: Effects

	/// Its clips, masks and filters, then those of the groups around it.
	private func effectLines(
		ancestors: [OutlineItem], resources: [String: ResourceInfo]
	) -> [DetailLine] {
		var lines: [DetailLine] = []
		for (owner, inherited) in [(item, false)] + ancestors.map({ ($0, true) }) {
			for ref in owner.references
			where ["clip-path", "mask", "filter"].contains(ref.attribute) {
				let resource = resources[ref.targetID]
				let name = Text("“\(resource?.name ?? ref.targetID)”").bold()
				var text =
					switch ref.attribute {
					case "clip-path": Text("Clipped by \(name)")
					case "mask": Text("Masked by \(name)")
					default: Text("Filtered by \(name)")
					}
				if let resource { text = Text("\(text): \(resource.what)") }
				if inherited {
					text = Text(
						"\(text), applied to \(Text(owner.displayName).bold()), which contains it")
				}
				lines.append(
					DetailLine(
						symbol: ref.attribute == "filter"
							? "camera.filters"
							: ref.attribute == "mask" ? "theatermasks" : "scissors",
						tint: resource?.kind.tint ?? .secondary, text: text,
						action: resource.map { r in { controller.select(order: r.order) } }))
			}
			if inherited, let value = owner.prop("opacity"), let percent = Self.percent(value),
				percent < 100
			{
				lines.append(
					DetailLine(
						symbol: "circle.lefthalf.filled", tint: .secondary,
						text: Text("Faded to \(percent)% by \(Text(owner.displayName).bold())"),
						action: { controller.select(order: owner.order) }))
			}
		}
		return lines
	}

	// MARK: Animations

	private func animationLines(ancestors: [OutlineItem]) -> [DetailLine] {
		let all = controller.animations
		var lines: [DetailLine] = []
		for (owner, inherited) in [(item, false)] + ancestors.map({ ($0, true) }) {
			for animation in all where animation.target?.order == owner.order {
				var text = Text("Animates \(Text(animation.property).bold())")
				if !animation.isCSS { text = Text("\(text), \(animation.change)") }
				text = Text("\(text), \(Self.timing(animation))")
				if inherited {
					text = Text("\(text), with \(Text(owner.displayName).bold())")
				}
				lines.append(
					DetailLine(
						symbol: "sparkles", tint: .indigo, text: text,
						action: {
							controller.select(order: animation.order)
							controller.showsTimeline = true
						}))
			}
		}
		return lines
	}

	// MARK: Helpers

	static func ancestors(of item: OutlineItem, in byOrder: [Int: OutlineItem]) -> [OutlineItem] {
		var result: [OutlineItem] = []
		var parent = byOrder[item.parent]
		while let p = parent {
			result.append(p)
			parent = byOrder[p.parent]
		}
		return result
	}

	/// "3 shapes, 1 text and 2 groups", counting everything inside.
	static func contents(of item: OutlineItem, in outline: [OutlineItem]) -> String {
		var inside = Set([item.order])
		var counts: [String: Int] = [:]
		for other in outline where inside.contains(other.parent) {
			inside.insert(other.order)
			if AnimationTag.contains(other.tag) { continue }
			counts[InspectorView.elementName(for: other.tag), default: 0] += 1
		}
		let parts = counts.sorted {
			$0.value > $1.value || ($0.value == $1.value && $0.key < $1.key)
		}
		.map { "\($0.value) \($0.key.lowercased())" }
		return "Contains " + ResourceInfo.list(parts) + "."
	}

	static func referencedID(_ value: String) -> String {
		value.firstMatch(of: #/url\(\s*['"]?#([^'")\s]+)/#).map { String($0.1) } ?? value
	}

	static func percent(_ value: String) -> Int? {
		let v = value.trimmingCharacters(in: .whitespaces)
		if v.hasSuffix("%") { return Double(v.dropLast()).map { Int($0.rounded()) } }
		return Double(v).map { Int(($0 * 100).rounded()) }
	}

	static func number(_ value: CGFloat) -> String {
		Double(value).formatted(.number.precision(.fractionLength(0...1)))
	}

	static func timing(_ a: AnimationInfo) -> String {
		var parts: [String] = []
		if let d = a.duration { parts.append("over \(AnimationInfo.format(seconds: d))") }
		if a.begin > 0 { parts.append("after \(AnimationInfo.format(seconds: a.begin))") }
		if a.repeatsForever {
			parts.append("forever")
		} else if let count = a.repeatCount, count != 1 {
			parts.append("\(count.formatted()) times")
		}
		return parts.joined(separator: " ")
	}
}

// MARK: - Drawing summary

private struct DrawingSummary: View {
	var controller: CanvasController
	var showKind: (LayerFilter.Kind) -> Void

	var body: some View {
		let items = LayersPanel.layerItems(controller.outline)
		let animated = LayersPanel.animatedOrders(controller.outline)
		let resources = ResourceInfo.all(in: controller.outline)

		VStack(alignment: .leading, spacing: 3) {
			Text("This Drawing").font(.title3.weight(.semibold))
			Text("Select a layer to see what applies to it.")
				.foregroundStyle(.secondary)
		}

		DetailSection(title: "Made Of") {
			ForEach(LayerFilter.Kind.allCases) { kind in
				let count = items.count(where: {
					LayerFilter(kinds: [kind]).matches($0, animated: animated)
				})
				if count > 0 {
					DetailLine(
						symbol: kind.symbol, tint: .secondary,
						text: Text("\(Text("\(count)").bold()) \(Text(kind.title))"),
						action: { showKind(kind) })
				}
			}
		}

		if !resources.isEmpty {
			DetailSection(title: "Resources") {
				ForEach(resources) { resource in
					DetailLine(
						symbol: "circle.fill", tint: resource.kind.tint,
						text: Text(
							"\(Text("“\(resource.name)”").bold()), \(resource.what), \(resource.isUnused ? String(localized: "unused") : String(localized: "used by \(resource.users.count)"))"
						),
						action: { controller.select(order: resource.order) })
				}
			}
		}
	}
}

// MARK: - Parts

private struct DetailSection<Content: View>: View {
	var title: LocalizedStringKey
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.accessibilityAddTraits(.isHeader)
			content
		}
		.font(.callout)
	}
}

private struct Lines: View {
	var lines: [DetailLine]
	init(_ lines: [DetailLine]) { self.lines = lines }

	var body: some View {
		ForEach(Array(lines.enumerated()), id: \.offset) { $0.element }
	}
}

/// One explained fact; clicking it selects what it's about.
private struct DetailLine: View {
	var symbol: String
	var tint: AnyShapeStyle
	var text: Text
	var action: (() -> Void)?

	init(symbol: String, tint: some ShapeStyle, text: Text, action: (() -> Void)? = nil) {
		self.symbol = symbol
		self.tint = AnyShapeStyle(tint)
		self.text = text
		self.action = action
	}

	@State private var isHovered = false

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			Image(systemName: symbol)
				.foregroundStyle(tint)
				.frame(width: 16)
				.accessibilityHidden(true)
			text
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
			if action != nil {
				Image(systemName: "arrow.right.circle")
					.foregroundStyle(.secondary)
					.opacity(isHovered ? 1 : 0)
					.accessibilityHidden(true)
			}
		}
		.padding(.vertical, 4)
		.padding(.horizontal, 6)
		.background(
			isHovered && action != nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 6, style: .continuous)
		)
		.contentShape(.rect)
		.onHover { isHovered = $0 }
		.onTapGesture { action?() }
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(action != nil ? .isButton : [])
	}
}

/// The element drawn on its own, large.
private struct LargePreview: View {
	var item: OutlineItem
	var controller: CanvasController

	@State private var image: NSImage?

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(.quaternary.opacity(0.6))
			if let image {
				Image(nsImage: image)
					.resizable()
					.interpolation(.high)
					.aspectRatio(contentMode: .fit)
					.padding(12)
			} else {
				Image(systemName: InspectorView.symbol(for: item.tag, isRoot: false))
					.font(.largeTitle)
					.foregroundStyle(.tertiary)
			}
		}
		.frame(maxWidth: .infinity)
		.frame(height: 180)
		.accessibilityHidden(true)
		.task(id: "\(item.order)-\(controller.thumbnailGeneration)") {
			image = await controller.thumbnail(order: item.order, size: 360)
		}
	}
}
