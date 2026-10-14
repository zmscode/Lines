import AppKit
import SwiftUI

/// A plain-text SVG editor built on NSTextView, so it gets the system Find bar,
/// text services, spelling-free input and native selection behavior.
struct SourceEditor: NSViewRepresentable {
	var document: SVGDocument
	var controller: CanvasController
	var fontSize: CGFloat
	var wrapsLines: Bool
	var theme: SyntaxTheme

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSTextView.scrollableTextView()
		let textView = scrollView.documentView as! NSTextView
		let coordinator = context.coordinator
		coordinator.textView = textView
		controller.sourceEditor = coordinator

		textView.delegate = coordinator
		textView.isRichText = false
		textView.importsGraphics = false
		textView.allowsUndo = false  // The document owns undo, with named actions.
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isAutomaticTextReplacementEnabled = false
		textView.isAutomaticSpellingCorrectionEnabled = false
		textView.isContinuousSpellCheckingEnabled = false
		textView.isGrammarCheckingEnabled = false
		textView.smartInsertDeleteEnabled = false
		textView.textContainerInset = NSSize(width: 6, height: 10)
		textView.drawsBackground = true
		textView.setAccessibilityLabel("SVG Source")
		textView.textStorage?.delegate = coordinator

		coordinator.apply(fontSize: fontSize, wrapsLines: wrapsLines, theme: theme)
		textView.string = document.text
		scrollView.hasHorizontalScroller = !wrapsLines
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		let coordinator = context.coordinator
		coordinator.parent = self
		coordinator.apply(fontSize: fontSize, wrapsLines: wrapsLines, theme: theme)
		scrollView.hasHorizontalScroller = !wrapsLines
		coordinator.sync(to: document.text)
	}

	@MainActor
	final class Coordinator: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
		var parent: SourceEditor
		weak var textView: NSTextView?
		private var isProgrammaticChange = false
		private var fontSize: CGFloat = 0
		private var wrapsLines: Bool?
		private var theme: SyntaxTheme?

		init(_ parent: SourceEditor) { self.parent = parent }

		func apply(fontSize: CGFloat, wrapsLines: Bool, theme: SyntaxTheme) {
			guard let textView else { return }
			if fontSize != self.fontSize || theme != self.theme {
				self.fontSize = fontSize
				self.theme = theme
				textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
				textView.typingAttributes = [.font: textView.font!, .foregroundColor: theme.plain]
				textView.backgroundColor = theme.background
				textView.insertionPointColor = theme.insertionPoint
				textView.selectedTextAttributes = [.backgroundColor: theme.selection]
				textView.enclosingScrollView?.backgroundColor = theme.background
				if let storage = textView.textStorage {
					Highlighter.highlight(storage, fontSize: fontSize, theme: theme)
				}
			}
			if wrapsLines != self.wrapsLines {
				self.wrapsLines = wrapsLines
				let container = textView.textContainer!
				if wrapsLines {
					container.widthTracksTextView = true
					textView.isHorizontallyResizable = false
				} else {
					container.widthTracksTextView = false
					container.containerSize = NSSize(
						width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
					textView.isHorizontallyResizable = true
					textView.maxSize = NSSize(
						width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
				}
			}
		}

		/// Pushes document changes (from the canvas, or undo) into the text view,
		/// keeping the insertion point near the edit.
		func sync(to text: String) {
			guard let textView, textView.string != text else { return }
			let old = textView.string as NSString
			let new = text as NSString
			var prefix = 0
			let limit = min(old.length, new.length)
			while prefix < limit, old.character(at: prefix) == new.character(at: prefix) {
				prefix += 1
			}

			isProgrammaticChange = true
			let visible = textView.enclosingScrollView?.contentView.bounds.origin
			textView.string = text
			textView.setSelectedRange(NSRange(location: min(prefix, new.length), length: 0))
			if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible) }
			isProgrammaticChange = false
		}

		func textDidChange(_ notification: Notification) {
			guard !isProgrammaticChange, let textView else { return }
			parent.document.replaceText(
				with: textView.string, actionName: "Typing", coalescingKey: "typing",
				undoManager: parent.controller.undoManager
			)
			scheduleFormat()
		}

		// MARK: Formatting as you type

		private var formatTask: Task<Void, Never>?

		/// Re-indents the markup once typing pauses, if it parses. Only
		/// whitespace between tags changes, so the caret keeps its place.
		private func scheduleFormat() {
			formatTask?.cancel()
			guard UserDefaults.standard.object(forKey: "formatsAutomatically") as? Bool ?? true
			else { return }
			formatTask = Task { @MainActor [weak self] in
				try? await Task.sleep(for: .seconds(1.2))
				guard !Task.isCancelled else { return }
				self?.formatNow()
			}
		}

		private func formatNow() {
			guard let textView, !textView.hasMarkedText() else { return }
			let text = textView.string
			guard XMLFormatter.isWellFormed(text) else { return }
			let formatted = XMLFormatter.format(text)
			guard formatted != text else { return }
			let caret = XMLFormatter.mapCaret(
				textView.selectedRange().location, from: text, to: formatted)
			let visible = textView.enclosingScrollView?.contentView.bounds.origin
			isProgrammaticChange = true
			textView.string = formatted
			textView.setSelectedRange(NSRange(location: caret, length: 0))
			if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible) }
			isProgrammaticChange = false
			// Part of the same typing burst, so one Undo reverts both.
			parent.document.replaceText(
				with: formatted, actionName: "Typing", coalescingKey: "typing",
				undoManager: parent.controller.undoManager
			)
		}

		func textStorage(
			_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
			range editedRange: NSRange, changeInLength delta: Int
		) {
			guard editedMask.contains(.editedCharacters) else { return }
			let size = fontSize
			let theme = theme ?? .automatic
			// Attribute changes must happen outside the editing transaction.
			DispatchQueue.main.async {
				Highlighter.highlight(textStorage, fontSize: size, theme: theme)
			}
		}

		/// Moving the insertion point into a start tag selects that element on the canvas.
		func textViewDidChangeSelection(_ notification: Notification) {
			guard !isProgrammaticChange, let textView,
				textView.window?.firstResponder === textView
			else { return }
			let caret = textView.selectedRange().location
			let tags = TagScanner.startTags(in: textView.string)
			if let index = tags.lastIndex(where: { $0.location <= caret && caret <= NSMaxRange($0) }
			) {
				parent.controller.select(order: index)
			}
		}

		/// Highlights an element's start tag after it's selected on the canvas.
		func revealElement(order: Int) {
			guard let textView, textView.window?.firstResponder !== textView else { return }
			let tags = TagScanner.startTags(in: textView.string)
			guard order >= 0, order < tags.count else { return }
			let range = tags[order]
			isProgrammaticChange = true
			textView.setSelectedRange(range)
			textView.scrollRangeToVisible(range)
			isProgrammaticChange = false
		}
	}
}
