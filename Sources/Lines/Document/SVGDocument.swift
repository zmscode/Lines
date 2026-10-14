import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// An SVG file, held as source text. The text is the single source of truth:
/// the canvas and the source editor both render from it and write back to it.
@Observable
final class SVGDocument: Document {
	static let readableContentTypes: [UTType] = [.svg]

	var text: String

	/// The open file's location, used for sharing and export names.
	@ObservationIgnored weak var configuration: URLDocumentConfiguration?

	@ObservationIgnored private var coalescingKey: String?
	@ObservationIgnored private var coalescingDate = Date.distantPast

	init(text: String = SVGDocument.template) {
		self.text = text
	}

	// MARK: Reading and writing

	func reader(configuration: sending ReadConfiguration)
		-> sending FileWrapperDocumentReader<String>
	{
		FileWrapperDocumentReader(configuration) { fileWrapper in
			guard let data = fileWrapper.regularFileContents else {
				throw CocoaError(.fileReadCorruptFile)
			}
			if let text = String(data: data, encoding: .utf8) { return text }
			if let text = String(data: data, encoding: .isoLatin1) { return text }
			throw CocoaError(.fileReadInapplicableStringEncoding)
		}
	}

	@MainActor
	func apply(snapshot: sending String, previous: sending String?) async throws {
		text = snapshot
	}

	func writer(configuration: sending WriteConfiguration)
		-> sending FileWrapperDocumentWriter<String>
	{
		FileWrapperDocumentWriter(configuration) { snapshot, _ in
			FileWrapper(regularFileWithContents: Data(snapshot.utf8))
		}
	}

	@MainActor
	func snapshot(contentType: UTType) async throws -> sending String { text }

	// MARK: Undoable edits

	/// Replaces the source and registers a named undo action.
	///
	/// Edits that share a `coalescingKey` within a short interval (typing, or
	/// dragging a color picker) collapse into a single undo step.
	@MainActor
	func replaceText(
		with newText: String, actionName: String, coalescingKey key: String? = nil,
		undoManager: UndoManager?
	) {
		guard newText != text else { return }
		let oldText = text
		let now = Date()
		let coalesce =
			key != nil && key == coalescingKey && now.timeIntervalSince(coalescingDate) < 1.5
		coalescingKey = key
		coalescingDate = now
		text = newText
		guard !coalesce, let undoManager else { return }
		registerUndo(restoring: oldText, actionName: actionName, undoManager: undoManager)
	}

	@MainActor
	private func registerUndo(
		restoring oldText: String, actionName: String, undoManager: UndoManager
	) {
		undoManager.registerUndo(withTarget: self) { document in
			MainActor.assumeIsolated {
				let current = document.text
				document.coalescingKey = nil
				document.text = oldText
				document.registerUndo(
					restoring: current, actionName: actionName, undoManager: undoManager)
			}
		}
		undoManager.setActionName(actionName)
	}

	/// Ends any in-progress coalescing, so the next edit gets its own undo step.
	@MainActor
	func breakUndoCoalescing() { coalescingKey = nil }

	static let template = """
		<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
		  <rect x="56" y="56" width="400" height="400" rx="88" fill="#1f6feb"/>
		  <circle cx="256" cy="220" r="96" fill="#ffffff" opacity="0.92"/>
		  <path d="M136 400 Q256 300 376 400" fill="none" stroke="#ffffff" stroke-width="24" stroke-linecap="round"/>
		</svg>

		"""
}
