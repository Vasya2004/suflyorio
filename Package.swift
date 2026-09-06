// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuflerCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SuflerCore", targets: ["SuflerCore"])],
    targets: [
        .target(name: "SuflerCore", path: "Sufler/Core"),
        .target(name: "SuflerStorage", dependencies: ["SuflerCore"], path: "Sufler",
                exclude: ["Core", "Views", "Resources", "SuflerApp.swift", "Services/CameraService.swift", "Services/RecordingModel.swift", "Services/PhotoExporter.swift"],
                sources: ["Models", "Services/LibraryStore.swift"]),
        .testTarget(name: "SuflerCoreTests", dependencies: ["SuflerCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SuflerStorageTests", dependencies: ["SuflerCore", "SuflerStorage"], resources: [.copy("Fixtures")])
    ]
)
