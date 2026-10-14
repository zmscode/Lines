import SwiftUI

/// A text field that commits when you press Return or move focus away,
/// mirroring how inspector fields behave in Keynote and Pages.
struct AttributeField: View {
	var title: String
	var value: String
	var prompt: String? = nil
	var axis: Axis = .horizontal
	var monospacedTitle = false
	var commit: (String) -> Void

	@State private var draft = ""
	@FocusState private var focused: Bool

	var body: some View {
		TextField(text: $draft, prompt: prompt.map { Text($0) }, axis: axis) {
			Text(title).font(monospacedTitle ? .body.monospaced() : .body)
		}
		.focused($focused)
		.onAppear { draft = value }
		.onChange(of: value) { _, new in if !focused { draft = new } }
		.onChange(of: focused) { _, isFocused in if !isFocused { send() } }
		.onSubmit(send)
	}

	private func send() {
		if draft != value { commit(draft) }
	}
}

struct NewAttributeRow: View {
	var controller: CanvasController
	@State private var name = ""
	@State private var value = ""
	@FocusState private var nameFocused: Bool

	var body: some View {
		HStack {
			TextField("Name", text: $name, prompt: Text("New attribute"))
				.labelsHidden()
				.focused($nameFocused)
				.font(.body.monospaced())
			TextField("Value", text: $value, prompt: Text("Value"))
				.labelsHidden()
				.onSubmit(add)
			Button("Add Attribute", systemImage: "plus.circle.fill", action: add)
				.labelStyle(.iconOnly)
				.buttonStyle(.borderless)
				.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
		}
	}

	private func add() {
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return }
		controller.setAttribute(trimmed, value)
		name = ""
		value = ""
		nameFocused = true
	}
}
