// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "SwiftFlow",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "SwiftFlow",
      targets: ["SwiftFlow"]
    )
  ],
  targets: [
    .target(
      name: "SwiftFlow",
      path: "Sources/SwiftFlow"
    ),
  ]
)
