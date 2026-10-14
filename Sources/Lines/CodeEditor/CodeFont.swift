import AppKit

/// The code editor's typeface: SF Mono (the system's monospaced font) unless
/// another fixed-width family is chosen in Settings.
enum CodeFont {
	static let key = "editorFontName"
	/// Shown for the default.
	static let systemName = "SF Mono (System)"

	static var name: String { UserDefaults.standard.string(forKey: key) ?? "" }

	static func regular(size: CGFloat, name: String = CodeFont.name) -> NSFont {
		guard !name.isEmpty,
			let font = NSFontManager.shared.font(
				withFamily: name, traits: [], weight: 5, size: size)
		else { return .monospacedSystemFont(ofSize: size, weight: .regular) }
		return font
	}

	static func bold(size: CGFloat, name: String = CodeFont.name) -> NSFont {
		guard !name.isEmpty else { return .monospacedSystemFont(ofSize: size, weight: .semibold) }
		return NSFontManager.shared.convert(
			regular(size: size, name: name), toHaveTrait: .boldFontMask)
	}

	/// Installed fixed-width families, for the picker.
	@MainActor static let families: [String] = NSFontManager.shared.availableFontFamilies.filter {
		family in
		guard
			let font = NSFontManager.shared.font(
				withFamily: family, traits: [], weight: 5, size: 12)
		else { return false }
		return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
	}
}
