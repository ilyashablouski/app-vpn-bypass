// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VPNBypass",
    platforms: [.macOS(.v14)],
    targets: [
        // Общая логика: валидация, конфиг, таблица маршрутов, PF_ROUTE, XPC-протокол.
        .target(name: "BypassCore", path: "Sources/BypassCore"),
        // Привилегированный демон (root): управляет маршрутами.
        .executableTarget(name: "VPNBypassHelper", dependencies: ["BypassCore"], path: "Sources/Helper"),
        // SwiftUI-приложение в строке меню.
        .executableTarget(name: "VPNBypass", dependencies: ["BypassCore"], path: "Sources/App"),
        .testTarget(name: "BypassCoreTests", dependencies: ["BypassCore"], path: "Tests/BypassCoreTests"),
    ]
)
