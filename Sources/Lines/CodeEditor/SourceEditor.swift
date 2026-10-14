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
		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		let textView = CodeTextView(usingTextLayoutManager: true)
		textView.isVerticallyResizable = true
		textView.autoresizingMask = [.width]
		textView.minSize = NSSize(width: 0, height: 0)
		textView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
		textView.textContainer?.widthTracksTextView = true
		scrollView.documentView = textView
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

	/// Text size for the code editor, shared with Settings.
	static let fontSizeKey = "editorFontSize"
	static let fontSizeRange: ClosedRange<Double> = 8...32

	@MainActor
	static func adjustFontSize(by delta: Double) {
		let current = UserDefaults.standard.object(forKey: fontSizeKey) as? Double ?? 12
		setFontSize(current + delta)
	}

	@MainActor
	static func setFontSize(_ size: Double) {
		let clamped = min(max(size.rounded(), fontSizeRange.lowerBound), fontSizeRange.upperBound)
		UserDefaults.standard.set(clamped, forKey: fontSizeKey)
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

		/// Whether the code editor has keyboard focus, so View › Zoom sizes text instead.
		var isFocused: Bool {
			guard let textView else { return false }
			return textView.window?.firstResponder === textView
		}

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

/// The code editor's text view: pinch to change the text size, like Xcode.
final class CodeTextView: NSTextView {
	private var pinch: CGFloat = 0

	/// ⌘-scroll changes the text size, like ⌘+ and ⌘−.
	override func scrollWheel(with event: NSEvent) {
		guard event.modifierFlags.contains(.command), event.scrollingDeltaY != 0 else {
			super.scrollWheel(with: event)
			return
		}
		pinch += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
		applyPinch()
		if event.phase == .ended || event.momentumPhase == .ended { pinch = 0 }
	}

	/// ⌘+ (or ⌘=), ⌘− and ⌘0 size the text while the editor has focus.
	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard flags == .command || flags == [.command, .shift], window?.firstResponder === self
		else {
			return super.performKeyEquivalent(with: event)
		}
		switch event.charactersIgnoringModifiers {
		case "=", "+": SourceEditor.adjustFontSize(by: 1)
		case "-": SourceEditor.adjustFontSize(by: -1)
		case "0": SourceEditor.setFontSize(12)
		default: return super.performKeyEquivalent(with: event)
		}
		return true
	}

	private func applyPinch() {
		while pinch >= 0.1 {
			SourceEditor.adjustFontSize(by: 1)
			pinch -= 0.1
		}
		while pinch <= -0.1 {
			SourceEditor.adjustFontSize(by: -1)
			pinch += 0.1
		}
	}

	override func magnify(with event: NSEvent) {
		pinch += event.magnification
		// One point per ~10% of pinch keeps it controllable.
		while pinch >= 0.1 {
			SourceEditor.adjustFontSize(by: 1)
			pinch -= 0.1
		}
		while pinch <= -0.1 {
			SourceEditor.adjustFontSize(by: -1)
			pinch += 0.1
		}
		if event.phase == .ended || event.phase == .cancelled { pinch = 0 }
	}
}
