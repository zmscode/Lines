import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
	case svg, png, jpeg, pdf
	var id: String { rawValue }
	var title: String { rawValue.uppercased() }
	var contentType: UTType {
		switch self {
		case .svg: .svg
		case .png: .png
		case .jpeg: .jpeg
		case .pdf: .pdf
		}
	}
}

enum Exporter {
	@MainActor
	static func data(
		for format: ExportFormat, controller: CanvasController, text: String, scale: Double = 2,
		transparent: Bool = true, minify: Bool = false, quality: Double = 0.9
	) async throws -> Data {
		switch format {
		case .svg:
			return Data((minify ? XMLFormatter.minify(text) : text).utf8)
		case .png:
			return try await controller.rasterize(
				scale: scale, background: transparent ? nil : "#ffffff", type: .png)
		case .jpeg:
			return try await controller.rasterize(
				scale: scale, background: "#ffffff", type: .jpeg, quality: quality)
		case .pdf:
			return try pdf(from: text)
		}
	}

	/// Draws the SVG into a PDF context using AppKit's SVG renderer, which keeps paths as vectors.
	static func pdf(from text: String) throws -> Data {
		guard let image = NSImage(data: Data(text.utf8)), image.size.width > 0 else {
			throw CocoaError(.fileWriteInapplicableStringEncoding)
		}
		let data = NSMutableData()
		var box = CGRect(origin: .zero, size: image.size)
		guard let consumer = CGDataConsumer(data: data as CFMutableData),
			let context = CGContext(consumer: consumer, mediaBox: &box, nil)
		else { throw CocoaError(.fileWriteUnknown) }
		context.beginPDFPage(nil)
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
		image.draw(in: box)
		NSGraphicsContext.restoreGraphicsState()
		context.endPDFPage()
		context.closePDF()
		return data as Data
	}

	/// Prints just the drawing (as vector PDF), scaled to fit the page.
	@MainActor
	static func print(text: String, name: String, window: NSWindow?) {
		guard let data = try? pdf(from: text), let pdf = PDFDocument(data: data) else {
			NSSound.beep()
			return
		}
		let info = NSPrintInfo.shared.copy() as! NSPrintInfo
		info.jobDisposition = .spool
		guard
			let operation = pdf.printOperation(
				for: info, scalingMode: .pageScaleToFit, autoRotate: true)
		else { return }
		operation.jobTitle = name
		if let window {
			operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
		} else {
			operation.run()
		}
	}

	@MainActor
	static func save(_ data: Data, type: UTType, suggestedName: String, window: NSWindow?) {
		let panel = NSSavePanel()
		panel.allowedContentTypes = [type]
		panel.canSelectHiddenExtension = true
		panel.nameFieldStringValue = suggestedName + "." + (type.preferredFilenameExtension ?? "")
		let write: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
		}
		if let window {
			panel.beginSheetModal(for: window, completionHandler: write)
		} else {
			write(panel.runModal())
		}
	}
}
