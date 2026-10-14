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

/// What's changed in the source since the window opened the file, as a
/// floating panel; Revert puts the original back (undoably).
struct ChangesPanel: View {
	var original: String
	var current: String
	var revert: () -> Void
	var close: () -> Void

	var body: some View {
		let diff = LineDiff(from: original, to: current)
		FloatingPanel(title: "Changes", close: close) {
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 10) {
					Label("\(diff.added)", systemImage: "plus")
						.foregroundStyle(.green)
					Label("\(diff.removed)", systemImage: "minus")
						.foregroundStyle(.red)
					Text("lines since opening")
						.foregroundStyle(.secondary)
					Spacer()
					Button("Revert All", systemImage: "arrow.uturn.backward", action: revert)
						.controlSize(.small)
						.disabled(diff.isEmpty)
						.help("Put back the source as it was when opened (undoable)")
				}
				.font(.caption)
				.padding(.horizontal, 14)
				.padding(.bottom, 8)

				if diff.isEmpty {
					ContentUnavailableView(
						"No Changes", systemImage: "checkmark.circle",
						description: Text("The source matches the file as opened."))
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
