import SwiftUI
import UniformTypeIdentifiers

/// The element drawn on its own, small, at the start of its layer row.
struct LayerThumbnail: View {
	var item: OutlineItem
	var controller: CanvasController

	@State private var image: NSImage?

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(.quaternary.opacity(0.6))
			if let image {
				Image(nsImage: image)
					.resizable()
					.interpolation(.high)
					.aspectRatio(contentMode: .fit)
					.padding(2)
			} else {
				Image(systemName: InspectorView.symbol(for: item.tag, isRoot: false))
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: 24, height: 24)
		.overlay {
			RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
				.separator, lineWidth: 0.5)
		}
		.task(id: "\(item.order)-\(controller.thumbnailGeneration)") {
			// A short wait, so scrolling past rows doesn't render them all.
			try? await Task.sleep(for: .milliseconds(120))
			guard !Task.isCancelled else { return }
			image = await controller.thumbnail(order: item.order)
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

/// The Resources section of the Layers panel: everything defined once and
/// used by reference, with who uses it. Drag one onto a layer to apply it;
/// rest on one to preview how it changes the drawing.
struct ResourcesSection: View {
	var controller: CanvasController
	@Binding var draggingResource: ResourceInfo?

	@AppStorage("layers.showsResources") private var isOpen = true
	@State private var expanded: Set<String> = []

	var body: some View {
		let resources = ResourceInfo.all(in: controller.outline)
		VStack(alignment: .leading, spacing: 1) {
			header(resources)
			if isOpen {
				if resources.isEmpty {
					Text("Gradients, masks, filters and other reusable pieces appear here.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
				}
				ForEach(resources) { resource in
					ResourceRow(
						resource: resource, controller: controller,
						isExpanded: expanded.contains(resource.id),
						toggle: {
							withAnimation(.snappy(duration: 0.2)) {
								if expanded.contains(resource.id) {
									expanded.remove(resource.id)
								} else {
									expanded.insert(resource.id)
								}
							}
						}
					)
					.onDrag {
						draggingResource = resource
						let provider = NSItemProvider()
						provider.registerDataRepresentation(
							forTypeIdentifier: UTType.linesLayer.identifier, visibility: .ownProcess
						) { completion in
							completion(Data("resource:\(resource.id)".utf8), nil)
							return nil
						}
						return provider
					} preview: {
						Label(
							resource.name,
							systemImage: InspectorView.symbol(for: resource.item.tag, isRoot: false)
						)
						.padding(6)
						.background(.regularMaterial, in: .capsule)
					}
				}
			}
		}
		.padding(.horizontal, 6)
		.padding(.bottom, 8)
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
			Spacer()
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
				"Add a gradient, pattern, clip, mask or filter (applied to the selection, if any)")
			Button("Remove Unused", systemImage: "trash.slash") {
				controller.removeUnusedDefinitions()
			}
			.buttonStyle(.icon(size: 22))
			.disabled(!resources.contains(where: \.isUnused))
			.help("Remove resources nothing uses")
		}
		.disabled(!controller.isEditing)
		.padding(.horizontal, 6)
		.padding(.top, 10)
		.padding(.bottom, 4)
		.overlay(alignment: .top) { Divider().opacity(0.6) }
	}
}

private struct ResourceRow: View {
	var resource: ResourceInfo
	var controller: CanvasController
	var isExpanded: Bool
	var toggle: () -> Void

	@State private var isHovered = false
	@State private var showsPreview = false
	@State private var previewTask: Task<Void, Never>?

	private var isSelected: Bool { controller.selection?.order == resource.order }

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 6) {
				Button(action: toggle) {
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.bold))
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.foregroundStyle(.secondary)
						.frame(width: 14, height: 20)
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.help(isExpanded ? "Collapse" : "Show what uses it")
				preview
				VStack(alignment: .leading, spacing: 0) {
					Text(resource.name).lineLimit(1).truncationMode(.middle)
					Text(InspectorView.elementName(for: resource.item.tag))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 4)
				Text(resource.isUnused ? "unused" : "\(resource.users.count)×")
					.font(.caption2.monospacedDigit())
					.foregroundStyle(
						resource.isUnused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
					)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(.quaternary.opacity(0.6), in: .capsule)
					.help(
						resource.isUnused
							? "Nothing uses it — drag it onto a layer"
							: "Used by \(ResourceInfo.list(resource.users.map(\.displayName)))")
			}
			.padding(.horizontal, 6)
			.frame(height: LayersPanel.rowHeight)
			.background(
				isSelected
					? AnyShapeStyle(.tint.opacity(0.2))
					: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
				in: .rect(cornerRadius: 7, style: .continuous)
			)
			.opacity(resource.isUnused ? 0.7 : 1)
			.contentShape(.rect)
			.onTapGesture { controller.select(order: resource.order) }
			.onHover(perform: hover)
			.popover(isPresented: $showsPreview, arrowEdge: .trailing) {
				ImpactPreviewCard(
					order: resource.order, title: resource.name,
					symbol: InspectorView.symbol(for: resource.item.tag, isRoot: false),
					summary: resource.summary, controller: controller)
			}
			.help("Drag onto a layer to apply it")
			.accessibilityElement(children: .combine)
			.accessibilityHint(resource.summary)

			if isExpanded {
				if resource.kind == .clip || resource.kind == .mask {
					detailHeader("Shapes")
					ForEach(resource.contents) { shape in
						detailRow(
							shape, symbol: InspectorView.symbol(for: shape.tag, isRoot: false))
					}
				}
				detailHeader(resource.isUnused ? "Not used yet" : "Used by")
				ForEach(resource.users) { user in
					detailRow(user, symbol: InspectorView.symbol(for: user.tag, isRoot: false))
				}
			}
		}
	}

	private func detailHeader(_ title: String) -> some View {
		Text(title)
			.font(.caption2.weight(.semibold))
			.foregroundStyle(.tertiary)
			.padding(.leading, 40)
			.padding(.top, 2)
	}

	private func detailRow(_ item: OutlineItem, symbol: String) -> some View {
		Button {
			controller.select(order: item.order)
		} label: {
			HStack(spacing: 6) {
				Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
				Text(item.displayName).lineLimit(1)
				Spacer()
			}
			.font(.callout)
			.padding(.leading, 40)
			.frame(height: 22)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.help("Select \(item.displayName)")
	}

	/// A swatch of the resource: its gradient, or its kind's icon.
	@ViewBuilder
	private var preview: some View {
		let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
		if resource.kind == .gradient, !resource.parts.isEmpty {
			let colours = resource.parts.map {
				CSSColor.parse(ResourceInfo.stopColour($0)) ?? .black
			}
			shape
				.fill(
					resource.item.tag == "radialGradient"
						? AnyShapeStyle(
							RadialGradient(
								colors: colours, center: .center, startRadius: 0, endRadius: 14))
						: AnyShapeStyle(
							LinearGradient(
								colors: colours, startPoint: .leading, endPoint: .trailing))
				)
				.frame(width: 24, height: 24)
				.overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
		} else {
			shape
				.fill(resource.kind.tint.opacity(0.18))
				.frame(width: 24, height: 24)
				.overlay {
					Image(systemName: InspectorView.symbol(for: resource.item.tag, isRoot: false))
						.font(.system(size: 11, weight: .semibold))
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
