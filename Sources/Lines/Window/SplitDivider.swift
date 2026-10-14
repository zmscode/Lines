import AppKit
import SwiftUI

/// A thin, draggable divider like NSSplitView's, for the code panel.
struct SplitDivider: View {
	@Binding var width: Double
	var range: ClosedRange<Double> = 220...900

	@State private var startWidth: Double?

	var body: some View {
		Rectangle()
			.fill(.separator)
			.frame(width: 1)
			.padding(.horizontal, 3)
			.contentShape(.rect)
			.padding(.horizontal, -3)
			.onHover { inside in
				if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
			}
			.gesture(
				DragGesture(minimumDistance: 1, coordinateSpace: .global)
					.onChanged { value in
						let start = startWidth ?? width
						startWidth = start
						width = min(
							max(start + value.translation.width, range.lowerBound), range.upperBound
						)
					}
					.onEnded { _ in startWidth = nil }
			)
			.accessibilityElement()
			.accessibilityLabel("Code panel width")
			.accessibilityValue("\(Int(width)) points")
			.accessibilityAdjustableAction { direction in
				switch direction {
				case .increment: width = min(width + 20, range.upperBound)
				case .decrement: width = max(width - 20, range.lowerBound)
				@unknown default: break
				}
			}
	}
}
