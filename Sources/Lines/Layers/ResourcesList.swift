import SwiftUI
import UniformTypeIdentifiers

/// The Resources tab: every gradient, pattern, clip path, mask, filter and
/// symbol in the drawing, grouped by kind, each with what it does and what
/// uses it. Rest on one to preview how it changes the drawing.
struct ResourcesList: View {
	var controller: CanvasController
	var resources: [ResourceInfo]
	/// Shows an element that uses a resource, in the Layers tab.
	var showUser: (Int) -> Void

	@State private var expanded: Set<String> = []

	private static let sections: [(ResourceInfo.Kind, LocalizedStringKey)] = [
		(.gradient, "Gradients"), (.pattern, "Patterns"), (.clip, "Clip Paths"),
		(.mask, "Masks"), (.filter, "Filters"), (.symbol, "Symbols"),
	]

	var body: some View {
		VStack(spacing: 0) {
			header
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 1, pinnedViews: .sectionHeaders) {
					ForEach(Self.sections.indices, id: \.self) { i in
						let (kind, title) = Self.sections[i]
						let items = resources.filter { $0.kind == kind }
						if !items.isEmpty {
							Section {
								ForEach(items) { resource in
									ResourceRow(
										resource: resource, controller: controller,
										isExpanded: expanded.contains(resource.id),
										toggle: { toggle(resource.id) }, showUser: showUser)
								}
							} header: {
								Text(title)
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
									.frame(maxWidth: .infinity, alignment: .leading)
									.padding(.horizontal, 8)
									.padding(.top, 10)
									.padding(.bottom, 2)
									.background(.background.opacity(0.001))
							}
						}
					}
				}
				.padding(.horizontal, 6)
				.padding(.bottom, 8)
			}
			.overlay {
				if resources.isEmpty {
					ContentUnavailableView(
						"No Resources", systemImage: "swatchpalette",
						description: Text(
							"Gradients, clips, masks, filters and other pieces defined once and reused appear here."
						))
				}
			}
		}
	}

	private var header: some View {
		HStack(spacing: 4) {
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
			.fixedSize()
			.help(
				"Add a gradient, pattern, clip, mask or filter (applied to the selection, if any)")
			Spacer()
			Button("Remove Unused", systemImage: "trash.slash") {
				controller.removeUnusedDefinitions()
			}
			.labelStyle(.titleAndIcon)
			.disabled(!resources.contains(where: \.isUnused))
			.help("Remove resources nothing uses")
		}
		.controlSize(.small)
		.disabled(!controller.isEditing)
		.padding(.horizontal, 10)
		.padding(.vertical, 4)
	}

	private func toggle(_ id: String) {
		withAnimation(.snappy(duration: 0.2)) {
			if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
		}
	}

	/// The drag payload that applies a resource where it's dropped.
	static func provider(for resource: ResourceInfo) -> NSItemProvider {
		let provider = NSItemProvider()
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.linesLayer.identifier, visibility: .ownProcess
		) { completion in
			completion(Data("resource:\(resource.id)".utf8), nil)
			return nil
		}
		return provider
	}
}

private struct ResourceRow: View {
	var resource: ResourceInfo
	var controller: CanvasController
	var isExpanded: Bool
	var toggle: () -> Void
	var showUser: (Int) -> Void

	@State private var isHovered = false
	@State private var showsPreview = false
	@State private var previewTask: Task<Void, Never>?

	private var isSelected: Bool { controller.selection?.order == resource.order }

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 8) {
				Button(action: toggle) {
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.bold))
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.foregroundStyle(.secondary)
						.frame(width: 12, height: 20)
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.opacity(resource.users.isEmpty && resource.contents.isEmpty ? 0 : 1)
				.help(isExpanded ? "Collapse" : "Show what uses it")
				ResourceSwatch(resource: resource)
				VStack(alignment: .leading, spacing: 0) {
					Text(resource.name).lineLimit(1).truncationMode(.middle)
					Text(resource.what)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				Spacer(minLength: 4)
				Text(
					resource.isUnused
						? String(localized: "unused")
						: String(localized: "\(resource.users.count)×")
				)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(
					resource.isUnused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
				)
				.padding(.horizontal, 5)
				.padding(.vertical, 1)
				.background(.quaternary.opacity(0.7), in: .capsule)
			}
			.padding(.horizontal, 6)
			.frame(height: 36)
			.background(
				isSelected
					? AnyShapeStyle(.tint.opacity(0.2))
					: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
				in: .rect(cornerRadius: 6, style: .continuous)
			)
			.opacity(resource.isUnused ? 0.75 : 1)
			.contentShape(.rect)
			.onTapGesture { controller.select(order: resource.order) }
			.onHover(perform: hover)
			.popover(isPresented: $showsPreview, arrowEdge: .trailing) {
				ImpactPreviewCard(
					order: resource.order, title: resource.name,
					symbol: InspectorView.symbol(for: resource.item.tag, isRoot: false),
					summary: resource.summary, controller: controller)
			}
			.contextMenu { menu }
			.help(resource.sentence)
			.accessibilityElement(children: .combine)
			.accessibilityHint(resource.summary)
			.accessibilityAddTraits(isSelected ? .isSelected : [])

			if isExpanded {
				if !resource.contents.isEmpty {
					caption("Made of")
					ForEach(resource.contents) { shape in
						userRow(shape) { controller.select(order: shape.order) }
					}
				}
				if !resource.users.isEmpty {
					caption("Used by")
					ForEach(resource.users) { user in
						userRow(user) { showUser(user.order) }
					}
				}
			}
		}
	}

	@ViewBuilder
	private var menu: some View {
		if let attribute = resource.kind.attribute, controller.hasElementSelection,
			let order = controller.selection?.order
		{
			Button("Apply to Selection", systemImage: "paintbrush") {
				controller.setReference(
					order: order, attribute: attribute, targetOrder: resource.order)
			}
			.disabled(!controller.isEditing)
		}
		if resource.kind == .clip || resource.kind == .mask, !resource.isUnused {
			Button("Edit on Canvas", systemImage: "pencil.and.outline") {
				controller.editOnCanvas(definition: resource.order)
			}
			.disabled(!controller.isEditing)
		}
		Divider()
		Button("Delete", systemImage: "trash", role: .destructive) {
			controller.delete(order: resource.order)
		}
		.disabled(!controller.isEditing)
	}

	private func caption(_ title: LocalizedStringKey) -> some View {
		Text(title)
			.font(.caption2.weight(.semibold))
			.foregroundStyle(.tertiary)
			.padding(.leading, 58)
			.padding(.top, 2)
	}

	private func userRow(_ item: OutlineItem, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 6) {
				LayerThumbnail(item: item, controller: controller, size: 18)
				Text(item.displayName).lineLimit(1)
				Spacer()
			}
			.font(.callout)
			.padding(.leading, 56)
			.frame(height: 24)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.help("Show \(item.displayName) in Layers")
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

/// The gradient itself, or the resource kind's icon in its colour.
struct ResourceSwatch: View {
	var resource: ResourceInfo
	var size: CGFloat = 26

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
		if resource.kind == .gradient, !resource.parts.isEmpty {
			let colours = resource.parts.map {
				CSSColor.parse(ResourceInfo.stopColour($0)) ?? .black
			}
			shape
				.fill(
					resource.item.tag == "radialGradient"
						? AnyShapeStyle(
							RadialGradient(
								colors: colours, center: .center, startRadius: 0,
								endRadius: size / 2))
						: AnyShapeStyle(
							LinearGradient(
								colors: colours, startPoint: .leading, endPoint: .trailing))
				)
				.frame(width: size, height: size)
				.overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
		} else {
			shape
				.fill(resource.kind.tint.opacity(0.18))
				.frame(width: size, height: size)
				.overlay {
					Image(systemName: InspectorView.symbol(for: resource.item.tag, isRoot: false))
						.font(.system(size: size * 0.42, weight: .semibold))
						.foregroundStyle(resource.kind.tint)
				}
		}
	}
}
