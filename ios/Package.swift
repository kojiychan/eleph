// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ElephBathroomMonitor",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ElephBathroomMonitor", targets: ["ElephBathroomMonitor"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ElephBathroomMonitor",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: ".",
            exclude: [
                "README.md",
                "Configuration/Supabase.example.plist",
                "Configuration/Supabase.template.xcconfig"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Configuration")
            ]
        )
    ]
)
