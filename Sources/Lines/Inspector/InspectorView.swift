import AppKit
import SwiftUI

struct InspectorView: View {
	var controller: CanvasController

	var body: some View {
		if let selection = controller.selection {
			Form {
				header(selection)
				if !selection.isRoot || selection.value("fill") != nil {
					appearance(selection)
				}
				geometry(selection)
				if let text = selection.textContent {
					Section("Text") {
						AttributeField(title: "Content", value: text, axis: .vertical) {
							controller.setTextContent($0)
						}
						.labelsHidden()
					}
				}
				attributes(selection)
			}
			.formStyle(.grouped)
			.id(selection.path)
		} else {
			ContentUnavailableView(
				"No Document", systemImage: "square.dashed",
				description: Text("Fix the source errors to inspect the drawing.")
			)
		}
	}

	// MARK: Sections

	@ViewBuilder
	private func header(_ selection: SelectionInfo) -> some View {
		Section {
			LabeledContent {
				if !selection.isRoot {
					Button("Select Enclosing Group", systemImage: "arrow.up.square") {
						controller.selectParent()
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.borderless)
					.help("Select Enclosing Group")
				}
			} label: {
				Label {
					Text(selection.isRoot ? "Document" : "<\(selection.tag)>")
						.font(selection.isRoot ? .headline : .headline.monospaced())
				} icon: {
					Image(systemName: Self.symbol(for: selection.tag, isRoot: selection.isRoot))
						.foregroundStyle(.tint)
				}
			}
			if !selection.isRoot {
				AttributeField(title: "ID", value: selection.value("id") ?? "", prompt: "None") {
					$0.isEmpty
						? controller.removeAttribute("id") : controller.setAttribute("id", $0)
				}
			}
		}
	}

	@ViewBuilder
	private func appearance(_ selection: SelectionInfo) -> some View {
		Section("Fill & Stroke") {
			PaintRow(
				title: "Fill", value: selection.value("fill"),
				opacity: selection.value("fill-opacity"),
				controller: controller, attribute: "fill")
			PaintRow(
				title: "Stroke", value: selection.value("stroke"),
				opacity: selection.value("stroke-opacity"),
				controller: controller, attribute: "stroke")
			AttributeField(
				title: "Stroke Width", value: selection.value("stroke-width") ?? "", prompt: "1"
			) {
				$0.isEmpty
					? controller.removeAttribute("stroke-width")
					: controller.setAttribute("stroke-width", $0)
			}
			OpacityRow(value: selection.value("opacity"), controller: controller)
		}
	}

	@ViewBuilder
	private func geometry(_ selection: SelectionInfo) -> some View {
		let fields = Self.geometryFields(for: selection.tag, isRoot: selection.isRoot)
		if !fields.isEmpty {
			Section(selection.isRoot ? "Canvas" : "Geometry") {
				Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
					ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { i in
						GridRow {
							ForEach(fields[i..<min(i + 2, fields.count)], id: \.self) { name in
								NumberField(name: name, value: selection.value(name) ?? "") {
									$0.isEmpty
										? controller.removeAttribute(name)
										: controller.setAttribute(name, $0)
								}
							}
						}
					}
				}
				if selection.isRoot {
					AttributeField(
						title: "View Box", value: selection.value("viewBox") ?? "", prompt: "None"
					) {
						$0.isEmpty
							? controller.removeAttribute("viewBox")
							: controller.setAttribute("viewBox", $0)
					}
				} else {
					AttributeField(
						title: "Transform", value: selection.value("transform") ?? "",
						prompt: "None"
					) {
						$0.isEmpty
							? controller.removeAttribute("transform")
							: controller.setAttribute("transform", $0)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func attributes(_ selection: SelectionInfo) -> some View {
		Section {
			ForEach(selection.attributes) { attribute in
				AttributeField(title: attribute.name, value: attribute.value, monospacedTitle: true)
				{
					controller.setAttribute(attribute.name, $0)
				}
				.contextMenu {
					Button("Remove Attribute", systemImage: "minus.circle", role: .destructive) {
						controller.removeAttribute(attribute.name)
					}
				}
			}
			NewAttributeRow(controller: controller)
		} header: {
			Text("All Attributes")
		} footer: {
			Text("Control-click an attribute to remove it.")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: Helpers

	static func geometryFields(for tag: String, isRoot: Bool) -> [String] {
		if isRoot { return ["width", "height"] }
		switch tag {
		case "rect": return ["x", "y", "width", "height", "rx", "ry"]
		case "circle": return ["cx", "cy", "r"]
		case "ellipse": return ["cx", "cy", "rx", "ry"]
		case "line": return ["x1", "y1", "x2", "y2"]
		case "image", "use", "foreignObject": return ["x", "y", "width", "height"]
		case "text": return ["x", "y", "font-size"]
		default: return []
		}
	}

	static func elementName(for tag: String) -> String {
		switch tag {
		case "g": "Group"
		case "rect": "Rectangle"
		case "circle": "Circle"
		case "ellipse": "Ellipse"
		case "line": "Line"
		case "polyline": "Polyline"
		case "polygon": "Polygon"
		case "path": "Path"
		case "text": "Text"
		case "tspan": "Text Span"
		case "image": "Image"
		case "use": "Instance"
		case "symbol": "Symbol"
		case "defs": "Definitions"
		case "linearGradient": "Linear Gradient"
		case "radialGradient": "Radial Gradient"
		case "stop": "Gradient Stop"
		case "pattern": "Pattern"
		case "clipPath": "Clipping Path"
		case "mask": "Mask"
		case "filter": "Filter"
		case "marker": "Marker"
		case "style": "Style Sheet"
		case "title": "Title"
		case "desc": "Description"
		case "metadata": "Metadata"
		default: tag
		}
	}

	static func symbol(for tag: String, isRoot: Bool) -> String {
		if isRoot { return "doc.richtext" }
		switch tag {
		case "rect": return "rectangle"
		case "circle": return "circle"
		case "ellipse": return "oval"
		case "line", "polyline": return "line.diagonal"
		case "polygon": return "pentagon"
		case "path": return "scribble"
		case "text", "tspan": return "textformat"
		case "g": return "square.on.square.dashed"
		case "image": return "photo"
		case "use": return "link"
		case "defs": return "archivebox"
		case "linearGradient", "radialGradient", "stop": return "circle.lefthalf.filled"
		case "pattern": return "square.grid.3x3"
		case "clipPath": return "scissors"
		case "mask": return "theatermask.and.paintbrush"
		case "filter": return "camera.filters"
		case "symbol": return "square.on.square"
		case "marker": return "arrowtriangle.right"
		case "style": return "paintbrush"
		case "title", "desc", "metadata": return "text.alignleft"
		default: return "chevron.left.forwardslash.chevron.right"
		}
	}
}
