import AppKit

extension NSAttributedString.Key {
	/// Marks characters folded out of view; the value is the fold's first index,
	/// which draws as an ellipsis.
	static let codeFold = NSAttributedString.Key("LinesCodeFold")
}

/// Long attribute values (path data, point lists, embedded images) fold to a
/// short prefix and an ellipsis so the markup stays readable. The text itself
/// is untouched: copying, finding and saving see everything. Putting the
/// insertion point in a value unfolds it.
enum CodeFolding {
	static let minimumLength = 160
	static let visiblePrefix = 48

	private static let foldable = try! NSRegularExpression(
		pattern: #"\s(?:d|points|values|keySplines|(?:xlink:)?href)\s*=\s*("[^"]*"|'[^']*')"#)

	/// The folds for `text`: each value's range past its visible prefix.
	static func folds(in text: String) -> [NSRange] {
		let ns = text as NSString
		var ranges: [NSRange] = []
		foldable.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) {
			match, _, _ in
			guard let value = match?.range(at: 1), value.length - 2 >= minimumLength else { return }
			ranges.append(
				NSRange(
					location: value.location + 1 + visiblePrefix,
					length: value.length - 2 - visiblePrefix))
		}
		return ranges
	}

	/// Marks the folds in `storage`, leaving `expanded` (the value being edited) open.
	static func apply(to storage: NSTextStorage, expanded: NSRange?) {
		guard storage.length < 2_000_000 else { return }
		let full = NSRange(location: 0, length: storage.length)
		storage.beginEditing()
		storage.removeAttribute(.codeFold, range: full)
		for fold in folds(in: storage.string) {
			if let expanded, NSIntersectionRange(expanded, fold).length > 0 { continue }
			storage.addAttribute(.codeFold, value: fold.location, range: fold)
		}
		storage.endEditing()
	}

	/// The foldable value containing `location` (a caret just inside the
	/// visible prefix counts), if any.
	static func fold(containing location: Int, in text: String) -> NSRange? {
		folds(in: text).first {
			$0.location - visiblePrefix <= location && location <= NSMaxRange($0)
		}
	}
}

/// Hides folded characters at layout time, drawing an ellipsis in their place.
final class FoldingLayoutDelegate: NSObject, NSLayoutManagerDelegate {
	func layoutManager(
		_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
		properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
		characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont,
		forGlyphRange glyphRange: NSRange
	) -> Int {
		guard let storage = layoutManager.textStorage else { return 0 }
		let count = glyphRange.length
		var changed = false
		var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
		var newProps = Array(UnsafeBufferPointer(start: props, count: count))
		var ellipsis: CGGlyph = 0
		var dots: UniChar = 0x2026
		CTFontGetGlyphsForCharacters(aFont, &dots, &ellipsis, 1)
		for i in 0..<count {
			let index = charIndexes[i]
			guard index < storage.length,
				let start = storage.attribute(.codeFold, at: index, effectiveRange: nil) as? Int
			else { continue }
			changed = true
			if index == start {
				newGlyphs[i] = ellipsis
			} else {
				newProps[i] = .null
			}
		}
		guard changed else { return 0 }
		layoutManager.setGlyphs(
			newGlyphs, properties: newProps, characterIndexes: charIndexes, font: aFont,
			forGlyphRange: glyphRange)
		return count
	}
}

extension CodeTextView {
	/// Replaces text through the usual delegate path, so the document hears about it.
	func replace(_ range: NSRange, with string: String) -> Bool {
		guard shouldChangeText(in: range, replacementString: string) else { return false }
		textStorage?.replaceCharacters(in: range, with: string)
		didChangeText()
		return true
	}

	/// ⌘/ wraps the selected lines in a comment, or unwraps them.
	func toggleComment() {
		let text = string as NSString
		let lines = text.lineRange(for: selectedRange())
		var body = text.substring(with: lines)
		var trailing = ""
		while body.hasSuffix("\n") || body.hasSuffix("\r") {
			trailing = String(body.removeLast()) + trailing
		}
		let indent = String(body.prefix { $0 == " " || $0 == "\t" })
		let inner = body.dropFirst(indent.count)
		let replacement: String
		if inner.hasPrefix("<!--") && inner.hasSuffix("-->") {
			var stripped = String(inner.dropFirst(4).dropLast(3))
			if stripped.hasPrefix(" ") { stripped.removeFirst() }
			if stripped.hasSuffix(" ") { stripped.removeLast() }
			replacement = indent + stripped + trailing
		} else {
			guard !inner.isEmpty else { return }
			replacement = indent + "<!-- " + inner + " -->" + trailing
		}
		if replace(lines, with: replacement) {
			setSelectedRange(
				NSRange(
					location: lines.location,
					length: (replacement as NSString).length - (trailing as NSString).length))
		}
	}

	/// After typing: ">" closing a start tag adds its end tag after the caret,
	/// and "</" finishes the innermost open element's end tag.
	func autoClose(after typed: String) {
		guard UserDefaults.standard.object(forKey: "autoClosesTags") as? Bool ?? true,
			!hasMarkedText()
		else { return }
		let caret = selectedRange().location
		let text = string as NSString
		if typed == ">" {
			let lt = text.range(
				of: "<", options: .backwards, range: NSRange(location: 0, length: caret))
			guard lt.location != NSNotFound else { return }
			let tag = text.substring(
				with: NSRange(location: lt.location, length: caret - lt.location))
			guard !tag.hasSuffix("/>"), tag.filter({ $0 == "\"" }).count % 2 == 0,
				tag.filter({ $0 == "'" }).count % 2 == 0,
				let match = tag.firstMatch(of: #/^<([A-Za-z_][\w:.\-]*)(\s[^<>]*)?>$/#)
			else { return }
			let name = String(match.1)
			let closing = "</\(name)>"
			// Don't double up when the end tag is already there.
			let ahead = text.substring(
				with: NSRange(
					location: caret, length: min(closing.utf16.count, text.length - caret)))
			guard ahead != closing else { return }
			if replace(NSRange(location: caret, length: 0), with: closing) {
				setSelectedRange(NSRange(location: caret, length: 0))
			}
		} else if typed == "/", caret >= 2, text.character(at: caret - 2) == 0x3C {
			guard
				let name = TagScanner.openElement(
					before: caret - 2, in: TagScanner.tags(in: text.substring(to: caret - 2)))
			else { return }
			let rest = name + ">"
			if replace(NSRange(location: caret, length: 0), with: rest) {
				setSelectedRange(NSRange(location: caret + rest.utf16.count, length: 0))
			}
		}
	}
}
