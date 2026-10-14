import SwiftFlow
import SwiftUI

struct GraphNodeView: View {
	var node: Node<GraphNodeData>
	var controller: CanvasController? = nil

	static func size(for data: GraphNodeData) -> CGSize {
		let preview: CGFloat = (data.preview?.isEmpty == false) ? 30 : 0
		return CGSize(width: 200, height: 52 + preview + CGFloat(data.inputs.count) * 20)
	}

	var body: some View {
		let data = node.data
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 8) {
				Image(systemName: InspectorView.symbol(for: data.tag, isRoot: false))
					.foregroundStyle(tint)
					.frame(width: 18)
				VStack(alignment: .leading, spacing: 0) {
					Text(data.name).font(.callout.weight(.semibold)).lineLimit(1)
					Text("<\(data.tag)>").font(.caption.monospaced()).foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				if data.isHidden {
					Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 10)
			.frame(height: 44)

			if let preview = data.preview, !preview.isEmpty {
				previewRow(preview, kind: data.kind)
					.padding(.horizontal, 10)
					.frame(height: 30)
			}

			if !data.inputs.isEmpty {
				Divider()
				VStack(alignment: .leading, spacing: 0) {
					ForEach(data.inputs, id: \.self) { input in
						HStack(spacing: 6) {
							Handle(
								nodeId: node.id, id: input, type: .target, position: .left,
								color: data.connected.contains(input)
									? Graph.color(for: input) : .gray,
								// Inputs only receive: connections start from an output.
								isConnectable: false
							)
							.offset(x: -6)
							Text(input).font(.caption.monospaced()).foregroundStyle(.secondary)
						}
						.frame(height: 20)
					}
				}
				.padding(.vertical, 4)
			}
		}
		.frame(width: Self.size(for: data).width, alignment: .leading)
		.background(.background, in: .rect(cornerRadius: 10, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(
					node.selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
					lineWidth: node.selected ? 2 : 1)
		}
		.overlay(alignment: .top) {
			Handle(
				nodeId: node.id, id: "parent", type: .target, position: .top, isConnectable: false
			)
			.offset(y: -6)
			.opacity(0)  // Structure edges attach here; the dots themselves are just clutter.
		}
		.overlay(alignment: .bottom) {
			Handle(
				nodeId: node.id, id: "children", type: .source, position: .bottom,
				isConnectable: false
			)
			.offset(y: 6)
			.opacity(0)  // Structure edges attach here; the dots themselves are just clutter.
		}
		.overlay(alignment: .trailing) {
			if data.hasOutput {
				Handle(nodeId: node.id, id: "ref", type: .source, position: .right, color: tint)
					.offset(x: 6)
					.help("Drag to an input to use this element")
			}
		}
		.contextMenu {
			if let controller {
				Button("Show on Canvas", systemImage: "photo") {
					controller.select(order: data.order)
					controller.layout = .canvas
				}
				Button("Remove Its References", systemImage: "link.badge.plus") {
					controller.removeAllReferences(order: data.order)
				}
				.disabled(data.connected.isEmpty)
				Divider()
				Button("Delete", systemImage: "trash", role: .destructive) {
					controller.delete(order: data.order)
				}
			}
		}
		.shadow(color: .black.opacity(0.08), radius: 3, y: 1)
		.opacity(data.isHidden ? 0.6 : 1)
	}

	private var tint: Color {
		switch node.data.kind {
		case .paint: .orange
		case .clip: .teal
		case .mask: .purple
		case .filter: .pink
		case .symbol: .indigo
		case .group, .container: .secondary
		case .element: .accentColor
		}
	}

	/// A gradient's colours as a strip, or a filter's effects as chips.
	@ViewBuilder
	private func previewRow(_ preview: [String], kind: GraphNodeData.Kind) -> some View {
		if kind == .paint {
			let colours = preview.map { CSSColor.parse($0) ?? .black }
			RoundedRectangle(cornerRadius: 5, style: .continuous)
				.fill(
					LinearGradient(
						colors: colours.count > 1 ? colours : colours + colours,
						startPoint: .leading,
						endPoint: .trailing)
				)
				.overlay {
					RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator)
				}
				.frame(height: 16)
				.help("Stops: " + preview.joined(separator: ", "))
		} else {
			HStack(spacing: 4) {
				ForEach(Array(preview.prefix(3).enumerated()), id: \.offset) { _, effect in
					Text(Self.effectName(effect))
						.font(.caption2.weight(.medium))
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(tint.opacity(0.18), in: .capsule)
				}
				if preview.count > 3 {
					Text("+\(preview.count - 3)").font(.caption2).foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
			}
		}
	}

	static func effectName(_ primitive: String) -> String {
		switch primitive {
		case "feGaussianBlur": "Blur"
		case "feDropShadow": "Shadow"
		case "feOffset": "Offset"
		case "feColorMatrix": "Colour"
		case "feFlood": "Flood"
		case "feBlend": "Blend"
		case "feComposite": "Composite"
		case "feMerge": "Merge"
		case "feMorphology": "Morphology"
		case "feTurbulence": "Noise"
		case "feDisplacementMap": "Displace"
		default: String(primitive.dropFirst(2))
		}
	}
}
