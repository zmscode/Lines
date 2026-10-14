import Foundation

/// fzf-style fuzzy matching: the query's characters must appear in order,
/// and matches score higher when they're consecutive, start words, or start
/// the text, as in fzf's scoring (its v1 algorithm, simplified).
enum FuzzyMatch {
	private static let scoreMatch = 16
	private static let gapStart = -3
	private static let gapExtension = -1
	private static let bonusBoundary = 8
	private static let bonusConsecutive = 4
	private static let bonusFirstCharMultiplier = 2

	/// A score (higher is better) and the matched character offsets, or nil
	/// when `query` isn't a subsequence of `text`. Case-insensitive.
	static func match(_ query: String, in text: String) -> (score: Int, positions: [Int])? {
		let q = Array(query.lowercased().filter { !$0.isWhitespace })
		guard !q.isEmpty else { return (0, []) }
		let original = Array(text)
		let t = Array(text.lowercased())
		guard t.count == original.count else { return nil }

		// Forward pass: find the first place the whole query fits…
		var qi = 0
		var end = -1
		for (i, c) in t.enumerated() where c == q[qi] {
			qi += 1
			if qi == q.count {
				end = i
				break
			}
		}
		guard end >= 0 else { return nil }
		// …then walk back to the latest start, for the tightest match.
		qi = q.count - 1
		var start = end
		var i = end
		while i >= 0 {
			if t[i] == q[qi] {
				qi -= 1
				if qi < 0 {
					start = i
					break
				}
			}
			i -= 1
		}

		var score = 0
		var positions: [Int] = []
		var inGap = false
		var consecutive = 0
		qi = 0
		for i in start...end {
			if qi < q.count, t[i] == q[qi] {
				var bonus = boundaryBonus(original, at: i)
				if consecutive > 0 { bonus = max(bonus, bonusConsecutive) }
				if qi == 0 { bonus *= bonusFirstCharMultiplier }
				score += scoreMatch + bonus
				positions.append(i)
				consecutive += 1
				inGap = false
				qi += 1
			} else {
				score += inGap ? gapExtension : gapStart
				inGap = true
				consecutive = 0
			}
		}
		// Matches near the start of the text rank a little higher.
		score -= min(start, 10)
		return (score, positions)
	}

	private static func boundaryBonus(_ text: [Character], at i: Int) -> Int {
		guard i > 0 else { return bonusBoundary }
		let previous = text[i - 1]
		let current = text[i]
		if previous.isWhitespace || "-_/.(".contains(previous) { return bonusBoundary }
		if previous.isLowercase && current.isUppercase { return bonusBoundary - 1 }
		return 0
	}

	/// The best score of `query` against any of `texts`.
	static func best(_ query: String, in texts: [String]) -> Int? {
		texts.compactMap { match(query, in: $0)?.score }.max()
	}
}
