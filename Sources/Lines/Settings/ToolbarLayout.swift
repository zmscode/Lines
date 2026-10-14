import SwiftUI

/// The order of a toolbar's items and which are shown, stored as a string
/// ("layers,inspector,|1,code,!graph") so it fits in @AppStorage. Items
/// starting with "|" are separators between groups; "!" hides an item.
struct ToolbarLayout: Equatable {
	struct Item: Identifiable, Hashable {
		var id: String
		var isShown: Bool
		var isSeparator: Bool { id.hasPrefix("|") }
	}

	var items: [Item]

	/// Parses a stored layout, keeping any items added since it was saved.
	init(_ stored: String, defaults: [String]) {
		var items: [Item] = []
		for raw in stored.split(separator: ",").map(String.init) where !raw.isEmpty {
			let hidden = raw.hasPrefix("!")
			let id = hidden ? String(raw.dropFirst()) : raw
			guard defaults.contains(id), !items.contains(where: { $0.id == id }) else { continue }
			items.append(Item(id: id, isShown: !hidden))
		}
		for id in defaults where !items.contains(where: { $0.id == id }) {
			// New items go after the one they follow by default.
			let before = defaults.firstIndex(of: id).flatMap { i in i > 0 ? defaults[i - 1] : nil }
			let at =
				before.flatMap { b in items.firstIndex { $0.id == b } }.map { $0 + 1 }
				?? items.count
			items.insert(Item(id: id, isShown: true), at: at)
		}
		self.items = items
	}

	var stored: String {
		items.map { ($0.isShown ? "" : "!") + $0.id }.joined(separator: ",")
	}

	/// Shown items split into groups at separators (empty groups dropped).
	var groups: [[String]] {
		var groups: [[String]] = [[]]
		for item in items where item.isShown {
			if item.isSeparator {
				groups.append([])
			} else {
				groups[groups.count - 1].append(item.id)
			}
		}
		return groups.filter { !$0.isEmpty }
	}

	// MARK: The layouts

	static let windowKey = "toolbar.layout"
	static let windowDefaults = [
		"layers", "inspector", "|1", "code", "graph", "changes", "timeline",
	]

	static let paletteKey = "palette.layout"
	static let paletteDefaults: [String] =
		CanvasTool.groups.indices.prefix(2).map { "tool\($0)" } + ["|1"]
		+ CanvasTool.groups.indices.dropFirst(2).map { "tool\($0)" } + ["|2"]
		+ ["effects", "fills", "masking", "transform", "animate", "image", "|3", "background"]

	static let graphKey = "graph.palette.layout"
	static let graphDefaults = ["add", "cleanup", "|1", "flow", "tree", "|2", "tidy", "canvas"]

	/// Names and symbols for the settings list.
	static func describe(_ id: String) -> (title: String, symbol: String) {
		if id.hasPrefix("|") { return ("Separator", "minus") }
		if id.hasPrefix("tool"), let i = Int(id.dropFirst(4)), CanvasTool.groups.indices.contains(i)
		{
			let group = CanvasTool.groups[i]
			let title =
				group.count > 1 ? group.map(\.title).joined(separator: ", ") : group[0].title
			return (title, group[0].symbol)
		}
		switch id {
		case "layers": return ("Layers", "square.3.layers.3d")
		case "inspector": return ("Inspector", "slider.horizontal.3")
		case "code": return ("Code", "chevron.left.forwardslash.chevron.right")
		case "graph": return ("Graph", EditorLayout.graph.symbol)
		case "changes": return ("Changes", "plusminus")
		case "timeline": return ("Animations", "film.stack")
		case "effects": return ("Shadow & Blur", "shadow")
		case "fills": return ("Gradient & Pattern Fills", "circle.lefthalf.filled")
		case "masking": return ("Clip & Mask", "scissors")
		case "transform": return ("Rotate & Flip", "rotate.right")
		case "animate": return ("Animations", "sparkles")
		case "image": return ("Image", "photo.badge.plus")
		case "background": return ("Canvas Background", "checkerboard.rectangle")
		case "add": return ("Add Definition", "plus")
		case "flow": return ("Flow Layout", GraphLayoutMode.flow.symbol)
		case "tree": return ("Tree Layout", GraphLayoutMode.tree.symbol)
		case "tidy": return ("Tidy Up", "wand.and.rays")
		case "cleanup": return ("Remove Unused", "trash.slash")
		case "canvas": return ("Show on Canvas", "scope")
		default: return (id, "questionmark")
		}
	}
}

/// A settings list for one toolbar: drag to reorder, switch items on or off.
struct ToolbarLayoutEditor: View {
	var key: String
	var defaults: [String]

	@AppStorage private var stored: String

	init(key: String, defaults: [String]) {
		self.key = key
		self.defaults = defaults
		_stored = AppStorage(wrappedValue: defaults.joined(separator: ","), key)
	}

	private var layout: ToolbarLayout { ToolbarLayout(stored, defaults: defaults) }

	var body: some View {
		List {
			ForEach(layout.items) { item in
				let info = ToolbarLayout.describe(item.id)
				HStack(spacing: 10) {
					Image(systemName: "line.3.horizontal")
						.foregroundStyle(.tertiary)
						.help("Drag to reorder")
					if item.isSeparator {
						Rectangle().fill(.separator).frame(width: 20, height: 1)
						Text("Separator").foregroundStyle(.secondary)
					} else {
						Image(systemName: info.symbol).frame(width: 20)
						Text(info.title)
					}
					Spacer()
					Toggle(
						info.title,
						isOn: Binding(
							get: { item.isShown },
							set: { shown in update { $0.items[index(of: item)].isShown = shown } })
					)
					.labelsHidden()
					.toggleStyle(.switch)
					.controlSize(.mini)
				}
				.opacity(item.isShown ? 1 : 0.5)
			}
			.onMove { from, to in update { $0.items.move(fromOffsets: from, toOffset: to) } }
		}
		.listStyle(.bordered(alternatesRowBackgrounds: true))
		.frame(height: CGFloat(layout.items.count) * 28 + 8)
		.scrollDisabled(true)
		HStack {
			Spacer()
			Button("Restore Defaults") { stored = defaults.joined(separator: ",") }
				.disabled(
					layout == ToolbarLayout(defaults.joined(separator: ","), defaults: defaults))
		}
	}

	private func index(of item: ToolbarLayout.Item) -> Int {
		layout.items.firstIndex { $0.id == item.id } ?? 0
	}

	private func update(_ change: (inout ToolbarLayout) -> Void) {
		var copy = layout
		change(&copy)
		stored = copy.stored
	}
}
