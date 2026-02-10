// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "HabitTracker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HabitTracker", targets: ["HabitTrackerApp"])
    ],
    targets: [
        .executableTarget(
            name: "HabitTrackerApp",
            path: "Sources"
        )
    ]
)
