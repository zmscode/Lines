import SwiftUI

/// Human-readable names and symbols for SVG elements, shared by the
/// inspector, layers panel and graph.
extension InspectorView {
	static func elementName(for tag: String) -> String {
		switch tag {
		case "g": String(localized: "Group")
		case "rect": String(localized: "Rectangle")
		case "circle": String(localized: "Circle")
		case "ellipse": String(localized: "Ellipse")
		case "line": String(localized: "Line")
		case "polyline": String(localized: "Polyline")
		case "polygon": String(localized: "Polygon")
		case "path": String(localized: "Path")
		case "text": String(localized: "Text")
		case "tspan": String(localized: "Text Span")
		case "image": String(localized: "Image")
		case "use": String(localized: "Instance")
		case "symbol": String(localized: "Symbol")
		case "defs": String(localized: "Definitions")
		case "linearGradient": String(localized: "Linear Gradient")
		case "radialGradient": String(localized: "Radial Gradient")
		case "stop": String(localized: "Gradient Stop")
		case "pattern": String(localized: "Pattern")
		case "clipPath": String(localized: "Clipping Path")
		case "mask": String(localized: "Mask")
		case "filter": String(localized: "Filter")
		case "marker": String(localized: "Marker")
		case "style": String(localized: "Style Sheet")
		case "title": String(localized: "Title")
		case "desc": String(localized: "Description")
		case "metadata": String(localized: "Metadata")
		case "animate": String(localized: "Animation")
		case "animateTransform": String(localized: "Transform Animation")
		case "animateMotion": String(localized: "Motion Path")
		case "set": String(localized: "Set")
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
