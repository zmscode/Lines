import Foundation

/// Re-indents SVG markup: one element per line, two spaces per level.
///
/// Only whitespace between tags changes. Attributes stay as written, and the
/// contents of elements where whitespace can matter (`<text>`, `<style>`,
/// `<script>` and friends) and of CDATA sections are kept exactly.
enum XMLFormatter {
	static let indentUnit = "  "
	private static let preserved: Set<String> = [
		"text", "tspan", "textPath", "style", "script", "title", "desc", "metadata",
		"foreignObject",
	]

	private enum Token {
		case start(name: String, raw: String, selfClosing: Bool)
		case end(name: String, raw: String)
		case other(raw: String)  // comments, processing instructions, doctype, CDATA
		case text(raw: String)
	}

	/// Strips comments and the whitespace between tags.
	static func minify(_ source: String) -> String {
		format(source, indent: nil, keepComments: false).trimmingCharacters(
			in: .whitespacesAndNewlines)
	}

	static func format(_ source: String) -> String {
		format(source, indent: indentUnit, keepComments: true)
	}

	private static func format(_ source: String, indent: String?, keepComments: Bool) -> String {
		let tokens = tokenize(source)
		var out = ""
		var depth = 0
		var preserveDepth = 0  // > 0 while inside a whitespace-sensitive element
		var lastStartName: String?  // the previous token was this element's start tag

		func newline() {
			if let indent, !out.isEmpty { out += "\n" + String(repeating: indent, count: depth) }
		}

		for token in tokens {
			switch token {
			case .text(let raw):
				if preserveDepth > 0 {
					out += raw
				} else if !raw.allSatisfy(\.isWhitespace) {
					out += raw.trimmingCharacters(in: .whitespacesAndNewlines)
					lastStartName = nil
				}
				continue
			case .start(let name, let raw, let selfClosing):
				if preserveDepth == 0 { newline() }
				out += raw
				if !selfClosing {
					depth += 1
					if preserveDepth > 0 || preserved.contains(name) { preserveDepth += 1 }
				}
				lastStartName = selfClosing ? nil : name
				continue
			case .end(let name, let raw):
				depth = max(0, depth - 1)
				if preserveDepth > 0 {
					preserveDepth -= 1
				} else if lastStartName != name {
					newline()
				}
				out += raw
			case .other(let raw):
				if !keepComments, preserveDepth == 0, raw.hasPrefix("<!--") { continue }
				if preserveDepth == 0 { newline() }
				out += raw
			}
			lastStartName = nil
		}
		return indent == nil ? out : out + "\n"
	}

	/// Whether the markup parses, so formatting never runs on a half-typed document.
	static func isWellFormed(_ source: String) -> Bool {
		XMLParser(data: Data(source.utf8)).parse()
	}

	private static func tokenize(_ string: String) -> [Token] {
		let s = string as NSString
		let n = s.length
		var tokens: [Token] = []
		var i = 0
		var textStart = 0

		func flushText(upTo end: Int) {
			if end > textStart {
				tokens.append(
					.text(
						raw: s.substring(
							with: NSRange(location: textStart, length: end - textStart))))
			}
		}
		func has(_ lit: String, at j: Int) -> Bool {
			j + lit.utf16.count <= n
				&& s.substring(with: NSRange(location: j, length: lit.utf16.count)) == lit
		}
		func end(of lit: String, from j: Int) -> Int {
			let r = s.range(of: lit, range: NSRange(location: j, length: n - j))
			return r.location == NSNotFound ? n : NSMaxRange(r)
		}
		func raw(_ a: Int, _ b: Int) -> String {
			s.substring(with: NSRange(location: a, length: b - a))
		}

		while i < n {
			guard s.character(at: i) == 0x3C else {
				i += 1
				continue
			}  // "<"
			flushText(upTo: i)
			let close: Int
			if has("<!--", at: i) {
				close = end(of: "-->", from: i + 4)
				tokens.append(.other(raw: raw(i, close)))
			} else if has("<![CDATA[", at: i) {
				close = end(of: "]]>", from: i + 9)
				tokens.append(.other(raw: raw(i, close)))
			} else if has("<?", at: i) {
				close = end(of: "?>", from: i + 2)
				tokens.append(.other(raw: raw(i, close)))
			} else if has("<!", at: i) {
				close = end(of: ">", from: i + 2)
				tokens.append(.other(raw: raw(i, close)))
			} else {
				// A start or end tag: find ">" outside quoted attribute values.
				var j = i + 1
				var quote: unichar = 0
				while j < n {
					let c = s.character(at: j)
					if quote != 0 {
						if c == quote { quote = 0 }
					} else if c == 0x22 || c == 0x27 {
						quote = c
					} else if c == 0x3E {
						break
					}
					j += 1
				}
				close = min(j + 1, n)
				let tag = raw(i, close)
				let isEnd = tag.hasPrefix("</")
				let nameStart = tag.index(tag.startIndex, offsetBy: isEnd ? 2 : 1)
				let name = String(
					tag[nameStart...].prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
				if isEnd {
					tokens.append(.end(name: name, raw: tag))
				} else {
					tokens.append(.start(name: name, raw: tag, selfClosing: tag.hasSuffix("/>")))
				}
			}
			i = close
			textStart = close
		}
		flushText(upTo: n)
		return tokens
	}

	/// Maps a caret offset across a whitespace-only reformat by counting the
	/// non-whitespace characters before it.
	static func mapCaret(_ caret: Int, from old: String, to new: String) -> Int {
		let o = old as NSString
		let nw = new as NSString
		var count = 0
		for k in 0..<min(caret, o.length) where !isSpace(o.character(at: k)) { count += 1 }
		var k = 0
		while k < nw.length, count > 0 {
			if !isSpace(nw.character(at: k)) { count -= 1 }
			k += 1
		}
		return k
	}

	private static func isSpace(_ c: unichar) -> Bool {
		c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09
	}
}
