import AppKit

enum Highlighter {
	private enum Token { case keyword, attribute, string, character, preprocessor, comment }

	// Later rules win, so strings override attribute matches inside values and
	// comments override everything.
	private static let rules: [(NSRegularExpression, Token)] = {
		func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
		return [
			(re(#"</?[A-Za-z_][\w:.-]*|/?>"#), .keyword),
			(re(#"\s[A-Za-z_][\w:.-]*(?=\s*=)"#), .attribute),
			(re(#""[^"]*"|'[^']*'"#), .string),
			(re(#"&[#\w]+;"#), .character),
			(re(#"<\?[\s\S]*?\?>|<!DOCTYPE[^>]*>|<!\[CDATA\[[\s\S]*?\]\]>"#), .preprocessor),
			(re(#"<!--[\s\S]*?-->"#), .comment),
		]
	}()

	static func highlight(_ storage: NSTextStorage, fontSize: CGFloat, theme: SyntaxTheme) {
		let full = NSRange(location: 0, length: storage.length)
		let font = CodeFont.regular(size: fontSize)
		let bold = CodeFont.bold(size: fontSize)
		storage.beginEditing()
		storage.setAttributes([.font: font, .foregroundColor: theme.plain], range: full)
		// Very large files stay plain so typing remains responsive.
		if storage.length < 400_000 {
			let text = storage.string
			for (regex, token) in rules {
				let color: NSColor =
					switch token {
					case .keyword: theme.keyword
					case .attribute: theme.attribute
					case .string: theme.string
					case .character: theme.character
					case .preprocessor: theme.preprocessor
					case .comment: theme.comment
					}
				regex.enumerateMatches(in: text, range: full) { match, _, _ in
					guard let r = match?.range else { return }
					storage.addAttribute(.foregroundColor, value: color, range: r)
					storage.addAttribute(
						.font, value: token == .keyword && theme.boldKeywords ? bold : font,
						range: r)
				}
			}
		}
		storage.endEditing()
	}

	/// A colored sample for the theme picker in Settings.
	static func sample(theme: SyntaxTheme, fontSize: CGFloat) -> NSAttributedString {
		let storage = NSTextStorage(
			string: """
				<!-- Lines -->
				<svg viewBox="0 0 64 64">
				  <rect x="8" y="8" width="48" height="48" rx="12"/>
				  <text>A &amp; B</text>
				</svg>
				""")
		highlight(storage, fontSize: fontSize, theme: theme)
		return storage
	}
}
