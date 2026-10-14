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

/// What's changed in the source: a git-style timeline of versions you can
/// scrub through on the canvas, and a line diff of the code.
struct ChangesPanel: View {
	var original: String
	var current: String
	var controller: CanvasController
	/// Puts a version's text back, as one undoable step named by the second argument.
	var restore: (String, String) -> Void
	var close: () -> Void

	enum Mode: String, CaseIterable {
		case timeline = "Timeline"
		case code = "Code"
	}
	@State private var mode: Mode = .timeline
	/// The version picked in the timeline; the code diff compares it with now.
	@State private var selected: CanvasController.Snapshot.ID?

	private var history: [CanvasController.Snapshot] { controller.history }
	private var selectedSnapshot: CanvasController.Snapshot? {
		history.first { $0.id == selected }
	}

	var body: some View {
		FloatingPanel(title: "Changes", close: close) {
			VStack(alignment: .leading, spacing: 0) {
				Picker("View", selection: $mode) {
					ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.padding(.horizontal, 14)
				.padding(.bottom, 10)

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
			if history.count > 1 {
				scrubber
					.padding(.horizontal, 14)
					.padding(.bottom, 10)
			}
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(Array(history.enumerated().reversed()), id: \.element.id) {
						index, snapshot in
						VersionRow(
							snapshot: snapshot, isLatest: index == history.count - 1,
							isFirst: index == 0,
							isSelected: snapshot.id == (selected ?? history.last?.id)
						) {
							select(snapshot.id)
						}
					}
				}
				.padding(.horizontal, 8)
				.padding(.bottom, 8)
			}
			if let snapshot = selectedSnapshot, snapshot.id != history.last?.id {
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
						restore(snapshot.text, "Restore Version")
						selected = nil
					}
					.buttonStyle(.borderedProminent)
					.help("Make this version current again (undoable)")
				}
				.controlSize(.small)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
			}
		}
	}

	/// Drag along the history to watch the drawing change on the canvas.
	private var scrubber: some View {
		let count = history.count
		let index = history.firstIndex { $0.id == selected } ?? (count - 1)
		return VStack(alignment: .leading, spacing: 4) {
			Slider(
				value: Binding(
					get: { Double(index) },
					set: { new in
						let i = min(max(Int(new.rounded()), 0), count - 1)
						select(history[i].id)
					}),
				in: 0...Double(max(1, count - 1)), step: 1
			) {
				Text("Version")
			} minimumValueLabel: {
				Text("Opened").font(.caption).foregroundStyle(.secondary)
			} maximumValueLabel: {
				Text("Now").font(.caption).foregroundStyle(.secondary)
			}
			.labelsHidden()
			.help("Drag through the history; the canvas shows each version")
			Text(
				index == count - 1
					? "Current version"
					: "Version \(index + 1) of \(count) · \(history[index].title)"
			)
			.font(.caption)
			.foregroundStyle(.secondary)
		}
	}

	private func select(_ id: CanvasController.Snapshot.ID) {
		let isLatest = id == history.last?.id
		selected = isLatest ? nil : id
		controller.preview(version: isLatest ? nil : id)
	}

	// MARK: Code

	@ViewBuilder
	private var code: some View {
		let base = selectedSnapshot?.text ?? original
		let diff = LineDiff(from: base, to: current)
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
			ScrollView([.vertical, .horizontal]) {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(diff.rows) { row in DiffRow(row: row) }
				}
				.padding(.bottom, 8)
			}
			.font(.system(size: 11, design: .monospaced))
		}
	}
}

/// One version in the timeline: a dot on a line, like `git log --graph`.
private struct VersionRow: View {
	var snapshot: CanvasController.Snapshot
	var isLatest: Bool
	var isFirst: Bool
	var isSelected: Bool
	var select: () -> Void

	@State private var isHovered = false

	var body: some View {
		Button(action: select) {
			HStack(alignment: .center, spacing: 10) {
				ZStack {
					// The line through the versions, open at the ends.
					VStack(spacing: 0) {
						Rectangle().fill(isLatest ? .clear : Color.secondary.opacity(0.35))
						Rectangle().fill(isFirst ? .clear : Color.secondary.opacity(0.35))
					}
					.frame(width: 2)
					Circle()
						.fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.background))
						.overlay {
							Circle().strokeBorder(
								isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary),
								lineWidth: 2)
						}
						.frame(width: 11, height: 11)
				}
				.frame(width: 14)
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(snapshot.title).fontWeight(isSelected ? .semibold : .regular)
						if isLatest {
							Text("Now")
								.font(.caption2.weight(.semibold))
								.padding(.horizontal, 5)
								.padding(.vertical, 1)
								.background(.tint.opacity(0.18), in: .capsule)
						}
					}
					HStack(spacing: 6) {
						Text(snapshot.date, format: .relative(presentation: .named))
						if snapshot.added > 0 { Text("+\(snapshot.added)").foregroundStyle(.green) }
						if snapshot.removed > 0 {
							Text("−\(snapshot.removed)").foregroundStyle(.red)
						}
					}
					.font(.caption)
					.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 6)
			.frame(height: 44)
			.background(
				isSelected
					? AnyShapeStyle(.tint.opacity(0.12))
					: isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
				in: .rect(cornerRadius: 8, style: .continuous)
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		.help(isLatest ? "The current version" : "Show this version on the canvas")
	}
}

private struct DiffRow: View {
	var row: LineDiff.Row

	var body: some View {
		HStack(spacing: 0) {
			Text(row.old.map(String.init) ?? "")
				.frame(width: 34, alignment: .trailing)
				.foregroundStyle(.tertiary)
			Text(row.new.map(String.init) ?? "")
				.frame(width: 34, alignment: .trailing)
				.foregroundStyle(.tertiary)
			Text(marker)
				.frame(width: 18)
				.foregroundStyle(colour)
			Text(row.text.isEmpty ? " " : row.text)
				.foregroundStyle(
					row.kind == .skipped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
				)
				.italic(row.kind == .skipped)
				.fixedSize()
				.padding(.trailing, 12)
		}
		.padding(.vertical, 1)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(colour.opacity(row.kind == .added || row.kind == .removed ? 0.14 : 0))
		.textSelection(.enabled)
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
