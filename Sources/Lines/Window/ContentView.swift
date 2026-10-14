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

	var body: some View {
		NavigationSplitView(
			columnVisibility: Binding(
				get: { controller.showsLayers ? .all : .detailOnly },
				set: { controller.showsLayers = $0 != .detailOnly }
			)
		) {
			LayersSidebar(controller: controller)
				.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 380)
				.toolbar(removing: .sidebarToggle)
		} detail: {
			editor
		}
		.background(WindowTransparency(isTransparent: isTransparent))
		// A see-through window would otherwise take the toolbar with it.
		.toolbarBackgroundVisibility(isTransparent ? .visible : .automatic, for: .windowToolbar)
		.inspector(isPresented: $showInspector) {
			InspectorView(controller: controller)
				.inspectorColumnWidth(min: 240, ideal: 280, max: 420)
		}
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
		}
		.onChange(of: undoManager) { _, new in controller.undoManager = new }
	}

	// MARK: Editor

	/// The code panel sits beside the main view. One canvas stays alive in
	/// every layout: it renders the drawing and also reports the element tree
	/// the layers list and graph are built from.
	///
	/// This is a SwiftUI split rather than `HSplitView`: next to the inspector,
	/// AppKit's split view could fall into an endless constraint-update loop
	/// (and abort) when it held the canvas alone.
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
			mainArea
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private var mainArea: some View {
		ZStack {
			canvas
				.opacity(controller.layout == .graph ? 0 : 1)
				.allowsHitTesting(controller.layout == .canvas)
				.accessibilityHidden(controller.layout == .graph)
			if controller.layout == .graph {
				GraphView(controller: controller)
			}
		}
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
