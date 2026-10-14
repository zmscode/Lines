import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The WebKit-backed canvas. WebKit renders SVG faithfully (filters, text,
/// masks, CSS); this subclass routes the standard Edit menu actions through
/// the responder chain to the selected element.
final class CanvasWebView: WKWebView {
	weak var controller: CanvasController?

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/// The cursor position in the page's viewport coordinates.
	private func viewportPoint(_ event: NSEvent) -> CGPoint {
		let p = convert(event.locationInWindow, from: nil)
		return CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
	}

	// A mouse wheel zooms around the cursor. Trackpads keep two-finger
	// scrolling, as everywhere else on the Mac; Command-scroll zooms on both.
	override func scrollWheel(with event: NSEvent) {
		let isMouseWheel = !event.hasPreciseScrollingDeltas
		guard isMouseWheel || event.modifierFlags.contains(.command) else {
			super.scrollWheel(with: event)
			return
		}
		let delta = event.scrollingDeltaY * (isMouseWheel ? 10 : 1)
		guard delta != 0 else { return }
		controller?.zoom(by: pow(1.0015, delta), at: viewportPoint(event))
	}

	override func magnify(with event: NSEvent) {
		controller?.zoom(by: 1 + event.magnification, at: viewportPoint(event))
	}

	// Two-finger double-tap toggles between Zoom to Fit and Actual Size, like Preview.
	override func smartMagnify(with event: NSEvent) {
		controller?.toggleSmartZoom(at: viewportPoint(event))
	}

	// Keep the context menu to what makes sense for a document canvas.
	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		menu.items.removeAll { item in
			let id = item.identifier?.rawValue ?? ""
			return id.contains("Reload") || id.contains("Back") || id.contains("Forward")
		}
		super.willOpenMenu(menu, with: event)
	}

	// MARK: Edit menu

	@objc func copy(_ sender: Any?) {
		Task { await copyToPasteboard() }
	}

	@objc func cut(_ sender: Any?) {
		Task {
			if await copyToPasteboard() { controller?.deleteSelection() }
		}
	}

	@objc func paste(_ sender: Any?) {
		let pasteboard = NSPasteboard.general
		let markup =
			pasteboard.string(forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
			?? pasteboard.string(forType: .string)
		guard let markup, markup.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
		else {
			NSSound.beep()
			return
		}
		controller?.paste(markup: markup)
	}

	@objc func delete(_ sender: Any?) {
		controller?.deleteSelection()
	}

	@discardableResult
	private func copyToPasteboard() async -> Bool {
		guard let markup = await controller?.copySelection() else { return false }
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(markup, forType: .string)
		pasteboard.setString(markup, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
		return true
	}

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		switch item.action {
		case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
			return controller?.hasElementSelection == true
		case #selector(paste(_:)):
			return NSPasteboard.general.string(forType: .string) != nil
		default:
			return super.validateUserInterfaceItem(item)
		}
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		controller?.setAccentColor(NSColor(Brand.accent))
	}
}

struct CanvasView: NSViewRepresentable {
	var text: String
	var background: CanvasBackground
	var customColour: String
	var controller: CanvasController

	func makeNSView(context: Context) -> CanvasWebView {
		let config = WKWebViewConfiguration()
		config.userContentController.add(WeakMessageHandler(controller), name: "bridge")
		let webView = CanvasWebView(frame: .zero, configuration: config)
		webView.controller = controller
		webView.underPageBackgroundColor = .clear
		webView.setValue(false, forKey: "drawsBackground")
		webView.setAccessibilityLabel("Canvas")
		controller.webView = webView
		webView.loadHTMLString(CanvasHTML.page, baseURL: nil)
		return webView
	}

	func updateNSView(_ webView: CanvasWebView, context: Context) {
		controller.render(text)
		let look = "\(background.rawValue) \(customColour)"
		if context.coordinator.look != look {
			context.coordinator.look = look
			controller.setBackground(background)
		}
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	final class Coordinator {
		var look: String?
	}

	static func dismantleNSView(_ webView: CanvasWebView, coordinator: Coordinator) {
		webView.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
	}
}
