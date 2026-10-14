import SwiftUI

/// Easing curves offered for an animation, written as SMIL key splines.
enum AnimationEasing: String, CaseIterable, Identifiable {
	case linear, ease, easeIn, easeOut, easeInOut, discrete
	var id: String { rawValue }

	var title: String {
		switch self {
		case .linear: "Linear"
		case .ease: "Ease"
		case .easeIn: "Ease In"
		case .easeOut: "Ease Out"
		case .easeInOut: "Ease In & Out"
		case .discrete: "Step"
		}
	}

	var spline: String? {
		switch self {
		case .ease: "0.25 0.1 0.25 1"
		case .easeIn: "0.42 0 1 1"
		case .easeOut: "0 0 0.58 1"
		case .easeInOut: "0.42 0 0.58 1"
		case .linear, .discrete: nil
		}
	}

	static func of(_ selection: SelectionInfo) -> AnimationEasing {
		switch selection.value("calcMode") {
		case "discrete": return .discrete
		case "spline":
			let first = selection.value("keySplines")?.split(separator: ";").first
				.map { $0.split(whereSeparator: { $0 == " " || $0 == "," }).joined(separator: " ") }
			return allCases.first { $0.spline == first } ?? .ease
		default: return .linear
		}
	}
}

/// The inspector for a selected `<animate>`, `<animateTransform>`,
/// `<animateMotion>` or `<set>`.
struct AnimationCard: View {
	var selection: SelectionInfo
	var controller: CanvasController

	private var tag: String { selection.tag }
	private func value(_ name: String) -> String { selection.value(name) ?? "" }

	var body: some View {
		InspectorCard(title: "Animation") {
			row("Animates") {
				if tag == "animateTransform" {
					Picker("Type", selection: transformType) {
						ForEach(["translate", "scale", "rotate", "skewX", "skewY"], id: \.self) {
							Text($0.capitalized).tag($0)
						}
					}
					.labelsHidden()
				} else if tag == "animateMotion" {
					Text("Motion path").foregroundStyle(.secondary)
				} else {
					AttributeField(title: "Attribute", value: value("attributeName")) {
						set("attributeName", $0)
					}
					.textFieldStyle(.roundedBorder)
				}
			}
			if selection.value("values") != nil {
				row("Values") {
					AttributeField(title: "Values", value: value("values"), prompt: "a; b; c") {
						set("values", $0)
					}
					.textFieldStyle(.roundedBorder)
				}
			} else if tag == "set" {
				row("To") {
					AttributeField(title: "To", value: value("to")) { set("to", $0) }
						.textFieldStyle(.roundedBorder)
				}
			} else if tag != "animateMotion" {
				row("From") {
					AttributeField(title: "From", value: value("from"), prompt: "current") {
						set("from", $0)
					}
					.textFieldStyle(.roundedBorder)
				}
				row("To") {
					AttributeField(title: "To", value: value("to")) { set("to", $0) }
						.textFieldStyle(.roundedBorder)
				}
			}
		}
		InspectorCard(title: "Timing") {
			row("Begin") {
				ScrubField(
					label: "Begin", systemImage: "arrow.right.to.line",
					value: AnimationInfo.seconds(selection.value("begin")) ?? 0, unit: "s",
					range: 0...3600, step: 0.05
				) { set("begin", Self.clock($0), coalesce: true) }
			}
			row("Duration") {
				ScrubField(
					label: "Duration", systemImage: "timer",
					value: AnimationInfo.seconds(selection.value("dur")) ?? 0, unit: "s",
					range: 0.01...3600, step: 0.05
				) { set("dur", Self.clock($0), coalesce: true) }
			}
			row("Repeat") {
				Picker("Repeat", selection: repeatMode) {
					Text("Once").tag(RepeatMode.once)
					Text("Times").tag(RepeatMode.times)
					Text("Forever").tag(RepeatMode.forever)
				}
				.labelsHidden()
			}
			if repeatMode.wrappedValue == .times {
				row("Count") {
					ScrubField(
						label: "Count", systemImage: "repeat",
						value: selection.value("repeatCount").flatMap(Double.init) ?? 2,
						range: 0.5...1000, step: 1
					) { set("repeatCount", ScrubField.format($0), coalesce: true) }
				}
			}
			if tag != "set" {
				row("Easing") {
					Picker("Easing", selection: easing) {
						ForEach(AnimationEasing.allCases) { Text($0.title).tag($0) }
					}
					.labelsHidden()
				}
			}
			Toggle("Hold the end state", isOn: holdsEnd)
				.help("Keep the final value when the animation finishes (fill=\"freeze\")")
			HStack {
				Button("Preview", systemImage: "play.fill") {
					let begin = AnimationInfo.seconds(selection.value("begin")) ?? 0
					controller.seek(to: begin)
					controller.play()
				}
				Spacer()
				Button("Show Timeline", systemImage: "film.stack") {
					controller.showsTimeline = true
				}
			}
			.controlSize(.small)
		}
	}

	private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		HStack {
			Text(title).foregroundStyle(.secondary)
			Spacer()
			content().frame(width: 150)
		}
	}

	private func set(_ name: String, _ v: String?, coalesce: Bool = false) {
		if let v, !v.isEmpty {
			controller.setAttribute(name, v, onOrder: selection.order, coalesce: coalesce)
		} else {
			controller.setAttribute(name, nil, onOrder: selection.order)
		}
	}

	static func clock(_ seconds: Double) -> String {
		"\(((seconds * 1000).rounded() / 1000).formatted(.number.precision(.fractionLength(0...3))))s"
	}

	// MARK: Bindings

	private var transformType: Binding<String> {
		Binding(
			get: { value("type").isEmpty ? "translate" : value("type") }, set: { set("type", $0) })
	}

	enum RepeatMode: Hashable { case once, times, forever }

	private var repeatMode: Binding<RepeatMode> {
		Binding(
			get: {
				switch selection.value("repeatCount") {
				case nil: selection.value("repeatDur") == "indefinite" ? .forever : .once
				case "indefinite": .forever
				default: .times
				}
			},
			set: { mode in
				set("repeatDur", nil)
				switch mode {
				case .once: set("repeatCount", nil)
				case .times: set("repeatCount", "2")
				case .forever: set("repeatCount", "indefinite")
				}
			})
	}

	private var holdsEnd: Binding<Bool> {
		Binding(
			get: { selection.value("fill") == "freeze" },
			set: { set("fill", $0 ? "freeze" : nil) })
	}

	private var easing: Binding<AnimationEasing> {
		Binding(
			get: { AnimationEasing.of(selection) },
			set: { new in
				switch new {
				case .linear:
					set("calcMode", nil)
					set("keySplines", nil)
					set("keyTimes", nil)
				case .discrete:
					set("calcMode", "discrete")
					set("keySplines", nil)
				default:
					// One spline per segment, with evenly spaced key times.
					let count =
						selection.value("values")
						.map { $0.split(separator: ";").count } ?? 2
					let segments = max(1, count - 1)
					let times = (0...segments).map {
						(Double($0) / Double(segments)).formatted(
							.number.precision(.fractionLength(0...3)))
					}
					set("calcMode", "spline")
					set("keyTimes", times.joined(separator: ";"))
					set(
						"keySplines",
						Array(repeating: new.spline ?? "", count: segments).joined(separator: "; "))
				}
			})
	}
}

/// The animations on a selected element, with a menu to add more.
struct ElementAnimationsCard: View {
	var selection: SelectionInfo
	var controller: CanvasController

	private var animations: [AnimationInfo] {
		controller.animations.filter { $0.target?.order == selection.order }
	}

	var body: some View {
		InspectorCard(title: "Animations") {
			ForEach(animations) { animation in
				HStack(spacing: 8) {
					Image(systemName: animation.symbol)
						.foregroundStyle(.indigo)
						.frame(width: 16)
					VStack(alignment: .leading, spacing: 1) {
						Text(animation.property).lineLimit(1)
						Text(summary(animation))
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					Spacer()
					if !animation.isCSS {
						Button("Delete Animation", systemImage: "minus.circle") {
							controller.delete(order: animation.order)
						}
						.buttonStyle(.icon(size: 22))
						.help("Delete this animation")
					}
				}
				.contentShape(.rect)
				.onTapGesture { controller.select(order: animation.order) }
				.help("Select to edit")
			}
			HStack {
				Menu {
					ForEach(AnimationPreset.allCases) { preset in
						Button(preset.title, systemImage: preset.symbol) {
							controller.addAnimation(preset, toOrder: selection.order)
						}
					}
				} label: {
					Label("Add Animation", systemImage: "plus")
				}
				.fixedSize()
				Spacer()
				if !animations.isEmpty {
					Button("Timeline", systemImage: "film.stack") {
						controller.showsTimeline = true
					}
					.help("Show Timeline (⌘4)")
				}
			}
			.controlSize(.small)
		}
	}

	private func summary(_ a: AnimationInfo) -> String {
		var parts = [a.change]
		if let d = a.duration { parts.append(AnimationInfo.format(seconds: d)) }
		if a.repeatsForever { parts.append("loops") }
		return parts.joined(separator: " · ")
	}
}
