import SwiftUI

/// The order of a toolbar's items and which are shown, stored as a string
/// ("layers,inspector,|1,code,!changes") so it fits in @AppStorage. Items
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
			// Any number of separators ("|…"); other items must be known.
			guard defaults.contains(id) || id.hasPrefix("|"),
				!items.contains(where: { $0.id == id })
			else { continue }
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

	/// Shown items in order, and the hidden ones (for the editor's tray).
	var shown: [String] { items.filter(\.isShown).map(\.id) }
	var hidden: [String] { items.filter { !$0.isShown && !$0.isSeparator }.map(\.id) }

	/// A separator id not used yet.
	var newSeparatorID: String {
		var n = 1
		while items.contains(where: { $0.id == "|\(n)" }) { n += 1 }
		return "|\(n)"
	}

	/// Puts `id` among the shown items at `index` (moving or showing it).
	mutating func show(_ id: String, at index: Int) {
		items.removeAll { $0.id == id }
		var shown = items.filter(\.isShown)
		let rest = items.filter { !$0.isShown }
		shown.insert(Item(id: id, isShown: true), at: min(max(0, index), shown.count))
		items = shown + rest
	}

	/// Takes `id` off the toolbar: separators go, items return to the tray.
	mutating func hide(_ id: String) {
		guard let i = items.firstIndex(where: { $0.id == id }) else { return }
		if items[i].isSeparator {
			items.remove(at: i)
		} else {
			items[i].isShown = false
		}
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
		"layers", "inspector", "|1", "code", "changes", "timeline",
	]

	static let paletteKey = "palette.layout"
	static let paletteDefaults: [String] =
		CanvasTool.groups.indices.prefix(2).map { "tool\($0)" } + ["|1"]
		+ CanvasTool.groups.indices.dropFirst(2).map { "tool\($0)" } + ["|2"]
		+ ["effects", "fills", "masking", "transform", "animate", "image", "|3", "background"]

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
		case "changes": return ("Changes", "plusminus")
		case "timeline": return ("Animations", "film.stack")
		case "effects": return ("Shadow & Blur", "shadow")
		case "fills": return ("Gradient & Pattern Fills", "circle.lefthalf.filled")
		case "masking": return ("Clip & Mask", "scissors")
		case "transform": return ("Rotate & Flip", "rotate.right")
		case "animate": return ("Animations", "sparkles")
		case "image": return ("Image", "photo.badge.plus")
		case "background": return ("Canvas Background", "checkerboard.rectangle")
		default: return (id, "questionmark")
		}
	}
}

/// Customises one toolbar like Finder's Customize Toolbar: the toolbar's
/// real icons in a strip you drag to reorder, a tray of items to drag in,
/// and dragging an icon out of the strip (onto the tray) removes it.
struct ToolbarLayoutEditor: View {
	var key: String
	var defaults: [String]

	@AppStorage private var stored: String
	@State private var dropIndex: Int?
	@State private var trayTargeted = false

	init(key: String, defaults: [String]) {
		self.key = key
		self.defaults = defaults
		_stored = AppStorage(wrappedValue: defaults.joined(separator: ","), key)
	}

	private var layout: ToolbarLayout { ToolbarLayout(stored, defaults: defaults) }

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			strip
			Text("Drag items into the toolbar, or out of it to remove them.")
				.font(.caption)
				.foregroundStyle(.secondary)
			tray
			HStack {
				Button("Add Separator", systemImage: "minus") {
					update { $0.show($0.newSeparatorID, at: $0.shown.count) }
				}
				Spacer()
				Button("Restore Defaults") { stored = defaults.joined(separator: ",") }
					.disabled(
						layout == ToolbarLayout(defaults.joined(separator: ","), defaults: defaults)
					)
			}
			.controlSize(.small)
		}
		.padding(.vertical, 4)
	}

	// MARK: The toolbar

	/// The shown items as they'll look, in a glass strip.
	private var strip: some View {
		let shown = layout.shown
		return ScrollView(.horizontal) {
			HStack(spacing: 2) {
				ForEach(Array(shown.enumerated()), id: \.element) { index, id in
					if dropIndex == index { insertionMark }
					StripItem(id: id)
						.draggable("strip:\(id)") { StripItem(id: id).opacity(0.8) }
						// The same changes without dragging (and for VoiceOver).
						.contextMenu {
							Button("Move Left", systemImage: "arrow.left") {
								update { $0.show(id, at: index - 1) }
							}
							.disabled(index == 0)
							Button("Move Right", systemImage: "arrow.right") {
								update { $0.show(id, at: index + 1) }
							}
							.disabled(index == shown.count - 1)
							Divider()
							Button("Remove", systemImage: "minus.circle") { update { $0.hide(id) } }
						}
						.accessibilityAction(named: "Move Left") {
							update { $0.show(id, at: max(0, index - 1)) }
						}
						.accessibilityAction(named: "Move Right") {
							update { $0.show(id, at: index + 1) }
						}
						.accessibilityAction(named: "Remove") { update { $0.hide(id) } }
						.dropDestination(for: String.self) { payloads, location in
							// Before or after this item, by which half it's dropped on.
							let after =
								location.x
								> (ToolbarLayout.Item(id: id, isShown: true).isSeparator ? 6 : 17)
							return accept(payloads, at: index + (after ? 1 : 0))
						} isTargeted: { targeted in
							if targeted {
								dropIndex = index
							} else if dropIndex == index {
								dropIndex = nil
							}
						}
				}
				if dropIndex == shown.count { insertionMark }
				// The end of the strip takes drops too.
				Color.clear
					.frame(minWidth: 40, maxWidth: .infinity, minHeight: 34)
					.contentShape(.rect)
					.dropDestination(for: String.self) { payloads, _ in
						accept(payloads, at: shown.count)
					} isTargeted: { targeted in
						dropIndex =
							targeted ? shown.count : (dropIndex == shown.count ? nil : dropIndex)
					}
			}
			.padding(6)
		}
		.scrollIndicators(.never)
		.background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(dropIndex != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
		}
		.animation(.snappy(duration: 0.15), value: dropIndex)
	}

	private var insertionMark: some View {
		Capsule().fill(.tint).frame(width: 3, height: 26)
	}

	// MARK: The tray

	/// Items not on the toolbar, plus a separator, to drag in.
	private var tray: some View {
		let hidden = layout.hidden
		return HStack(alignment: .top, spacing: 12) {
			ForEach(["|"] + hidden, id: \.self) { id in
				VStack(spacing: 4) {
					StripItem(id: id == "|" ? "|0" : id)
					Text(id == "|" ? "Separator" : ToolbarLayout.describe(id).title)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.frame(width: 64)
						.lineLimit(2)
				}
				.draggable("tray:\(id)") { StripItem(id: id == "|" ? "|0" : id) }
				.help("Drag into the toolbar above")
			}
			if hidden.isEmpty {
				Text("Everything else is on the toolbar.")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxHeight: .infinity)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
		.background(
			trayTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 12, style: .continuous)
		)
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
				.foregroundStyle(trayTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
		}
		// Dropping a toolbar item here takes it off the toolbar.
		.dropDestination(for: String.self) { payloads, _ in
			var changed = false
			for payload in payloads where payload.hasPrefix("strip:") {
				let id = String(payload.dropFirst(6))
				update { $0.hide(id) }
				changed = true
			}
			return changed
		} isTargeted: {
			trayTargeted = $0
		}
	}

	// MARK: Changes

	private func accept(_ payloads: [String], at index: Int) -> Bool {
		defer { dropIndex = nil }
		guard let payload = payloads.first else { return false }
		if payload.hasPrefix("strip:") {
			let id = String(payload.dropFirst(6))
			// Moving right past itself shifts the target left by one.
			let from = layout.shown.firstIndex(of: id) ?? index
			update { $0.show(id, at: from < index ? index - 1 : index) }
			return true
		}
		if payload.hasPrefix("tray:") {
			let id = String(payload.dropFirst(5))
			update { $0.show(id == "|" ? $0.newSeparatorID : id, at: index) }
			return true
		}
		return false
	}

	private func update(_ change: (inout ToolbarLayout) -> Void) {
		var copy = layout
		change(&copy)
		stored = copy.stored
	}
}

/// One toolbar item as it looks on the toolbar: an icon button, or a separator line.
private struct StripItem: View {
	var id: String

	var body: some View {
		if id.hasPrefix("|") {
			Rectangle()
				.fill(.separator)
				.frame(width: 1.5, height: 22)
				.padding(.horizontal, 5)
				.frame(height: 34)
				.contentShape(.rect)
				.help("Separator")
		} else {
			let info = ToolbarLayout.describe(id)
			Image(systemName: info.symbol)
				.font(.system(size: 15, weight: .medium))
				.frame(width: 34, height: 34)
				.background(
					.background.opacity(0.6), in: .rect(cornerRadius: 8, style: .continuous)
				)
				.contentShape(.rect)
				.help(info.title)
				.accessibilityLabel(info.title)
		}
	}
}
