import AppKit
import SwiftUI

struct ContentView: View {
	var document: SVGDocument

	@State private var controller = CanvasController()
	/// Set once the window has restored its panels, so restoring them doesn't
	/// count as the user opening the code or graph.
	@State private var isLoaded = false
	@SceneStorage("showInspector") private var savedShowsInspector = false
	@SceneStorage("codeWidth") private var codeWidth: Double = 380
	@Environment(\.undoManager) private var undoManager
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openDocument) private var openDocument

	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.customColourKey) private var customColour = "#f2a65a"
	@AppStorage("defaultLayout") private var defaultLayout: EditorLayout = .canvas
	@AppStorage("showsCodeByDefault") private var showsCodeByDefault = false
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage(SyntaxTheme.darkKey) private var darkTheme = SyntaxTheme.defaultDark
	@AppStorage(SyntaxTheme.lightKey) private var lightTheme = SyntaxTheme.defaultLight

	private var isTransparent: Bool { background == .transparent && controller.layout == .canvas }

	/// Floating panel sizes; the canvas keeps the drawing clear of them.
	static let panelMargin: CGFloat = 12
	static let layersWidth: CGFloat = 264
	static let inspectorWidth: CGFloat = 308

	var body: some View {
		editor
			.background(WindowTransparency(isTransparent: isTransparent))
			// A see-through window would otherwise take the toolbar with it.
			.toolbarBackgroundVisibility(isTransparent ? .visible : .automatic, for: .windowToolbar)
			.tint(Brand.accent)
			.toolbar(id: "editor") { toolbar }
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
				controller.layout = defaultLayout
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
				withAnimation(Self.panelAnimation) { controller.showsInspector = true }
			}
			.onChange(of: controller.showsLayers) { _, _ in updateInsets() }
			.onChange(of: documentFrameShown, initial: true) { _, shown in
				controller.setDocumentFrame(shown)
			}
			.onChange(of: controller.layout) { _, layout in
				if layout == .graph && isLoaded { closeSidePanels() }
				updateInsets()
			}
			.onChange(of: controller.showsCode) { _, shows in
				if shows && isLoaded { closeSidePanels() }
				updateInsets()
			}
			.onChange(of: codeWidth) { _, _ in updateInsets() }
			.onChange(of: controller.showsTimeline, initial: true) { _, shows in
				controller.setTimelineActive(shows)
				updateInsets()
			}
			.onChange(of: controller.showsInspector) { _, shows in
				savedShowsInspector = shows
				updateInsets()
			}
	}

	static let panelAnimation = Animation.snappy(duration: 0.28)

	/// Room taken by the floating code panel on the leading edge.
	private var codeSpace: CGFloat {
		controller.showsCode ? codeWidth + Self.panelMargin : 0
	}

	/// Room taken by the code and layers panels, for things placed after them.
	private var leadingPanelsSpace: CGFloat {
		codeSpace + (controller.showsLayers ? Self.layersWidth + Self.panelMargin : 0)
	}

	/// Room taken by the tools palette on the canvas's leading edge.
	private var paletteSpace: CGFloat {
		controller.layout == .canvas ? ToolPalette.width + Self.panelMargin : 0
	}

	/// The document's extents and resize handles show while the inspector is
	/// showing the document (nothing selected).
	private var documentFrameShown: Bool {
		controller.showsInspector && controller.layout == .canvas
			&& (controller.selection?.isRoot ?? false)
	}

	/// The node and code editors want the room: layers and the inspector make
	/// way when either opens.
	private func closeSidePanels() {
		withAnimation(Self.panelAnimation) {
			controller.showsLayers = false
			controller.showsInspector = false
		}
	}

	private func updateInsets() {
		let m = Self.panelMargin
		controller.setInsets(
			left: codeSpace + paletteSpace
				+ (controller.showsLayers ? Self.layersWidth + m * 2 : 0),
			right: controller.showsInspector ? Self.inspectorWidth + m * 2 : 0,
			top: 0,
			bottom: controller.showsTimeline && controller.layout == .canvas
				? TimelinePanel.height + m * 2 : 0)
	}

	// MARK: Editor

	/// One canvas stays alive in every layout: it renders the drawing and also
	/// reports the element tree the layers panel and graph are built from.
	private var editor: some View {
		viewer
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.overlay(alignment: .leading) {
				if controller.showsCode {
					CodePanel(
						document: document, controller: controller, fontSize: fontSize,
						wrapsLines: wrapsLines,
						theme: SyntaxTheme.pair(light: lightTheme, dark: darkTheme),
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
			.animation(Self.panelAnimation, value: controller.showsCode)
	}

	/// The canvas or graph fills the viewer; layers and the inspector float over it.
	private var viewer: some View {
		ZStack {
			canvas
				.opacity(controller.layout == .graph ? 0 : 1)
				.allowsHitTesting(controller.layout == .canvas)
				.accessibilityHidden(controller.layout == .graph)
			if controller.layout == .graph {
				GraphView(controller: controller)
					.transition(.opacity)
					.dropDestination(for: URL.self) { urls, _ in
						controller.handleDroppedFiles(urls.filter(CanvasController.isSVG))
					}
			}
			if controller.layout == .canvas {
				CanvasControls(controller: controller)
					.padding(
						.bottom,
						controller.showsTimeline ? TimelinePanel.height + Self.panelMargin : 0
					)
					.padding(
						.leading, leadingPanelsSpace
					)
					.padding(
						.trailing,
						controller.showsInspector ? Self.inspectorWidth + Self.panelMargin : 0)
			}
		}
		.overlay(alignment: .topLeading) {
			if controller.layout == .canvas {
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
				.frame(width: Self.layersWidth)
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
		.overlay(alignment: .bottom) {
			if controller.showsTimeline {
				TimelinePanel(controller: controller, close: { controller.showsTimeline = false })
					.padding(Self.panelMargin)
					.padding(
						.leading, leadingPanelsSpace
					)
					.padding(
						.trailing,
						controller.showsInspector ? Self.inspectorWidth + Self.panelMargin : 0
					)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(Self.panelAnimation, value: controller.showsTimeline)
		.animation(Self.panelAnimation, value: controller.showsLayers)
		.animation(Self.panelAnimation, value: controller.showsInspector)
	}

	private var canvas: some View {
		CanvasView(
			text: document.text, background: background, customColour: customColour,
			controller: controller
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
	// Two groups (HIG › Toolbars): what the window shows on the leading edge
	// (the panels and the element graph) and sharing on the trailing edge.
	// Drawing tools live in the palette on the canvas. Every item is also in
	// the menu bar.

	@ToolbarContentBuilder
	private var toolbar: some CustomizableToolbarContent {
		ToolbarItem(id: "panels", placement: .navigation) {
			ControlGroup {
				Toggle(isOn: $controller.showsLayers) {
					Label("Layers", systemImage: "square.3.layers.3d")
				}
				.help(controller.showsLayers ? "Hide Layers (⌘1)" : "Show Layers (⌘1)")
				Toggle(isOn: $controller.showsInspector) {
					Label("Inspector", systemImage: "slider.horizontal.3")
				}
				.help(controller.showsInspector ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
				Toggle(isOn: $controller.showsCode) {
					Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
				}
				.help(controller.showsCode ? "Hide Code (⌘2)" : "Show Code (⌘2)")
				Toggle(
					isOn: Binding(
						get: { controller.layout == .graph },
						set: { controller.layout = $0 ? .graph : .canvas })
				) {
					Label("Graph", systemImage: EditorLayout.graph.symbol)
				}
				.help(controller.layout == .graph ? "Show Canvas (⌘3)" : "Show Element Graph (⌘3)")
				Toggle(isOn: $controller.showsTimeline) {
					Label("Timeline", systemImage: "film.stack")
				}
				.help(controller.showsTimeline ? "Hide Timeline (⌘4)" : "Show Timeline (⌘4)")
			} label: {
				Label("Panels", systemImage: "rectangle.3.group")
			}
		}
		.customizationBehavior(.disabled)

		ToolbarItem(id: "share", placement: .primaryAction) {
			Menu {
				Button("Export…", systemImage: "square.and.arrow.down") {
					controller.isExporting = true
				}
				Button("Print…", systemImage: "printer") { controller.printDrawing() }
				Divider()
				ShareLink(
					item: SharedDrawing(name: controller.documentName, controller: controller),
					preview: SharePreview(
						controller.documentName, image: Image(systemName: "photo"))
				) {
					Label("Share…", systemImage: "square.and.arrow.up")
				}
				if let url = document.configuration?.fileURL {
					ShareLink(item: url) {
						Label("Share File…", systemImage: "doc")
					}
				}
			} label: {
				Label("Share", systemImage: "square.and.arrow.up")
			}
			.menuIndicator(.hidden)
			.help("Export, print or share the drawing")
		}
	}
}
