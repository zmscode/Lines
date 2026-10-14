import AppKit
import SwiftUI

struct ContentView: View {
	var document: SVGDocument

	@State private var controller = CanvasController()
	@SceneStorage("showInspector") private var showInspector = false
	@State private var showsInsert = false
	@State private var arrangeExpanded = false
	@SceneStorage("codeWidth") private var codeWidth: Double = 380
	@Environment(\.undoManager) private var undoManager
	@Environment(\.dismissWindow) private var dismissWindow

	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard
	@AppStorage(CanvasBackground.customColourKey) private var customColour = "#f2a65a"
	@AppStorage("defaultLayout") private var defaultLayout: EditorLayout = .canvas
	@AppStorage("showsCodeByDefault") private var showsCodeByDefault = false
	@AppStorage("editorFontSize") private var fontSize: Double = 12
	@AppStorage("wrapsLines") private var wrapsLines = true
	@AppStorage("syntaxTheme") private var themeName = SyntaxTheme.automaticName

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
				controller.undoManager = undoManager
				updateInsets()
			}
			.onChange(of: undoManager) { _, new in controller.undoManager = new }
			.onChange(of: controller.wantsInspector) { _, wants in
				guard wants else { return }
				controller.wantsInspector = false
				withAnimation(Self.panelAnimation) { showInspector = true }
			}
			.onChange(of: controller.showsLayers) { _, _ in updateInsets() }
			.onChange(of: showInspector) { _, _ in updateInsets() }
	}

	static let panelAnimation = Animation.snappy(duration: 0.28)

	private func updateInsets() {
		let m = Self.panelMargin
		controller.setInsets(
			left: controller.showsLayers ? Self.layersWidth + m * 2 : 0,
			right: showInspector ? Self.inspectorWidth + m * 2 : 0,
			top: 0, bottom: 0)
	}

	// MARK: Editor

	/// The code panel sits beside the viewer. One canvas stays alive in every
	/// layout: it renders the drawing and also reports the element tree the
	/// layers panel and graph are built from.
	private var editor: some View {
		HStack(spacing: 0) {
			if controller.showsCode {
				CodePanel(
					document: document, controller: controller, fontSize: fontSize,
					wrapsLines: wrapsLines, theme: SyntaxTheme.named(themeName)
				)
				.frame(width: codeWidth)
				SplitDivider(width: $codeWidth)
			}
			viewer
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
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
			}
			if controller.layout == .canvas {
				CanvasControls(controller: controller)
					.padding(
						.leading, controller.showsLayers ? Self.layersWidth + Self.panelMargin : 0
					)
					.padding(.trailing, showInspector ? Self.inspectorWidth + Self.panelMargin : 0)
			}
		}
		.overlay(alignment: .topLeading) {
			if controller.showsLayers {
				FloatingPanel(title: "Layers", close: { controller.showsLayers = false }) {
					LayersPanel(controller: controller)
				}
				.frame(width: Self.layersWidth)
				.padding(Self.panelMargin)
				.transition(.move(edge: .leading).combined(with: .opacity))
			}
		}
		.overlay(alignment: .topTrailing) {
			if showInspector {
				FloatingPanel(title: nil, close: { showInspector = false }) {
					InspectorView(controller: controller)
				}
				.frame(width: Self.inspectorWidth)
				.padding(Self.panelMargin)
				.transition(.move(edge: .trailing).combined(with: .opacity))
			}
		}
		.animation(Self.panelAnimation, value: controller.showsLayers)
		.animation(Self.panelAnimation, value: showInspector)
	}

	private var canvas: some View {
		CanvasView(
			text: document.text, background: background, customColour: customColour,
			controller: controller
		)
		.overlay {
			if controller.layout == .canvas {
				CanvasControls(controller: controller)
			}
		}
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
	// Grouped by function (HIG › Toolbars): what the window shows, then
	// insertion, arrangement and zoom; sharing and the inspector stay on the
	// trailing edge. Every item is also in the menu bar.

	@ToolbarContentBuilder
	private var toolbar: some CustomizableToolbarContent {
		viewItems
		editingItems
		trailingItems
	}

	@ToolbarContentBuilder
	private var viewItems: some CustomizableToolbarContent {
		ToolbarItem(id: "view", placement: .navigation) {
			ControlGroup {
				Toggle(isOn: $controller.showsLayers) {
					Label("Layers", systemImage: "square.3.layers.3d")
				}
				.help(controller.showsLayers ? "Hide Layers" : "Show Layers")
				Toggle(isOn: $controller.showsCode) {
					Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
				}
				.help(controller.showsCode ? "Hide Code" : "Show Code")
				Toggle(
					isOn: Binding(
						get: { controller.layout == .graph },
						set: { controller.layout = $0 ? .graph : .canvas }
					)
				) {
					Label("Graph", systemImage: EditorLayout.graph.symbol)
				}
				.help(controller.layout == .graph ? "Show Canvas" : "Show Element Graph")
			} label: {
				Label("View", systemImage: "rectangle.3.group")
			}
		}
		.customizationBehavior(.disabled)

		ToolbarSpacer(.flexible)
	}

	@ToolbarContentBuilder
	private var editingItems: some CustomizableToolbarContent {
		ToolbarItem(id: "insert") {
			Button("Insert", systemImage: "plus") { showsInsert.toggle() }
				.help("Insert a shape, text or image")
				.popover(isPresented: $showsInsert, arrowEdge: .bottom) {
					InsertPalette(controller: controller) { showsInsert = false }
				}
		}

		ToolbarSpacer(.fixed)

		ToolbarItem(id: "arrange") {
			ExpandingControl(
				title: "Arrange", systemImage: "square.3.layers.3d.middle.filled",
				isExpanded: $arrangeExpanded
			) {
				Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") {
					controller.reorder(.front)
				}
				Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
					controller.reorder(.forward)
				}
				Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
					controller.reorder(.backward)
				}
				Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") {
					controller.reorder(.back)
				}
				Button("Group", systemImage: "square.on.square.dashed") {
					controller.groupSelection()
				}
				Button("Ungroup", systemImage: "square.on.square.intersection.dashed") {
					controller.ungroupSelection()
				}
				.disabled(controller.selection?.tag != "g")
			}
			.disabled(!controller.hasElementSelection)
		}
	}

	@ToolbarContentBuilder
	private var trailingItems: some CustomizableToolbarContent {
		ToolbarSpacer(.flexible)

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
			.help("Export or share the drawing")
		}

		ToolbarItem(id: "inspector", placement: .primaryAction) {
			Button(
				showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing"
			) {
				showInspector.toggle()
			}
			.help(showInspector ? "Hide Inspector" : "Show Inspector")
		}
		.customizationBehavior(.disabled)
	}
}
