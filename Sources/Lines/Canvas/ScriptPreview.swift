import SwiftUI
import WebKit

/// Runs a drawing's scripts, on request, in a web view of its own: the
/// drawing as a browser would show it, with its `<script>`s and event
/// handlers live, but cut off from everything else. It has no bridge to the
/// app, keeps nothing between runs, can't reach the network or navigate
/// away, and changes its scripts make are never saved.
///
/// The canvas itself never runs a drawing's code (see canvas.html).
struct ScriptPreview: NSViewRepresentable {
	var text: String
	/// Bumped to start the scripts again from the beginning.
	var generation: Int

	static let scheme = "lines-preview"
	private static let documentURL = URL(string: "\(scheme)://drawing/drawing")!

	/// Whether a drawing has anything to run: `<script>` elements or `on…`
	/// event handler attributes.
	static func hasScripts(_ text: String) -> Bool {
		text.contains(#/(?i)<script[\s>\/]|\son[a-z]+\s*=\s*["']/#)
	}

	func makeNSView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		config.websiteDataStore = .nonPersistent()
		config.setURLSchemeHandler(context.coordinator.server, forURLScheme: Self.scheme)
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = context.coordinator
		webView.uiDelegate = context.coordinator
		webView.setAccessibilityLabel(String(localized: "Drawing, with scripts running"))
		load(webView, context: context)
		return webView
	}

	func updateNSView(_ webView: WKWebView, context: Context) {
		if context.coordinator.server.text != text || context.coordinator.generation != generation {
			load(webView, context: context)
		}
	}

	private func load(_ webView: WKWebView, context: Context) {
		context.coordinator.server.text = text
		context.coordinator.generation = generation
		webView.load(URLRequest(url: Self.documentURL))
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
		let server = Server()
		var generation = 0

		/// Only the drawing itself loads; links, form posts and script-driven
		/// navigations go nowhere.
		func webView(
			_ webView: WKWebView, decidePolicyFor action: WKNavigationAction
		) async -> WKNavigationActionPolicy {
			action.request.url == ScriptPreview.documentURL
				&& action.targetFrame?.isMainFrame == true
				? .allow : .cancel
		}

		/// No pop-up windows.
		func webView(
			_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
			for action: WKNavigationAction, windowFeatures: WKWindowFeatures
		) -> WKWebView? { nil }
	}

	/// Serves the drawing, and nothing else, under a policy that lets its own
	/// inline scripts run but loads nothing from anywhere.
	final class Server: NSObject, WKURLSchemeHandler {
		var text = ""

		static let policy =
			"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"

		func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
			guard task.request.url == ScriptPreview.documentURL else {
				task.didFailWithError(URLError(.fileDoesNotExist))
				return
			}
			let data = Data(text.utf8)
			let response = HTTPURLResponse(
				url: ScriptPreview.documentURL, statusCode: 200, httpVersion: "HTTP/1.1",
				headerFields: [
					"Content-Type": "\(Self.mimeType(for: text)); charset=utf-8",
					"Content-Security-Policy": Self.policy,
					"Content-Length": "\(data.count)",
				])!
			task.didReceive(response)
			task.didReceive(data)
			task.didFinish()
		}

		func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

		/// An SVG document when the root is <svg>; a page holding a drawing
		/// (see "non-svg roots") is shown as the page.
		static func mimeType(for text: String) -> String {
			let rootTag = TagScanner.tags(in: text).first { $0.kind != .end }?.name.lowercased()
			switch rootTag {
			case "svg", nil: return "image/svg+xml"
			case "html": return "text/html"
			default: return "application/xhtml+xml"
			}
		}
	}
}

/// Shown in preview mode when the drawing has scripts: they're off until you
/// run them, and while they run you can start them over or stop them.
struct ScriptBanner: View {
	var isRunning: Bool
	var run: () -> Void
	var restart: () -> Void
	var stop: () -> Void

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "curlybraces")
				.foregroundStyle(isRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 0) {
				(isRunning ? Text("Scripts are running") : Text("This drawing has scripts"))
					.font(.callout.weight(.medium))
				(isRunning
					? Text("Offline, and anything they change isn't saved.")
					: Text("They're off. Run them to see the drawing as a browser would."))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			if isRunning {
				Button("Restart", systemImage: "arrow.clockwise", action: restart)
					.labelStyle(.iconOnly)
					.controlSize(.small)
					.help("Run the scripts again from the start")
				Button("Stop", action: stop)
					.buttonStyle(.borderedProminent)
					.controlSize(.small)
					.help("Stop the scripts and show the drawing as it's saved")
			} else {
				Button("Run Scripts", action: run)
					.buttonStyle(.borderedProminent)
					.controlSize(.small)
					.help(
						"Run the drawing's scripts, cut off from the network and the rest of Lines")
			}
		}
		.padding(.leading, 12)
		.padding(.trailing, 6)
		.padding(.vertical, 6)
		.glassEffect(.regular, in: .capsule)
		.shadow(color: .black.opacity(0.12), radius: 8, y: 3)
	}
}
