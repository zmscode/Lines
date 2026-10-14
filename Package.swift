// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "Lines",
	platforms: [.macOS("27.0")],
	dependencies: [
		.package(url: "https://github.com/aaurelions/SwiftFlow.git", exact: "0.2.0"),
		// Vendored with fixes; see Vendor/ColourPickerMaker/VENDORED.md.
		.package(path: "Vendor/ColourPickerMaker"),
	],
	targets: [
		.executableTarget(
			name: "Lines",
			dependencies: [
				.product(name: "SwiftFlow", package: "SwiftFlow"),
				.product(name: "ColourPickerMaker", package: "ColourPickerMaker"),
			],
			path: "Sources/Lines",
			resources: [.process("Canvas/Resources")],
			swiftSettings: [.swiftLanguageMode(.v5)]
		)
	]
)
