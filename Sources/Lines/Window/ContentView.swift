import AppKit
import SwiftUI

struct ContentView: View {
	var document: SVGDocument

	@State private var controller = CanvasController()
	/// Set once the window has restored its panels, so restoring them doesn't
	/// count as the user opening the code or graph.
	@State private var isLoaded = false
	@State private var versionTask: Task<Void, Never>?
	@State private var showsPreviewBadge = true
	@SceneStorage("showInspector") private var savedShowsInspector = false
	@SceneStorage("codeWidth") private var codeWidth: Double = 380
	/// The window's width, for the Layers panel's half.
	@State private var windowWidth: CGFloat = 1000
	@Environment(\.undoManager) private var undoManager
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openDocument) private var openDocument

	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.customColourKey) private var customColour = "#f2a65a"
	@AppStorage(CanvasBackground.drawingOnlyKey) private var backgroundDrawingOnly = false
	@AppStorage("showsCodeByDefault") private var showsCodeByDefault = false
	@AppStorage("opensFilesLocked") private var opensFilesLocked = true
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage(CodeFont.key) private var codeFontName = ""
	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight
	@AppStorage(ToolbarLayout.windowKey) private var toolbarLayout = ToolbarLayout.windowDefaults
		.joined(separator: ",")

	/// Floating panel sizes; the canvas keeps the drawing clear of them.
	static let panelMargin: CGFloat = 12
	static let inspectorWidth: CGFloat = 308
	static let changesWidth: CGFloat = 440

	/// Room taken on the trailing edge by the inspector or the changes panel.
	private var trailingPanelWidth: CGFloat {
		controller.showsChanges
			? Self.changesWidth : controller.showsInspector ? Self.inspectorWidth : 0
	}

	var body: some View {
		editor
			.tint(Brand.accent)
			.toolbar { toolbar }
			.toolbarRole(.editor)
			.focusedSceneValue(controller)
			.sheet(
				isPresented: Binding(
					get: { controller.isExporting }, set: { controller.isExporting = $0 })
			) {
				ExportSheet(controller: controller, document: document)
			}
			.onAppear {
				dismissWindow(id: WelcomeView.windowID)
				controller.document = document
				controller.resetHistory(to: document.openedText)
				// Files open to look at; new drawings open ready to edit.
				controller.isEditing = !(opensFilesLocked && document.configuration?.fileURL != nil)
				controller.showsCode = showsCodeByDefault
				controller.showsInspector = savedShowsInspector
				controller.undoManager = undoManager
				controller.openDocuments = { urls in
					for url in urls {
						Task {
							do { try await openDocument(at: url) } catch {
								NSAlert(error: error).runModal()
							}
						}
					}
				}
				updateInsets()
				Task {
					try? await Task.sleep(for: .milliseconds(300))
					isLoaded = true
				}
			}
			.onChange(of: undoManager) { _, new in controller.undoManager = new }
			.onChange(of: controller.wantsInspector) { _, wants in
				guard wants else { return }
				controller.wantsInspector = false
				withAnimation(panelMotion) { controller.showsInspector = true }
			}
			.onChange(of: controller.showsLayers) { _, _ in updateInsets() }
			.onChange(of: documentFrameShown, initial: true) { _, shown in
				controller.setDocumentFrame(shown)
			}
			.onChange(of: controller.isEditing) { _, _ in updateInsets() }
			.onChange(of: controller.showsChanges) { _, shows in
				// The changes panel takes the inspector's place.
				if shows { controller.showsInspector = false }
				updateInsets()
			}
			// The file's contents arrive after the window opens: that's the
			// starting point, not an edit.
			.onChange(of: document.openedText) { _, opened in
				controller.resetHistory(to: opened)
			}
			.onChange(of: document.text) { _, text in
				// A version per pause in editing, named after the undo action.
				versionTask?.cancel()
				versionTask = Task {
					try? await Task.sleep(for: .milliseconds(700))
					guard !Task.isCancelled else { return }
					controller.recordVersion(text, title: undoManager?.undoActionName)
				}
			}
			.onChange(of: controller.showsCode) { _, shows in
				if shows && isLoaded { closeSidePanels() }
				updateInsets()
			}
			.onChange(of: codeWidth) { _, _ in updateInsets() }
			.onChange(of: windowWidth) { _, _ in if controller.showsLayers { updateInsets() } }
			.onChange(of: controller.showsTimeline, initial: true) { _, shows in
				controller.setTimelineActive(shows)
				// Opening the timeline stops at the start; Play starts it.
				if shows { controller.stop() }
				updateInsets()
			}
			.onChange(of: controller.showsInspector) { _, shows in
				if shows { controller.showsChanges = false }
				savedShowsInspector = shows
				updateInsets()
			}
	}

	static let panelAnimation = Animation.snappy(duration: 0.28)
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	/// Panels slide in, or simply appear with Reduce Motion on.
	private var panelMotion: Animation {
		reduceMotion ? .easeInOut(duration: 0.12) : Self.panelAnimation
	}

	/// Room taken by the floating code panel on the leading edge.
	private var codeSpace: CGFloat {
		controller.showsCode ? codeWidth + Self.panelMargin : 0
	}

	/// Room taken by the code and layers panels, for things placed after them.
	private var leadingPanelsSpace: CGFloat {
		codeSpace + (controller.showsLayers ? layersWidth + Self.panelMargin : 0)
	}

	/// Room taken by the tools palette on the canvas's leading edge.
	private var paletteSpace: CGFloat {
		// Kept while locked too: the lock lives at the foot of this column.
		// The Layers panel takes the tools' place.
		controller.showsLayers ? 0 : ToolPalette.width + Self.panelMargin
	}

	/// The Layers panel and the canvas share the room beside the code half and half.
	private var layersWidth: CGFloat {
		max(280, (windowWidth - codeSpace) / 2 - Self.panelMargin * 2)
	}

	/// The document's extents and resize handles show while the inspector is
	/// showing the document (nothing selected).
	private var documentFrameShown: Bool {
		controller.showsInspector
			&& (controller.selection?.isRoot ?? false)
	}

	/// The node and code editors want the room: layers and the inspector make
	/// way when either opens.
	private func closeSidePanels() {
		withAnimation(panelMotion) {
			controller.showsLayers = false
			controller.showsInspector = false
		}
	}

	private func updateInsets() {
		let m = Self.panelMargin
		controller.setInsets(
			left: codeSpace + paletteSpace
				+ (controller.showsLayers ? layersWidth + m * 2 : 0),
			right: trailingPanelWidth > 0 ? trailingPanelWidth + m * 2 : 0,
			top: 0,
			bottom: controller.showsTimeline
				? TimelinePanel.height + m * 2 : 0)
		// The minimap starts beside the lock when the palette isn't above it.
		controller.setMinimapShift(
			paletteSpace > 0 || controller.showsLayers ? 0 : ToolPalette.width + m)
	}

	// MARK: Editor

	/// One canvas stays alive in every layout: it renders the drawing and also
	/// reports the element tree the layers panel and graph are built from.
	private var editor: some View {
		viewer
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
			.overlay(alignment: .leading) {
				if controller.showsCode {
					CodePanel(
						document: document, controller: controller, fontSize: fontSize,
						wrapsLines: wrapsLines,
						theme: SyntaxTheme.pair(light: lightTheme, dark: darkTheme),
						fontName: codeFontName,
						close: { controller.showsCode = false }
					)
					.frame(width: codeWidth)
					.overlay(alignment: .trailing) {
						SplitDivider(width: $codeWidth, showsLine: false)
							.padding(.vertical, 24)
							.offset(x: 4)
					}
					.padding(Self.panelMargin)
					.transition(.move(edge: .leading).combined(with: .opacity))
				}
			}
			.animation(panelMotion, value: controller.showsCode)
	}

	/// The canvas fills the viewer; layers and the inspector float over it.
	private var viewer: some View {
		ZStack {
			canvas
			CanvasControls(controller: controller)
				.padding(
					.bottom,
					controller.showsTimeline ? TimelinePanel.height + Self.panelMargin : 0
				)
				.padding(.leading, leadingPanelsSpace)
				.padding(
					.trailing,
					trailingPanelWidth > 0 ? trailingPanelWidth + Self.panelMargin : 0)
		}
		.overlay(alignment: .topLeading) {
			if controller.isEditing && !controller.showsLayers {
				ToolPalette(controller: controller)
					.padding(Self.panelMargin)
					.padding(.leading, codeSpace)
					.transition(.opacity)
			}
		}
		.overlay(alignment: .topLeading) {
			if controller.showsLayers {
				FloatingPanel(title: "Layers", close: { controller.showsLayers = false }) {
					LayersPanel(controller: controller)
				}
				.frame(width: layersWidth)
				.padding(Self.panelMargin)
				.padding(.leading, paletteSpace + codeSpace)
				.transition(.move(edge: .leading).combined(with: .opacity))
			}
		}
		.overlay(alignment: .topTrailing) {
			if controller.showsInspector {
				FloatingPanel(title: nil, close: { controller.showsInspector = false }) {
					InspectorView(controller: controller)
				}
				.frame(width: Self.inspectorWidth)
				.padding(Self.panelMargin)
				.transition(.move(edge: .trailing).combined(with: .opacity))
			}
		}
		.overlay(alignment: .topTrailing) {
			if controller.showsChanges, let original = controller.originalText {
				ChangesPanel(
					original: original, current: document.text, controller: controller,
					restore: { text, name in
						controller.preview(version: nil)
						document.replaceText(
							with: text, actionName: name, undoManager: controller.undoManager)
					},
					close: {
						controller.preview(version: nil)
						controller.showsChanges = false
					}
				)
				.frame(width: Self.changesWidth)
				.padding(Self.panelMargin)
				.transition(.move(edge: .trailing).combined(with: .opacity))
			}
		}
		.animation(panelMotion, value: controller.showsChanges)
		.overlay(alignment: .bottom) {
			if controller.showsTimeline {
				TimelinePanel(controller: controller, close: { controller.showsTimeline = false })
					.padding(Self.panelMargin)
					.padding(
						.leading, leadingPanelsSpace
					)
					.padding(
						.trailing,
						trailingPanelWidth > 0 ? trailingPanelWidth + Self.panelMargin : 0
					)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.overlay(alignment: .bottomLeading) {
			// The lock, at the canvas's lower left (the minimap sits beside it);
			// the timeline takes the bottom of the window when it's open.
			if !controller.showsTimeline && !controller.showsLayers {
				FloatingStrip {
					Button(
						controller.isEditing ? "Lock" : "Unlock",
						systemImage: controller.isEditing ? "lock.open" : "lock.fill"
					) {
						controller.isEditing.toggle()
					}
					.buttonStyle(
						.icon(size: ToolPalette.buttonSize, selected: !controller.isEditing)
					)
					.contentTransition(.symbolEffect(.replace))
					.help(
						controller.isEditing
							? "Lock to preview without changing anything (⇧⌘L)"
							: "Unlock to edit (⇧⌘L)")
				}
				// It stays in the tools column, beside the panels, not under them.
				.padding(Self.panelMargin)
				.padding(.leading, codeSpace)
			}
		}
		.overlay(alignment: .top) {
			if let edit = controller.definitionEdit {
				DefinitionEditBanner(
					kind: edit.kind == "mask" ? "mask" : "clip path", name: edit.name
				) { controller.endDefinitionEdit() }
				.padding(Self.panelMargin)
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(panelMotion, value: controller.definitionEdit?.name)
		.overlay(alignment: .top) {
			if !controller.isEditing && showsPreviewBadge {
				PreviewBadge { controller.isEditing = true }
					.padding(Self.panelMargin)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(panelMotion, value: controller.isEditing)
		.animation(.easeInOut(duration: 0.4), value: showsPreviewBadge)
		// The badge is a reminder, not a fixture: it fades after a few seconds
		// each time the window locks (the lock button stays).
		.task(id: controller.isEditing) {
			guard !controller.isEditing else { return }
			showsPreviewBadge = true
			try? await Task.sleep(for: .seconds(4))
			if !Task.isCancelled { showsPreviewBadge = false }
		}
		.animation(panelMotion, value: controller.showsTimeline)
		.animation(panelMotion, value: controller.showsLayers)
		.animation(panelMotion, value: controller.showsInspector)
	}

	private var canvas: some View {
		CanvasView(
			text: document.text, background: background, customColour: customColour,
			drawingOnly: backgroundDrawingOnly, controller: controller
		)
		.overlay(alignment: .bottom) {
			if let error = controller.parseError {
				ParseErrorBanner(message: error)
					.padding(12)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.smooth(duration: 0.2), value: controller.parseError)
	}

	// MARK: Toolbar
	//
	// Two groups on the leading edge (the side panels, then the editors) and
	// sharing on the trailing edge. Drawing tools live in the palette on the
	// canvas. Which buttons show is chosen in Settings › General; every item
	// is also in the menu bar.

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
		// Locked windows are for looking: just the title and Export.
		if controller.isEditing {
			editingToolbar
		}
		ToolbarItem(placement: .primaryAction) {
			ExportButton(controller: controller, document: document)
		}
	}

	@ToolbarContentBuilder
	private var editingToolbar: some ToolbarContent {
		// The order chosen in Settings › Toolbar, in one group; separators show
		// as lines (spacers between leading groups don't draw).
		let groups = ToolbarLayout(toolbarLayout, defaults: ToolbarLayout.windowDefaults).groups
		ToolbarItemGroup(placement: .navigation) {
			ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
				if index > 0 {
					Rectangle()
						.fill(.separator)
						.frame(width: 1, height: 18)
						.padding(.horizontal, 4)
						.accessibilityHidden(true)
				}
				ForEach(group, id: \.self) { toolbarButton($0) }
			}
		}
	}

	@ViewBuilder
	private func toolbarButton(_ id: String) -> some View {
		switch id {
		case "layers":
			Toggle(isOn: $controller.showsLayers) {
				Label("Layers", systemImage: "square.3.layers.3d")
			}
			.help(controller.showsLayers ? "Hide Layers (⌘1)" : "Show Layers (⌘1)")
		case "inspector":
			Toggle(isOn: $controller.showsInspector) {
				Label("Inspector", systemImage: "slider.horizontal.3")
			}
			.help(controller.showsInspector ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
		case "code":
			Toggle(isOn: $controller.showsCode) {
				Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
			}
			.help(controller.showsCode ? "Hide Code (⌘2)" : "Show Code (⌘2)")
		case "changes":
			Toggle(isOn: $controller.showsChanges) {
				Label("Changes", systemImage: "plusminus")
			}
			.disabled(!controller.hasChanges)
			.help(
				controller.hasChanges
					? (controller.showsChanges ? "Hide Changes (⌘5)" : "Show Changes (⌘5)")
					: "No changes since opening")
		case "timeline":
			Toggle(isOn: $controller.showsTimeline) {
				Label("Animations", systemImage: "film.stack")
			}
			.help(controller.showsTimeline ? "Hide Timeline (⌘4)" : "Show Timeline (⌘4)")
		default:
			EmptyView()
		}
	}

}

/// Shown at the top of the viewer while a file is open for preview.
private struct PreviewBadge: View {
	var unlock: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "lock.fill").foregroundStyle(.secondary)
			Text("Preview").font(.callout.weight(.medium))
			Text("⌘-click links to open them").font(.caption).foregroundStyle(.secondary)
			Button("Edit", action: unlock)
				.controlSize(.small)
				.help("Unlock to edit (⇧⌘L)")
		}
		.padding(.leading, 12)
		.padding(.trailing, 6)
		.padding(.vertical, 5)
		.glassEffect(.regular, in: .capsule)
		.shadow(color: .black.opacity(0.12), radius: 8, y: 3)
	}
}

/// Shown while a clip path's or mask's shapes are edited on the canvas.
private struct DefinitionEditBanner: View {
	var kind: String
	var name: String
	var done: () -> Void

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "hand.draw").foregroundStyle(.tint)
			VStack(alignment: .leading, spacing: 0) {
				Text("Editing \(kind) “\(name)”").font(.callout.weight(.medium))
				Text("Move and resize its dashed shapes over the element.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Button("Done", action: done)
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				.help("Finish editing (Esc)")
		}
		.padding(.leading, 12)
		.padding(.trailing, 6)
		.padding(.vertical, 6)
		.glassEffect(.regular, in: .capsule)
		.shadow(color: .black.opacity(0.12), radius: 8, y: 3)
	}
}
