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

/// What a layer is made of, at a glance: its fill and stroke, chips for the
/// resources it uses (click one to select it), and a badge if it animates.
struct LayerBadges: View {
	var item: OutlineItem
	var isAnimated: Bool
	var controller: CanvasController

	private var paintRefs: Set<String> {
		Set(
			item.references.filter { $0.attribute == "fill" || $0.attribute == "stroke" }.map(
				\.attribute))
	}

	var body: some View {
		HStack(spacing: 4) {
			if let fill = item.fill, fill != "none", !paintRefs.contains("fill") {
				PaintDot(value: fill, isStroke: false)
			}
			if let stroke = item.prop("stroke"), stroke != "none", !paintRefs.contains("stroke") {
				PaintDot(value: stroke, isStroke: true)
			}
			ForEach(item.references, id: \.self) { ref in
				ReferenceChip(reference: ref, controller: controller)
			}
			if isAnimated {
				Button {
					controller.select(order: item.order)
					controller.showsTimeline = true
				} label: {
					Image(systemName: "sparkles")
						.font(.system(size: 10, weight: .semibold))
						.foregroundStyle(.indigo)
				}
				.buttonStyle(.plain)
				.help("Animated — show the timeline")
				.accessibilityLabel("Animated")
			}
		}
	}
}

/// A fill (solid dot) or stroke (ring) colour.
private struct PaintDot: View {
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

/// A resource this layer uses: its kind's icon in its colour. Click to select
/// the resource (in the Resources section).
private struct ReferenceChip: View {
	var reference: OutlineItem.Reference
	var controller: CanvasController

	private var symbol: String {
		switch reference.attribute {
		case "fill", "stroke": "circle.lefthalf.filled"
		case "clip-path": "scissors"
		case "mask": "theatermasks"
		case "filter": "camera.filters"
		default: "link"
		}
	}

	private var tint: Color {
		switch reference.attribute {
		case "fill", "stroke": .orange
		case "clip-path": .teal
		case "mask": .purple
		case "filter": .pink
		default: .indigo
		}
	}

	var body: some View {
		Button {
			if let target = controller.outline.first(where: { $0.elementID == reference.targetID })
			{
				controller.select(order: target.order)
			}
		} label: {
			Image(systemName: symbol)
				.font(.system(size: 9, weight: .semibold))
				.foregroundStyle(tint)
				.frame(width: 16, height: 16)
				.background(tint.opacity(0.15), in: .rect(cornerRadius: 4, style: .continuous))
		}
		.buttonStyle(.plain)
		.help("\(reference.attribute): \(reference.targetID) — click to select it")
		.accessibilityLabel("\(reference.attribute) \(reference.targetID)")
	}
}

// MARK: - Resources

/// The resources strip under the layer cards: everything defined once and
/// used by reference, as tiles. Drag one onto a card to apply it; rest on one
/// to preview how it changes the drawing; click to select it.
struct ResourceStrip: View {
	var controller: CanvasController
	@Binding var draggingResource: ResourceInfo?

	@AppStorage("layers.showsResources") private var isOpen = true

	var body: some View {
		let resources = ResourceInfo.all(in: controller.outline)
		VStack(alignment: .leading, spacing: 4) {
			header(resources)
			if isOpen {
				if resources.isEmpty {
					Text("Gradients, masks, filters and other reusable pieces appear here.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 12)
						.padding(.bottom, 8)
				} else {
					ScrollView(.horizontal) {
						HStack(spacing: 6) {
							ForEach(resources) { resource in
								ResourceTile(resource: resource, controller: controller)
									.onDrag {
										draggingResource = resource
										let provider = NSItemProvider()
										provider.registerDataRepresentation(
											forTypeIdentifier: UTType.linesLayer.identifier,
											visibility: .ownProcess
										) { completion in
											completion(Data("resource:\(resource.id)".utf8), nil)
											return nil
										}
										return provider
									} preview: {
										Label(
											resource.name,
											systemImage: InspectorView.symbol(
												for: resource.item.tag, isRoot: false)
										)
										.padding(6)
										.background(.regularMaterial, in: .capsule)
									}
							}
						}
						.padding(.horizontal, 8)
						.padding(.bottom, 8)
					}
					.scrollIndicators(.never)
				}
			}
		}
		.overlay(alignment: .top) { Divider().opacity(0.6) }
	}

	private func header(_ resources: [ResourceInfo]) -> some View {
		HStack(spacing: 4) {
			Button {
				withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
			} label: {
				HStack(spacing: 6) {
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.bold))
						.rotationEffect(.degrees(isOpen ? 90 : 0))
					Text("Resources")
					Text("\(resources.count)").foregroundStyle(.tertiary)
				}
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.help(isOpen ? "Hide resources" : "Show resources")
			Spacer()
			Group {
				Menu {
					ForEach(CanvasController.Definition.allCases) { kind in
						Button(kind.title, systemImage: kind.symbol) {
							if let s = controller.selection, !s.isRoot {
								controller.addDefinition(kind, applyingTo: s.order)
							} else {
								controller.addDefinition(kind)
							}
						}
					}
				} label: {
					Label("Add Resource", systemImage: "plus")
				}
				.menuIndicator(.hidden)
				.buttonStyle(.icon(size: 22))
				.fixedSize()
				.help(
					"Add a gradient, pattern, clip, mask or filter (applied to the selection, if any)"
				)
				Button("Remove Unused", systemImage: "trash.slash") {
					controller.removeUnusedDefinitions()
				}
				.buttonStyle(.icon(size: 22))
				.disabled(!resources.contains(where: \.isUnused))
				.help("Remove resources nothing uses")
			}
			.disabled(!controller.isEditing)
		}
		.padding(.horizontal, 10)
		.padding(.top, 6)
	}
}

/// One resource: a swatch in its kind's colour, its name, and how many use it.
private struct ResourceTile: View {
	var resource: ResourceInfo
	var controller: CanvasController

	@State private var isHovered = false
	@State private var showsPreview = false
	@State private var previewTask: Task<Void, Never>?

	private var isSelected: Bool { controller.selection?.order == resource.order }

	var body: some View {
		VStack(spacing: 4) {
			swatch
			Text(resource.name)
				.font(.caption2)
				.lineLimit(1)
				.truncationMode(.middle)
			Text(resource.isUnused ? "unused" : "\(resource.users.count)×")
				.font(.caption2.monospacedDigit())
				.foregroundStyle(
					resource.isUnused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
		}
		.frame(width: 64)
		.padding(.vertical, 6)
		.background(
			isSelected
				? AnyShapeStyle(.tint.opacity(0.16))
				: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.45)),
			in: .rect(cornerRadius: 10, style: .continuous)
		)
		.overlay {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(
					isSelected
						? AnyShapeStyle(.tint.opacity(0.7))
						: AnyShapeStyle(.separator.opacity(0.5)),
					lineWidth: 1)
		}
		.opacity(resource.isUnused ? 0.7 : 1)
		.contentShape(.rect)
		.onTapGesture { controller.select(order: resource.order) }
		.onHover(perform: hover)
		.popover(isPresented: $showsPreview, arrowEdge: .top) {
			ImpactPreviewCard(
				order: resource.order, title: resource.name,
				symbol: InspectorView.symbol(for: resource.item.tag, isRoot: false),
				summary: resource.summary, controller: controller)
		}
		.help(
			resource.isUnused
				? "Nothing uses \(resource.name) — drag it onto a layer"
				: "Used by \(ResourceInfo.list(resource.users.map(\.displayName))) — drag onto a layer to apply"
		)
		.accessibilityElement(children: .combine)
		.accessibilityHint(resource.summary)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	/// The gradient itself, or the kind's icon in its colour.
	@ViewBuilder
	private var swatch: some View {
		let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
		if resource.kind == .gradient, !resource.parts.isEmpty {
			let colours = resource.parts.map {
				CSSColor.parse(ResourceInfo.stopColour($0)) ?? .black
			}
			shape
				.fill(
					resource.item.tag == "radialGradient"
						? AnyShapeStyle(
							RadialGradient(
								colors: colours, center: .center, startRadius: 0, endRadius: 18))
						: AnyShapeStyle(
							LinearGradient(
								colors: colours, startPoint: .leading, endPoint: .trailing))
				)
				.frame(width: 36, height: 36)
				.overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
		} else {
			shape
				.fill(resource.kind.tint.opacity(0.18))
				.frame(width: 36, height: 36)
				.overlay {
					Image(systemName: InspectorView.symbol(for: resource.item.tag, isRoot: false))
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(resource.kind.tint)
				}
		}
	}

	private func hover(_ inside: Bool) {
		isHovered = inside
		previewTask?.cancel()
		if inside {
			previewTask = Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(700))
				guard !Task.isCancelled else { return }
				showsPreview = true
			}
		} else {
			showsPreview = false
		}
	}
}
