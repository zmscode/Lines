import SwiftUI
import UniformTypeIdentifiers

/// The element drawn on its own, small, on its layer card.
struct LayerThumbnail: View {
	var item: OutlineItem
	var controller: CanvasController
	var size: CGFloat = 24

	@State private var image: NSImage?

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: size > 30 ? 8 : 5, style: .continuous)
				.fill(.quaternary.opacity(0.6))
			if let image {
				Image(nsImage: image)
					.resizable()
					.interpolation(.high)
					.aspectRatio(contentMode: .fit)
					.padding(size > 30 ? 4 : 2)
			} else {
				Image(systemName: InspectorView.symbol(for: item.tag, isRoot: false))
					.font(.system(size: size * 0.45))
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: size, height: size)
		.overlay {
			RoundedRectangle(cornerRadius: size > 30 ? 8 : 5, style: .continuous).strokeBorder(
				.separator, lineWidth: 0.5)
		}
		.task(id: "\(item.order)-\(controller.thumbnailGeneration)") {
			// A short wait, so scrolling past rows doesn't render them all.
			try? await Task.sleep(for: .milliseconds(120))
			guard !Task.isCancelled else { return }
			image = await controller.thumbnail(order: item.order, size: max(64, Double(size) * 2))
		}
		.accessibilityHidden(true)
	}
}

/// An element's plain fill and stroke colours, as dots. Gradients and
/// patterns are attachments instead.
struct PaintDots: View {
	var item: OutlineItem

	var body: some View {
		HStack(spacing: 3) {
			if let fill = item.fill, fill != "none", !fill.hasPrefix("url(") {
				PaintDot(value: fill, isStroke: false)
			}
			if let stroke = item.prop("stroke"), stroke != "none", !stroke.hasPrefix("url(") {
				PaintDot(value: stroke, isStroke: true)
			}
		}
	}
}

/// A fill (solid dot) or stroke (ring) colour.
struct PaintDot: View {
	var value: String
	var isStroke: Bool

	var body: some View {
		let colour = CSSColor.parse(value) ?? .gray
		Group {
			if isStroke {
				Circle().strokeBorder(colour, lineWidth: 2.5)
			} else {
				Circle().fill(colour).overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
			}
		}
		.frame(width: 10, height: 10)
		.help("\(isStroke ? "Stroke" : "Fill"): \(value)")
		.accessibilityLabel("\(isStroke ? "Stroke" : "Fill") \(ColourName.of(value))")
	}
}

// MARK: - Attachments

/// Something applied to an element, listed under it: a gradient or pattern
/// paint, a clip, mask, filter or marker it points at, or an animation.
struct Attachment: Identifiable {
	enum Kind {
		case resource(ResourceInfo, attribute: String)
		/// Points at an id nothing defines.
		case missing(id: String, attribute: String)
		case animation(AnimationInfo)
	}

	var owner: OutlineItem
	var kind: Kind

	var id: String {
		switch kind {
		case .resource(_, let attribute), .missing(_, let attribute): "\(owner.path)/\(attribute)"
		case .animation(let a): "\(owner.path)/anim-\(a.id)"
		}
	}

	/// What it does: "clip", "fill", "animates".
	var label: String {
		switch kind {
		case .resource(_, let attribute), .missing(_, let attribute): Self.label(attribute)
		case .animation: String(localized: "animates")
		}
	}

	var title: String {
		switch kind {
		case .resource(let r, _): "“\(r.name)”"
		case .missing(let id, _): "“\(id)”"
		case .animation(let a): a.property
		}
	}

	var detail: String {
		switch kind {
		case .resource(let r, _): r.what
		case .missing: String(localized: "isn't defined, so it does nothing")
		case .animation(let a):
			[a.isCSS ? nil : a.change, Self.timing(a)].compactMap { $0 }.filter { !$0.isEmpty }
				.joined(separator: " · ")
		}
	}

	var summary: String { "\(label) \(title): \(detail)" }

	var symbol: String {
		switch kind {
		case .resource(let r, let attribute):
			switch attribute {
			case "clip-path": "scissors"
			case "mask": "theatermasks"
			case "filter": "camera.filters"
			case "href", "xlink:href": "square.on.square"
			default: r.kind == .pattern ? "square.grid.3x3.fill" : "circle.lefthalf.filled"
			}
		case .missing: "exclamationmark.triangle.fill"
		case .animation: "sparkles"
		}
	}

	var tint: Color {
		switch kind {
		case .resource(let r, _): r.kind.tint
		case .missing: .orange
		case .animation: .indigo
		}
	}

	/// How many elements share it, for resources used more than once.
	var sharedBy: Int? {
		if case .resource(let r, _) = kind, r.users.count > 1 { return r.users.count }
		return nil
	}

	/// What applies to each element, by order.
	static func all(
		in outline: [OutlineItem], resources: [ResourceInfo], animations: [AnimationInfo]
	) -> [Int: [Attachment]] {
		let byID = Dictionary(
			resources.compactMap { r in r.item.elementID.map { ($0, r) } },
			uniquingKeysWith: { first, _ in first })
		var result: [Int: [Attachment]] = [:]
		for item in outline where !ResourceInfo.isResource(item.tag) {
			var seen = Set<String>()
			for ref in item.references where seen.insert(ref.attribute).inserted {
				let isLink = ref.attribute == "href" || ref.attribute == "xlink:href"
				// A <use> shows the symbol it places; other links aren't applied.
				if isLink && byID[ref.targetID] == nil { continue }
				let kind: Kind =
					byID[ref.targetID].map { .resource($0, attribute: ref.attribute) }
					?? .missing(id: ref.targetID, attribute: ref.attribute)
				result[item.order, default: []].append(Attachment(owner: item, kind: kind))
			}
		}
		for animation in animations {
			guard let target = animation.target else { continue }
			result[target.order, default: []].append(
				Attachment(owner: target, kind: .animation(animation)))
		}
		return result
	}

	static func label(_ attribute: String) -> String {
		switch attribute {
		case "clip-path": String(localized: "clip")
		case "mask": String(localized: "mask")
		case "filter": String(localized: "filter")
		case "fill": String(localized: "fill")
		case "stroke": String(localized: "stroke")
		case let a where a.hasPrefix("marker"): String(localized: "marker")
		case "href", "xlink:href": String(localized: "places")
		default: attribute
		}
	}

	/// "4s · after 1s · forever".
	static func timing(_ a: AnimationInfo) -> String {
		var parts: [String] = []
		if let d = a.duration { parts.append(AnimationInfo.format(seconds: d)) }
		if a.begin > 0 {
			parts.append(String(localized: "after \(AnimationInfo.format(seconds: a.begin))"))
		}
		if a.repeatsForever {
			parts.append("∞")
		} else if let count = a.repeatCount, count != 1 {
			parts.append("\(count.formatted())×")
		}
		return parts.joined(separator: " · ")
	}
}

/// One attachment, indented under its element. Click to select what it is
/// (the resource, to edit in the inspector, or the animation, on the
/// timeline); drag it onto another layer to apply it there too.
struct AttachmentRow: View {
	var attachment: Attachment
	var depth: Int
	var controller: CanvasController

	@State private var isHovered = false

	private var isSelected: Bool {
		switch attachment.kind {
		case .resource(let r, _): controller.selection?.order == r.order
		case .animation(let a): controller.selection?.order == a.order
		case .missing: false
		}
	}

	var body: some View {
		HStack(spacing: 6) {
			// Lines up under the element's thumbnail.
			Color.clear.frame(width: CGFloat(depth) * 16 + 2)
			Image(systemName: attachment.symbol)
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(attachment.tint)
				.frame(width: 18, height: 18)
				.background(attachment.tint.opacity(0.14), in: .rect(cornerRadius: 4))
			Text(attachment.label)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(attachment.title)
				.font(.callout.weight(.medium))
				.lineLimit(1)
			Text(attachment.detail)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.tail)
			Spacer(minLength: 4)
			if let shared = attachment.sharedBy {
				Text("\(shared)×")
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(.quaternary.opacity(0.7), in: .capsule)
					.help("Shared by \(shared) elements: changing it changes them all")
			}
		}
		.padding(.horizontal, 6)
		.frame(height: LayersPanel.attachmentHeight)
		.background(
			isSelected
				? AnyShapeStyle(.tint.opacity(0.14))
				: isHovered ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 6, style: .continuous)
		)
		.contentShape(.rect)
		.onTapGesture(perform: open)
		.onHover { isHovered = $0 }
		.help(attachment.summary)
		.contextMenu { menu }
		.accessibilityElement(children: .combine)
		.accessibilityLabel(attachment.summary)
		.accessibilityAddTraits(.isButton)
		.accessibilityAction { open() }
	}

	private func open() {
		switch attachment.kind {
		case .resource(let r, _): controller.select(order: r.order)
		case .animation(let a):
			controller.select(order: a.order)
			controller.showsTimeline = true
		case .missing: break
		}
	}

	@ViewBuilder
	private var menu: some View {
		switch attachment.kind {
		case .resource(let r, let attribute):
			Button("Select \(attachment.title)", systemImage: "cursorarrow.click") {
				controller.select(order: r.order)
			}
			if r.kind == .clip || r.kind == .mask {
				Button("Edit on Canvas", systemImage: "pencil.and.outline") {
					controller.editOnCanvas(definition: r.order)
				}
				.disabled(!controller.isEditing)
			}
			Divider()
			Button("Remove from \(attachment.owner.displayName)", systemImage: "minus.circle") {
				controller.removeReference(order: attachment.owner.order, attribute: attribute)
			}
			.disabled(!controller.isEditing)
		case .missing(_, let attribute):
			Button("Remove from \(attachment.owner.displayName)", systemImage: "minus.circle") {
				controller.removeReference(order: attachment.owner.order, attribute: attribute)
			}
			.disabled(!controller.isEditing)
		case .animation(let a):
			Button("Show on Timeline", systemImage: "timeline.selection") { open() }
			if !a.isCSS {
				Divider()
				Button("Delete Animation", systemImage: "trash", role: .destructive) {
					controller.delete(order: a.order)
				}
				.disabled(!controller.isEditing)
			}
		}
	}
}
