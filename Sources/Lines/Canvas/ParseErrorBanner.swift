import SwiftUI

struct ParseErrorBanner: View {
	var message: String

	var body: some View {
		Label {
			Text(message)
				.lineLimit(3)
				.textSelection(.enabled)
		} icon: {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.yellow)
		}
		.font(.callout)
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.glassEffect(.regular, in: .rect(cornerRadius: 14))
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Source error: \(message)")
	}
}
