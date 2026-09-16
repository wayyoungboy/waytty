// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WayttyPrototype",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WayttyPrototype", targets: ["WayttyPrototype"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")
    ],
    targets: [
        .target(name: "TerminalCore"),
        .executableTarget(name: "WayttyPrototype", dependencies: ["TerminalCore", "SwiftTerm"]),
        .testTarget(name: "TerminalCoreTests", dependencies: ["TerminalCore"]),
        .testTarget(name: "AppIntegrationTests", dependencies: ["WayttyPrototype", "TerminalCore"])
    ],
    swiftLanguageModes: [.v5]
)
