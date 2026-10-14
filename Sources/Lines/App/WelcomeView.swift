import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window Lines shows when no document is open: a quiet drop target with
/// Open and New. Recent files are in File › Open Recent.
struct WelcomeView: View {
	static let windowID = "welcome"

	@Environment(\.openDocument) private var openDocument
	@State private var isTargeted = false
	@State private var rejectedDrop = false

	var body: some View {
		VStack(spacing: 14) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 72, height: 72)
				.scaleEffect(isTargeted ? 1.06 : 1)
				.accessibilityHidden(true)

			Text(message)
				.font(.title3)
				.foregroundStyle(rejectedDrop ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))

			VStack(spacing: 8) {
				Button("Open File…") {
					NSDocumentController.shared.openDocument(nil)
				}
				.keyboardShortcut(.defaultAction)

				Button("New Drawing") {
					NSDocumentController.shared.newDocument(nil)
				}
				.buttonStyle(.link)
				.font(.callout)
			}
			.padding(.top, 4)
		}
		.frame(width: 560, height: 380)
		.background {
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(.tint.opacity(isTargeted ? 0.08 : 0))
				.strokeBorder(.tint.opacity(isTargeted ? 0.5 : 0), lineWidth: 2)
				.padding(10)
		}
		.animation(.smooth(duration: 0.15), value: isTargeted)
		.containerBackground(.background, for: .window)
		.tint(Brand.accent)
		.dropDestination(for: URL.self) { urls, _ in
			open(urls)
		} isTargeted: {
			isTargeted = $0
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Drop an SVG file here to open it")
	}

	private var message: String {
		if isTargeted { return "Release to Open" }
		if rejectedDrop { return "Lines can only open SVG files" }
		return "Drag and Drop an SVG File Here"
	}

	@discardableResult
	private func open(_ urls: [URL]) -> Bool {
		let svgs = urls.filter { url in
			(try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .svg)
				?? (url.pathExtension.lowercased() == "svg")
		}
		guard !svgs.isEmpty else {
			rejectedDrop = true
			NSSound.beep()
			return false
		}
		rejectedDrop = false
		for url in svgs {
			Task {
				do { try await openDocument(at: url) } catch { NSAlert(error: error).runModal() }
			}
		}
		return true
	}
}
