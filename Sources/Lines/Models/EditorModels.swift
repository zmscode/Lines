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
	case checkerboard, white, grey, black, custom, window, transparent
	var id: String { rawValue }
	var title: String {
		switch self {
		case .checkerboard: "Checkerboard"
		case .white: "White"
		case .grey: "Grey"
		case .black: "Black"
		case .custom: "Custom Colour"
		case .window: "Window Background"
		case .transparent: "Transparent"
		}
	}

	/// The quick choices in the canvas's background pill.
	static let swatches: [CanvasBackground] = [.checkerboard, .white, .grey, .black, .custom]

	/// Where the custom colour (a hex string) is stored.
	static let customColourKey = "canvasCustomColour"
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
	var isRoot: Bool { path.isEmpty }

	func value(_ name: String) -> String? {
		attributes.first { $0.name == name }?.value
	}
}
