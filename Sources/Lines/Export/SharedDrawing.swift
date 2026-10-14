import CoreTransferable
import SwiftUI

/// What the Share button sends: the SVG, or a PNG for apps that want an image.
struct SharedDrawing: Transferable {
	var name: String
	var controller: CanvasController

	static var transferRepresentation: some TransferRepresentation {
		DataRepresentation(exportedContentType: .svg) { drawing in
			try await drawing.data(.svg)
		}
		.suggestedFileName { $0.name + ".svg" }
		DataRepresentation(exportedContentType: .png) { drawing in
			try await drawing.data(.png)
		}
		.suggestedFileName { $0.name + ".png" }
	}

	@MainActor private func data(_ format: ExportFormat) async throws -> Data {
		try await Exporter.data(
			for: format, controller: controller, text: controller.document?.text ?? "")
	}
}
