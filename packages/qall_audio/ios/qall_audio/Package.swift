// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "qall_audio",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "qall-audio", targets: ["qall_audio"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "qall_audio",
            dependencies: [
                "qall_denoiser",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
        // RNNoise (BSD-3-Clause, https://gitlab.xiph.org/xiph/rnnoise v0.1.1) と
        // WebRTC の 10ms ブロックに適用するためのラッパー。Android の CMake からも参照している。
        .target(
            name: "qall_denoiser",
            exclude: ["rnnoise/COPYING", "rnnoise/AUTHORS"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("rnnoise"),
            ]
        ),
    ]
)
