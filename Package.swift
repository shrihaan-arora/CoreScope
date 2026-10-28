// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreScope",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CoreScope", targets: ["CoreScope"])
    ],
    dependencies: [],
    targets: [
        // C target exposing private IOHIDEventSystem API declarations.
        // No external code is fetched; these are header-only type
        // declarations resolved at link time against system IOKit.
        .target(
            name: "CIOHIDSensors",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CoreScope",
            dependencies: ["CIOHIDSensors"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "CoreScopeTests",
            dependencies: [
                "CoreScope",
                "CIOHIDSensors"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
