import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Owns the bridge between SwiftUI, the canvas web view and the source editor
/// for a single document window.
@MainActor
@Observable
final class CanvasController {
	var selection: SelectionInfo?
	var parseError: String?
	var zoom: CGFloat = 1
	var layout: EditorLayout = .canvas
	var showsCode = false
	var showsLayers = false
	var isExporting = false

	/// Re-indents the source as one undoable step.
	func formatDocument() {
		guard let document else { return }
		let formatted = XMLFormatter.format(document.text)
		guard formatted != document.text else { return }
		document.breakUndoCoalescing()
		document.replaceText(with: formatted, actionName: "Format", undoManager: undoManager)
	}

	var outline: [OutlineItem] = []
	var outlineTruncated = false

	var hasElementSelection: Bool { selection.map { !$0.isRoot } ?? false }

	@ObservationIgnored weak var webView: WKWebView?
	@ObservationIgnored weak var sourceEditor: SourceEditor.Coordinator?
	@ObservationIgnored weak var undoManager: UndoManager?
	@ObservationIgnored weak var document: SVGDocument?

	/// The last text known to be rendered by the canvas; avoids reload loops.
	@ObservationIgnored private var renderedText: String?
	@ObservationIgnored private var isReady = false

	// MARK: Swift -> JS

	func render(_ text: String) {
		guard text != renderedText else { return }
		renderedText = text
		call("setSVG(\(js(text)))")
	}

	func setBackground(_ background: CanvasBackground) {
		call("setBackground(\(js(background.rawValue)), \(js(CanvasBackground.customColour)))")
	}

	func setAccentColor(_ color: NSColor) {
		guard let c = color.usingColorSpace(.sRGB) else { return }
		let css =
			"rgb(\(Int(c.redComponent * 255)), \(Int(c.greenComponent * 255)), \(Int(c.blueComponent * 255)))"
		call("setAccent(\(js(css)))")
	}

	func select(order: Int) { call("selectByOrder(\(order), true)") }
	func selectParent() { call("selectParent()") }
	func deselect() { call("select(null)") }
	func setAttribute(_ name: String, _ value: String, coalesce: Bool = false) {
		call("setAttr(\(js(name)), \(js(value)), \(coalesce))")
	}
	func setPaint(_ name: String, color: String, opacity: Double?, coalesce: Bool) {
		call(
			"setPaint(\(js(name)), \(js(color)), \(opacity.map { "\($0)" } ?? "null"), \(coalesce))"
		)
	}
	func removeAttribute(_ name: String) { call("removeAttr(\(js(name)))") }
	func setTextContent(_ text: String) { call("setText(\(js(text)))") }
	func addShape(_ kind: ShapeKind) { call("addShape(\(js(kind.rawValue)))") }
	func deleteSelection() { call("deleteSelected()") }
	func duplicateSelection() { call("duplicateSelected()") }
	func reorder(_ mode: ReorderMode) { call("reorder(\(js(mode.rawValue)))") }
	func groupSelection() { call("groupSelected()") }
	func ungroupSelection() { call("ungroupSelected()") }
	func paste(markup: String) { call("pasteMarkup(\(js(markup)))") }
	func toggleHidden(order: Int) { call("toggleHidden(\(order))") }
	func move(orders: [Int], intoParent parent: Int, after: Int?) {
		call("moveElements(\(orders), \(parent), \(after.map(String.init) ?? "null"))")
	}
	func hover(order: Int?) { call("hoverOrder(\(order.map(String.init) ?? "null"))") }
	func rename(order: Int, to name: String) { call("renameElement(\(order), \(js(name)))") }

	func markup(order: Int) async -> String? {
		guard isReady, let webView else { return nil }
		return try? await webView.evaluateJavaScript("copyByOrder(\(order))") as? String
	}
	func delete(order: Int) { call("deleteByOrder(\(order))") }
	func setReference(order: Int, attribute: String, targetOrder: Int) {
		call("setReference(\(order), \(js(attribute)), \(targetOrder))")
	}
	func removeReference(order: Int, attribute: String) {
		call("removeReference(\(order), \(js(attribute)))")
	}

	func copySelection() async -> String? {
		guard isReady, let webView else { return nil }
		return try? await webView.evaluateJavaScript("copySelected()") as? String
	}

	/// Whether the canvas is tracking the window size (Zoom to Fit).
	var isFitted = true

	func zoom(by factor: CGFloat) { setZoom(zoom * factor) }

	func zoom(by factor: CGFloat, at point: CGPoint) {
		call("zoomBy(\(factor), \(point.x), \(point.y))")
	}

	func setZoom(_ value: CGFloat) { call("setZoom(\(value))") }

	func zoomToFit() { call("zoomToFit()") }

	func toggleSmartZoom(at point: CGPoint) {
		if isFitted { call("setZoom(1, \(point.x), \(point.y))") } else { zoomToFit() }
	}

	func exportPNG(scale: Int = 2) { call("exportPNG(\(scale))") }

	func printDrawing() {
		Exporter.print(text: document?.text ?? "", name: documentName, window: webView?.window)
	}

	/// Embeds an image file, fitted inside the drawing.
	func addImage(from url: URL) {
		guard let data = try? Data(contentsOf: url), let image = NSImage(data: data),
			let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
		else {
			NSSound.beep()
			return
		}
		let dataURL = "data:\(type);base64,\(data.base64EncodedString())"
		call("addImage(\(js(dataURL)), \(image.size.width), \(image.size.height))")
	}

	/// The drawing's size in its own units, for the export sheet.
	func drawingSize() async -> CGSize? {
		guard isReady, let webView,
			let size = try? await webView.evaluateJavaScript("drawingSize()") as? [String: Double],
			let w = size["w"], let h = size["h"]
		else { return nil }
		return CGSize(width: w, height: h)
	}

	/// Renders the drawing with WebKit, the same renderer as the canvas.
	func rasterize(scale: Double, background: String?, type: UTType, quality: Double = 0.92)
		async throws -> Data
	{
		guard isReady, let webView else { throw CocoaError(.fileWriteUnknown) }
		let mime = type == .jpeg ? "image/jpeg" : "image/png"
		let result = try await webView.callAsyncJavaScript(
			"return await rasterize(scale, background, type, quality)",
			arguments: [
				"scale": scale, "background": background ?? NSNull(), "type": mime,
				"quality": quality,
			],
			contentWorld: .page
		)
		guard let url = result as? String, let comma = url.firstIndex(of: ","),
			let data = Data(base64Encoded: String(url[url.index(after: comma)...]))
		else { throw CocoaError(.fileWriteUnknown) }
		return data
	}

	var documentName: String {
		document?.configuration?.fileURL?.deletingPathExtension().lastPathComponent
			?? webView?.window?.title ?? "Untitled"
	}

	private func call(_ script: String) {
		guard isReady, let webView else { return }
		webView.evaluateJavaScript(script) { _, error in
			if let error { NSLog("Lines JS error: \(error)") }
		}
	}

	private func js(_ s: String) -> String {
		let data = try! JSONSerialization.data(withJSONObject: [s])
		return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
	}

	// MARK: JS -> Swift

	func handle(message body: [String: Any]) {
		switch body["type"] as? String {
		case "ready":
			isReady = true
			if let text = document?.text {
				renderedText = nil
				render(text)
			}
			setBackground(
				UserDefaults.standard.string(forKey: "canvasBackground")
					.flatMap(CanvasBackground.init(rawValue:)) ?? .checkerboard)
			setAccentColor(.controlAccentColor)

		case "changed":
			guard var svg = body["svg"] as? String, let document else { return }
			// Canvas edits come back as serialized DOM; tidy the markup to match.
			if UserDefaults.standard.object(forKey: "formatsAutomatically") as? Bool ?? true {
				svg = XMLFormatter.format(svg)
			}
			renderedText = svg
			let key = body["coalesce"] as? String
			document.replaceText(
				with: svg, actionName: body["action"] as? String ?? "Edit",
				coalescingKey: key, undoManager: undoManager
			)

		case "zoom":
			if let value = body["value"] as? Double { zoom = value }
			isFitted = body["fit"] as? Bool ?? false

		case "outline":
			let items = (body["items"] as? [[String: Any]] ?? []).compactMap { d -> OutlineItem? in
				guard let order = d["order"] as? Int, let tag = d["tag"] as? String else {
					return nil
				}
				let refs = (d["refs"] as? [[String]] ?? []).compactMap { pair in
					pair.count == 2
						? OutlineItem.Reference(attribute: pair[0], targetID: pair[1]) : nil
				}
				return OutlineItem(
					order: order, parent: d["parent"] as? Int ?? 0, depth: d["depth"] as? Int ?? 0,
					path: d["path"] as? String ?? "\(order)", tag: tag,
					elementID: d["id"] as? String,
					label: d["label"] as? String, isHidden: d["hidden"] as? Bool ?? false,
					fill: d["fill"] as? String, references: refs
				)
			}
			if items != outline { outline = items }
			outlineTruncated = body["truncated"] as? Bool ?? false

		case "error":
			parseError = body["message"] as? String

		case "ok":
			parseError = nil

		case "selection":
			guard let path = body["path"] as? [Int], let tag = body["tag"] as? String else {
				selection = nil
				return
			}
			let attributes = (body["attrs"] as? [[String]] ?? []).compactMap { pair in
				pair.count == 2 ? Attribute(name: pair[0], value: pair[1]) : nil
			}
			let order = body["order"] as? Int ?? 0
			let info = SelectionInfo(
				path: path, order: order, tag: tag, attributes: attributes,
				textContent: body["text"] as? String
			)
			let moved = selection?.order != order
			if selection != info { selection = info }
			if moved, !info.isRoot, body["fromSource"] as? Bool != true {
				sourceEditor?.revealElement(order: order)
			}

		case "png":
			guard let url = body["data"] as? String,
				let comma = url.firstIndex(of: ","),
				let data = Data(base64Encoded: String(url[url.index(after: comma)...]))
			else { return }
			savePNG(data)

		case "pngFailed":
			// WebKit refused to rasterize (for example, a tainted canvas);
			// fall back to AppKit's SVG renderer.
			if let text = renderedText, let image = NSImage(data: Data(text.utf8)),
				let data = rasterize(image, scale: body["scale"] as? Double ?? 2)
			{
				savePNG(data)
			} else {
				NSSound.beep()
			}

		default:
			break
		}
	}

	private func rasterize(_ image: NSImage, scale: Double) -> Data? {
		let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
		guard
			let rep = NSBitmapImageRep(
				bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
				bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
				colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
			)
		else { return nil }
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
		image.draw(in: NSRect(origin: .zero, size: size))
		NSGraphicsContext.restoreGraphicsState()
		return rep.representation(using: .png, properties: [:])
	}

	private func savePNG(_ data: Data) {
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.png]
		panel.canSelectHiddenExtension = true
		let name =
			document?.configuration?.fileURL?.deletingPathExtension().lastPathComponent
			?? webView?.window?.title ?? "Untitled"
		panel.nameFieldStringValue = name + ".png"
		let write: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
		}
		if let window = webView?.window {
			panel.beginSheetModal(for: window, completionHandler: write)
		} else {
			write(panel.runModal())
		}
	}
}
