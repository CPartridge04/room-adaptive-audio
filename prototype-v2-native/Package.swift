// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AudioPrototype", platforms: [.macOS(.v13)], products: [.executable(name: "AudioPrototype", targets: ["AudioPrototype"])], targets: [.executableTarget(name: "AudioPrototype"), .testTarget(name: "AudioPrototypeTests", dependencies: ["AudioPrototype"])])
