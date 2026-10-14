import SwiftUI

/// A line diff between two versions of the source.
struct LineDiff {
	enum Kind { case same, added, removed, skipped }

	struct Row: Identifiable {
		var id: Int
		var kind: Kind
		var text: String
		/// Line numbers in the old and new text.
		var old: Int?
		var new: Int?
	}

	var rows: [Row] = []
	var added = 0
	var removed = 0
	var isEmpty: Bool { added == 0 && removed == 0 }

	/// Unchanged runs longer than this fold to `context` lines either side.
	static let context = 3

	init(from oldText: String, to newText: String) {
		let old = oldText.components(separatedBy: "\n")
		let new = newText.components(separatedBy: "\n")
		let difference = new.difference(from: old)
		var removedLines = Set<Int>()
		var insertedLines = Set<Int>()
		for change in difference {
			switch change {
			case .remove(let offset, _, _): removedLines.insert(offset)
			case .insert(let offset, _, _): insertedLines.insert(offset)
			}
		}
		removed = removedLines.count
		added = insertedLines.count

		var full: [Row] = []
		var i = 0
		var j = 0
		while i < old.count || j < new.count {
			if i < old.count, removedLines.contains(i) {
				full.append(Row(id: full.count, kind: .removed, text: old[i], old: i + 1))
				i += 1
			} else if j < new.count, insertedLines.contains(j) {
				full.append(Row(id: full.count, kind: .added, text: new[j], new: j + 1))
				j += 1
			} else {
				full.append(
					Row(
						id: full.count, kind: .same, text: j < new.count ? new[j] : "",
						old: i + 1, new: j + 1))
				i += 1
				j += 1
			}
		}

		// Keep a few lines around each change; fold the rest.
		let changed = full.indices.filter { full[$0].kind != .same }
		var keep = Set<Int>()
		for c in changed {
			for k in max(0, c - Self.context)...min(full.count - 1, c + Self.context) {
				keep.insert(k)
			}
		}
		var index = 0
		while index < full.count {
			if keep.contains(index) {
				var row = full[index]
				row.id = rows.count
				rows.append(row)
				index += 1
			} else {
				var end = index
				while end < full.count, !keep.contains(end) { end += 1 }
				rows.append(
					Row(id: rows.count, kind: .skipped, text: "\(end - index) unchanged lines"))
				index = end
			}
		}
	}
}

/// What's changed in the source: the history of versions as a git-style
/// graph you can scrub, branch and prune, and a line diff of the code.
struct ChangesPanel: View {
	var original: String
	var current: String
	var controller: CanvasController
	/// Puts a version's text back, as one undoable step named by the second argument.
	var restore: (String, String) -> Void
	var close: () -> Void

	enum Mode: String, CaseIterable {
		case timeline, code
		var title: String {
			self == .timeline ? String(localized: "Timeline") : String(localized: "Code")
		}
		var symbol: String {
			self == .timeline
				? "point.topleft.down.to.point.bottomright.curvepath"
				: "chevron.left.forwardslash.chevron.right"
		}
	}
	@State private var mode: Mode = .timeline
	/// The version shown on the canvas; the code diff compares it with now.
	@State private var selected: CanvasController.Snapshot.ID?
	/// Versions picked with ⌘- or ⇧-click, to delete.
	@State private var marked: Set<CanvasController.Snapshot.ID> = []

	private var history: [CanvasController.Snapshot] { controller.history }
	private var selectedSnapshot: CanvasController.Snapshot? {
		history.first { $0.id == selected }
	}

	var body: some View {
		FloatingPanel(title: "Changes", close: close) {
			VStack(alignment: .leading, spacing: 0) {
				// The same icon buttons as the app's other strips.
				HStack(spacing: 2) {
					ForEach(Mode.allCases, id: \.self) { m in
						Button(m.title, systemImage: m.symbol) { mode = m }
							.buttonStyle(.icon(size: 28, selected: mode == m))
							.help(m.title)
					}
					Spacer()
					if mode == .timeline && !marked.isEmpty {
						Button(
							"Delete \(marked.count) Version\(marked.count == 1 ? "" : "s")",
							role: .destructive
						) {
							deleteMarked()
						}
						.controlSize(.small)
						.help(
							"Remove these versions from the history (the drawing goes back if Now is one of them)"
						)
					}
				}
				.padding(.horizontal, 10)
				.padding(.bottom, 8)

				switch mode {
				case .timeline: timeline
				case .code: code
				}
			}
		}
		.onChange(of: mode) { _, new in
			if new == .code { controller.preview(version: nil) }
		}
		.onDisappear { controller.preview(version: nil) }
	}

	// MARK: Timeline

	private var timeline: some View {
		VStack(alignment: .leading, spacing: 0) {
			ScrollView {
				CommitGraph(
					history: history, headID: controller.headID,
					selected: selected ?? controller.headID, marked: marked,
					select: select, mark: mark
				)
				.padding(.horizontal, 8)
				.padding(.bottom, 8)
			}
			if let snapshot = selectedSnapshot, snapshot.id != controller.headID {
				Divider()
				HStack {
					Text("Showing “\(snapshot.title)” on the canvas")
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
					Spacer()
					Button("Compare") { mode = .code }
						.help("See this version's code against the current one")
					Button("Restore") {
						// Later versions stay, on their own branch.
						controller.checkOut(snapshot.id)
						restore(snapshot.text, "Restore Version")
						selected = nil
					}
					.buttonStyle(.borderedProminent)
					.help(
						"Make this version current again; newer versions stay on a branch (undoable)"
					)
				}
				.controlSize(.small)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
			}
		}
	}

	private func select(_ id: CanvasController.Snapshot.ID) {
		marked = []
		let isHead = id == controller.headID
		selected = isHead ? nil : id
		controller.preview(version: isHead ? nil : id)
	}

	/// ⌘-click toggles one; ⇧-click marks everything between it and the last.
	private func mark(_ id: CanvasController.Snapshot.ID, range: Bool) {
		guard id != history.first?.id else { return }  // "Opened" stays
		if range, let anchor = marked.first ?? selected,
			let a = history.firstIndex(where: { $0.id == anchor }),
			let b = history.firstIndex(where: { $0.id == id })
		{
			for s in history[min(a, b)...max(a, b)] where s.id != history.first?.id {
				marked.insert(s.id)
			}
		} else if marked.contains(id) {
			marked.remove(id)
		} else {
			marked.insert(id)
		}
	}

	private func deleteMarked() {
		let ids = marked
		marked = []
		selected = nil
		if let text = controller.deleteVersions(ids) {
			restore(text, "Delete Versions")
		}
	}

	// MARK: Code

	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage(CodeFont.key) private var fontName = ""

	@ViewBuilder
	private var code: some View {
		let base = selectedSnapshot?.text ?? original
		let diff = LineDiff(from: base, to: current)
		let theme = SyntaxTheme.pair(light: lightTheme, dark: darkTheme)
		HStack(spacing: 10) {
			Label("\(diff.added)", systemImage: "plus")
				.foregroundStyle(.green)
			Label("\(diff.removed)", systemImage: "minus")
				.foregroundStyle(.red)
			Text(selectedSnapshot.map { "lines since “\($0.title)”" } ?? "lines since opening")
				.foregroundStyle(.secondary)
				.lineLimit(1)
			Spacer()
			Button("Revert", systemImage: "arrow.uturn.backward") {
				if let id = selectedSnapshot?.id { controller.checkOut(id) }
				restore(base, selectedSnapshot == nil ? "Revert Changes" : "Restore Version")
				selected = nil
			}
			.controlSize(.small)
			.disabled(diff.isEmpty)
			.help("Put back the source as it was then (undoable)")
		}
		.font(.caption)
		.padding(.horizontal, 14)
		.padding(.bottom, 8)

		if diff.isEmpty {
			ContentUnavailableView(
				"No Changes", systemImage: "checkmark.circle",
				description: Text("The source matches that version."))
		} else {
			// In the code editor's theme and font.
			ScrollView([.vertical, .horizontal]) {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(diff.rows) { row in
						DiffRow(row: row, theme: theme, fontSize: fontSize, fontName: fontName)
					}
				}
				.padding(.vertical, 6)
			}
			.background(Color(nsColor: theme.background))
			.clipShape(.rect(cornerRadius: 10, style: .continuous))
			.padding([.horizontal, .bottom], 8)
		}
	}
}

private struct DiffRow: View {
	var row: LineDiff.Row
	var theme: SyntaxTheme
	var fontSize: Double
	var fontName: String

	var body: some View {
		let size = max(9, fontSize - 1)
		HStack(spacing: 0) {
			Text(row.old.map(String.init) ?? "")
				.frame(width: 34, alignment: .trailing)
				.foregroundStyle(Color(nsColor: theme.plain).opacity(0.4))
			Text(row.new.map(String.init) ?? "")
				.frame(width: 34, alignment: .trailing)
				.foregroundStyle(Color(nsColor: theme.plain).opacity(0.4))
			Text(marker)
				.frame(width: 18)
				.foregroundStyle(colour)
			Group {
				if row.kind == .skipped {
					Text(row.text).italic().foregroundStyle(
						Color(nsColor: theme.plain).opacity(0.5))
				} else {
					Text(highlighted(size: size))
				}
			}
			.fixedSize()
			.padding(.trailing, 12)
		}
		.font(Font(CodeFont.regular(size: size, name: fontName)))
		.padding(.vertical, 1)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(colour.opacity(row.kind == .added || row.kind == .removed ? 0.16 : 0))
		.textSelection(.enabled)
	}

	/// The line coloured like the code editor colours it.
	private func highlighted(size: Double) -> AttributedString {
		let storage = NSTextStorage(string: row.text.isEmpty ? " " : row.text)
		Highlighter.highlight(storage, fontSize: size, theme: theme)
		return (try? AttributedString(storage, including: \.appKit)) ?? AttributedString(row.text)
	}

	private var marker: String {
		switch row.kind {
		case .added: "+"
		case .removed: "−"
		case .skipped: "⋯"
		case .same: ""
		}
	}

	private var colour: Color {
		switch row.kind {
		case .added: .green
		case .removed: .red
		default: .secondary
		}
	}
}

/// The history as `git log --graph`: newest at the top, the current branch
/// on the main line and versions left behind by a restore on a side line.
/// Click a version to see it on the canvas, ⌘- or ⇧-click to pick several,
/// or drag along the lines to scrub.
private struct CommitGraph: View {
	var history: [CanvasController.Snapshot]
	var headID: CanvasController.Snapshot.ID?
	var selected: CanvasController.Snapshot.ID?
	var marked: Set<CanvasController.Snapshot.ID>
	var select: (CanvasController.Snapshot.ID) -> Void
	var mark: (CanvasController.Snapshot.ID, Bool) -> Void

	static let rowHeight: CGFloat = 50
	static let laneWidth: CGFloat = 14
	static let railX: CGFloat = 14

	/// Newest first.
	private var rows: [CanvasController.Snapshot] { history.reversed() }

	/// The head's ancestry is lane 0; each branch that left it gets the next lane.
	private var lanes: [UUID: Int] {
		let byID = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
		var lanes: [UUID: Int] = [:]
		var id = headID
		while let current = id {
			lanes[current] = 0
			id = byID[current]?.parentID
		}
		var nextLane = 1
		// Newest first, so a branch's tip claims its lane and its ancestors follow.
		for snapshot in rows where lanes[snapshot.id] == nil {
			var chain: [UUID] = []
			var current: UUID? = snapshot.id
			while let c = current, lanes[c] == nil {
				chain.append(c)
				current = byID[c]?.parentID
			}
			for c in chain { lanes[c] = nextLane }
			nextLane += 1
		}
		return lanes
	}

	var body: some View {
		let lanes = lanes
		let rowIndex = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
		let laneCount = (lanes.values.max() ?? 0) + 1
		let railWidth = Self.railX * 2 + CGFloat(laneCount - 1) * Self.laneWidth
		VStack(spacing: 0) {
			ForEach(Array(rows.enumerated()), id: \.element.id) { index, snapshot in
				CommitRow(
					snapshot: snapshot, lane: lanes[snapshot.id] ?? 0, railWidth: railWidth,
					isNow: snapshot.id == headID, isSelected: snapshot.id == selected,
					isMarked: marked.contains(snapshot.id)
				) { modifiers in
					if modifiers.contains(.command) {
						mark(snapshot.id, false)
					} else if modifiers.contains(.shift) {
						mark(snapshot.id, true)
					} else {
						select(snapshot.id)
					}
				}
				.frame(height: Self.rowHeight)
			}
		}
		.background(alignment: .topLeading) {
			// Each version joined to the one it came from.
			Canvas { context, _ in
				for snapshot in rows {
					guard let parent = snapshot.parentID, let from = rowIndex[snapshot.id],
						let to = rowIndex[parent]
					else { continue }
					let x1 = Self.railX + CGFloat(lanes[snapshot.id] ?? 0) * Self.laneWidth
					let x2 = Self.railX + CGFloat(lanes[parent] ?? 0) * Self.laneWidth
					let y1 = (CGFloat(from) + 0.5) * Self.rowHeight
					let y2 = (CGFloat(to) + 0.5) * Self.rowHeight
					var path = Path()
					path.move(to: CGPoint(x: x1, y: y1))
					if x1 == x2 {
						path.addLine(to: CGPoint(x: x2, y: y2))
					} else {
						// A branch curves back to where it left.
						path.addLine(to: CGPoint(x: x1, y: y2 - Self.rowHeight * 0.6))
						path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: x1, y: y2))
					}
					let onMain = (lanes[snapshot.id] ?? 0) == 0
					context.stroke(
						path,
						with: onMain
							? .color(.accentColor.opacity(0.6)) : .color(.secondary.opacity(0.45)),
						style: StrokeStyle(
							lineWidth: 2.5, lineCap: .round, dash: onMain ? [] : [4, 3]))
				}
			}
			.frame(width: railWidth, height: CGFloat(rows.count) * Self.rowHeight)
		}
		.overlay(alignment: .leading) {
			// Dragging along the lines scrubs.
			Color.clear
				.frame(width: railWidth)
				.contentShape(.rect)
				.gesture(
					DragGesture(minimumDistance: 2)
						.onChanged { value in
							let row = min(
								max(Int(value.location.y / Self.rowHeight), 0), rows.count - 1)
							if rows[row].id != selected { select(rows[row].id) }
						}
				)
				.help("Drag along the line to scrub through the versions")
		}
	}
}

/// One version: its dot on its line, its name, when, and a `git --stat`
/// style bar of lines added and removed.
private struct CommitRow: View {
	var snapshot: CanvasController.Snapshot
	var lane: Int
	var railWidth: CGFloat
	var isNow: Bool
	var isSelected: Bool
	var isMarked: Bool
	var action: (NSEvent.ModifierFlags) -> Void

	@State private var isHovered = false

	var body: some View {
		HStack(spacing: 8) {
			dot
				.padding(.leading, CommitGraph.railX - 6 + CGFloat(lane) * CommitGraph.laneWidth)
				.frame(width: railWidth, alignment: .leading)
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(snapshot.title)
						.fontWeight(isSelected ? .semibold : .regular)
						.lineLimit(1)
					if isNow {
						Text("Now")
							.font(.caption2.weight(.semibold))
							.padding(.horizontal, 5)
							.padding(.vertical, 1)
							.background(.tint.opacity(0.18), in: .capsule)
					}
				}
				Text(snapshot.date, format: .relative(presentation: .named))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.opacity(lane > 0 ? 0.7 : 1)
			Spacer(minLength: 6)
			if snapshot.added + snapshot.removed > 0 { stat }
		}
		.padding(.trailing, 8)
		.frame(maxHeight: .infinity)
		.background(
			isMarked
				? AnyShapeStyle(.red.opacity(0.14))
				: isSelected
					? AnyShapeStyle(.tint.opacity(0.12))
					: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 8, style: .continuous)
		)
		.contentShape(.rect)
		.onTapGesture { action(NSEvent.modifierFlags) }
		.onHover { isHovered = $0 }
		.help(
			isNow
				? "The current version"
				: "Show this version on the canvas (⌘-click or ⇧-click to pick several)"
		)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityLabel(
			"\(snapshot.title), \(snapshot.added) lines added, \(snapshot.removed) removed"
		)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private var dot: some View {
		ZStack {
			Circle()
				.fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.background))
				.frame(width: 12, height: 12)
			Circle()
				.strokeBorder(
					isMarked
						? AnyShapeStyle(.red)
						: isSelected || isNow ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary),
					lineWidth: 2
				)
				.frame(width: 12, height: 12)
			if isNow && !isSelected {
				Circle().strokeBorder(.tint.opacity(0.35), lineWidth: 2).frame(
					width: 20, height: 20)
			}
		}
		.frame(width: 12, height: 12)
	}

	/// "+12 −3" and five blocks split between them, like `git diff --stat`.
	private var stat: some View {
		let total = snapshot.added + snapshot.removed
		let green = total == 0 ? 0 : Int((Double(snapshot.added) / Double(total) * 5).rounded())
		return VStack(alignment: .trailing, spacing: 3) {
			HStack(spacing: 4) {
				if snapshot.added > 0 { Text("+\(snapshot.added)").foregroundStyle(.green) }
				if snapshot.removed > 0 { Text("−\(snapshot.removed)").foregroundStyle(.red) }
			}
			.font(.caption.monospacedDigit())
			HStack(spacing: 1.5) {
				ForEach(0..<5, id: \.self) { i in
					RoundedRectangle(cornerRadius: 1)
						.fill(i < green ? Color.green : Color.red)
						.frame(width: 5, height: 5)
				}
			}
		}
	}
}
