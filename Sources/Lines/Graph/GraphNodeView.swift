import SwiftFlow
import SwiftUI

struct GraphNodeView: View {
	var node: Node<GraphNodeData>

	static func size(for data: GraphNodeData) -> CGSize {
		CGSize(width: 200, height: 52 + CGFloat(data.inputs.count) * 20)
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

			if !data.inputs.isEmpty {
				Divider()
				VStack(alignment: .leading, spacing: 0) {
					ForEach(data.inputs, id: \.self) { input in
						HStack(spacing: 6) {
							Handle(
								nodeId: node.id, id: input, type: .target, position: .left,
								color: data.connected.contains(input)
									? Graph.color(for: input) : .gray
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
			.opacity(0.6)
		}
		.overlay(alignment: .bottom) {
			Handle(
				nodeId: node.id, id: "children", type: .source, position: .bottom,
				isConnectable: false
			)
			.offset(y: 6)
			.opacity(0.6)
		}
		.overlay(alignment: .trailing) {
			if data.hasOutput {
				Handle(nodeId: node.id, id: "ref", type: .source, position: .right, color: tint)
					.offset(x: 6)
					.help("Drag to an input to use this element")
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
}
