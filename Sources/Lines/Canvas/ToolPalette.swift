import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The tools palette: a vertical strip on the canvas like Photoshop's.
/// Pick a shape tool and drag on the canvas to draw. Slots with more options
/// show a small corner triangle; right-click (or click the triangle) to open
/// them as a mini toolbar. Below the tools, slots apply effects, fills,
/// transforms and animations to the selection, remembering the last one used.
struct ToolPalette: View {
	var controller: CanvasController

	static let buttonSize: CGFloat = 34
	static let width: CGFloat = buttonSize + 12

	/// The option each slot shows, by slot id.
	@State private var chosen: [String: Int] = [:]
	@State private var imageDropShown = false

	var body: some View {
		FloatingStrip {
			ForEach(Array(CanvasTool.groups.enumerated()), id: \.offset) { index, group in
				PaletteSlot(
					id: "tool\(index)", options: group.map(toolOption), chosen: $chosen,
					isSelected: group.contains(controller.tool))
				if index == 1 { StripDivider() }  // navigation tools, then drawing tools
			}
			StripDivider()
			ForEach(actionSlots, id: \.id) { slot in
				PaletteSlot(id: slot.id, options: slot.options, chosen: $chosen, isSelected: false)
			}
			imageButton
			StripDivider()
			BackgroundPill()
		}
		.onChange(of: controller.tool) { _, tool in
			// Keep the slot showing whichever variant was picked (by key or flyout).
			if let index = CanvasTool.groups.firstIndex(where: { $0.contains(tool) }),
				let position = CanvasTool.groups[index].firstIndex(of: tool)
			{
				chosen["tool\(index)"] = position
			}
		}
	}

	// MARK: Tools

	private func toolOption(_ tool: CanvasTool) -> PaletteOption {
		PaletteOption(title: tool.title, symbol: tool.symbol, help: help(for: tool)) {
			controller.setTool(tool)
		}
	}

	private func help(for tool: CanvasTool) -> String {
		let action: String
		switch tool {
		case .select: action = "Select and move elements (drag on empty canvas to select several)"
		case .hand: action = "Pan the canvas"
		case .text: action = "Click to add text"
		default: action = "Drag to draw a \(tool.title.lowercased()) (Shift keeps it even)"
		}
		return tool.key.map { "\(tool.title) (\($0)) — \(action)" } ?? "\(tool.title) — \(action)"
	}

	// MARK: Actions on the selection

	private struct ActionSlot {
		var id: String
		var options: [PaletteOption]
	}

	private var actionSlots: [ActionSlot] {
		[
			ActionSlot(
				id: "effects",
				options: [CanvasController.Definition.shadow, .blur].map(definitionOption)),
			ActionSlot(
				id: "fills",
				options: [CanvasController.Definition.linearGradient, .radialGradient, .pattern]
					.map(definitionOption)),
			ActionSlot(
				id: "masking",
				options: [CanvasController.Definition.clipPath, .mask].map(definitionOption)),
			ActionSlot(
				id: "transform",
				options: [
					onSelection("Rotate Right 90°", "rotate.right") {
						controller.setRotation((controller.selection?.rotation ?? 0) + 90)
					},
					onSelection("Rotate Left 90°", "rotate.left") {
						controller.setRotation((controller.selection?.rotation ?? 0) - 90)
					},
					onSelection(
						"Flip Horizontal",
						"arrow.left.and.right.righttriangle.left.righttriangle.right"
					) {
						controller.flipSelection(horizontally: true)
					},
					onSelection(
						"Flip Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down"
					) {
						controller.flipSelection(horizontally: false)
					},
				]),
			ActionSlot(
				id: "animate",
				options: AnimationPreset.allCases.map { preset in
					onSelection("Animate: \(preset.title)", preset.symbol, effect: preset.effect) {
						if let order = elementOrder {
							controller.addAnimation(preset, toOrder: order)
						}
					}
				}),
		]
	}

	private func definitionOption(_ kind: CanvasController.Definition) -> PaletteOption {
		let verb =
			switch kind {
			case .linearGradient, .radialGradient, .pattern: "Fill with"
			default: "Add"
			}
		return onSelection("\(verb) \(kind.title)", kind.symbol) {
			if let order = elementOrder { controller.addDefinition(kind, applyingTo: order) }
		}
	}

	/// An option that needs something selected; it beeps otherwise.
	private func onSelection(
		_ title: String, _ symbol: String, effect: PaletteEffect = .none,
		perform: @escaping () -> Void
	) -> PaletteOption {
		PaletteOption(
			title: title, symbol: symbol, help: "\(title) (to the selection)", effect: effect
		) {
			if controller.hasElementSelection { perform() } else { NSSound.beep() }
		}
	}

	private var elementOrder: Int? {
		guard let s = controller.selection, !s.isRoot else { return nil }
		return s.order
	}

	// MARK: Image

	/// Click for a drop zone to drag images onto; right-click to choose a file.
	private var imageButton: some View {
		Button("Image", systemImage: "photo.badge.plus") { imageDropShown.toggle() }
			.buttonStyle(.icon(size: Self.buttonSize, selected: imageDropShown))
			.help("Place an image: drop one here, or right-click to choose a file")
			.overlay(alignment: .bottomTrailing) { CornerTriangle() }
			.overlay { RightClickCatcher { chooseImage() } }
			.popover(isPresented: $imageDropShown, arrowEdge: .trailing) {
				ImageDropZone(
					drop: { urls in
						for url in urls { controller.addImage(from: url) }
						imageDropShown = false
					},
					choose: {
						imageDropShown = false
						chooseImage()
					})
			}
	}

	private func chooseImage() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .heic, .svg]
		panel.allowsMultipleSelection = true
		panel.message = "Choose images to place in the drawing."
		let pick: (NSApplication.ModalResponse) -> Void = { response in
			if response == .OK { for url in panel.urls { controller.addImage(from: url) } }
		}
		if let window = controller.webView?.window {
			panel.beginSheetModal(for: window, completionHandler: pick)
		} else {
			pick(panel.runModal())
		}
	}
}

/// Something a palette slot can do.
struct PaletteOption {
	var title: String
	var symbol: String
	var help: String
	var effect: PaletteEffect = .none
	var perform: () -> Void
}

/// A symbol animation for palette icons.
enum PaletteEffect {
	case none, pulse, breathe, rotate, wiggle, bounce, variableColour
}

/// Plays a palette icon's effect: continuously while `isActive`, otherwise
/// every few seconds so the icon reads as an animation.
private struct PaletteEffectModifier: ViewModifier {
	var effect: PaletteEffect
	var isActive: Bool

	func body(content: Content) -> some View {
		let repeating: SymbolEffectOptions =
			isActive ? .repeat(.continuous) : .repeat(.periodic(delay: 3.5))
		switch effect {
		case .none: content
		case .pulse: content.symbolEffect(.pulse, options: repeating)
		case .breathe: content.symbolEffect(.breathe, options: repeating)
		case .rotate: content.symbolEffect(.rotate, options: repeating)
		case .wiggle: content.symbolEffect(.wiggle.left, options: repeating)
		case .bounce: content.symbolEffect(.bounce, options: repeating)
		case .variableColour: content.symbolEffect(.variableColor.iterative, options: repeating)
		}
	}
}

/// One palette button. With several options it shows the last one used, a
/// corner triangle, and a mini toolbar of the rest on right-click.
struct PaletteSlot: View {
	var id: String
	var options: [PaletteOption]
	@Binding var chosen: [String: Int]
	var isSelected: Bool
	var size: CGFloat = ToolPalette.buttonSize

	@State private var flyoutShown = false
	@State private var isHovered = false

	private var current: Int { min(chosen[id] ?? 0, options.count - 1) }

	var body: some View {
		let option = options[current]
		Button(option.title, systemImage: option.symbol, action: option.perform)
			.buttonStyle(.icon(size: size, selected: isSelected))
			.modifier(PaletteEffectModifier(effect: option.effect, isActive: isHovered))
			.onHover { isHovered = $0 }
			.help(options.count > 1 ? option.help + " — right-click for more" : option.help)
			.accessibilityAddTraits(isSelected ? .isSelected : [])
			.overlay(alignment: .bottomTrailing) {
				if options.count > 1 {
					CornerTriangle()
						.contentShape(.rect)
						.onTapGesture { flyoutShown = true }
				}
			}
			.overlay {
				if options.count > 1 { RightClickCatcher { flyoutShown = true } }
			}
			.popover(isPresented: $flyoutShown, arrowEdge: .trailing) {
				// A vertical mini toolbar: each option with its name, like
				// Photoshop's tool flyouts.
				VStack(alignment: .leading, spacing: 2) {
					ForEach(Array(options.enumerated()), id: \.offset) { index, option in
						FlyoutRow(option: option, isSelected: index == current) {
							chosen[id] = index
							flyoutShown = false
							option.perform()
						}
					}
				}
				.padding(6)
			}
			.accessibilityAction(named: "More Options") { flyoutShown = true }
	}
}

private struct FlyoutRow: View {
	var option: PaletteOption
	var isSelected: Bool
	var action: () -> Void

	@State private var isHovered = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				Image(systemName: option.symbol)
					.font(.system(size: 15, weight: .medium))
					.frame(width: 22)
					.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
					.modifier(PaletteEffectModifier(effect: option.effect, isActive: true))
				Text(option.title)
					.lineLimit(1)
				Spacer(minLength: 12)
				if isSelected {
					Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 8)
			.frame(minWidth: 190, minHeight: 30)
			.background(
				isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
				in: .rect(cornerRadius: 7, style: .continuous)
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		.help(option.help)
	}
}

/// Photoshop's hint that a tool has more options.
private struct CornerTriangle: View {
	var body: some View {
		Path { p in
			p.move(to: CGPoint(x: 6, y: 0))
			p.addLine(to: CGPoint(x: 6, y: 6))
			p.addLine(to: CGPoint(x: 0, y: 6))
			p.closeSubpath()
		}
		.fill(.secondary)
		.frame(width: 6, height: 6)
		.padding(4)
		.allowsHitTesting(true)
	}
}

/// Catches right-clicks (and Control-clicks) over a view, letting every other
/// click through to it.
struct RightClickCatcher: NSViewRepresentable {
	var action: () -> Void

	func makeNSView(context: Context) -> CatcherView {
		let view = CatcherView()
		view.action = action
		return view
	}

	func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

	final class CatcherView: NSView {
		var action: (() -> Void)?

		override func hitTest(_ point: NSPoint) -> NSView? {
			guard let event = NSApp.currentEvent else { return nil }
			let isSecondary =
				event.type == .rightMouseDown
				|| (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
			return isSecondary ? super.hitTest(point) : nil
		}

		override func rightMouseDown(with event: NSEvent) { action?() }
		override func mouseDown(with event: NSEvent) { action?() }
	}
}

/// A drop target for images, with a button to choose files instead.
private struct ImageDropZone: View {
	var drop: ([URL]) -> Void
	var choose: () -> Void

	@State private var isTargeted = false

	var body: some View {
		VStack(spacing: 10) {
			VStack(spacing: 6) {
				Image(systemName: "photo.on.rectangle.angled")
					.font(.system(size: 26))
					.foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				Text(isTargeted ? "Release to Place" : "Drop Images Here")
					.font(.callout)
			}
			.frame(width: 200, height: 110)
			.background {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(
						isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
						style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
					)
					.background(
						.tint.opacity(isTargeted ? 0.08 : 0),
						in: .rect(cornerRadius: 12, style: .continuous))
			}
			.dropDestination(for: URL.self) { urls, _ in
				let images = urls.filter {
					UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) ?? false
				}
				guard !images.isEmpty else { return false }
				drop(images)
				return true
			} isTargeted: {
				isTargeted = $0
			}
			Button("Choose File…", action: choose)
				.controlSize(.small)
		}
		.padding(14)
		.animation(.easeOut(duration: 0.12), value: isTargeted)
	}
}
