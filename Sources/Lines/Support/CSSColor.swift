import AppKit
import SwiftUI

/// Parses the CSS colours SVG attributes use, and writes hex.

enum CSSColor {
	private static let named: [String: String] = [
		"black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
		"blue": "#0000ff",
		"yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "gray": "#808080",
		"grey": "#808080",
		"pink": "#ffc0cb", "cyan": "#00ffff", "magenta": "#ff00ff", "lime": "#00ff00",
		"navy": "#000080",
		"teal": "#008080", "silver": "#c0c0c0", "maroon": "#800000", "olive": "#808000",
		"brown": "#a52a2a",
	]

	static func parse(_ string: String?) -> Color? {
		guard var s = string?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else {
			return nil
		}
		if s == "none" || s == "transparent" { return .clear }
		if let hex = named[s] { s = hex }
		if s.hasPrefix("#") {
			var hex = String(s.dropFirst())
			if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
			guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
			return Color(
				.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
				blue: Double(v & 0xFF) / 255)
		}
		if s.hasPrefix("rgb") {
			let parts = s.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
				.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).compactMap {
					Double($0)
				}
			guard parts.count >= 3 else { return nil }
			return Color(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
		}
		return nil
	}

	static func hex(_ color: Color) -> String {
		guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#000000" }
		let r = Int((c.redComponent * 255).rounded())
		let g = Int((c.greenComponent * 255).rounded())
		let b = Int((c.blueComponent * 255).rounded())
		return String(format: "#%02x%02x%02x", r, g, b)
	}
}
