import AppKit
import SwiftUI

struct LayerTreeRow: View {
	var node: LayerNode
	var controller: CanvasController
	@Binding var expanded: Set<String>
	@Binding var renaming: String?

	var body: some View {
		if node.children.isEmpty {
			row
		} else {
			DisclosureGroup(
				isExpanded: Binding(
					get: { expanded.contains(node.id) },
					set: { if $0 { expanded.insert(node.id) } else { expanded.remove(node.id) } }
				)
			) {
				ForEach(node.children) { child in
					LayerTreeRow(
						node: child, controller: controller, expanded: $expanded,
						renaming: $renaming)
				}
				.reorderable(collectionID: node.id)
			} label: {
				row
			}
		}
	}

	private var row: some View {
		LayerRow(
			item: node.item, isGroup: !node.children.isEmpty, controller: controller,
			renaming: $renaming
		)
		.tag(node.item.order)
	}
}

private struct LayerRow: View {
	var item: OutlineItem
	var isGroup: Bool
	var controller: CanvasController
	@Binding var renaming: String?

	@State private var isHovered = false
	@State private var draft = ""
	@FocusState private var nameFocused: Bool

	private var isRenaming: Bool { renaming == item.id }

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: InspectorView.symbol(for: item.tag, isRoot: false))
				.foregroundStyle(swatch)
				.frame(width: 18)

			if isRenaming {
				TextField("Name", text: $draft)
					.textFieldStyle(.plain)
					.focused($nameFocused)
					.onSubmit(finishRename)
					.onExitCommand { renaming = nil }
					.onChange(of: nameFocused) { _, focused in if !focused { finishRename() } }
					.onAppear {
						draft = item.elementID ?? ""
						nameFocused = true
					}
			} else {
				Text(item.displayName)
					.lineLimit(1)
					.truncationMode(.middle)
					.foregroundStyle(item.isHidden ? .secondary : .primary)
					.onTapGesture(count: 2) { renaming = item.id }
			}

			Spacer(minLength: 4)

			if !item.references.isEmpty {
				Image(systemName: "link")
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.help(
						"Uses "
							+ item.references.map { "#\($0.targetID) (\($0.attribute))" }.joined(
								separator: ", "))
			}

			Button(
				item.isHidden ? "Show" : "Hide", systemImage: item.isHidden ? "eye.slash" : "eye"
			) {
				controller.toggleHidden(order: item.order)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.borderless)
			.foregroundStyle(.secondary)
			.opacity(isHovered || item.isHidden ? 1 : 0)
			.help(item.isHidden ? "Show Element" : "Hide Element")
		}
		.contentShape(.rect)
		.onHover { hovering in
			isHovered = hovering
			controller.hover(order: hovering ? item.order : nil)
		}
		.contextMenu { menu }
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(item.displayName), \(InspectorView.elementName(for: item.tag))")
		.accessibilityValue(item.isHidden ? "Hidden" : "")
		.accessibilityAction(named: item.isHidden ? "Show" : "Hide") {
			controller.toggleHidden(order: item.order)
		}
		.accessibilityAction(named: "Rename") { renaming = item.id }
	}

	@ViewBuilder
	private var menu: some View {
		Button("Rename", systemImage: "pencil") { renaming = item.id }
		Button(item.isHidden ? "Show" : "Hide", systemImage: item.isHidden ? "eye" : "eye.slash") {
			controller.toggleHidden(order: item.order)
		}
		Divider()
		Button("Duplicate", systemImage: "plus.square.on.square") {
			controller.select(order: item.order)
			controller.duplicateSelection()
		}
		Button("Group", systemImage: "square.on.square.dashed") {
			controller.select(order: item.order)
			controller.groupSelection()
		}
		if isGroup || item.tag == "g" {
			Button("Ungroup") {
				controller.select(order: item.order)
				controller.ungroupSelection()
			}
		}
		Divider()
		Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") {
			controller.select(order: item.order)
			controller.reorder(.front)
		}
		Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
			controller.select(order: item.order)
			controller.reorder(.forward)
		}
		Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
			controller.select(order: item.order)
			controller.reorder(.backward)
		}
		Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") {
			controller.select(order: item.order)
			controller.reorder(.back)
		}
		Divider()
		Button("Copy", systemImage: "doc.on.doc") {
			Task {
				guard let markup = await controller.markup(order: item.order) else { return }
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(markup, forType: .string)
			}
		}
		Button("Delete", systemImage: "trash", role: .destructive) {
			controller.delete(order: item.order)
		}
	}

	private func finishRename() {
		guard isRenaming else { return }
		if draft != (item.elementID ?? "") { controller.rename(order: item.order, to: draft) }
		renaming = nil
	}

	/// Tints the icon with the element's fill when it's a plain colour.
	private var swatch: AnyShapeStyle {
		if let fill = item.fill, fill != "none", let colour = CSSColor.parse(fill) {
			return AnyShapeStyle(colour)
		}
		return AnyShapeStyle(.secondary)
	}
}
