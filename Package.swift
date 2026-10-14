// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "Lines",
	platforms: [.macOS("27.0")],
	dependencies: [
		// Vendored with fixes; see Vendor/ColourPickerMaker/VENDORED.md.
		.package(path: "Vendor/ColourPickerMaker"),
		// The search field in Settings.
		.package(url: "https://github.com/SzpakKamil/SearchBar.git", from: "2.1.5"),
	],
	targets: [
		.executableTarget(
			name: "Lines",
			dependencies: [
				.product(name: "ColourPickerMaker", package: "ColourPickerMaker"),
				.product(name: "SearchBar", package: "SearchBar"),
			],
			path: "Sources/Lines",
			resources: [.process("Canvas/Resources")],
			swiftSettings: [.swiftLanguageMode(.v5)]
		)
	]
)
