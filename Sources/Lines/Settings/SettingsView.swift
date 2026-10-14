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
		SettingsEntry(title: "Layers button", pane: .toolbar, keywords: ["toolbar", "layers"]),
		SettingsEntry(
			title: "Inspector button", pane: .toolbar, keywords: ["toolbar", "inspector"]),
		SettingsEntry(title: "Code button", pane: .toolbar, keywords: ["toolbar", "source"]),
		SettingsEntry(title: "Graph button", pane: .toolbar, keywords: ["toolbar", "node editor"]),
		SettingsEntry(
			title: "Animations button", pane: .toolbar, keywords: ["toolbar", "timeline"]),
		SettingsEntry(
			title: "Changes button", pane: .toolbar, keywords: ["toolbar", "diff", "history"]),
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

/// Settings, laid out like System Settings: categories in a searchable
/// sidebar, each opening a grouped form on the right.
struct SettingsView: View {
	@AppStorage("settings.pane") private var pane: SettingsPane = .general
	@State private var query = ""

	private var results: [SettingsEntry] { SettingsEntry.search(query) }
	private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

	var body: some View {
		NavigationSplitView {
			List(selection: selection) {
				if isSearching {
					Section("Results") {
						ForEach(results) { entry in
							VStack(alignment: .leading, spacing: 1) {
								Text(entry.title)
								Text(entry.pane.title).font(.caption).foregroundStyle(.secondary)
							}
							.tag(entry.pane)
						}
					}
				} else {
					ForEach(SettingsPane.allCases) { pane in
						Label {
							Text(pane.title)
						} icon: {
							Image(systemName: pane.symbol)
								.font(.system(size: 11, weight: .semibold))
								.foregroundStyle(.white)
								.frame(width: 20, height: 20)
								.background(
									Brand.accent.gradient,
									in: .rect(cornerRadius: 5, style: .continuous))
						}
						.tag(pane)
					}
				}
			}
			.navigationSplitViewColumnWidth(210)
			.searchable(text: $query, placement: .sidebar, prompt: "Search Settings")
			.overlay {
				if isSearching && results.isEmpty {
					ContentUnavailableView.search(text: query)
				}
			}
			.toolbar(removing: .sidebarToggle)
		} detail: {
			// The window is always "Settings"; each section has its own header.
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 10) {
					Image(systemName: pane.symbol)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: 28, height: 28)
						.background(
							Brand.accent.gradient, in: .rect(cornerRadius: 7, style: .continuous))
					Text(pane.title).font(.title2.weight(.semibold))
				}
				.padding(.horizontal, 24)
				.padding(.top, 18)
				.padding(.bottom, 2)
				detail(for: pane)
			}
			.navigationTitle("Settings")
		}
		.navigationTitle("Settings")
		.frame(width: 720, height: 540)
		.tint(Brand.accent)
		.onChange(of: query) { _, _ in
			if let first = results.first { pane = first.pane }
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
		case .toolbar:
			Form {
				Section {
					ToolbarButtonsSettings()
				} header: {
					Text("Buttons")
				} footer: {
					SettingsFootnote(
						"Choose which buttons appear in each window's toolbar. Everything stays available from the View menu and its shortcuts (⌘1–⌘5) either way."
					)
				}
			}
			.formStyle(.grouped)
		case .editor: EditorSettings()
		}
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

/// Which buttons the window toolbar shows (instead of right-click customising).
enum ToolbarButtons {
	static let layers = "toolbar.layers"
	static let inspector = "toolbar.inspector"
	static let code = "toolbar.code"
	static let graph = "toolbar.graph"
	static let timeline = "toolbar.timeline"
	static let changes = "toolbar.changes"
}

private struct ToolbarButtonsSettings: View {
	@AppStorage(ToolbarButtons.layers) private var layers = true
	@AppStorage(ToolbarButtons.inspector) private var inspector = true
	@AppStorage(ToolbarButtons.code) private var code = true
	@AppStorage(ToolbarButtons.graph) private var graph = true
	@AppStorage(ToolbarButtons.timeline) private var timeline = true
	@AppStorage(ToolbarButtons.changes) private var changes = true

	var body: some View {
		Toggle(isOn: $layers) { Label("Layers", systemImage: "square.3.layers.3d") }
		Toggle(isOn: $inspector) { Label("Inspector", systemImage: "slider.horizontal.3") }
		Toggle(isOn: $code) {
			Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
		}
		Toggle(isOn: $graph) { Label("Graph", systemImage: EditorLayout.graph.symbol) }
		Toggle(isOn: $timeline) { Label("Animations", systemImage: "film.stack") }
		Toggle(isOn: $changes) { Label("Changes", systemImage: "plusminus") }
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
