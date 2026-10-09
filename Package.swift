// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DDCHop",
    platforms: [.macOS(.v13)],
    targets: [
        // Declarations for the private IOAVService I2C API in IOKit.
        .target(name: "CIOAVService"),
        .executableTarget(
            name: "DDCHop",
            dependencies: ["CIOAVService"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
