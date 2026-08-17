// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Downleaf",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Downleaf", targets: ["Downleaf"])
    ],
    targets: [
        .executableTarget(
            name: "Downleaf",
            path: "Downleaf",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "Downleaf.entitlements",
                "MarkdownDocument.icns"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "DownleafTests",
            dependencies: ["Downleaf"],
            path: "DownleafTests"
        )
    ]
)
