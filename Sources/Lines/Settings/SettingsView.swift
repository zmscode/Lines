import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
	case system, light, dark
	var id: String { rawValue }

	var title: String {
		switch self {
		case .system: "System"
		case .light: "Light"
		case .dark: "Dark"
		}
	}

	var nsAppearance: NSAppearance? {
		switch self {
		case .system: nil
		case .light: NSAppearance(named: .aqua)
		case .dark: NSAppearance(named: .darkAqua)
		}
	}

	static let storageKey = "appearance"

	@MainActor
	static func applySaved() {
		let saved =
			UserDefaults.standard.string(forKey: storageKey).flatMap(AppAppearance.init) ?? .system
		NSApp.appearance = saved.nsAppearance
	}
}

/// Settings, laid out like the system's own: a tab per area, grouped forms.
struct SettingsView: View {
	var body: some View {
		TabView {
			Tab("General", systemImage: "gearshape") {
				GeneralSettings()
			}
			Tab("Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
				EditorSettings()
			}
		}
		.frame(width: 500)
		.tint(Brand.accent)
	}
}

// MARK: - General

private struct GeneralSettings: View {
	@AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage("defaultLayout") private var defaultLayout: EditorLayout = .canvas
	@AppStorage("showsCodeByDefault") private var showsCodeByDefault = false

	var body: some View {
		Form {
			Section {
				LabeledContent("Appearance") {
					HStack(spacing: 14) {
						ForEach(AppAppearance.allCases) { option in
							AppearanceTile(option: option, isSelected: appearance == option) {
								appearance = option
							}
						}
					}
				}
			}

			Section("New Windows") {
				Picker("Open in", selection: $defaultLayout) {
					ForEach(EditorLayout.allCases) { layout in
						Label(layout.title, systemImage: layout.symbol).tag(layout)
					}
				}
				Toggle("Show code alongside", isOn: $showsCodeByDefault)
			}

			Section("Toolbar") {
				ToolbarButtonsSettings()
			}

			Section {
				Picker("Background", selection: $background) {
					ForEach(CanvasBackground.allCases) { Text($0.title).tag($0) }
				}
			} header: {
				Text("Canvas")
			} footer: {
				Text("The background only affects how drawings are shown, not the saved file.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
		.fixedSize(horizontal: false, vertical: true)
		.onChange(of: appearance, initial: false) { _, new in
			NSApp.appearance = new.nsAppearance
		}
	}
}

/// A thumbnail of a window in each appearance, like System Settings › Appearance.
private struct AppearanceTile: View {
	var option: AppAppearance
	var isSelected: Bool
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			VStack(spacing: 6) {
				thumbnail
					.frame(width: 68, height: 46)
					.clipShape(.rect(cornerRadius: 7, style: .continuous))
					.overlay {
						RoundedRectangle(cornerRadius: 7, style: .continuous)
							.strokeBorder(.separator, lineWidth: 0.5)
					}
					.padding(3)
					.overlay {
						RoundedRectangle(cornerRadius: 9, style: .continuous)
							.strokeBorder(
								isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
								lineWidth: 2.5)
					}
				Text(option.title)
					.font(.caption)
					.fontWeight(isSelected ? .semibold : .regular)
					.foregroundStyle(isSelected ? .primary : .secondary)
			}
		}
		.buttonStyle(.plain)
		.help("\(option.title) appearance")
		.accessibilityLabel(option.title)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	@ViewBuilder
	private var thumbnail: some View {
		switch option {
		case .light: MiniWindow(dark: false)
		case .dark: MiniWindow(dark: true)
		case .system:
			HStack(spacing: 0) {
				MiniWindow(dark: false).frame(width: 34, alignment: .leading).clipped()
				MiniWindow(dark: true).frame(width: 34, alignment: .trailing).clipped()
			}
		}
	}
}

private struct MiniWindow: View {
	var dark: Bool

	var body: some View {
		ZStack(alignment: .topLeading) {
			LinearGradient(
				colors: dark
					? [Color(white: 0.28), Color(white: 0.16)]
					: [
						Color(red: 0.62, green: 0.76, blue: 0.95),
						Color(red: 0.84, green: 0.9, blue: 0.98),
					],
				startPoint: .top, endPoint: .bottom
			)
			RoundedRectangle(cornerRadius: 3, style: .continuous)
				.fill(dark ? Color(white: 0.2) : .white)
				.frame(width: 50, height: 30)
				.overlay(alignment: .topLeading) {
					HStack(spacing: 2) {
						Circle().fill(.red)
						Circle().fill(.yellow)
						Circle().fill(.green)
					}
					.frame(height: 3.5)
					.padding(3)
				}
				.overlay {
					RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
						.frame(width: 16, height: 10)
						.offset(x: 4, y: 3)
				}
				.offset(x: 9, y: 9)
				.shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
		}
		.frame(width: 68, height: 46)
	}
}

// MARK: - Editor

private struct EditorSettings: View {
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage("formatsAutomatically") private var formatsAutomatically = true
	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight

	var body: some View {
		Form {
			Section {
				themePicker("Dark Theme", selection: $darkTheme, themes: SyntaxTheme.dark)
				themePicker("Light Theme", selection: $lightTheme, themes: SyntaxTheme.light)
				HStack(spacing: 10) {
					preview(darkTheme, dark: true)
					preview(lightTheme, dark: false)
				}
			} header: {
				Text("Colours")
			} footer: {
				Text(
					"The editor uses the dark theme in Dark Mode and the light theme in Light Mode. Themes come from their Zed extensions."
				)
				.font(.footnote)
				.foregroundStyle(.secondary)
			}

			Section("Text") {
				LabeledContent("Font size") {
					Stepper(value: $fontSize, in: 9...24, step: 1) {
						Text("\(Int(fontSize)) pt").monospacedDigit()
					}
				}
				Toggle("Wrap lines", isOn: $wrapsLines)
				Toggle(isOn: $formatsAutomatically) {
					Text("Format automatically")
					Text("Re-indents the markup after canvas edits and when you pause typing.")
				}
			}
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
		.fixedSize(horizontal: false, vertical: true)
	}

	/// Themes grouped by family, like an editor's theme picker.
	private func themePicker(
		_ title: String, selection: Binding<String>, themes: [SyntaxTheme]
	) -> some View {
		Picker(title, selection: selection) {
			let families = themes.reduce(into: [String]()) {
				if !$0.contains($1.family) { $0.append($1.family) }
			}
			ForEach(families, id: \.self) { family in
				Section(family) {
					ForEach(themes.filter { $0.family == family }) { theme in
						Text(theme.name).tag(theme.name)
					}
				}
			}
		}
	}

	private func preview(_ name: String, dark: Bool) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			ThemePreview(
				theme: SyntaxTheme.named(name) ?? SyntaxTheme.builtIn[0], fontSize: fontSize,
				isDark: dark
			)
			.frame(height: 108)
			.clipShape(.rect(cornerRadius: 8, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 8, style: .continuous)
					.strokeBorder(.separator, lineWidth: 0.5)
			}
			Text(dark ? "Dark" : "Light").font(.caption).foregroundStyle(.secondary)
		}
		.accessibilityHidden(true)
	}
}

/// A read-only text view showing sample markup in the chosen theme.
private struct ThemePreview: NSViewRepresentable {
	var theme: SyntaxTheme
	var fontSize: Double
	var isDark: Bool

	func makeNSView(context: Context) -> NSTextView {
		let textView = NSTextView()
		textView.isEditable = false
		textView.isSelectable = false
		textView.textContainerInset = NSSize(width: 10, height: 10)
		return textView
	}

	func updateNSView(_ textView: NSTextView, context: Context) {
		textView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
		textView.backgroundColor = theme.background
		textView.textStorage?.setAttributedString(
			Highlighter.sample(theme: theme, fontSize: fontSize))
	}
}

/// Which buttons the window toolbar shows (instead of right-click customising).
enum ToolbarButtons {
	static let layers = "toolbar.layers"
	static let inspector = "toolbar.inspector"
	static let code = "toolbar.code"
	static let graph = "toolbar.graph"
	static let timeline = "toolbar.timeline"
}

private struct ToolbarButtonsSettings: View {
	@AppStorage(ToolbarButtons.layers) private var layers = true
	@AppStorage(ToolbarButtons.inspector) private var inspector = true
	@AppStorage(ToolbarButtons.code) private var code = true
	@AppStorage(ToolbarButtons.graph) private var graph = true
	@AppStorage(ToolbarButtons.timeline) private var timeline = true

	var body: some View {
		Toggle(isOn: $layers) { Label("Layers", systemImage: "square.3.layers.3d") }
		Toggle(isOn: $inspector) { Label("Inspector", systemImage: "slider.horizontal.3") }
		Toggle(isOn: $code) {
			Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
		}
		Toggle(isOn: $graph) { Label("Graph", systemImage: EditorLayout.graph.symbol) }
		Toggle(isOn: $timeline) { Label("Animations", systemImage: "film.stack") }
	}
}
