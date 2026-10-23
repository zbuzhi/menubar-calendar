// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "menubar-calendar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PerpetualCalendar", targets: ["PerpetualCalendar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "CalendarCore"),
        .executableTarget(name: "PerpetualCalendar", dependencies: ["CalendarCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "CalendarCoreChecks", dependencies: ["CalendarCore"], path: "Tests/CalendarCoreTests")
    ]
)
