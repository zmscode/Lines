import AppKit

/// Source editor colors, modeled on Xcode's font and color themes.
///
/// Built-in themes use the colors from Xcode's own theme files. If Xcode is installed, its
/// bundled themes and any custom ones in ~/Library/Developer/Xcode/UserData
/// are read directly from their `.xccolortheme` files.
struct SyntaxTheme: Identifiable, Hashable {
	var name: String
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

	static let automaticName = "Automatic"

	static func == (a: Self, b: Self) -> Bool { a.name == b.name }
	func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension SyntaxTheme {
	private static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
		NSColor(
			srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
			blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
	}

	static let defaultLight = SyntaxTheme(
		name: "Default (Light)", background: hex(0xFFFFFF), plain: hex(0x000000, 0.85),
		keyword: hex(0x9B2393), attribute: hex(0x815F03), string: hex(0xC41A16),
		comment: hex(0x5D6C79),
		character: hex(0x1C00CF), preprocessor: hex(0x643820), selection: hex(0xA4CDFF),
		insertionPoint: hex(0x000000)
	)

	static let defaultDark = SyntaxTheme(
		name: "Default (Dark)", background: hex(0x1F1F24), plain: hex(0xFFFFFF, 0.85),
		keyword: hex(0xFC5FA3), attribute: hex(0xBF8555), string: hex(0xFC6A5D),
		comment: hex(0x6C7986),
		character: hex(0xD0BF69), preprocessor: hex(0xFD8F3F), selection: hex(0x515B70),
		insertionPoint: hex(0xFFFFFF), boldKeywords: true
	)

	static let classicLight = SyntaxTheme(
		name: "Classic (Light)", background: hex(0xFFFFFF), plain: hex(0x000000, 0.85),
		keyword: hex(0x9B2393), attribute: hex(0x815F03), string: hex(0xC41A16),
		comment: hex(0x267507),
		character: hex(0x1C00CF), preprocessor: hex(0x643820), selection: hex(0xA4CDFF),
		insertionPoint: hex(0x000000)
	)

	static let midnight = SyntaxTheme(
		name: "Midnight", background: hex(0x000000), plain: hex(0xFFFFFF),
		keyword: hex(0xD31895), attribute: hex(0x2D449B), string: hex(0xFF2C38),
		comment: hex(0x41CC45),
		character: hex(0x786DFF), preprocessor: hex(0xE47C48), selection: hex(0x4B4740),
		insertionPoint: hex(0xFFFFFF)
	)

	static let dusk = SyntaxTheme(
		name: "Dusk", background: hex(0x1E2028), plain: hex(0xFFFFFF),
		keyword: hex(0xB21889), attribute: hex(0x55747C), string: hex(0xDB2C38),
		comment: hex(0x41B645),
		character: hex(0x786DC4), preprocessor: hex(0xC67C48), selection: hex(0x54554A),
		insertionPoint: hex(0xFFFFFF)
	)

	static let sunset = SyntaxTheme(
		name: "Sunset", background: hex(0xFFFCE5), plain: hex(0x000000),
		keyword: hex(0x294277), attribute: hex(0x2C329D), string: hex(0xDF0700),
		comment: hex(0xC3741C),
		character: hex(0x294277), preprocessor: hex(0x646485), selection: hex(0xF9DF9C),
		insertionPoint: hex(0x000000)
	)

	static let spartan = SyntaxTheme(
		name: "Spartan", background: hex(0xFFFFFF), plain: hex(0x000000),
		keyword: hex(0xD31679), attribute: hex(0x264F66), string: hex(0x666666),
		comment: hex(0xB20000),
		character: hex(0x000000), preprocessor: hex(0x000000), selection: hex(0xA4CDFF),
		insertionPoint: hex(0x000000)
	)

	/// Default (Light) or Default (Dark), following the system appearance.
	static let automatic: SyntaxTheme = {
		func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
			NSColor(name: nil) { appearance in
				appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
			}
		}
		let l = defaultLight
		let d = defaultDark
		return SyntaxTheme(
			name: automaticName, background: dynamic(l.background, d.background),
			plain: dynamic(l.plain, d.plain),
			keyword: dynamic(l.keyword, d.keyword), attribute: dynamic(l.attribute, d.attribute),
			string: dynamic(l.string, d.string), comment: dynamic(l.comment, d.comment),
			character: dynamic(l.character, d.character),
			preprocessor: dynamic(l.preprocessor, d.preprocessor),
			selection: dynamic(l.selection, d.selection),
			insertionPoint: dynamic(l.insertionPoint, d.insertionPoint),
			boldKeywords: true
		)
	}()

	static let builtIn: [SyntaxTheme] = [
		automatic, defaultLight, defaultDark, classicLight, midnight, dusk, sunset, spartan,
	]

	/// Built-in themes, overlaid with themes read from Xcode where available.
	static let all: [SyntaxTheme] = {
		var themes = builtIn
		for theme in XcodeThemeLoader.load() {
			if let i = themes.firstIndex(where: { $0.name == theme.name }) {
				if theme.name != automaticName { themes[i] = theme }
			} else {
				themes.append(theme)
			}
		}
		return themes
	}()

	static func named(_ name: String) -> SyntaxTheme {
		all.first { $0.name == name } ?? automatic
	}
}

// MARK: - Xcode .xccolortheme files

enum XcodeThemeLoader {
	static func load() -> [SyntaxTheme] {
		var directories = [
			FileManager.default.homeDirectoryForCurrentUser
				.appendingPathComponent("Library/Developer/Xcode/UserData/FontAndColorThemes")
		]
		if let xcode = NSWorkspace.shared.urlForApplication(
			withBundleIdentifier: "com.apple.dt.Xcode")
		{
			directories.insert(
				xcode.appendingPathComponent(
					"Contents/SharedFrameworks/DVTUserInterfaceKit.framework/Versions/A/Resources/FontAndColorThemes"
				), at: 0)
		}
		return directories.flatMap { directory -> [SyntaxTheme] in
			let files =
				(try? FileManager.default.contentsOfDirectory(
					at: directory, includingPropertiesForKeys: nil)) ?? []
			return files.filter { $0.pathExtension == "xccolortheme" }
				.sorted { $0.lastPathComponent < $1.lastPathComponent }
				.compactMap(parse)
		}
	}

	private static func parse(_ url: URL) -> SyntaxTheme? {
		guard let data = try? Data(contentsOf: url),
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
				as? [String: Any],
			let syntax = plist["DVTSourceTextSyntaxColors"] as? [String: String]
		else { return nil }

		func color(_ value: String?) -> NSColor? {
			let parts = value?.split(separator: " ").compactMap { Double($0) } ?? []
			guard parts.count == 4 else { return nil }
			return NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: parts[3])
		}
		let plain = color(syntax["xcode.syntax.plain"]) ?? .textColor
		func token(_ key: String) -> NSColor { color(syntax[key]) ?? plain }
		let fonts = plist["DVTSourceTextSyntaxFonts"] as? [String: String] ?? [:]

		return SyntaxTheme(
			name: url.deletingPathExtension().lastPathComponent,
			background: color(plist["DVTSourceTextBackground"] as? String) ?? .textBackgroundColor,
			plain: plain,
			keyword: token("xcode.syntax.keyword"),
			attribute: token("xcode.syntax.attribute"),
			string: token("xcode.syntax.string"),
			comment: token("xcode.syntax.comment"),
			character: token("xcode.syntax.character"),
			preprocessor: token("xcode.syntax.preprocessor"),
			selection: color(plist["DVTSourceTextSelectionColor"] as? String)
				?? .selectedTextBackgroundColor,
			insertionPoint: color(plist["DVTSourceTextInsertionPointColor"] as? String) ?? plain,
			boldKeywords: fonts["xcode.syntax.keyword"]?.contains("Bold") ?? false
		)
	}
}
