// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "LearnVulkan",
    products: [
        .executable(name: "SetupEnvironment", targets: ["SetupEnvironment"]),
        .executable(name: "HelloTriangle", targets: ["HelloTriangle"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "SetupEnvironment", dependencies: [
            .target(name: "CVulkan"),
            .target(name: "CGlfw"),
        ]),

        .target(name: "HelloTriangle", dependencies: [
            .target(name: "CVulkan"),
            .target(name: "CGlfw"),
            .target(name: "CVulkanDebug"),
            .target(name: "Utilities"),
        ], exclude: [
            "Shaders/shader.frag",
            "Shaders/shader.vert",
        ], resources: [
            .copy("Resources/frag.spv"),
            .copy("Resources/vert.spv"),
        ], swiftSettings: [
            .define("DEBUG", .when(configuration: .debug)),
        ]),

        .target(name: "CVulkanDebug", dependencies: [
            .target(name: "CVulkan"),
        ]),

        .target(name: "Utilities"),

        .systemLibrary(name: "CVulkan", pkgConfig: "vulkan"),
        .systemLibrary(name: "CGlfw", pkgConfig: "glfw3", providers: [
            .brew(["glfw"]),
            .apt(["glfw3", "xorg-dev", "libglu1-mesa-dev"]),
        ]),
    ]
)
