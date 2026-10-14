import SwiftUI

/// File › Export…: choose a format and its options, then where to save.
struct ExportSheet: View {
	var controller: CanvasController
	var document: SVGDocument

	@Environment(\.dismiss) private var dismiss
	@AppStorage("export.format") private var format: ExportFormat = .png
	@AppStorage("export.scale") private var scale: Double = 2
	@AppStorage("export.transparent") private var transparent = true
	@AppStorage("export.minify") private var minify = false
	@AppStorage("export.quality") private var quality: Double = 0.9
	@State private var size: CGSize?
	@State private var isExporting = false
	@State private var error: String?

	var body: some View {
		VStack(spacing: 0) {
			Form {
				Section {
					Picker("Format", selection: $format) {
						ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
					}
					.pickerStyle(.segmented)
				}
				options
			}
			.formStyle(.grouped)
			.scrollDisabled(true)

			HStack {
				if let error {
					Label(error, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
						.font(.callout)
						.lineLimit(2)
				}
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Export…") { Task { await export() } }
					.keyboardShortcut(.defaultAction)
					.disabled(isExporting)
			}
			.padding([.horizontal, .bottom], 20)
		}
		.frame(width: 440)
		.fixedSize(horizontal: false, vertical: true)
		.task { size = await controller.drawingSize() }
	}

	@ViewBuilder
	private var options: some View {
		switch format {
		case .svg:
			Section {
				Toggle("Minify", isOn: $minify)
			} footer: {
				Text(
					minify
						? "Removes comments and the whitespace between tags for the smallest file."
						: "Exports the source as it is, formatted."
				)
				.font(.footnote).foregroundStyle(.secondary)
			}
		case .png, .jpeg:
			Section {
				Picker("Scale", selection: $scale) {
					ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { Text("\(Int($0))×").tag($0) }
				}
				.pickerStyle(.segmented)
				LabeledContent("Size") {
					Text(pixelSize).monospacedDigit()
				}
				if format == .png {
					Toggle("Transparent background", isOn: $transparent)
				} else {
					LabeledContent("Quality") {
						HStack {
							Slider(value: $quality, in: 0.3...1)
							Text(quality, format: .percent.precision(.fractionLength(0)))
								.monospacedDigit().foregroundStyle(.secondary).frame(
									width: 40, alignment: .trailing)
						}
					}
				}
			} footer: {
				Text("Rendered with WebKit, the same engine as the canvas.")
					.font(.footnote).foregroundStyle(.secondary)
			}
		case .pdf:
			Section {
				LabeledContent("Page size") { Text(pointSize).monospacedDigit() }
			} footer: {
				Text(
					"A vector PDF at the drawing’s size, rendered by macOS. Filters and some effects may be simplified."
				)
				.font(.footnote).foregroundStyle(.secondary)
			}
		}
	}

	private var pixelSize: String {
		guard let size else { return "—" }
		return
			"\(Int((size.width * scale).rounded())) × \(Int((size.height * scale).rounded())) pixels"
	}

	private var pointSize: String {
		guard let size else { return "—" }
		return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) points"
	}

	// MARK: Export

	private func export() async {
		isExporting = true
		defer { isExporting = false }
		do {
			let data = try await Exporter.data(
				for: format, controller: controller, text: document.text, scale: scale,
				transparent: transparent, minify: minify, quality: quality
			)
			error = nil
			let window = controller.webView?.window
			let name = controller.documentName
			dismiss()
			Exporter.save(data, type: format.contentType, suggestedName: name, window: window)
		} catch {
			self.error = error.localizedDescription
		}
	}
}
