// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenPlayer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumenPlayer", targets: ["PlayerApp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PlayerCore", dependencies: ["CSQLite"]),
        .target(name: "CMpv", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc", "-Wno-deprecated-declarations"])], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("OpenGL")]),
        .executableTarget(name: "PlayerApp", dependencies: ["PlayerCore", "CMpv"], swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"])
    ]
)
