// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XTerminalNative",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "XTerminalNative", targets: ["XTerminalNative"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")
    ],
    targets: [
        .target(name: "TerminalCore"),
        .executableTarget(name: "XTerminalNative", dependencies: ["TerminalCore", "SwiftTerm"]),
        .testTarget(name: "TerminalCoreTests", dependencies: ["TerminalCore"]),
        .testTarget(name: "AppIntegrationTests", dependencies: ["XTerminalNative", "TerminalCore"])
    ],
    swiftLanguageModes: [.v5]
)
