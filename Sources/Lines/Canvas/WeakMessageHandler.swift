import WebKit

/// Avoids the retain cycle WKUserContentController creates with its handlers.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
	weak var controller: CanvasController?
	init(_ controller: CanvasController) { self.controller = controller }

	func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage)
	{
		guard let body = message.body as? [String: Any] else { return }
		MainActor.assumeIsolated { controller?.handle(message: body) }
	}
}
