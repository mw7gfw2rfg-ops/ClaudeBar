// swift-tools-version: 6.2
import PackageDescription

// ClaudeBar — Claude Code usage and limits in the macOS menu bar.
//
// Built entirely on GlassKit. This package contains no design code at all: no colours, no
// type scale, no panel plumbing, no glyphs. If something visual needed to be written here,
// the extraction would have failed.
let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v26)],
    dependencies: [
        // URL rather than a local path so a standalone clone of this repo actually
        // builds. For local GlassKit work, `swift package edit GlassKit --path ../GlassKit`
        // swaps in a sibling checkout without touching this file.
        .package(url: "https://github.com/mw7gfw2rfg-ops/GlassKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ClaudeBarKit",
            dependencies: [.product(name: "GlassKit", package: "GlassKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ClaudeBar",
            dependencies: ["ClaudeBarKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClaudeBarTests",
            dependencies: ["ClaudeBarKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
