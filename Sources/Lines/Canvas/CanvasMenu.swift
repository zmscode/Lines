import AppKit

/// The canvas's right-click menu. Items act on the selection when chosen, by
/// which time the page has selected what was clicked.
@MainActor
enum CanvasMenu {
	static func items(for controller: CanvasController, editing: NSResponder) -> [NSMenuItem] {
		guard controller.isEditing else {
			return [
				item("Unlock to Edit", "lock.open") { controller.isEditing = true },
				item("Show Timeline", "film.stack") { controller.showsTimeline = true },
			]
		}
		var items: [NSMenuItem] = [
			standard("Cut", #selector(CanvasWebView.cut(_:)), "x", editing),
			standard("Copy", #selector(CanvasWebView.copy(_:)), "c", editing),
			standard("Paste", #selector(CanvasWebView.paste(_:)), "v", editing),
			item("Duplicate", "plus.square.on.square") { controller.duplicateSelection() },
			item("Delete", "trash") { controller.deleteSelection() },
			.separator(),
			submenu(
				"Arrange", "square.3.layers.3d",
				[
					item("Bring to Front", "square.3.layers.3d.top.filled") {
						controller.reorder(.front)
					},
					item("Bring Forward", "square.2.layers.3d.top.filled") {
						controller.reorder(.forward)
					},
					item("Send Backward", "square.2.layers.3d.bottom.filled") {
						controller.reorder(.backward)
					},
					item("Send to Back", "square.3.layers.3d.bottom.filled") {
						controller.reorder(.back)
					},
				]),
			item("Group", "square.on.square.dashed") { controller.groupSelection() },
			item("Ungroup", "square.on.square.squareshape.controlhandles") {
				controller.ungroupSelection()
			},
			.separator(),
		]
		items.append(
			submenu(
				"Add Effect", "camera.filters",
				[CanvasController.Definition.blur, .shadow, .clipPath, .mask].map { kind in
					item(kind.title, kind.symbol) {
						guard let order = elementOrder(controller) else { return }
						controller.addDefinition(kind, applyingTo: order)
					}
				} + [
					.separator(),
					item("Linear Gradient Fill", "circle.lefthalf.filled") {
						guard let order = elementOrder(controller) else { return }
						controller.addDefinition(.linearGradient, applyingTo: order)
					},
					item("Radial Gradient Fill", "circle.circle") {
						guard let order = elementOrder(controller) else { return }
						controller.addDefinition(.radialGradient, applyingTo: order)
					},
				]))
		items.append(
			submenu(
				"Add Animation", "film.stack",
				AnimationPreset.allCases.map { preset in
					item(preset.title, preset.symbol) {
						guard let order = elementOrder(controller) else { return }
						controller.addAnimation(preset, toOrder: order)
					}
				}))
		items += [
			.separator(),
			item("Hide", "eye.slash") {
				if let order = elementOrder(controller) { controller.toggleHidden(order: order) }
			},
			item("Select Enclosing Group", "arrow.up.square") { controller.selectParent() },
			item("Show in Inspector", "slider.horizontal.3") { controller.showsInspector = true },
			item("Show Timeline", "film.stack") { controller.showsTimeline = true },
		]
		return items
	}

	/// The selected element, if it's one (not the document).
	private static func elementOrder(_ controller: CanvasController) -> Int? {
		guard let s = controller.selection, !s.isRoot else { return nil }
		return s.order
	}

	private static func standard(
		_ title: String, _ action: Selector, _ key: String, _ target: NSResponder
	) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
		item.target = target
		return item
	}

	private static func item(_ title: String, _ symbol: String, action: @escaping () -> Void)
		-> NSMenuItem
	{
		let item = ClosureMenuItem(title: title, action: action)
		item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
		return item
	}

	private static func submenu(_ title: String, _ symbol: String, _ children: [NSMenuItem])
		-> NSMenuItem
	{
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
		let menu = NSMenu(title: title)
		for child in children { menu.addItem(child) }
		item.submenu = menu
		return item
	}
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
	private let handler: () -> Void

	init(title: String, action: @escaping () -> Void) {
		handler = action
		super.init(title: title, action: #selector(run), keyEquivalent: "")
		target = self
	}

	required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

	@objc private func run() { handler() }
}
