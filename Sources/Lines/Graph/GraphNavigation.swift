import AppKit
import SwiftFlow
import SwiftUI

/// Middle-button drag pans the graph, and scrolling (mouse wheel or
/// trackpad) zooms around the pointer. Dragging empty space also pans.
struct GraphNavigation: NSViewRepresentable {
	var flow: SwiftFlowInstance

	func makeNSView(context: Context) -> MonitorView { MonitorView() }
	func updateNSView(_ view: MonitorView, context: Context) { view.flow = flow }

	final class MonitorView: NSView {
		weak var flow: SwiftFlowInstance?
		private var monitor: Any?
		private var panning = false

		override var isFlipped: Bool { true }
		override func hitTest(_ point: NSPoint) -> NSView? { nil }

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if let monitor {
				NSEvent.removeMonitor(monitor)
				self.monitor = nil
			}
			guard window != nil else { return }
			// AppKit calls the newest local monitor first, so install after
			// SwiftFlow's own scroll monitor to see mouse-wheel events before it.
			DispatchQueue.main.async { [weak self] in self?.install() }
		}

		private func install() {
			monitor = NSEvent.addLocalMonitorForEvents(
				matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp, .scrollWheel]
			) { [weak self] event in
				guard let self, let flow, event.window === self.window else { return event }
				let point = self.convert(event.locationInWindow, from: nil)
				switch event.type {
				case .otherMouseDown where event.buttonNumber == 2:
					guard self.bounds.contains(point) else { return event }
					self.panning = true
					NSCursor.closedHand.push()
					return nil
				case .otherMouseDragged where self.panning:
					var vp = flow.viewport
					vp.x += event.deltaX
					vp.y += event.deltaY
					flow.setViewport(vp, animated: false)
					return nil
				case .otherMouseUp where self.panning:
					self.panning = false
					NSCursor.pop()
					return nil
				// Scrolling zooms around the pointer: wheels in notches, trackpads smoothly.
				case .scrollWheel:
					guard self.bounds.contains(point), event.scrollingDeltaY != 0 else {
						return event
					}
					let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
					var vp = flow.viewport
					let zoom = min(
						max(vp.zoom * pow(1.0015, delta), Viewport.minZoom), Viewport.maxZoom)
					vp.x = point.x - (point.x - vp.x) * zoom / vp.zoom
					vp.y = point.y - (point.y - vp.y) * zoom / vp.zoom
					vp.zoom = zoom
					flow.setViewport(vp, animated: false)
					return nil
				default:
					return event
				}
			}
		}

		deinit {
			if let monitor { NSEvent.removeMonitor(monitor) }
		}
	}
}
