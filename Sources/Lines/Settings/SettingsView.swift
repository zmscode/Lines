import AppKit
import SearchBar
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
	case general, windows, canvas, toolbar, editor
	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: "General"
		case .windows: "Windows"
		case .canvas: "Canvas"
		case .toolbar: "Toolbar"
		case .editor: "Code Editor"
		}
	}

	var symbol: String {
		switch self {
		case .general: "gearshape"
		case .windows: "macwindow"
		case .canvas: "square.on.square.dashed"
		case .toolbar: "menubar.rectangle"
		case .editor: "chevron.left.forwardslash.chevron.right"
		}
	}
}

/// One setting, for search: what it's called and words people might use.
struct SettingsEntry: Identifiable, Hashable {
	var title: String
	var pane: SettingsPane
	var keywords: [String] = []
	var id: String { "\(pane.rawValue).\(title)" }

	static let all: [SettingsEntry] = [
		SettingsEntry(
			title: "Appearance", pane: .general,
			keywords: ["light", "dark", "system", "auto", "mode"]),
		SettingsEntry(
			title: "Default app for SVG files", pane: .general,
			keywords: ["open with", "finder", "double-click"]),
		SettingsEntry(
			title: "Open new windows in", pane: .windows,
			keywords: ["layout", "canvas", "graph", "node"]),
		SettingsEntry(
			title: "Show code alongside", pane: .windows, keywords: ["source", "editor", "panel"]),
		SettingsEntry(
			title: "Open files locked", pane: .windows,
			keywords: ["preview", "lock", "read only", "edit"]),
		SettingsEntry(
			title: "Canvas background", pane: .canvas,
			keywords: [
				"checkerboard", "white", "black", "grey", "custom", "colour",
				"color",
			]),
		SettingsEntry(
			title: "Background behind the drawing only", pane: .canvas,
			keywords: ["artboard", "page", "area"]),
		SettingsEntry(
			title: "Window toolbar buttons", pane: .toolbar,
			keywords: [
				"reorder", "layers", "inspector", "code", "graph", "changes", "animations", "hide",
			]),
		SettingsEntry(
			title: "Tools palette", pane: .toolbar,
			keywords: ["reorder", "tools", "shapes", "left", "hide"]),
		SettingsEntry(
			title: "Graph palette", pane: .toolbar,
			keywords: ["reorder", "node editor", "tidy", "hide"]),
		SettingsEntry(
			title: "Code font", pane: .editor,
			keywords: ["typeface", "monospaced", "sf mono", "family"]),
		SettingsEntry(title: "Font size", pane: .editor, keywords: ["text", "points", "zoom"]),
		SettingsEntry(title: "Wrap lines", pane: .editor, keywords: ["soft wrap", "long lines"]),
		SettingsEntry(
			title: "Format automatically", pane: .editor, keywords: ["indent", "pretty", "tidy"]),
		SettingsEntry(
			title: "Dark theme", pane: .editor, keywords: ["syntax", "colours", "highlighting"]),
		SettingsEntry(
			title: "Light theme", pane: .editor, keywords: ["syntax", "colours", "highlighting"]),
	]

	/// Entries matching `query`, best first (fzf-style fuzzy matching).
	static func search(_ query: String) -> [SettingsEntry] {
		all.compactMap { entry -> (SettingsEntry, Int)? in
			let titleScore = FuzzyMatch.match(query, in: entry.title)?.score
			let otherScore = FuzzyMatch.best(query, in: entry.keywords + [entry.pane.title])
				.map { $0 - 6 }  // the setting's own name counts most
			guard let score = [titleScore, otherScore].compactMap({ $0 }).max() else { return nil }
			return (entry, score)
		}
		.sorted { $0.1 > $1.1 }
		.map(\.0)
	}
}

/// Settings, as the HIG describes for macOS: a noncustomizable toolbar of
/// panes that always shows the active one, the window titled after the
/// pane and sized to it, and the last pane restored. A search field finds
/// any setting and opens its pane.
struct SettingsView: View {
	@AppStorage("settings.pane") private var pane: SettingsPane = .general

	var body: some View {
		TabView(selection: $pane) {
			ForEach(SettingsPane.allCases) { pane in
				Tab(pane.title, systemImage: pane.symbol, value: pane) {
					PaneContainer(pane: pane, current: $pane) { detail(for: pane) }
				}
			}
		}
		.tint(Brand.accent)
	}

	@ViewBuilder
	private func detail(for pane: SettingsPane) -> some View {
		switch pane {
		case .general: GeneralSettings()
		case .windows: WindowSettings()
		case .canvas: CanvasSettings()
		case .toolbar: ToolbarSettings()
		case .editor: EditorSettings()
		}
	}
}

/// One pane: the search field, then the pane's form at a fixed width and
/// its natural height, so the window fits it.
private struct PaneContainer<Content: View>: View {
	var pane: SettingsPane
	@Binding var current: SettingsPane
	@ViewBuilder var content: Content

	var body: some View {
		VStack(spacing: 0) {
			SettingsSearch(current: $current)
				.padding(.horizontal, 20)
				.padding(.top, 14)
			content
				.scrollDisabled(!isTall)
		}
		.frame(width: 560, height: isTall ? 580 : nil)
		.fixedSize(horizontal: false, vertical: !isTall)
	}

	/// Panes with more than fits comfortably scroll inside a fixed height.
	private var isTall: Bool {
		pane == .editor || pane == .toolbar
	}
}

/// Finds a setting by name (fzf-style) and opens its pane.
private struct SettingsSearch: View {
	@Binding var current: SettingsPane
	@State private var query = ""

	var body: some View {
		SearchBar(text: $query, prompt: "Search Settings")
			.searchBarSuggestions(
				SettingsEntry.search(query).prefix(8).map {
					SearchBarSuggestion(
						text: $0.title, description: $0.pane.title, systemName: $0.pane.symbol)
				}
			)
			.searchBarChangeAction { text in
				// Picking a suggestion fills in its exact name: go to its pane.
				if let entry = SettingsEntry.all.first(where: { $0.title == text }) {
					current = entry.pane
				} else if let best = SettingsEntry.search(text).first,
					!text.trimmingCharacters(in: .whitespaces).isEmpty
				{
					current = best.pane
				}
			}
			.searchBarScale(.small)
			.accessibilityLabel("Search Settings")
	}
}

/// The Toolbar pane: reorder and show or hide each toolbar's items.
private struct ToolbarSettings: View {
	var body: some View {
		Form {
			Section {
				ToolbarLayoutEditor(
					key: ToolbarLayout.windowKey, defaults: ToolbarLayout.windowDefaults)
			} header: {
				Text("Window Toolbar")
			} footer: {
				SettingsFootnote(
					"Drag to reorder; separators split the buttons into groups. Hidden buttons stay in the View menu with their shortcuts (⌘1–⌘5)."
				)
			}
			Section {
				ToolbarLayoutEditor(
					key: ToolbarLayout.paletteKey, defaults: ToolbarLayout.paletteDefaults)
			} header: {
				Text("Tools Palette")
			} footer: {
				SettingsFootnote(
					"The tools down the left of the canvas. Tools you hide keep their keyboard shortcuts."
				)
			}
			Section {
				ToolbarLayoutEditor(
					key: ToolbarLayout.graphKey, defaults: ToolbarLayout.graphDefaults)
			} header: {
				Text("Graph Palette")
			} footer: {
				SettingsFootnote("The buttons down the left of the element graph.")
			}
		}
		.formStyle(.grouped)
	}
}

/// The explanatory text under a settings section.
struct SettingsFootnote: View {
	var text: String
	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text).font(.footnote).foregroundStyle(.secondary)
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
			} footer: {
				SettingsFootnote(
					"System follows your Mac's Light or Dark setting. Drawings themselves aren't affected: only the app's windows, panels and code editor change."
				)
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
			SettingsFootnote(
				"Double-clicking an SVG in the Finder opens it in the default app. macOS may ask you to confirm the change; you can still open SVGs in other apps with Open With."
			)
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
			Section {
				Picker("Open in", selection: $defaultLayout) {
					ForEach(EditorLayout.allCases) { layout in
						Label(layout.title, systemImage: layout.symbol).tag(layout)
					}
				}
				Toggle("Show code alongside", isOn: $showsCodeByDefault)
			} header: {
				Text("New Windows")
			} footer: {
				SettingsFootnote(
					"Canvas shows the drawing; Graph shows its elements as connected nodes. Showing code opens the source panel on the left of each new window. You can switch either at any time (⌘2, ⌘3)."
				)
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
			} footer: {
				SettingsFootnote(
					"A locked window lets you zoom, pan, play animations and ⌘-click links, but nothing in the file can change until you unlock it with the lock at the bottom left of the canvas."
				)
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
			} footer: {
				SettingsFootnote(
					"The background is only what Lines shows behind your drawing; it's never saved into the file. Behind the drawing only keeps the window's own colour around the drawing's edges, like a page on a desk."
				)
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
	@AppStorage(CodeFont.key) private var fontName = ""
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage("formatsAutomatically") private var formatsAutomatically = true
	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight

	var body: some View {
		Form {
			text
			themes
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
			SettingsFootnote(
				"The editor uses the dark theme in Dark Mode and the light theme in Light Mode, so it always matches the app. The themes are ports of their Zed extensions."
			)
		}

	}

	@ViewBuilder
	private var text: some View {
		Section {
			CodeFontPicker(fontName: $fontName)
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
		} header: {
			Text("Text")
		} footer: {
			SettingsFootnote(
				"Only fixed-width fonts are listed, so tags and attributes line up. You can also change the size with ⌘+ and ⌘− (or a pinch) while the editor is focused. Wrapping keeps long path data on screen instead of scrolling sideways."
			)
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

/// The code font: a few good defaults, then (if you ask) any fixed-width
/// font installed on this Mac.
private struct CodeFontPicker: View {
	@Binding var fontName: String
	@State private var choosingOther = false

	/// Picked only to open the installed-fonts sheet.
	private static let other = "\u{1}other"

	/// Defaults that are on every Mac, then popular coding fonts if installed.
	private static var defaults: [String] {
		let builtIn = ["Menlo", "Monaco", "Courier New"]
		let popular = [
			"JetBrains Mono", "Fira Code", "Source Code Pro", "Cascadia Code", "IBM Plex Mono",
			"Hack", "Iosevka", "Berkeley Mono", "Input Mono",
		]
		let installed = Set(NSFontManager.shared.availableFontFamilies)
		return builtIn + popular.filter(installed.contains)
	}

	var body: some View {
		Picker(
			"Font",
			selection: Binding(
				get: { fontName },
				set: { new in
					if new == Self.other { choosingOther = true } else { fontName = new }
				})
		) {
			Text(CodeFont.systemName).tag("")
			ForEach(Self.defaults, id: \.self) { family in
				Text(family).font(.custom(family, size: 13)).tag(family)
			}
			if !fontName.isEmpty && !Self.defaults.contains(fontName) {
				Text(fontName).font(.custom(fontName, size: 13)).tag(fontName)
			}
			Divider()
			Text("Other Installed Font…").tag(Self.other)
		}
		.sheet(isPresented: $choosingOther) {
			InstalledFontSheet(current: fontName) { chosen in
				if let chosen { fontName = chosen }
				choosingOther = false
			}
		}
	}
}

/// Asks before listing the fixed-width fonts on this Mac, then lets you pick one.
private struct InstalledFontSheet: View {
	var current: String
	var done: (String?) -> Void

	@State private var families: [String]?
	@State private var query = ""
	@State private var selection: String?

	private var shown: [String] {
		guard let families else { return [] }
		let q = query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return families }
		return families.compactMap { f in FuzzyMatch.match(q, in: f).map { (f, $0.score) } }
			.sorted { $0.1 > $1.1 }.map(\.0)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Use a Font Installed on This Mac").font(.headline)
			if families == nil {
				Text(
					"Lines can list the fixed-width fonts installed on your Mac, including ones from other apps. Only fixed-width fonts are shown, so code lines up."
				)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				Spacer()
				HStack {
					Spacer()
					Button("Cancel") { done(nil) }
						.keyboardShortcut(.cancelAction)
					Button("Show Installed Fonts") { families = CodeFont.families }
						.keyboardShortcut(.defaultAction)
				}
			} else {
				TextField("Search", text: $query)
					.textFieldStyle(.roundedBorder)
				List(shown, id: \.self, selection: $selection) { family in
					VStack(alignment: .leading, spacing: 2) {
						Text(family).font(.callout.weight(.medium))
						Text("<rect width=\"24\"/>")
							.font(.custom(family, size: 12))
							.foregroundStyle(.secondary)
					}
					.tag(family)
				}
				.frame(minHeight: 240)
				HStack {
					Text("\(shown.count) fonts").font(.caption).foregroundStyle(.secondary)
					Spacer()
					Button("Cancel") { done(nil) }
						.keyboardShortcut(.cancelAction)
					Button("Use Font") { done(selection) }
						.keyboardShortcut(.defaultAction)
						.disabled(selection == nil)
				}
			}
		}
		.padding(20)
		.frame(width: 380, height: families == nil ? 200 : 440)
		.onAppear { selection = current.isEmpty ? nil : current }
	}
}
