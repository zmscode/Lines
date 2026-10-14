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
	var layout: EditorLayout = .canvas {
		didSet { if layout != oldValue { call("setCanvasBehind(\(layout == .outline))") } }
	}
	var showsCode = false
	var showsLayers = false
	var showsInspector = false {
		didSet { if showsInspector != oldValue { call("setInspectorOpen(\(showsInspector))") } }
	}
	var tool: CanvasTool = .select
	var showsTimeline = false
	/// The changes panel, comparing the source with `originalText`.
	var showsChanges = false
	/// The source as the window opened it.
	var originalText: String? {
		didSet {
			if history.isEmpty, let originalText {
				history = [Snapshot(text: originalText, title: "Opened", date: .now)]
			}
		}
	}

	/// One version of the source in this window's history, like a commit.
	struct Snapshot: Identifiable, Equatable {
		let id = UUID()
		var text: String
		var title: String
		var date: Date
		var added = 0
		var removed = 0
		/// A short, git-style id for the version's text.
		var shortID: String { Self.shortID(of: text) }

		/// FNV-1a over the text, as seven hex digits.
		static func shortID(of text: String) -> String {
			var hash: UInt32 = 2_166_136_261
			for byte in text.utf8 {
				hash ^= UInt32(byte)
				hash = hash &* 16_777_619
			}
			return String(String(format: "%08x", hash).prefix(7))
		}
	}

	/// Versions of the source since the window opened, oldest first.
	var history: [Snapshot] = []
	/// The version being shown on the canvas while scrubbing the history.
	private(set) var previewedVersion: Snapshot.ID?

	/// Starts the history over from `text`, as the file was opened.
	func resetHistory(to text: String) {
		originalText = text
		history = [Snapshot(text: text, title: "Opened", date: .now)]
		previewedVersion = nil
	}

	/// Records the source as a new version if it changed.
	func recordVersion(_ text: String, title: String?) {
		guard let last = history.last, last.text != text else { return }
		let diff = LineDiff(from: last.text, to: text)
		history.append(
			Snapshot(
				text: text, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Edit", date: .now,
				added: diff.added, removed: diff.removed))
		if history.count > 300 { history.remove(at: 1) }  // keep "Opened"
	}

	/// Shows an older version on the canvas (locked while shown); nil returns
	/// to the document.
	func preview(version id: Snapshot.ID?) {
		guard id != previewedVersion else { return }
		previewedVersion = id
		if let id, let snapshot = history.first(where: { $0.id == id }),
			snapshot.id != history.last?.id
		{
			call("setEditable(false)")
			renderedText = nil
			call("setSVG(\(js(snapshot.text)))")
		} else {
			previewedVersion = nil
			call("setEditable(\(isEditing))")
			renderedText = nil
			if let text = document?.text { render(text) }
		}
	}
	/// Whether the source differs from how it was opened.
	var hasChanges: Bool {
		guard let originalText, let document else { return false }
		return document.text != originalText
	}
	/// The animation playhead, in seconds, and whether animations are playing.
	var animationTime: Double = 0
	var isPlaying = false
	/// Off in preview mode: the drawing can be viewed but not changed.
	var isEditing = true {
		didSet { if isEditing != oldValue { call("setEditable(\(isEditing))") } }
	}
	/// Playback rate for previewing animations (SMIL itself has none).
	var animationSpeed: Double = 1 {
		didSet { call("animSetSpeed(\(animationSpeed))") }
	}
	var isExporting = false
	/// Set when someone double-clicks an element that has no in-place editing.
	var wantsInspector = false
	@ObservationIgnored private var lastInsets = ""
	@ObservationIgnored private var documentFrameShown = false

	/// Re-indents the source as one undoable step.
	func formatDocument() {
		guard let document, isEditing else { return }
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
		// An older version is on show while the history is scrubbed.
		guard text != renderedText, previewedVersion == nil else { return }
		renderedText = text
		call("setSVG(\(js(text)))")
	}

	func setBackground(_ background: CanvasBackground) {
		call(
			"setBackground(\(js(background.rawValue)), \(js(CanvasBackground.customColour)), \(CanvasBackground.drawingOnly))"
		)
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
	/// Mirrors the selection across its centre.
	func flipSelection(horizontally: Bool) { call("flipSelected(\(js(horizontally ? "h" : "v")))") }
	func paste(markup: String) { call("pasteMarkup(\(js(markup)))") }
	func toggleHidden(order: Int) { call("toggleHidden(\(order))") }

	enum DropPosition: String { case before, after, inside }

	/// Moves layers relative to another, in document order.
	func move(orders: [Int], relativeTo target: Int, position: DropPosition) {
		call("moveRelative(\(orders), \(target), \(js(position.rawValue)))")
	}

	/// Exact position, size or rotation from the inspector. Pass nil to keep a value.
	func setBounds(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil)
	{
		func arg(_ v: Double?) -> String { v.map { "\($0)" } ?? "null" }
		call("setBounds(\(arg(x)), \(arg(y)), \(arg(width)), \(arg(height)))")
	}
	func setRotation(_ degrees: Double) { call("setRotation(\(degrees))") }

	enum Definition: String, CaseIterable, Identifiable {
		case linearGradient, radialGradient, pattern, clipPath, mask, blur, shadow
		var id: String { rawValue }
		var title: String {
			switch self {
			case .linearGradient: String(localized: "Linear Gradient")
			case .radialGradient: String(localized: "Radial Gradient")
			case .pattern: String(localized: "Pattern")
			case .clipPath: String(localized: "Clip Path")
			case .mask: String(localized: "Mask")
			case .blur: String(localized: "Blur")
			case .shadow: String(localized: "Drop Shadow")
			}
		}
		var symbol: String {
			switch self {
			case .linearGradient: "circle.lefthalf.filled"
			case .radialGradient: "circle.circle"
			case .pattern: "circle.grid.3x3.fill"
			case .clipPath: "scissors"
			case .mask: "theatermasks"
			case .blur: "drop"
			case .shadow: "shadow"
			}
		}
	}

	func addDefinition(_ kind: Definition, applyingTo order: Int? = nil) {
		call("addDefinition(\(js(kind.rawValue)), \(order.map(String.init) ?? "null"))")
	}
	func removeAllReferences(order: Int) { call("removeAllReferences(\(order))") }
	func addStop(toGradient order: Int) { call("addStop(\(order))") }
	/// Adds a rectangle or circle to a mask or clip path.
	func addShape(_ kind: String, toDefinition order: Int) {
		call("addDefinitionShape(\(order), \(js(kind)))")
	}
	func invertMask(order: Int) { call("invertMask(\(order))") }
	/// Deletes gradients, clips, masks, filters, patterns and symbols nothing uses.
	func removeUnusedDefinitions() { call("removeUnusedDefinitions()") }

	/// A clip path or mask being edited on the canvas: its kind and name.
	var definitionEdit: (kind: String, name: String)?
	/// Shows a clip path's or mask's shapes over the element that uses it, to edit directly.
	func editOnCanvas(definition order: Int) {
		layout = .canvas
		call("editDefinitionOnCanvas(\(order))")
	}
	func endDefinitionEdit() { call("endDefinitionEdit(true)") }
	/// Corner radii for the selected rectangle: top left, top right, bottom right, bottom left.
	func setCornerRadii(_ radii: [Double]) {
		guard radii.count == 4 else { return }
		call("setCornerRadii(\(radii.map { "\($0)" }.joined(separator: ", ")))")
	}

	// MARK: Animation

	var animations: [AnimationInfo] { AnimationInfo.all(in: outline) }

	func play() { call("animPlay()") }
	func pause() { call("animPause()") }
	/// Pauses and returns to the start.
	func stop() { call("animStop()") }
	func seek(to seconds: Double) { call("animSeek(\(seconds))") }
	func addAnimation(_ preset: AnimationPreset, toOrder order: Int) {
		call("addAnimation(\(order), \(js(preset.rawValue)))")
	}
	func setTimelineActive(_ on: Bool) { call("setTimelineActive(\(on))") }

	func setTool(_ newTool: CanvasTool) {
		tool = newTool
		call("setTool(\(js(newTool.rawValue)))")
	}
	func fitViewBoxToContent() { call("fitViewBoxToContent()") }

	/// Edits an attribute on any element (by order) without selecting it; nil removes it.
	func setAttribute(_ name: String, _ value: String?, onOrder order: Int, coalesce: Bool = false)
	{
		call("setAttrOn(\(order), \(js(name)), \(value.map(js) ?? "null"), \(coalesce))")
	}

	/// Outlines the document with resize handles (while the inspector shows it).
	func setDocumentFrame(_ shown: Bool) {
		guard shown != documentFrameShown else { return }
		documentFrameShown = shown
		call("showDocumentFrame(\(shown))")
	}

	/// Space covered by floating panels, so fitting and centring use what's left.
	@ObservationIgnored private var minimapShift: CGFloat = -1
	/// Moves the canvas minimap right, clear of controls at the lower left.
	func setMinimapShift(_ shift: CGFloat) {
		guard shift != minimapShift else { return }
		minimapShift = shift
		call("setMinimapShift(\(shift))")
	}

	func setInsets(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
		let key = "\(left), \(right), \(top), \(bottom)"
		guard key != lastInsets else { return }
		lastInsets = key
		call("setInsets(\(key))")
	}
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

	/// View › Zoom In/Out/Actual Size act on whichever has focus: the code
	/// editor's text size, or the canvas.
	func zoom(by factor: CGFloat) {
		if sourceEditor?.isFocused == true {
			SourceEditor.adjustFontSize(by: factor > 1 ? 1 : -1)
		} else {
			setZoom(zoom * factor)
		}
	}

	func actualSize() {
		if sourceEditor?.isFocused == true { SourceEditor.setFontSize(12) } else { setZoom(1) }
	}

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
	/// Opens SVG files in their own windows; set by the window.
	@ObservationIgnored var openDocuments: (([URL]) -> Void)?

	/// Files dropped on the viewer: SVGs open in new windows, images are placed
	/// in the drawing. Returns whether anything was used.
	@discardableResult
	func handleDroppedFiles(_ urls: [URL]) -> Bool {
		let svgs = urls.filter(Self.isSVG)
		let images = urls.filter { url in
			!Self.isSVG(url)
				&& (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false)
		}
		if !svgs.isEmpty { openDocuments?(svgs) }
		for url in images { addImage(from: url) }
		return !svgs.isEmpty || !images.isEmpty
	}

	static func isSVG(_ url: URL) -> Bool {
		(try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .svg)
			?? (url.pathExtension.lowercased() == "svg")
	}

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
	/// Bumped when the drawing changes, so layer thumbnails redraw.
	private(set) var thumbnailGeneration = 0
	@ObservationIgnored private var thumbnailCache: [Int: NSImage] = [:]

	/// An element drawn on its own, framed to its box, for layer rows.
	func thumbnail(order: Int, size: Double = 64) async -> NSImage? {
		if let cached = thumbnailCache[order] { return cached }
		guard isReady, let webView,
			let result = try? await webView.callAsyncJavaScript(
				"return await elementThumbnail(order, size)",
				arguments: ["order": order, "size": size], contentWorld: .page),
			let url = result as? String, let comma = url.firstIndex(of: ","),
			let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
			let image = NSImage(data: data)
		else { return nil }
		thumbnailCache[order] = image
		return image
	}

	/// How a resource or element changes the drawing: labelled pictures (without/with a
	/// definition, an animation's frames, or an element in place).
	func impactPreview(order: Int, size: Double = 200) async -> [(label: String, image: NSImage)] {
		guard isReady, let webView,
			let result = try? await webView.callAsyncJavaScript(
				"return await impactPreview(order, size)",
				arguments: ["order": order, "size": size], contentWorld: .page),
			let dict = result as? [String: Any],
			let labels = dict["labels"] as? [String], let urls = dict["images"] as? [Any]
		else { return [] }
		return zip(labels, urls).compactMap { label, value in
			guard let url = value as? String, let comma = url.firstIndex(of: ","),
				let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
				let image = NSImage(data: data)
			else { return nil }
			return (label, image)
		}
	}

	/// A small picture of an element on its own, or a sample shape using a
	/// definition, for the graph's hover previews.
	func previewImage(order: Int, size: Double = 180) async -> NSImage? {
		guard isReady, let webView,
			let result = try? await webView.callAsyncJavaScript(
				"return await previewImage(order, size)",
				arguments: ["order": order, "size": size], contentWorld: .page),
			let url = result as? String, let comma = url.firstIndex(of: ","),
			let data = Data(base64Encoded: String(url[url.index(after: comma)...]))
		else { return nil }
		return NSImage(data: data)
	}

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
			setAccentColor(NSColor(Brand.accent))
			if !lastInsets.isEmpty { call("setInsets(\(lastInsets))") }
			if minimapShift > 0 { call("setMinimapShift(\(minimapShift))") }
			if documentFrameShown { call("showDocumentFrame(true)") }
			if !isEditing { call("setEditable(false)") }
			if layout == .outline { call("setCanvasBehind(true)") }
			if showsInspector { call("setInspectorOpen(true)") }

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
					fill: d["fill"] as? String, references: refs,
					preview: d["preview"] as? [String],
					props: d["props"] as? [String: String] ?? [:],
					cssAnimations: (d["css"] as? [[String: Any]] ?? []).map { a in
						let iterations = (a["iterations"] as? Double) ?? 1
						return OutlineItem.CSSAnimation(
							name: a["name"] as? String ?? "animation",
							properties: a["props"] as? [String] ?? [],
							duration: a["duration"] as? Double ?? 0,
							delay: a["delay"] as? Double ?? 0,
							iterations: iterations < 0 ? nil : iterations,
							easing: a["easing"] as? String ?? "linear")
					},
					box: (d["box"] as? [Double]).flatMap {
						$0.count == 4
							? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil
					}
				)
			}
			if items != outline {
				outline = items
				// Thumbnails redraw after any change to the drawing.
				thumbnailCache.removeAll()
				thumbnailGeneration += 1
			}
			webView?.setAccessibilityValue(
				"\(documentName), \(items.count) element\(items.count == 1 ? "" : "s")")
			webView?.setAccessibilityHelp(
				"Use the Layers panel (⌘1) to move through the elements, and the inspector to change them."
			)
			outlineTruncated = body["truncated"] as? Bool ?? false

		case "definitionEdit":
			definitionEdit =
				body["active"] as? Bool == true
				? (body["kind"] as? String ?? "clipPath", body["name"] as? String ?? "")
				: nil

		case "openLink":
			// ⌘-click on a link in preview mode; only web and mail links leave the app.
			if let string = body["url"] as? String, let url = URL(string: string),
				let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
			{
				NSWorkspace.shared.open(url)
			}

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
			let b = body["bounds"] as? [Double]
			let info = SelectionInfo(
				path: path, order: order, tag: tag, attributes: attributes,
				textContent: body["text"] as? String,
				bounds: b.flatMap {
					$0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil
				},
				rotation: body["rotation"] as? Double ?? 0,
				count: body["count"] as? Int ?? 1
			)
			let moved = selection?.order != order
			// VoiceOver hears what got selected on the canvas.
			if moved, NSWorkspace.shared.isVoiceOverEnabled, !info.isRoot {
				let name =
					outline.first(where: { $0.order == order })?.displayName
					?? InspectorView.elementName(for: tag)
				NSAccessibility.post(
					element: NSApp.mainWindow as Any, notification: .announcementRequested,
					userInfo: [
						.announcement: info.count > 1
							? "\(info.count) selected" : "Selected \(name)",
						.priority: NSAccessibilityPriorityLevel.medium.rawValue,
					])
			}
			if selection != info { selection = info }
			if moved, !info.isRoot, body["fromSource"] as? Bool != true {
				sourceEditor?.revealElement(order: order)
			}

		case "time":
			if let t = body["t"] as? Double { animationTime = t }
			isPlaying = body["playing"] as? Bool ?? isPlaying

		case "tool":
			if let name = body["tool"] as? String, let t = CanvasTool(rawValue: name) { tool = t }

		case "editElement":
			wantsInspector = true

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
