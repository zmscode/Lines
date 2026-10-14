import AppKit

/// Source editor colours, from popular editor themes.
///
/// The colours come from each theme's Zed extension (Gruvbox and Ayu from
/// Zed's built-in themes; Catppuccin, 0x96f, One Dark Pro, Dracula, JetBrains,
/// Monokai and VS Code Dark Modern from their extensions), mapped to what an
/// SVG needs: tags, attribute names, values, comments, entities and the prolog.
///
/// People pick one dark and one light theme; the editor follows the app's
/// appearance between them.
struct SyntaxTheme: Identifiable, Hashable {
	var name: String
	var family: String
	var isDark: Bool
	var background: NSColor
	var plain: NSColor
	var keyword: NSColor  // element names and brackets
	var attribute: NSColor  // attribute names
	var string: NSColor  // attribute values
	var comment: NSColor
	var character: NSColor  // entities like &amp;
	var preprocessor: NSColor  // <?xml ?>, <!DOCTYPE>, CDATA
	var selection: NSColor
	var insertionPoint: NSColor
	var boldKeywords = false

	var id: String { name }

	static func == (a: Self, b: Self) -> Bool { a.name == b.name }
	func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension SyntaxTheme {
	static let darkKey = "syntaxThemeDark"
	static let lightKey = "syntaxThemeLight"
	static let defaultDark = "Catppuccin Mocha"
	static let defaultLight = "Catppuccin Latte"

	static var dark: [SyntaxTheme] { builtIn.filter(\.isDark) }
	static var light: [SyntaxTheme] { builtIn.filter { !$0.isDark } }

	static func named(_ name: String) -> SyntaxTheme? { builtIn.first { $0.name == name } }

	/// The chosen dark and light themes as one, switching with the appearance.
	static func pair(light lightName: String, dark darkName: String) -> SyntaxTheme {
		let l = named(lightName) ?? named(defaultLight)!
		let d = named(darkName) ?? named(defaultDark)!
		func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
			NSColor(name: nil) { appearance in
				appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
			}
		}
		return SyntaxTheme(
			name: "\(l.name) / \(d.name)", family: "", isDark: false,
			background: dynamic(l.background, d.background), plain: dynamic(l.plain, d.plain),
			keyword: dynamic(l.keyword, d.keyword), attribute: dynamic(l.attribute, d.attribute),
			string: dynamic(l.string, d.string), comment: dynamic(l.comment, d.comment),
			character: dynamic(l.character, d.character),
			preprocessor: dynamic(l.preprocessor, d.preprocessor),
			selection: dynamic(l.selection, d.selection),
			insertionPoint: dynamic(l.insertionPoint, d.insertionPoint),
			boldKeywords: l.boldKeywords || d.boldKeywords
		)
	}

	/// "#rrggbb" or "#rrggbbaa".
	private static func c(_ hex: String) -> NSColor {
		let digits = hex.dropFirst()
		let value = UInt64(digits, radix: 16) ?? 0
		let hasAlpha = digits.count == 8
		let r = (value >> (hasAlpha ? 24 : 16)) & 0xFF
		let g = (value >> (hasAlpha ? 16 : 8)) & 0xFF
		let b = (value >> (hasAlpha ? 8 : 0)) & 0xFF
		let a = hasAlpha ? value & 0xFF : 0xFF
		return NSColor(
			srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255,
			alpha: CGFloat(a) / 255)
	}

	// Generated from the themes' Zed extensions (see the note at the top of the file).
	static let builtIn: [SyntaxTheme] = [
		SyntaxTheme(
			name: "Gruvbox Dark Soft", family: "Gruvbox", isDark: true,
			background: c("#32302fff"), plain: c("#ebdbb2ff"), keyword: c("#8ec07cff"),
			attribute: c("#83a598ff"), string: c("#b8bb25ff"), comment: c("#a89984ff"),
			character: c("#c6b697ff"), preprocessor: c("#fb4833ff"), selection: c("#83a5983d"),
			insertionPoint: c("#83a598ff")),
		SyntaxTheme(
			name: "Gruvbox Dark", family: "Gruvbox", isDark: true,
			background: c("#282828ff"), plain: c("#ebdbb2ff"), keyword: c("#8ec07cff"),
			attribute: c("#83a598ff"), string: c("#b8bb25ff"), comment: c("#a89984ff"),
			character: c("#c6b697ff"), preprocessor: c("#fb4833ff"), selection: c("#83a5983d"),
			insertionPoint: c("#83a598ff")),
		SyntaxTheme(
			name: "Gruvbox Dark Hard", family: "Gruvbox", isDark: true,
			background: c("#1d2021ff"), plain: c("#ebdbb2ff"), keyword: c("#8ec07cff"),
			attribute: c("#83a598ff"), string: c("#b8bb25ff"), comment: c("#a89984ff"),
			character: c("#c6b697ff"), preprocessor: c("#fb4833ff"), selection: c("#83a5983d"),
			insertionPoint: c("#83a598ff")),
		SyntaxTheme(
			name: "Gruvbox Light Soft", family: "Gruvbox", isDark: false,
			background: c("#f2e5bcff"), plain: c("#282828ff"), keyword: c("#427b58ff"),
			attribute: c("#0b6678ff"), string: c("#79740eff"), comment: c("#7c6f64ff"),
			character: c("#5d544eff"), preprocessor: c("#9d0006ff"), selection: c("#0b66783d"),
			insertionPoint: c("#0b6678ff")),
		SyntaxTheme(
			name: "Gruvbox Light", family: "Gruvbox", isDark: false,
			background: c("#fbf1c7ff"), plain: c("#282828ff"), keyword: c("#427b58ff"),
			attribute: c("#0b6678ff"), string: c("#79740eff"), comment: c("#7c6f64ff"),
			character: c("#5d544eff"), preprocessor: c("#9d0006ff"), selection: c("#0b66783d"),
			insertionPoint: c("#0b6678ff")),
		SyntaxTheme(
			name: "Gruvbox Light Hard", family: "Gruvbox", isDark: false,
			background: c("#f9f5d7ff"), plain: c("#282828ff"), keyword: c("#427b58ff"),
			attribute: c("#0b6678ff"), string: c("#79740eff"), comment: c("#7c6f64ff"),
			character: c("#5d544eff"), preprocessor: c("#9d0006ff"), selection: c("#0b66783d"),
			insertionPoint: c("#0b6678ff")),
		SyntaxTheme(
			name: "0x96f", family: "0x96f", isDark: true,
			background: c("#262427"), plain: c("#fcfcfc"), keyword: c("#64d2e8"),
			attribute: c("#fc9d6f"), string: c("#ffd271"), comment: c("#757075"),
			character: c("#ffd271"), preprocessor: c("#fcfcfc"), selection: c("#b5a5b540"),
			insertionPoint: c("#ffbd3e")),
		SyntaxTheme(
			name: "0x96f Lighter", family: "0x96f", isDark: true,
			background: c("#2e2c2f"), plain: c("#fcfcfc"), keyword: c("#64d2e8"),
			attribute: c("#fc9d6f"), string: c("#ffd271"), comment: c("#757075"),
			character: c("#ffd271"), preprocessor: c("#fcfcfc"), selection: c("#bdadbd40"),
			insertionPoint: c("#ffbd3e")),
		SyntaxTheme(
			name: "0x96f Darker", family: "0x96f", isDark: true,
			background: c("#1e1c1f"), plain: c("#fcfcfc"), keyword: c("#64d2e8"),
			attribute: c("#fc9d6f"), string: c("#ffd271"), comment: c("#757075"),
			character: c("#ffd271"), preprocessor: c("#fcfcfc"), selection: c("#ad9dad40"),
			insertionPoint: c("#ffbd3e")),
		SyntaxTheme(
			name: "Catppuccin Latte", family: "Catppuccin", isDark: false,
			background: c("#eff1f5"), plain: c("#4c4f69"), keyword: c("#1e66f5"),
			attribute: c("#df8e1d"), string: c("#40a02b"), comment: c("#7c7f93"),
			character: c("#ea76cb"), preprocessor: c("#ea76cb"), selection: c("#7c7f934d"),
			insertionPoint: c("#dc8a78")),
		SyntaxTheme(
			name: "Catppuccin Frappé", family: "Catppuccin", isDark: true,
			background: c("#303446"), plain: c("#c6d0f5"), keyword: c("#8caaee"),
			attribute: c("#e5c890"), string: c("#a6d189"), comment: c("#949cbb"),
			character: c("#f4b8e4"), preprocessor: c("#f4b8e4"), selection: c("#949cbb40"),
			insertionPoint: c("#f2d5cf")),
		SyntaxTheme(
			name: "Catppuccin Macchiato", family: "Catppuccin", isDark: true,
			background: c("#24273a"), plain: c("#cad3f5"), keyword: c("#8aadf4"),
			attribute: c("#eed49f"), string: c("#a6da95"), comment: c("#939ab7"),
			character: c("#f5bde6"), preprocessor: c("#f5bde6"), selection: c("#939ab740"),
			insertionPoint: c("#f4dbd6")),
		SyntaxTheme(
			name: "Catppuccin Mocha", family: "Catppuccin", isDark: true,
			background: c("#1e1e2e"), plain: c("#cdd6f4"), keyword: c("#89b4fa"),
			attribute: c("#f9e2af"), string: c("#a6e3a1"), comment: c("#9399b2"),
			character: c("#f5c2e7"), preprocessor: c("#f5c2e7"), selection: c("#9399b240"),
			insertionPoint: c("#f5e0dc")),
		SyntaxTheme(
			name: "One Dark Pro", family: "One Dark Pro", isDark: true,
			background: c("#23272e"), plain: c("#abb2bf"), keyword: c("#e06c75"),
			attribute: c("#d19a66"), string: c("#98c379"), comment: c("#7f838c"),
			character: c("#56b6c2"), preprocessor: c("#c678dd"), selection: c("#67769640"),
			insertionPoint: c("#74ade8ff")),
		SyntaxTheme(
			name: "Dracula", family: "Dracula", isDark: true,
			background: c("#282a36ff"), plain: c("#f8f8f2ff"), keyword: c("#ff79c6ff"),
			attribute: c("#8be9fdff"), string: c("#f1fa8cff"), comment: c("#6272a4ff"),
			character: c("#ff79c6ff"), preprocessor: c("#6272a4ff"), selection: c("#bd93f933"),
			insertionPoint: c("#bd93f9ff")),
		SyntaxTheme(
			name: "Alucard (Dracula Light)", family: "Dracula", isDark: false,
			background: c("#f5f5f5"), plain: c("#1f1f1f"), keyword: c("#a3144d"),
			attribute: c("#036a96"), string: c("#846e15"), comment: c("#635d97"),
			character: c("#a3144d"), preprocessor: c("#635d97"), selection: c("#644ac933"),
			insertionPoint: c("#644ac9")),
		SyntaxTheme(
			name: "JetBrains Dark", family: "JetBrains", isDark: true,
			background: c("#1e1f22"), plain: c("#bcbec4ff"), keyword: c("#d5b778"),
			attribute: c("#b3ae60ff"), string: c("#6aab73"), comment: c("#7a7e85ff"),
			character: c("#cf8e6dff"), preprocessor: c("#cf8e6dff"), selection: c("#214283ff"),
			insertionPoint: c("#ced0d6ff")),
		SyntaxTheme(
			name: "JetBrains Light", family: "JetBrains", isDark: false,
			background: c("#ffffffff"), plain: c("#080808ff"), keyword: c("#0033b3"),
			attribute: c("#9e880d"), string: c("#067d17ff"), comment: c("#8c8c8cff"),
			character: c("#0037a6ff"), preprocessor: c("#0033b3ff"), selection: c("#a6d2ffff"),
			insertionPoint: c("#000000ff")),
		SyntaxTheme(
			name: "Monokai", family: "Monokai", isDark: true,
			background: c("#272822"), plain: c("#f8f8f2"), keyword: c("#f92672"),
			attribute: c("#a6e22e"), string: c("#e6db74"), comment: c("#88846f"),
			character: c("#ae81ff"), preprocessor: c("#f92672"), selection: c("#66d9ef3d"),
			insertionPoint: c("#66d9ef")),
		SyntaxTheme(
			name: "VS Code Dark Modern", family: "VS Code", isDark: true,
			background: c("#1f1f1f"), plain: c("#cccccc"), keyword: c("#569cd6"),
			attribute: c("#9cdcfe"), string: c("#ce9178"), comment: c("#6a9955"),
			character: c("#d7ba7d"), preprocessor: c("#569cd6"), selection: c("#264f78"),
			insertionPoint: c("#aeafad")),
		SyntaxTheme(
			name: "Ayu Dark", family: "Ayu", isDark: true,
			background: c("#0d1016ff"), plain: c("#bfbdb6ff"), keyword: c("#5ac1feff"),
			attribute: c("#5ac1feff"), string: c("#a9d94bff"), comment: c("#5c6773ff"),
			character: c("#8c8b88ff"), preprocessor: c("#ff8f3fff"), selection: c("#5ac1fe3d"),
			insertionPoint: c("#5ac1feff")),
		SyntaxTheme(
			name: "Ayu Mirage", family: "Ayu", isDark: true,
			background: c("#242835ff"), plain: c("#cccac2ff"), keyword: c("#72cffeff"),
			attribute: c("#72cffeff"), string: c("#d4fe7fff"), comment: c("#5c6773ff"),
			character: c("#9b9b99ff"), preprocessor: c("#ffad65ff"), selection: c("#72cffe3d"),
			insertionPoint: c("#72cffeff")),
		SyntaxTheme(
			name: "Ayu Light", family: "Ayu", isDark: false,
			background: c("#fcfcfcff"), plain: c("#5c6166ff"), keyword: c("#3b9ee5ff"),
			attribute: c("#3b9ee5ff"), string: c("#86b300ff"), comment: c("#abb0b6ff"),
			character: c("#898d90ff"), preprocessor: c("#fa8d3eff"), selection: c("#3b9ee53d"),
			insertionPoint: c("#3b9ee5ff")),
	]
}
