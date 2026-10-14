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
