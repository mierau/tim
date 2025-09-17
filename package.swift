// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "tim",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "tim",
      targets: ["tim"]
    )
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "tim",
      dependencies: [],
      path: "src"
    )
  ]
)