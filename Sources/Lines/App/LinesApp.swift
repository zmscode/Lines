import AppKit
import SwiftUI

@main
struct LinesApp: App {
	@NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

	var body: some Scene {
		// Shown at launch and when the Dock icon is clicked with no windows open,
		// in place of the Open panel.
		Window("Welcome to Lines", id: WelcomeView.windowID) {
			WelcomeView()
		}
		.defaultLaunchBehavior(.presented)
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		.restorationBehavior(.disabled)
		.keyboardShortcut("1", modifiers: [.command, .shift])

		DocumentGroup { document in
			ContentView(document: document)
		} makeDocument: { configuration, _ in
			let document = SVGDocument()
			document.configuration = configuration
			return document
		}
		.defaultSize(width: 1280, height: 860)
		// The document title sits in line with the toolbar buttons.
		.windowToolbarStyle(.unified)
		.commands {
			FileCommands()
			EditCommands()
			ViewCommands()
			InsertCommands()
			ArrangeCommands()
		}

		Settings {
			SettingsView()
		}
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationWillFinishLaunching(_ notification: Notification) {
		AppAppearance.applySaved()
		// Tooltips appear after a short pause instead of AppKit's default second or so.
		UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])
	}

	// The welcome window replaces the untitled document AppKit would otherwise open.
	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Menu bar
//
// Per the HIG, every toolbar item is also available from the menu bar, menu
// items carry symbols, and standard shortcuts keep their standard meanings.

private struct FileCommands: Commands {
	@FocusedValue(CanvasController.self) private var controller

	var body: some Commands {
		CommandGroup(replacing: .printItem) {
			Button("Print…", systemImage: "printer") { controller?.printDrawing() }
				.keyboardShortcut("p", modifiers: .command)
				.disabled(controller == nil)
		}
		CommandGroup(after: .importExport) {
			Button("Export…", systemImage: "square.and.arrow.down") {
				controller?.isExporting = true
			}
			.keyboardShortcut("e", modifiers: [.command, .shift])
			.disabled(controller == nil)
		}
	}
}

private struct EditCommands: Commands {
	@FocusedValue(CanvasController.self) private var controller

	var body: some Commands {
		CommandGroup(after: .textEditing) {
			Button("Format Document", systemImage: "text.alignleft") {
				controller?.formatDocument()
			}
			.keyboardShortcut("i", modifiers: .control)
			.disabled(controller == nil)
		}
		CommandGroup(after: .pasteboard) {
			Button("Duplicate", systemImage: "plus.square.on.square") {
				controller?.duplicateSelection()
			}
			.keyboardShortcut("d", modifiers: .command)
			.disabled(controller?.hasElementSelection != true)
			Button("Deselect All") { controller?.deselect() }
				.keyboardShortcut("a", modifiers: [.command, .shift])
				.disabled(controller?.hasElementSelection != true)
		}
	}
}

private struct ViewCommands: Commands {
	@FocusedValue(CanvasController.self) private var controller
	@AppStorage("canvasBackground") private var background: CanvasBackground = .checkerboard

	var body: some Commands {
		CommandGroup(before: .toolbar) {
			Button(
				controller?.showsLayers == true ? "Hide Layers" : "Show Layers",
				systemImage: "square.3.layers.3d"
			) {
				controller?.showsLayers.toggle()
			}
			.keyboardShortcut("1", modifiers: .command)
			Button(
				controller?.showsCode == true ? "Hide Code" : "Show Code",
				systemImage: "chevron.left.forwardslash.chevron.right"
			) {
				controller?.showsCode.toggle()
			}
			.keyboardShortcut("2", modifiers: .command)
			Button(
				controller?.showsInspector == true ? "Hide Inspector" : "Show Inspector",
				systemImage: "slider.horizontal.3"
			) {
				controller?.showsInspector.toggle()
			}
			.keyboardShortcut("i", modifiers: [.command, .option])
			Button(
				controller?.layout == .graph ? "Show Canvas" : "Show Element Graph",
				systemImage: controller?.layout == .graph
					? EditorLayout.canvas.symbol : EditorLayout.graph.symbol
			) {
				controller?.layout = controller?.layout == .graph ? .canvas : .graph
			}
			.keyboardShortcut("3", modifiers: .command)
			.disabled(controller == nil)
			Button(
				controller?.isEditing == false ? "Unlock Editing" : "Lock Editing",
				systemImage: controller?.isEditing == false ? "lock.open" : "lock"
			) {
				controller?.isEditing.toggle()
			}
			.keyboardShortcut("l", modifiers: [.command, .shift])
			.disabled(controller == nil)
			Button(
				controller?.showsTimeline == true ? "Hide Timeline" : "Show Timeline",
				systemImage: "film.stack"
			) {
				controller?.showsTimeline.toggle()
			}
			.keyboardShortcut("4", modifiers: .command)
			.disabled(controller == nil)
			Button(
				controller?.showsChanges == true ? "Hide Changes" : "Show Changes",
				systemImage: "plusminus"
			) {
				controller?.showsChanges.toggle()
			}
			.keyboardShortcut("5", modifiers: .command)
			.disabled(controller?.hasChanges != true)
			Button(
				controller?.isPlaying == true ? "Pause Animations" : "Play Animations",
				systemImage: controller?.isPlaying == true ? "pause" : "play"
			) {
				if controller?.isPlaying == true { controller?.pause() } else { controller?.play() }
			}
			.keyboardShortcut("p", modifiers: [.command, .option])
			.disabled(controller == nil)

			Divider()

			Button("Actual Size", systemImage: "1.magnifyingglass") { controller?.actualSize() }
				.keyboardShortcut("0", modifiers: .command)
			Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
				controller?.zoomToFit()
			}
			.keyboardShortcut("9", modifiers: .command)
			Button("Zoom In", systemImage: "plus.magnifyingglass") { controller?.zoom(by: 1.25) }
				.keyboardShortcut("+", modifiers: .command)
			Button("Zoom Out", systemImage: "minus.magnifyingglass") { controller?.zoom(by: 0.8) }
				.keyboardShortcut("-", modifiers: .command)

			Divider()

			Picker("Canvas Background", selection: $background) {
				ForEach(CanvasBackground.allCases) { Text($0.title).tag($0) }
			}

			Divider()
		}
	}
}

private struct InsertCommands: Commands {
	@FocusedValue(CanvasController.self) private var controller

	var body: some Commands {
		CommandMenu("Insert") {
			ForEach(ShapeKind.allCases) { kind in
				Button(kind.title, systemImage: kind.symbol) { controller?.addShape(kind) }
			}
			.disabled(controller == nil)
		}
	}
}

private struct ArrangeCommands: Commands {
	@FocusedValue(CanvasController.self) private var controller

	var body: some Commands {
		// Shortcuts match Keynote, Pages and Freeform. Command-[ and Command-]
		// are reserved for alignment, so they aren't used for ordering.
		CommandMenu("Arrange") {
			Group {
				Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") {
					controller?.reorder(.front)
				}
				.keyboardShortcut("f", modifiers: [.command, .shift])
				Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
					controller?.reorder(.forward)
				}
				.keyboardShortcut("f", modifiers: [.command, .option, .shift])
				Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
					controller?.reorder(.backward)
				}
				.keyboardShortcut("b", modifiers: [.command, .option, .shift])
				Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") {
					controller?.reorder(.back)
				}
				.keyboardShortcut("b", modifiers: [.command, .shift])
				Divider()
				Button("Group", systemImage: "square.on.square.dashed") {
					controller?.groupSelection()
				}
				.keyboardShortcut("g", modifiers: [.command, .option])
				Button("Ungroup") { controller?.ungroupSelection() }
					.keyboardShortcut("g", modifiers: [.command, .option, .shift])
					.disabled(controller?.selection?.tag != "g")
				Divider()
				Button("Select Enclosing Group", systemImage: "arrow.up.square") {
					controller?.selectParent()
				}
				.keyboardShortcut(.upArrow, modifiers: [.command, .option])
			}
			.disabled(controller?.hasElementSelection != true)
		}
	}
}
