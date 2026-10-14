import SwiftUI

/// The one icon-button look used across Lines: a square that tints on hover,
/// darkens when pressed, and takes the accent when it's the active choice.
/// Floating controls put these on a `FloatingStrip`; panels use them as is.
struct IconButtonStyle: ButtonStyle {
	var size: CGFloat = 34
	var isSelected = false

	func makeBody(configuration: Configuration) -> some View {
		IconButtonBody(configuration: configuration, size: size, isSelected: isSelected)
	}
}

private struct IconButtonBody: View {
	var configuration: ButtonStyleConfiguration
	var size: CGFloat
	var isSelected: Bool

	@Environment(\.isEnabled) private var isEnabled
	@State private var isHovered = false

	var body: some View {
		configuration.label
			.labelStyle(.iconOnly)
			.font(.system(size: size * 0.44, weight: .medium))
			.foregroundStyle(
				!isEnabled
					? AnyShapeStyle(.tertiary)
					: isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
			)
			.frame(width: size, height: size)
			.background(fill, in: .rect(cornerRadius: size * 0.24, style: .continuous))
			.contentShape(.rect)
			.onHover { isHovered = $0 }
			.animation(.easeOut(duration: 0.12), value: isHovered)
	}

	private var fill: AnyShapeStyle {
		if isSelected { return AnyShapeStyle(.tint.opacity(configuration.isPressed ? 0.28 : 0.18)) }
		if configuration.isPressed { return AnyShapeStyle(.quaternary.opacity(1.6)) }
		if isHovered && isEnabled { return AnyShapeStyle(.quaternary) }
		return AnyShapeStyle(.clear)
	}
}

extension ButtonStyle where Self == IconButtonStyle {
	/// A square icon button; `size` is its side in points.
	static func icon(size: CGFloat = 34, selected: Bool = false) -> IconButtonStyle {
		IconButtonStyle(size: size, isSelected: selected)
	}
	static var icon: IconButtonStyle { IconButtonStyle() }
}

/// A floating group of controls on Liquid Glass: the tools palette, the zoom
/// buttons and the graph's actions all sit on one of these.
struct FloatingStrip<Content: View>: View {
	var axis: Axis = .vertical
	@ViewBuilder var content: Content

	var body: some View {
		Group {
			if axis == .vertical {
				VStack(spacing: 2) { content }
			} else {
				HStack(spacing: 2) { content }
			}
		}
		.padding(6)
		.fixedSize()
		.glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
		.shadow(color: .black.opacity(0.14), radius: 10, y: 4)
	}
}

/// A short divider between groups in a `FloatingStrip`.
struct StripDivider: View {
	var axis: Axis = .vertical

	var body: some View {
		if axis == .vertical {
			Divider().frame(width: 24).padding(.vertical, 3)
		} else {
			Divider().frame(height: 24).padding(.horizontal, 3)
		}
	}
}
