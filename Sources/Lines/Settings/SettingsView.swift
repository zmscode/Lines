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

/// A page of Settings, listed in the sidebar like System Settings.
enum SettingsPane: String, CaseIterable, Identifiable {
	case general, windows, canvas, toolbar, editor, themes
	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: "General"
		case .windows: "Windows"
		case .canvas: "Canvas"
		case .toolbar: "Toolbar"
		case .editor: "Code Editor"
		case .themes: "Code Themes"
		}
	}

	var symbol: String {
		switch self {
		case .general: "gearshape"
		case .windows: "macwindow"
		case .canvas: "square.on.square.dashed"
		case .toolbar: "menubar.rectangle"
		case .editor: "chevron.left.forwardslash.chevron.right"
		case .themes: "paintpalette"
		}
	}

	var tint: Color {
		switch self {
		case .general: .gray
		case .windows: .blue
		case .canvas: Brand.accent
		case .toolbar: .indigo
		case .editor: .teal
		case .themes: .pink
		}
	}

	/// Words the search field matches, beyond the title.
	var keywords: [String] {
		switch self {
		case .general:
			["appearance", "light", "dark", "system", "default", "svg", "open with", "app"]
		case .windows: ["new", "layout", "graph", "code", "preview", "locked", "lock", "open"]
		case .canvas:
			[
				"background", "transparent", "checkerboard", "white", "black", "grey", "custom",
				"colour", "color", "drawing",
			]
		case .toolbar:
			["buttons", "layers", "inspector", "code", "graph", "animations", "timeline"]
		case .editor: ["font", "size", "wrap", "lines", "format", "indent", "text"]
		case .themes: ["theme", "colours", "colors", "syntax", "highlighting", "dark", "light"]
		}
	}

	func matches(_ query: String) -> Bool {
		let q = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !q.isEmpty else { return true }
		return title.lowercased().contains(q) || keywords.contains { $0.contains(q) }
	}
}

/// Settings, laid out like System Settings: categories in a searchable
/// sidebar, each opening a grouped form on the right.
struct SettingsView: View {
	@AppStorage("settings.pane") private var pane: SettingsPane = .general
	@State private var query = ""

	private var panes: [SettingsPane] { SettingsPane.allCases.filter { $0.matches(query) } }

	var body: some View {
		NavigationSplitView {
			List(panes, selection: selection) { pane in
				Label {
					Text(pane.title)
				} icon: {
					Image(systemName: pane.symbol)
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: 20, height: 20)
						.background(
							pane.tint.gradient, in: .rect(cornerRadius: 5, style: .continuous))
				}
				.tag(pane)
			}
			.navigationSplitViewColumnWidth(200)
			.searchable(text: $query, placement: .sidebar, prompt: "Search")
			.overlay {
				if panes.isEmpty {
					ContentUnavailableView.search(text: query)
				}
			}
		} detail: {
			detail(for: panes.contains(pane) ? pane : panes.first ?? pane)
				.navigationTitle((panes.contains(pane) ? pane : panes.first ?? pane).title)
		}
		.frame(width: 720, height: 520)
		.tint(Brand.accent)
		.onChange(of: query) { _, _ in
			if let first = panes.first, !panes.contains(pane) { pane = first }
		}
	}

	private var selection: Binding<SettingsPane?> {
		Binding(get: { pane }, set: { if let new = $0 { pane = new } })
	}

	@ViewBuilder
	private func detail(for pane: SettingsPane) -> some View {
		switch pane {
		case .general: GeneralSettings()
		case .windows: WindowSettings()
		case .canvas: CanvasSettings()
		case .toolbar: Form { Section("Buttons") { ToolbarButtonsSettings() } }.formStyle(.grouped)
		case .editor: EditorSettings(part: .text)
		case .themes: EditorSettings(part: .themes)
		}
	}
}

// MARK: - General

private struct GeneralSettings: View {
	@AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

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
			DefaultAppSection()
		}
		.formStyle(.grouped)
		.onChange(of: appearance, initial: false) { _, new in
			NSApp.appearance = new.nsAppearance
		}
	}
}

/// Shows which app opens .svg files, with a button to make it Lines.
private struct DefaultAppSection: View {
	@State private var current: URL?
	@State private var error: String?

	private var isLines: Bool {
		current?.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path
			|| current.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
	}

	var body: some View {
		Section {
			LabeledContent("Opens SVG files") {
				HStack(spacing: 6) {
					if let current {
						Image(nsImage: NSWorkspace.shared.icon(forFile: current.path))
							.resizable()
							.frame(width: 18, height: 18)
						Text(FileManager.default.displayName(atPath: current.path))
					} else {
						Text("No app").foregroundStyle(.secondary)
					}
				}
			}
			HStack {
				Spacer()
				Button(isLines ? "Lines Is the Default" : "Make Lines the Default") {
					Task { await makeDefault() }
				}
				.disabled(isLines)
			}
			if let error {
				Text(error).font(.footnote).foregroundStyle(.red)
			}
		} header: {
			Text("Default App")
		} footer: {
			Text("Double-clicking an SVG in the Finder opens it in the default app.")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.onAppear(perform: refresh)
	}

	private func refresh() {
		current = NSWorkspace.shared.urlForApplication(toOpen: .svg)
	}

	private func makeDefault() async {
		do {
			try await NSWorkspace.shared.setDefaultApplication(
				at: Bundle.main.bundleURL, toOpen: .svg)
			error = nil
		} catch {
			self.error = error.localizedDescription
		}
		refresh()
	}
}

// MARK: - Windows

private struct WindowSettings: View {
	@AppStorage("defaultLayout") private var defaultLayout: EditorLayout = .canvas
	@AppStorage("showsCodeByDefault") private var showsCodeByDefault = false
	@AppStorage("opensFilesLocked") private var opensFilesLocked = true

	var body: some View {
		Form {
			Section("New Windows") {
				Picker("Open in", selection: $defaultLayout) {
					ForEach(EditorLayout.allCases) { layout in
						Label(layout.title, systemImage: layout.symbol).tag(layout)
					}
				}
				Toggle("Show code alongside", isOn: $showsCodeByDefault)
			}
			Section {
				Toggle(isOn: $opensFilesLocked) {
					Text("Open files locked, for preview")
					Text(
						"Unlock with the toolbar lock or ⇧⌘L. New drawings always open ready to edit."
					)
				}
			} header: {
				Text("Preview")
			}
		}
		.formStyle(.grouped)
	}
}

// MARK: - Canvas

private struct CanvasSettings: View {
	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.drawingOnlyKey) private var drawingOnly = false

	var body: some View {
		Form {
			Section {
				Picker("Background", selection: $background) {
					ForEach(CanvasBackground.allCases) { Text($0.title).tag($0) }
				}
				Toggle(isOn: $drawingOnly) {
					Text("Behind the drawing only")
					Text("Fills just the drawing's area, with the window colour around it.")
				}
				.disabled(background == .transparent)
			} footer: {
				Text("The background only affects how drawings are shown, not the saved file.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
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
	enum Part { case text, themes }
	var part: Part
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage("formatsAutomatically") private var formatsAutomatically = true
	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight

	var body: some View {
		Form {
			if part == .themes { themes } else { text }
		}
		.formStyle(.grouped)
	}

	@ViewBuilder
	private var themes: some View {
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

	}

	@ViewBuilder
	private var text: some View {
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
