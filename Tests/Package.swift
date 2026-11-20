// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PDFTests",
    platforms: [
        .macOS(.v13),
    ],
    products: [

        // testing
        .executable(name: "t_pdf", targets: ["PDFTests"]),
        .executable(name: "t_pdf_fixtures", targets: ["PDFFixtureTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Primitives.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/IO.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Schema.git", branch: "master"),

        // for test fixtures
        .package(url: "https://github.com/leviouwendijk/Milieu.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "PDFTests",
            dependencies: [
                .product(name: "PDF", package: "PDF"), .product(name: "PDFCore", package: "PDF"), .product(name: "PDFApple", package: "PDF"),
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
                .product(name: "IO", package: "IO"),
                .product(name: "Schema", package: "Schema"),
            ]
        ),
        .executableTarget(
            name: "PDFFixtureTests",
            dependencies: [
                .product(name: "PDF", package: "PDF"), .product(name: "PDFCore", package: "PDF"), .product(name: "PDFApple", package: "PDF"),
                .product(name: "Milieu", package: "Milieu"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        settings.append(
            .unsafeFlags(
                [
                    "-continue-building-after-errors"
                ]
            )
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
