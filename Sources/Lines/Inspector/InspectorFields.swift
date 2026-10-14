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
	@FocusState private var focus: Field?

	private enum Field { case name, value }

	private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
	/// XML attribute names: a letter or underscore, then letters, digits, `.`, `-`, `_` or `:`.
	private var isValid: Bool {
		trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9._:-]*$"#, options: .regularExpression) != nil
	}

	var body: some View {
		HStack(spacing: 6) {
			TextField("Name", text: $name, prompt: Text("New attribute"))
				.labelsHidden()
				.textFieldStyle(.roundedBorder)
				.font(.caption.monospaced())
				.focused($focus, equals: .name)
				.onSubmit { if isValid { focus = .value } }
				.overlay {
					if !trimmed.isEmpty && !isValid {
						RoundedRectangle(cornerRadius: 5).strokeBorder(.red, lineWidth: 1.5)
					}
				}
				.help(
					!trimmed.isEmpty && !isValid
						? "Attribute names start with a letter and can’t contain spaces"
						: "Attribute name, like stroke-dasharray")
			TextField("Value", text: $value, prompt: Text("Value"))
				.labelsHidden()
				.textFieldStyle(.roundedBorder)
				.font(.caption.monospaced())
				.focused($focus, equals: .value)
				.onSubmit(add)
				.help("Attribute value")
			Button("Add Attribute", systemImage: "plus.circle.fill", action: add)
				.labelStyle(.iconOnly)
				.buttonStyle(.borderless)
				.foregroundStyle(isValid ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
				.disabled(!isValid)
				.help(isValid ? "Add \(trimmed)" : "Type an attribute name to add it")
		}
	}

	private func add() {
		guard isValid else { return }
		controller.setAttribute(trimmed, value)
		name = ""
		value = ""
		focus = .name
	}
}
