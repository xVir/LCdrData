import ProjectDescription

// MARK: - Shared Settings

let sharedSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    // Must match PACKAGE_NAME in BUILD.bazel. Xcode compiles the app as one flat
    // module, but `package` declarations are still a hard error without it.
    "SWIFT_PACKAGE_NAME": "lcdrdata",
]

let appSettings: SettingsDictionary = sharedSettings.merging([
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_USER_SELECTED_FILES": "readwrite",
    "ENABLE_APP_SANDBOXED_FILES_BOOKMARKS_APP_SCOPE": "YES",
    "ENABLE_PREVIEWS": "YES",
    "REGISTER_APP_GROUPS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
])

let testSettings: SettingsDictionary = sharedSettings.merging([
    "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
])

// Library modules need the same actor-isolation default as the app, since the
// sources move between targets unchanged.
let coreSettings: SettingsDictionary = sharedSettings.merging([
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
])

// MARK: - Project

let project = Project(
    name: "LCdrData",
    settings: .settings(
        configurations: [
            .debug(name: .debug),
            .release(name: .release),
        ]
    ),
    targets: [
        // MARK: Utilities Module
        // Mirrors the `Utilities` swift_library in LCdrData/Core/Utilities/BUILD.bazel.
        // Both build systems must agree on the module structure, since the sources
        // contain `import Utilities`. Each of the four Core modules is one directory.
        .target(
            name: "Utilities",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Utilities",
            bundleId: "com.xvir.LCdrData.Utilities",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Core/Utilities/**"],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Models Module
        // A leaf: the domain types depend on no other first-party module.
        .target(
            name: "Models",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Models",
            bundleId: "com.xvir.LCdrData.Models",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Core/Models/**"],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Bindings Module
        // The keyboard binding for each Command. Needs both a Command and a key,
        // which is why it is neither Models nor Utilities.
        .target(
            name: "Bindings",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Bindings",
            bundleId: "com.xvir.LCdrData.Bindings",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Core/Bindings/**"],
            dependencies: [
                .target(name: "Models"),
                .target(name: "Utilities"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Formatting Module
        // Presentation strings for model values. Depends on Models, which
        // Utilities must not.
        .target(
            name: "Formatting",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Formatting",
            bundleId: "com.xvir.LCdrData.Formatting",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Core/Formatting/**"],
            dependencies: [
                .target(name: "Models"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Services Module
        // Mirrors the `Services` swift_library in BUILD.bazel. KDL lives here
        // because ConfigurationService is its only consumer.
        .target(
            name: "Services",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Services",
            bundleId: "com.xvir.LCdrData.Services",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Services/**"],
            dependencies: [
                .target(name: "Models"),
                .external(name: "KDL"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: ViewModels Module
        // Mirrors the `ViewModels` swift_library in BUILD.bazel.
        .target(
            name: "ViewModels",
            destinations: [.mac],
            product: .staticFramework,
            productName: "ViewModels",
            bundleId: "com.xvir.LCdrData.ViewModels",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/ViewModels/**"],
            dependencies: [
                .target(name: "Models"),
                .target(name: "Utilities"),
                .target(name: "Formatting"),
                .target(name: "Services"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: AppEnvironment Module
        // Mirrors the `AppEnvironment` swift_library in BUILD.bazel. Its own
        // module because Views needs it while it depends on ViewModels, which is
        // what breaks the App <-> Views cycle. Note this splits LCdrData/App/
        // across two targets.
        .target(
            name: "AppEnvironment",
            destinations: [.mac],
            product: .staticFramework,
            productName: "AppEnvironment",
            bundleId: "com.xvir.LCdrData.AppEnvironment",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/App/AppEnvironment.swift"],
            dependencies: [
                .target(name: "Models"),
                .target(name: "Services"),
                .target(name: "ViewModels"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Views Module
        // Mirrors the `Views` swift_library in BUILD.bazel.
        .target(
            name: "Views",
            destinations: [.mac],
            product: .staticFramework,
            productName: "Views",
            bundleId: "com.xvir.LCdrData.Views",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/Views/**"],
            dependencies: [
                .target(name: "Models"),
                .target(name: "Bindings"),
                .target(name: "Utilities"),
                .target(name: "Formatting"),
                .target(name: "Services"),
                .target(name: "ViewModels"),
                .target(name: "AppEnvironment"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: App Target
        .target(
            name: "LCdrData",
            destinations: [.mac],
            product: .app,
            productName: "LCdrData",
            bundleId: "com.xvir.LCdrData",
            deploymentTargets: .macOS("26.4"),
            sources: [
                .glob(
                    "LCdrData/**",
                    excluding: [
                        "LCdrData/Core/**",
                        "LCdrData/Services/**",
                        "LCdrData/ViewModels/**",
                        "LCdrData/App/AppEnvironment.swift",
                        "LCdrData/Views/**",
                    ]
                ),
            ],
            resources: [
                "LCdrData/Assets.xcassets",
                "LCdrData/Resources/DefaultConfig.kdl",
            ],
            dependencies: [
                .target(name: "Models"),
                .target(name: "Bindings"),
                .target(name: "Utilities"),
                .target(name: "Formatting"),
                .target(name: "Services"),
                .target(name: "ViewModels"),
                .target(name: "AppEnvironment"),
                .target(name: "Views"),
            ],
            settings: .settings(
                base: appSettings,
                configurations: [
                    .debug(name: .debug),
                    .release(name: .release, settings: [
                        "DEVELOPMENT_TEAM": "M57JSUC35C",
                    ]),
                ]
            )
        ),
        // MARK: Test Support Module
        // Mirrors `TestSupportLib` in BUILD.bazel. Holds the test doubles shared
        // across test folders, so the per-module Bazel test targets do not have
        // to depend on one another. Xcode keeps a single combined test target,
        // but still needs this module to exist for `@testable import TestSupport`.
        .target(
            name: "TestSupport",
            destinations: [.mac],
            product: .staticFramework,
            productName: "TestSupport",
            bundleId: "com.xvir.LCdrData.TestSupport",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrDataTests/TestSupport/**"],
            dependencies: [
                .target(name: "Services"),
                .target(name: "AppEnvironment"),
            ],
            settings: .settings(
                base: coreSettings
            )
        ),
        // MARK: Unit Tests Target
        .target(
            name: "LCdrDataTests",
            destinations: [.mac],
            product: .unitTests,
            productName: "LCdrDataTests",
            bundleId: "com.xvir.LCdrDataTests",
            deploymentTargets: .macOS("26.4"),
            sources: [
                .glob(
                    "LCdrDataTests/**",
                    excluding: ["LCdrDataTests/TestSupport/**"]
                ),
            ],
            dependencies: [
                .target(name: "LCdrData"),
                .target(name: "Models"),
                .target(name: "Bindings"),
                .target(name: "Utilities"),
                .target(name: "Formatting"),
                .target(name: "Services"),
                .target(name: "ViewModels"),
                .target(name: "AppEnvironment"),
                .target(name: "Views"),
                .target(name: "TestSupport"),
            ],
            settings: .settings(
                base: testSettings
            )
        ),
        // MARK: UI Tests Target
        .target(
            name: "LCdrDataUITests",
            destinations: [.mac],
            product: .uiTests,
            productName: "LCdrDataUITests",
            bundleId: "com.xvir.LCdrDataUITests",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrDataUITests/**"],
            dependencies: [
                .target(name: "LCdrData"),
            ],
            settings: .settings(
                base: testSettings
            )
        ),
    ]
)
