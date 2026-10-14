import SwiftUI

/// Human-readable names and symbols for SVG elements, shared by the
/// inspector, layers panel and graph.
extension InspectorView {
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
		case "animate": "Animation"
		case "animateTransform": "Transform Animation"
		case "animateMotion": "Motion Path"
		case "set": "Set"
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
		case "animate", "animateTransform", "animateMotion", "set": return "play.circle"
		default: return "chevron.left.forwardslash.chevron.right"
		}
	}
}
