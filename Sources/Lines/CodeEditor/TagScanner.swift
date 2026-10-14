import Foundation

/// Finds element start tags in document order, so index N in this list is the
/// same element as preorder index N in the DOM.
enum TagScanner {
	static func startTags(in string: String) -> [NSRange] {
		let s = string as NSString
		let n = s.length
		var ranges: [NSRange] = []
		var i = 0
		func has(_ lit: String, at j: Int) -> Bool {
			j + lit.utf16.count <= n
				&& s.substring(with: NSRange(location: j, length: lit.utf16.count)) == lit
		}
		func skip(past lit: String, from j: Int) -> Int {
			let r = s.range(of: lit, range: NSRange(location: j, length: n - j))
			return r.location == NSNotFound ? n : NSMaxRange(r)
		}
		while i < n {
			guard s.character(at: i) == 0x3C else {
				i += 1
				continue
			}  // "<"
			if has("<!--", at: i) {
				i = skip(past: "-->", from: i + 4)
				continue
			}
			if has("<![CDATA[", at: i) {
				i = skip(past: "]]>", from: i + 9)
				continue
			}
			if has("<?", at: i) {
				i = skip(past: "?>", from: i + 2)
				continue
			}
			guard i + 1 < n else { break }
			let next = s.character(at: i + 1)
			if next == 0x21 || next == 0x2F {
				i = skip(past: ">", from: i + 1)
				continue
			}  // "!" or "/"
			guard let scalar = UnicodeScalar(next),
				CharacterSet.letters.contains(scalar) || next == 0x5F
			else {
				i += 1
				continue
			}
			// Find the closing ">" while respecting quoted attribute values.
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
			let end = min(j + 1, n)
			ranges.append(NSRange(location: i, length: end - i))
			i = end
		}
		return ranges
	}
}

extension TagScanner {
	/// The start tags of the drawing's elements: those in its first <svg>,
	/// the part the canvas shows. Matches the canvas's preorder indices even
	/// when the <svg> sits inside another root, like an XHTML page.
	static func elementTags(in string: String) -> [NSRange] {
		let ranges = startTags(in: string)
		guard let drawing = drawingRange(in: string) else { return ranges }
		return ranges.filter { NSLocationInRange($0.location, drawing) }
	}

	/// The first <svg> element, from its start tag to the end of its end tag.
	static func drawingRange(in string: String) -> NSRange? {
		let all = tags(in: string)
		guard let first = all.firstIndex(where: { $0.name == "svg" && $0.kind != .end }) else {
			return nil
		}
		let start = all[first].range
		if all[first].kind == .empty { return start }
		var depth = 0
		for tag in all[(first + 1)...] where tag.name == "svg" {
			if tag.kind == .start { depth += 1 }
			if tag.kind == .end {
				if depth == 0 {
					return NSRange(
						location: start.location, length: NSMaxRange(tag.range) - start.location)
				}
				depth -= 1
			}
		}
		return NSRange(
			location: start.location, length: (string as NSString).length - start.location)
	}

	/// A start, end or self-closing tag, with where its name is.
	struct Tag {
		enum Kind { case start, end, empty }
		var range: NSRange
		var nameRange: NSRange
		var name: String
		var kind: Kind
	}

	/// Every element tag in order, skipping comments, CDATA and declarations.
	static func tags(in string: String) -> [Tag] {
		let s = string as NSString
		let n = s.length
		var tags: [Tag] = []
		var i = 0
		func has(_ lit: String, at j: Int) -> Bool {
			j + lit.utf16.count <= n
				&& s.substring(with: NSRange(location: j, length: lit.utf16.count)) == lit
		}
		func skip(past lit: String, from j: Int) -> Int {
			let r = s.range(of: lit, range: NSRange(location: j, length: n - j))
			return r.location == NSNotFound ? n : NSMaxRange(r)
		}
		func isNameChar(_ c: unichar) -> Bool {
			guard let u = UnicodeScalar(c) else { return false }
			return CharacterSet.alphanumerics.contains(u) || c == 0x5F || c == 0x3A || c == 0x2D
				|| c == 0x2E
		}
		while i < n {
			guard s.character(at: i) == 0x3C else {
				i += 1
				continue
			}
			if has("<!--", at: i) {
				i = skip(past: "-->", from: i + 4)
				continue
			}
			if has("<![CDATA[", at: i) {
				i = skip(past: "]]>", from: i + 9)
				continue
			}
			if has("<?", at: i) || has("<!", at: i) {
				i = skip(past: ">", from: i + 2)
				continue
			}
			let isEnd = i + 1 < n && s.character(at: i + 1) == 0x2F
			var nameStart = i + (isEnd ? 2 : 1)
			var nameEnd = nameStart
			while nameEnd < n, isNameChar(s.character(at: nameEnd)) { nameEnd += 1 }
			guard nameEnd > nameStart else {
				i += 1
				continue
			}
			var j = nameEnd
			var quote: unichar = 0
			while j < n {
				let c = s.character(at: j)
				if quote != 0 {
					if c == quote { quote = 0 }
				} else if c == 0x22 || c == 0x27 {
					quote = c
				} else if c == 0x3E || c == 0x3C {
					break
				}
				j += 1
			}
			let closed = j < n && s.character(at: j) == 0x3E
			let end = closed ? j + 1 : j
			let isEmpty = closed && !isEnd && j > 0 && s.character(at: j - 1) == 0x2F
			nameStart = isEnd ? i + 2 : i + 1
			tags.append(
				Tag(
					range: NSRange(location: i, length: end - i),
					nameRange: NSRange(location: nameStart, length: nameEnd - nameStart),
					name: s.substring(
						with: NSRange(location: nameStart, length: nameEnd - nameStart)),
					kind: isEnd ? .end : isEmpty ? .empty : .start))
			i = end
		}
		return tags
	}

	/// The tag at `location` and the tag it pairs with, if any.
	static func pair(at location: Int, in tags: [Tag]) -> (Tag, Tag?)? {
		guard
			let index = tags.firstIndex(where: {
				$0.range.location < location && location < NSMaxRange($0.range)
					|| $0.range.location == location
			})
		else { return nil }
		let tag = tags[index]
		switch tag.kind {
		case .empty: return (tag, nil)
		case .start:
			var depth = 0
			for other in tags[(index + 1)...] {
				if other.kind == .start && other.name == tag.name { depth += 1 }
				if other.kind == .end && other.name == tag.name {
					if depth == 0 { return (tag, other) }
					depth -= 1
				}
			}
			return (tag, nil)
		case .end:
			var depth = 0
			for other in tags[..<index].reversed() {
				if other.kind == .end && other.name == tag.name { depth += 1 }
				if other.kind == .start && other.name == tag.name {
					if depth == 0 { return (tag, other) }
					depth -= 1
				}
			}
			return (tag, nil)
		}
	}

	/// The innermost element still open at `location`.
	static func openElement(before location: Int, in tags: [Tag]) -> String? {
		var stack: [String] = []
		for tag in tags where NSMaxRange(tag.range) <= location {
			switch tag.kind {
			case .start: stack.append(tag.name)
			case .end:
				if let i = stack.lastIndex(of: tag.name) { stack.removeSubrange(i...) }
			case .empty: break
			}
		}
		return stack.last
	}
}
