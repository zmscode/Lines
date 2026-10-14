import SwiftUI

/// The animation timeline, floating along the bottom of the viewer: transport
/// controls, a ruler to scrub, and one bar per animation grouped by the
/// element it animates. Bars drag to change when an animation begins, and
/// their trailing edge drags to change its duration.
struct TimelinePanel: View {
	var controller: CanvasController
	var close: () -> Void

	static let height: CGFloat = 220
	static let labelWidth: CGFloat = 200
	static let rowHeight: CGFloat = 26
	static let rulerHeight: CGFloat = 22

	var body: some View {
		VStack(spacing: 0) {
			TimelineHeader(controller: controller, close: close)
			Divider()
			if controller.animations.isEmpty {
				empty
			} else {
				TimelineTracks(controller: controller)
			}
		}
		.frame(height: Self.height)
		.floatingPanelChrome()
	}

	private var empty: some View {
		ContentUnavailableView {
			Label("No Animations", systemImage: "film.stack")
		} description: {
			Text(
				controller.hasElementSelection
					? "Add one to the selected element with the + menu."
					: "Select an element, then add an animation with the + menu.")
		}
		.controlSize(.small)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: Header

private struct TimelineHeader: View {
	var controller: CanvasController
	var close: () -> Void

	private static let speeds: [Double] = [0.25, 0.5, 1, 1.5, 2]
	@State private var chosenPreset: [String: Int] = [:]

	var body: some View {
		HStack(spacing: 2) {
			Text("Timeline").font(.headline).padding(.trailing, 8)

			Button("Back to Start", systemImage: "backward.end.fill") {
				controller.seek(to: 0)
			}
			.buttonStyle(.icon(size: 26))
			.help("Back to Start")
			Button(
				controller.isPlaying ? "Pause" : "Play",
				systemImage: controller.isPlaying ? "pause.fill" : "play.fill"
			) {
				if controller.isPlaying { controller.pause() } else { controller.play() }
			}
			.buttonStyle(.icon(size: 26))
			.help(controller.isPlaying ? "Pause" : "Play")
			Button("Stop", systemImage: "stop.fill") { controller.stop() }
				.buttonStyle(.icon(size: 26))
				.help("Stop and return to the start")
			Button("Step Back", systemImage: "chevron.left") {
				controller.pause()
				controller.seek(to: max(0, controller.animationTime - 0.1))
			}
			.buttonStyle(.icon(size: 26))
			.help("Back 0.1s")
			Button("Step Forward", systemImage: "chevron.right") {
				controller.pause()
				controller.seek(to: controller.animationTime + 0.1)
			}
			.buttonStyle(.icon(size: 26))
			.help("Forward 0.1s")

			Text(AnimationInfo.format(seconds: controller.animationTime))
				.font(.callout.monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(minWidth: 56, alignment: .leading)
				.padding(.leading, 6)

			Menu {
				Picker("Speed", selection: speed) {
					ForEach(Self.speeds, id: \.self) { Text(Self.speedTitle($0)).tag($0) }
				}
				.pickerStyle(.inline)
			} label: {
				Text(Self.speedTitle(controller.animationSpeed))
					.font(.callout.monospacedDigit())
			}
			.menuStyle(.button)
			.buttonStyle(.borderless)
			.fixedSize()
			.help("Playback speed")

			Spacer()

			// Like the tools palette's animation slot: click adds the last preset
			// used; right-click or the corner triangle lists them all.
			PaletteSlot(
				id: "timeline.animate",
				options: AnimationPreset.allCases.map { preset in
					PaletteOption(
						title: "Add \(preset.title)", symbol: preset.symbol,
						help: targetOrder == nil
							? "Select an element to animate"
							: "Add \(preset.title) to the selection",
						effect: preset.effect
					) {
						if let order = targetOrder, controller.isEditing {
							controller.addAnimation(preset, toOrder: order)
						} else {
							NSSound.beep()
						}
					}
				}, chosen: $chosenPreset, isSelected: false, size: 28
			)
			.opacity(targetOrder == nil || !controller.isEditing ? 0.5 : 1)

			Button("Delete Animation", systemImage: "trash") {
				if let order = selectedAnimation { controller.delete(order: order) }
			}
			.buttonStyle(.icon(size: 26))
			.disabled(selectedAnimation == nil || !controller.isEditing)
			.help("Delete the selected animation")

			Button("Close", systemImage: "xmark", action: close)
				.buttonStyle(.icon(size: 24))
				.help("Close Timeline")
				.padding(.leading, 4)
		}
		.padding(.leading, 14)
		.padding(.trailing, 8)
		.padding(.vertical, 6)
	}

	private var speed: Binding<Double> {
		Binding(get: { controller.animationSpeed }, set: { controller.animationSpeed = $0 })
	}

	static func speedTitle(_ s: Double) -> String {
		s == s.rounded() ? "\(Int(s))×" : "\(s.formatted())×"
	}

	/// The selected animation's order, if an animation is selected.
	private var selectedAnimation: Int? {
		guard let s = controller.selection, AnimationTag.contains(s.tag) else { return nil }
		return s.order
	}

	/// The element new animations go on: the selection, or the element a
	/// selected animation animates.
	private var targetOrder: Int? {
		guard let s = controller.selection, !s.isRoot else { return nil }
		if AnimationTag.contains(s.tag) {
			return controller.outline.first { $0.order == s.order }?.parent
		}
		return s.order
	}
}

// MARK: Tracks

private struct TimelineTracks: View {
	var controller: CanvasController

	/// Elements and their animations, in document order.
	private var groups: [(target: OutlineItem?, animations: [AnimationInfo])] {
		var order: [Int] = []
		var byTarget: [Int: [AnimationInfo]] = [:]
		for a in controller.animations {
			let key = a.target?.order ?? -1
			if byTarget[key] == nil { order.append(key) }
			byTarget[key, default: []].append(a)
		}
		return order.map { key in
			(byTarget[key]?.first?.target, byTarget[key] ?? [])
		}
	}

	/// The seconds shown across the track: everything, with room to spare.
	private var span: Double {
		let ends = controller.animations.map { a in
			a.repeatsForever ? a.begin + (a.duration ?? 1) * 2 : a.end
		}
		let longest = max(ends.max() ?? 0, controller.animationTime + 0.5, 3)
		let steps: [Double] = [3, 4, 5, 6, 8, 10, 12, 15, 20, 30, 45, 60, 90, 120]
		return steps.first { $0 >= longest * 1.1 } ?? (longest * 1.1).rounded(.up)
	}

	var body: some View {
		GeometryReader { geo in
			let trackWidth = max(100, geo.size.width - TimelinePanel.labelWidth - 16)
			let scale = trackWidth / span
			VStack(spacing: 0) {
				HStack(spacing: 0) {
					Color.clear.frame(width: TimelinePanel.labelWidth)
					TimelineRuler(span: span, scale: scale) { t in scrub(to: t) }
						.frame(width: trackWidth)
				}
				.frame(height: TimelinePanel.rulerHeight)
				ScrollView(.vertical) {
					VStack(spacing: 0) {
						ForEach(groups, id: \.target?.path) { group in
							GroupRow(
								target: group.target, isSelected: isSelected(group.target?.order)
							) {
								if let order = group.target?.order {
									controller.select(order: order)
								}
							}
							ForEach(group.animations) { animation in
								HStack(spacing: 0) {
									AnimationLabel(
										animation: animation,
										isSelected: isSelected(animation.order)
									)
									.frame(width: TimelinePanel.labelWidth, alignment: .leading)
									.contentShape(.rect)
									.onTapGesture { controller.select(order: animation.order) }
									AnimationBar(
										animation: animation, scale: scale, span: span,
										isSelected: isSelected(animation.order),
										isEditable: controller.isEditing,
										select: { controller.select(order: animation.order) },
										setBegin: { seconds in
											controller.setAttribute(
												"begin", Self.clock(seconds),
												onOrder: animation.order)
										},
										setDuration: { seconds in
											controller.setAttribute(
												"dur", Self.clock(seconds),
												onOrder: animation.order)
										}
									)
									.frame(width: trackWidth, height: TimelinePanel.rowHeight)
									.background {
										// Clicking or dragging between bars moves the playhead.
										Color.clear
											.contentShape(.rect)
											.gesture(
												DragGesture(minimumDistance: 0)
													.onChanged { value in
														scrub(to: value.location.x / scale)
													})
									}
								}
							}
						}
					}
					.padding(.bottom, 6)
				}
				.scrollIndicators(.automatic)
			}
			.overlay {
				// The line runs through the tracks; its head sits in the ruler and
				// drags to scrub.
				GeometryReader { box in
					let x = TimelinePanel.labelWidth + controller.animationTime * scale
					Rectangle()
						.fill(.tint)
						.frame(
							width: 1.5,
							height: max(0, box.size.height - TimelinePanel.rulerHeight + 4)
						)
						.position(
							x: x,
							y: TimelinePanel.rulerHeight - 4
								+ (box.size.height - TimelinePanel.rulerHeight + 4) / 2
						)
						.allowsHitTesting(false)
					PlayheadHandle(time: controller.animationTime)
						.position(x: x, y: TimelinePanel.rulerHeight / 2)
						.gesture(
							DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
								.onChanged { value in
									scrub(to: (value.location.x - TimelinePanel.labelWidth) / scale)
								}
						)
						.pointerStyle(.columnResize)
						.help("Drag to scrub")
				}
			}
			.coordinateSpace(.named("timeline"))
			.padding(.horizontal, 8)
		}
	}

	/// Pauses and moves the playhead (snapped to 0.01s).
	private func scrub(to seconds: Double) {
		if controller.isPlaying { controller.pause() }
		controller.seek(to: (max(0, min(seconds, span)) * 100).rounded() / 100)
	}

	private func isSelected(_ order: Int?) -> Bool {
		order != nil && controller.selection?.order == order
	}

	/// Seconds as a short SMIL clock value: "1.5s".
	static func clock(_ seconds: Double) -> String {
		let rounded = (seconds * 100).rounded() / 100
		return "\(rounded.formatted(.number.precision(.fractionLength(0...2))))s"
	}
}

private struct GroupRow: View {
	var target: OutlineItem?
	var isSelected: Bool
	var select: () -> Void

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: InspectorView.symbol(for: target?.tag ?? "g", isRoot: false))
				.foregroundStyle(.secondary)
				.frame(width: 16)
			Text(target?.displayName ?? "Unknown")
				.font(.callout.weight(.semibold))
				.lineLimit(1)
			Spacer()
		}
		.padding(.horizontal, 6)
		.frame(height: TimelinePanel.rowHeight)
		.background(
			isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 6)
		)
		.contentShape(.rect)
		.onTapGesture(perform: select)
		.help("Select \(target?.displayName ?? "element")")
	}
}

private struct AnimationLabel: View {
	var animation: AnimationInfo
	var isSelected: Bool

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: animation.symbol)
				.foregroundStyle(.indigo)
				.frame(width: 16)
			Text(animation.property)
				.lineLimit(1)
			Spacer(minLength: 4)
			Text(animation.duration.map(AnimationInfo.format(seconds:)) ?? "–")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
		}
		.font(.callout)
		.padding(.leading, 22)
		.padding(.trailing, 10)
		.frame(height: TimelinePanel.rowHeight)
		.background(
			isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
			in: .rect(cornerRadius: 6)
		)
		.help("\(animation.property): \(animation.change)")
	}
}

/// One animation's bar. Drag the body to move it in time, the trailing edge to
/// change its duration. Repeats show as ticks; endless repeats run to the end.
private struct AnimationBar: View {
	var animation: AnimationInfo
	var scale: Double
	var span: Double
	var isSelected: Bool
	var isEditable = true
	var select: () -> Void
	var setBegin: (Double) -> Void
	var setDuration: (Double) -> Void

	@State private var moveBy: Double = 0
	@State private var stretchBy: Double = 0

	private var duration: Double { max(0.05, (animation.duration ?? 0.5) + stretchBy) }
	private var begin: Double { max(0, animation.begin + moveBy) }
	private var passes: Double {
		animation.repeatsForever
			? max(1, (span - begin) / duration) : (animation.repeatCount ?? 1)
	}

	var body: some View {
		let x = begin * scale
		let width = max(6, duration * passes * scale)
		ZStack(alignment: .leading) {
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(.indigo.opacity(isSelected ? 0.55 : 0.32))
				.overlay {
					RoundedRectangle(cornerRadius: 5, style: .continuous)
						.strokeBorder(.indigo.opacity(isSelected ? 0.9 : 0.5), lineWidth: 1)
				}
				.overlay(alignment: .leading) { repeatTicks(width: width) }
				.overlay(alignment: .leading) {
					Text(animation.change)
						.font(.caption2)
						.lineLimit(1)
						.foregroundStyle(.primary.opacity(0.8))
						.padding(.horizontal, 6)
						.frame(maxWidth: max(0, duration * scale - 10), alignment: .leading)
				}
				.frame(width: width, height: TimelinePanel.rowHeight - 8)
				.contentShape(.rect)
				.gesture(
					DragGesture(minimumDistance: 2)
						.onChanged { value in
							select()
							moveBy = value.translation.width / scale
						}
						.onEnded { _ in
							setBegin(Self.snap(begin))
							moveBy = 0
						},
					isEnabled: !animation.isCSS && isEditable
				)
				.onTapGesture(perform: select)
				.help(
					animation.isCSS
						? "A CSS animation: edit its timing in the stylesheet"
						: "Drag to change when it begins"
				)
				.offset(x: x)

			// The first pass's trailing edge sets the duration.
			if !animation.isCSS && isEditable { durationHandle(x: x) }
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(animation.property)
		.accessibilityValue(
			"begins at \(AnimationInfo.format(seconds: begin)), lasts \(AnimationInfo.format(seconds: duration))"
				+ (animation.repeatsForever ? ", repeats forever" : "")
		)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.accessibilityAction { select() }
		.accessibilityAdjustableAction { direction in
			// Nudges when it begins, a tenth of a second at a time.
			guard isEditable, !animation.isCSS else { return }
			switch direction {
			case .increment: setBegin(Self.snap(animation.begin + 0.1))
			case .decrement: setBegin(Self.snap(max(0, animation.begin - 0.1)))
			@unknown default: break
			}
		}
	}

	private func durationHandle(x: Double) -> some View {
		Rectangle()
			.fill(.clear)
			.frame(width: 8, height: TimelinePanel.rowHeight - 8)
			.contentShape(.rect)
			.pointerStyle(.frameResize(position: .trailing))
			.gesture(
				DragGesture(minimumDistance: 1)
					.onChanged { value in
						select()
						stretchBy = value.translation.width / scale
					}
					.onEnded { _ in
						setDuration(Self.snap(duration))
						stretchBy = 0
					}
			)
			.help("Drag to change the duration")
			.offset(x: x + duration * scale - 4)
	}

	/// A tick at the end of each pass after the first.
	private func repeatTicks(width: Double) -> some View {
		Canvas { context, size in
			guard duration * scale > 4 else { return }
			var x = duration * scale
			while x < size.width - 1 {
				context.stroke(
					Path { p in
						p.move(to: CGPoint(x: x, y: 3))
						p.addLine(to: CGPoint(x: x, y: size.height - 3))
					}, with: .color(.indigo.opacity(0.8)), lineWidth: 1)
				x += duration * scale
			}
		}
		.frame(width: width)
		.allowsHitTesting(false)
	}

	/// To the nearest 0.05s.
	static func snap(_ seconds: Double) -> Double { (seconds * 20).rounded() / 20 }
}

/// Seconds along the top; click or drag to scrub.
private struct TimelineRuler: View {
	var span: Double
	var scale: Double
	var seek: (Double) -> Void

	var body: some View {
		Canvas { context, size in
			let step: Double = span <= 5 ? 0.5 : span <= 15 ? 1 : span <= 45 ? 5 : 10
			var t = 0.0
			while t <= span + 0.001 {
				let x = t * scale
				let major = (t / step).rounded().truncatingRemainder(dividingBy: 2) == 0
				context.stroke(
					Path { p in
						p.move(to: CGPoint(x: x, y: size.height - (major ? 8 : 4)))
						p.addLine(to: CGPoint(x: x, y: size.height))
					}, with: .color(.secondary), lineWidth: 1)
				if major {
					context.draw(
						Text(t.formatted(.number.precision(.fractionLength(0...1))) + "s")
							.font(.caption2.monospacedDigit())
							.foregroundStyle(.secondary),
						at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
				}
				t += step
			}
		}
		.contentShape(.rect)
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { value in seek(max(0, value.location.x / scale)) }
		)
		.help("Click or drag to scrub")
	}
}

/// The playhead's head: a tab with a point at the bottom, centred on the time.
private struct PlayheadHandle: View {
	var time: Double

	var body: some View {
		VStack(spacing: 0) {
			RoundedRectangle(cornerRadius: 3, style: .continuous)
				.fill(.tint)
				.frame(width: 12, height: 11)
			Triangle()
				.fill(.tint)
				.frame(width: 12, height: 5)
		}
		.frame(width: 12, height: 16)
		.shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
		.contentShape(.rect.inset(by: -6))
		.accessibilityElement()
		.accessibilityLabel("Playhead")
		.accessibilityValue(AnimationInfo.format(seconds: time))
	}

	private struct Triangle: Shape {
		func path(in r: CGRect) -> Path {
			Path { p in
				p.move(to: CGPoint(x: r.minX, y: r.minY))
				p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
				p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
				p.closeSubpath()
			}
		}
	}
}
