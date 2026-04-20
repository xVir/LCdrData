import ProjectDescription

// MARK: - Shared Settings

let sharedSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
]

let appSettings: SettingsDictionary = sharedSettings.merging([
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_USER_SELECTED_FILES": "readonly",
    "ENABLE_PREVIEWS": "YES",
    "REGISTER_APP_GROUPS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
])

let testSettings: SettingsDictionary = sharedSettings.merging([
    "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
])

// MARK: - Project

let project = Project(
    name: "LCDR Data",
    settings: .settings(
        configurations: [
            .debug(name: .debug),
            .release(name: .release),
        ]
    ),
    targets: [
        // MARK: App Target
        .target(
            name: "LCDR Data",
            destinations: [.mac],
            product: .app,
            bundleId: "com.xvir.LCDR-Data",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCDR Data/**"],
            resources: ["LCDR Data/Assets.xcassets"],
            dependencies: [
                .external(name: "KDL"),
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
        // MARK: Unit Tests Target
        .target(
            name: "LCDR DataTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.xvir.LCDR-DataTests",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCDR DataTests/**"],
            dependencies: [
                .target(name: "LCDR Data"),
                .external(name: "SwiftMocking"),
            ],
            settings: .settings(
                base: testSettings
            )
        ),
        // MARK: UI Tests Target
        .target(
            name: "LCDR DataUITests",
            destinations: [.mac],
            product: .uiTests,
            bundleId: "com.xvir.LCDR-DataUITests",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCDR DataUITests/**"],
            dependencies: [
                .target(name: "LCDR Data"),
            ],
            settings: .settings(
                base: testSettings
            )
        ),
    ]
)
