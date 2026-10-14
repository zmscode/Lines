import Foundation

/// The canvas page. Its markup, styles and script live in Resources as
/// ordinary files; they're inlined into one document at load, so the page has
/// no file origin and can rasterize the drawing without tainting its canvas.
enum CanvasHTML {
	static let page: String = {
		func resource(_ name: String, _ ext: String) -> String {
			guard let url = Bundle.module.url(forResource: name, withExtension: ext),
				let text = try? String(contentsOf: url, encoding: .utf8)
			else { fatalError("Missing canvas resource \(name).\(ext)") }
			return text
		}
		// The page's script runs by this nonce; the drawing can't know it.
		let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
		return resource("canvas", "html")
			.replacingOccurrences(of: "CANVAS_NONCE", with: nonce)
			.replacingOccurrences(of: "/* canvas.css */\n", with: resource("canvas", "css"))
			.replacingOccurrences(of: "// canvas.js\n", with: resource("canvas", "js"))
	}()
}
