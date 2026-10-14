import AppKit
import SwiftUI

/// A compact number field whose label you can drag left and right to change
/// the value, like Figma's and Pixelmator's inspectors. Shift moves in 10s,
/// Option in tenths; click the number to type an exact value.
struct ScrubField: View {
	var label: String
	var systemImage: String? = nil
	var value: Double?
	var unit: String = ""
	var range: ClosedRange<Double> = -1_000_000...1_000_000
	var step: Double = 1
	var onChange: (Double) -> Void

	@State private var draft = ""
	@State private var dragStart: Double?
	@FocusState private var focused: Bool
	@State private var isHovered = false

	var body: some View {
		HStack(spacing: 4) {
			labelView
				.frame(width: 18)
				.contentShape(.rect)
				.onHover { inside in
					isHovered = inside
					if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
				}
				.gesture(scrub)
				.help("Drag to adjust \(label)")

			TextField(label, text: $draft)
				.textFieldStyle(.plain)
				.monospacedDigit()
				.multilineTextAlignment(.trailing)
				.focused($focused)
				.onSubmit(commitDraft)
				.onChange(of: focused) { _, isFocused in if !isFocused { commitDraft() } }

			if !unit.isEmpty {
				Text(unit).foregroundStyle(.tertiary)
			}
		}
		.font(.callout)
		.padding(.horizontal, 8)
		.frame(height: 28)
		.background(.fill.tertiary, in: .rect(cornerRadius: 7, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.strokeBorder(
					focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
		}
		.onAppear { draft = Self.format(value) }
		.onChange(of: value) { _, new in if !focused { draft = Self.format(new) } }
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(label)
		.accessibilityValue(Self.format(value) + unit)
		.accessibilityAdjustableAction { direction in
			let v = value ?? 0
			send(direction == .increment ? v + step : v - step)
		}
	}

	@ViewBuilder
	private var labelView: some View {
		if let systemImage {
			Image(systemName: systemImage)
				.foregroundStyle(
					isHovered || dragStart != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
				)
		} else {
			Text(label)
				.fontWeight(.medium)
				.foregroundStyle(
					isHovered || dragStart != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
				)
		}
	}

	private var scrub: some Gesture {
		DragGesture(minimumDistance: 1)
			.onChanged { drag in
				let start = dragStart ?? (value ?? 0)
				dragStart = start
				let flags = NSEvent.modifierFlags
				let scale = flags.contains(.shift) ? 10 : flags.contains(.option) ? 0.1 : 1
				let raw = start + (drag.translation.width / 2).rounded() * step * scale
				send(raw)
			}
			.onEnded { _ in dragStart = nil }
	}

	private func commitDraft() {
		let cleaned = draft.replacingOccurrences(of: unit, with: "").trimmingCharacters(
			in: .whitespaces)
		guard let v = Double(cleaned) else {
			draft = Self.format(value)
			return
		}
		if v != value { send(v) }
	}

	private func send(_ v: Double) {
		let clamped = min(max((v * 100).rounded() / 100, range.lowerBound), range.upperBound)
		draft = Self.format(clamped)
		onChange(clamped)
	}

	static func format(_ v: Double?) -> String {
		guard let v else { return "" }
		return v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
	}
}

/// A titled group of inspector controls on a soft card, for the floating panel.
struct InspectorCard<Content: View>: View {
	var title: String?
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let title {
				Text(title)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.leading, 4)
			}
			VStack(alignment: .leading, spacing: 10) {
				content
			}
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.fill.quinary, in: .rect(cornerRadius: 12, style: .continuous))
		}
	}
}
