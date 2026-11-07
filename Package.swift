// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LIFTR",
  platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
  products: [
    .executable(name: "liftr-schema-fixture", targets: ["LIFTRSchemaFixture"]),
    .library(name: "LIFTRCore", targets: ["LIFTRCore"]),
    .library(name: "LIFTRPersistence", targets: ["LIFTRPersistence"]),
    .library(name: "LIFTRSync", targets: ["LIFTRSync"]),
    .library(name: "LIFTRMotion", targets: ["LIFTRMotion"]),
  ],
  targets: [
    .executableTarget(
      name: "LIFTRSchemaFixture", dependencies: ["LIFTRCore"], path: "tests/swift/SchemaFixture"),
    .target(name: "LIFTRCore", path: "packages/LIFTRCore/Sources"),
    .target(
      name: "LIFTRPersistence", dependencies: ["LIFTRCore"],
      path: "packages/LIFTRPersistence/Sources"),
    .target(
      name: "LIFTRSync", dependencies: ["LIFTRCore", "LIFTRPersistence"],
      path: "packages/LIFTRSync/Sources"),
    .target(name: "LIFTRMotion", dependencies: ["LIFTRCore"], path: "packages/LIFTRMotion/Sources"),
    .testTarget(
      name: "LIFTRCoreTests", dependencies: ["LIFTRCore", "LIFTRPersistence"],
      path: "tests/swift/LIFTRCoreTests"),
    .testTarget(
      name: "LIFTRMotionTests", dependencies: ["LIFTRMotion", "LIFTRCore"],
      path: "tests/swift/LIFTRMotionTests"),
  ]
)
