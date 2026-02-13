// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "my-claude-code",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "NotifyCore",
      targets: ["NotifyCore"]
    ),
    .executable(
      name: "claude-notify",
      targets: ["ClaudeNotify"]
    )
  ],
  targets: [
    .target(
      name: "NotifyCore"
    ),
    .executableTarget(
      name: "ClaudeNotify",
      dependencies: ["NotifyCore"]
    ),
    .testTarget(
      name: "NotifyCoreTests",
      dependencies: ["NotifyCore"]
    )
  ]
)
