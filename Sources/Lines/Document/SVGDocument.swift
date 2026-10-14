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
	/// The text as opened: the template for a new drawing, or the file's
	/// contents once they've been read (which happens after the window opens).
	private(set) var openedText: String

	/// The open file's location, used for sharing and export names.
	@ObservationIgnored weak var configuration: URLDocumentConfiguration?

	@ObservationIgnored private var coalescingKey: String?
	@ObservationIgnored private var coalescingDate = Date.distantPast

	init(text: String = SVGDocument.template) {
		self.text = text
		self.openedText = text
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
		// The first read is the file as opened, not an edit of the template.
		if previous == nil { openedText = snapshot }
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
			<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 18.4418 18.4585">
		 			<g>
		   				<rect height="18.4585" opacity="0" width="18.4418" x="0" y="0"/>
		      			<path d="M3.48575 18.4046C5.41026 18.4046 6.9715 16.8413 6.9715 14.9064L6.9715 3.49821C6.9715 1.56335 5.41026 0 3.48575 0C1.56335 0 0 1.56335 0 3.49821C0 5.43519 1.56335 6.95713 3.48575 6.95713L6.21721 6.95713C6.6234 6.95713 6.9508 6.62762 6.9508 6.21319C6.9508 5.807 6.6234 5.47959 6.21721 5.47959L3.48575 5.47959C2.41291 5.47959 1.51894 4.58351 1.51894 3.49821C1.51894 2.41502 2.41291 1.52929 3.48575 1.52929C4.55859 1.52929 5.45467 2.41502 5.45467 3.49821L5.45467 14.9064C5.45467 15.9917 4.55859 16.8753 3.48575 16.8753C2.41291 16.8753 1.51894 15.9917 1.51894 14.9064C1.51894 13.8211 2.41291 12.925 3.48575 12.925L14.956 12.925C16.0268 12.925 16.9228 13.8211 16.9228 14.9064C16.9228 15.9917 16.0268 16.8753 14.956 16.8753C13.8832 16.8753 12.9975 15.9917 12.9975 14.9064L12.9975 3.49821C12.9975 2.41502 13.8832 1.52929 14.956 1.52929C16.0268 1.52929 16.9228 2.41502 16.9228 3.49821C16.9228 4.58351 16.0268 5.47959 14.956 5.47959L6.21721 5.47959C5.80278 5.47959 5.47537 5.807 5.47537 6.21319C5.47537 6.62762 5.80278 6.95713 6.21721 6.95713L14.956 6.95713C16.8784 6.95713 18.4418 5.43519 18.4418 3.49821C18.4418 1.56335 16.8784 0 14.956 0C13.0315 0 11.4682 1.56335 11.4682 3.49821L11.4682 14.9064C11.4682 16.8413 13.0315 18.4046 14.956 18.4046C16.8784 18.4046 18.4418 16.8413 18.4418 14.9064C18.4418 12.9694 16.8784 11.4578 14.956 11.4578L3.48575 11.4578C1.56335 11.4578 0 12.9694 0 14.9064C0 16.8413 1.56335 18.4046 3.48575 18.4046Z" fill="white" fill-opacity="0.85"/>
		        	</g>
			</svg>
		"""
}
