import SwiftUI

/// What fills the main area of the window. The code and layers panels are
/// shown alongside either one.
enum EditorLayout: String, CaseIterable, Identifiable {
	case canvas, graph
	var id: String { rawValue }
	var title: String {
		switch self {
		case .canvas: "Canvas"
		case .graph: "Element Graph"
		}
	}
	var symbol: String {
		switch self {
		case .canvas: "photo"
		case .graph: "point.3.connected.trianglepath.dotted"
		}
	}
}

enum CanvasBackground: String, CaseIterable, Identifiable {
	// A saved "transparent" (no longer offered) falls back to the default.
	case checkerboard, white, grey, black, custom, window
	var id: String { rawValue }
	var title: String {
		switch self {
		case .checkerboard: "Checkerboard"
		case .white: "White"
		case .grey: "Grey"
		case .black: "Black"
		case .custom: "Custom Colour"
		case .window: "Window Background"
		}
	}

	/// The quick choices in the canvas's background pill.
	static let swatches: [CanvasBackground] = [.checkerboard, .white, .grey, .black, .custom]

	/// Where the custom colour (a hex string) is stored.
	static let customColourKey = "canvasCustomColour"
	/// Paint the background behind the drawing only, with the window colour around it.
	static let drawingOnlyKey = "canvasBackgroundDrawingOnly"
	static var drawingOnly: Bool { UserDefaults.standard.bool(forKey: drawingOnlyKey) }
	static var customColour: String {
		UserDefaults.standard.string(forKey: customColourKey) ?? "#f2a65a"
	}
}

enum ShapeKind: String, CaseIterable, Identifiable {
	case rect, roundedRect, circle, ellipse, triangle, hexagon, star, line, arrow, text, group
	var id: String { rawValue }
	var title: String {
		switch self {
		case .rect: "Rectangle"
		case .roundedRect: "Rounded Rectangle"
		case .circle: "Circle"
		case .ellipse: "Ellipse"
		case .triangle: "Triangle"
		case .hexagon: "Hexagon"
		case .star: "Star"
		case .line: "Line"
		case .arrow: "Arrow"
		case .text: "Text"
		case .group: "Empty Group"
		}
	}
	var symbol: String {
		switch self {
		case .rect: "rectangle"
		case .roundedRect: "app"
		case .circle: "circle"
		case .ellipse: "oval"
		case .triangle: "triangle"
		case .hexagon: "hexagon"
		case .star: "star"
		case .line: "line.diagonal"
		case .arrow: "arrow.up.right"
		case .text: "textformat"
		case .group: "square.on.square.dashed"
		}
	}
	/// Shapes, then lines, then text and structure, for the insert palette.
	var section: Int {
		switch self {
		case .rect, .roundedRect, .circle, .ellipse, .triangle, .hexagon, .star: 0
		case .line, .arrow: 1
		case .text, .group: 2
		}
	}
}

enum ReorderMode: String { case front, forward, backward, back }

struct Attribute: Equatable, Identifiable {
	var name: String
	var value: String
	var id: String { name }
}

/// One element in the drawing's tree, as reported by the canvas.
struct OutlineItem: Identifiable, Equatable, Sendable {
	struct Reference: Hashable, Sendable {
		var attribute: String
		var targetID: String
	}

	var order: Int  // preorder index; root is 0
	var parent: Int
	var depth: Int
	var path: String  // child indices, stable for an unchanged tree
	var tag: String
	var elementID: String?
	var label: String?
	var isHidden: Bool
	var fill: String?
	var references: [Reference]
	/// Gradient stop colours, or a filter's effects, for the graph.
	var preview: [String]? = nil
	/// Attribute values: paints for shapes; everything for stops, filter
	/// primitives and animations.
	var props: [String: String] = [:]
	/// CSS (@keyframes) animations running on the element.
	var cssAnimations: [CSSAnimation] = []

	struct CSSAnimation: Equatable, Sendable {
		var name: String
		/// The properties its keyframes change, like "translate" or "opacity".
		var properties: [String] = []
		var duration: Double
		var delay: Double
		/// nil repeats forever.
		var iterations: Double?
		var easing: String
	}

	func prop(_ name: String) -> String? { props[name] }

	var id: String { path }

	var displayName: String {
		label ?? InspectorView.elementName(for: tag)
	}
}

struct SelectionInfo: Equatable {
	var path: [Int]
	var order: Int
	var tag: String
	var attributes: [Attribute]
	var textContent: String?
	/// The element's box in its parent's coordinates.
	var bounds: CGRect? = nil
	var rotation: Double = 0
	/// How many elements are selected (Shift-click or a marquee); this one is the first.
	var count = 1
	var isRoot: Bool { path.isEmpty }

	func value(_ name: String) -> String? {
		attributes.first { $0.name == name }?.value
	}
}

/// The canvas tools, as in the palette. Shape tools draw by dragging.
enum CanvasTool: String, CaseIterable, Identifiable {
	case select, hand, rect, roundedRect, ellipse, line, arrow, triangle, hexagon, star, text
	var id: String { rawValue }

	var title: String {
		switch self {
		case .select: "Select"
		case .hand: "Hand"
		case .rect: "Rectangle"
		case .roundedRect: "Rounded Rectangle"
		case .ellipse: "Ellipse"
		case .line: "Line"
		case .arrow: "Arrow"
		case .triangle: "Triangle"
		case .hexagon: "Hexagon"
		case .star: "Star"
		case .text: "Text"
		}
	}

	var symbol: String {
		switch self {
		case .select: "cursorarrow"
		case .hand: "hand.raised"
		case .rect: "rectangle"
		case .roundedRect: "app"
		case .ellipse: "circle"
		case .line: "line.diagonal"
		case .arrow: "arrow.up.right"
		case .triangle: "triangle"
		case .hexagon: "hexagon"
		case .star: "star"
		case .text: "textformat"
		}
	}

	/// The single-key shortcut while the canvas has focus.
	var key: String? {
		switch self {
		case .select: "V"
		case .hand: "H"
		case .rect: "R"
		case .ellipse: "O"
		case .line: "L"
		case .star: "P"
		case .text: "T"
		default: nil
		}
	}

	/// Tools that share a palette slot: the slot shows the last one used.
	static let groups: [[CanvasTool]] = [
		[.select], [.hand], [.rect, .roundedRect], [.ellipse], [.line, .arrow],
		[.star, .triangle, .hexagon], [.text],
	]
}
