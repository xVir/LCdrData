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
    "ENABLE_USER_SELECTED_FILES": "readwrite",
    "ENABLE_APP_SANDBOXED_FILES_BOOKMARKS_APP_SCOPE": "YES",
    "ENABLE_PREVIEWS": "YES",
    "REGISTER_APP_GROUPS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
])

let testSettings: SettingsDictionary = sharedSettings.merging([
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
        // MARK: App Target
        .target(
            name: "LCdrData",
            destinations: [.mac],
            product: .app,
            productName: "LCdrData",
            bundleId: "com.xvir.LCdrData",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrData/**"],
            resources: ["LCdrData/Assets.xcassets"],
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
            name: "LCdrDataTests",
            destinations: [.mac],
            product: .unitTests,
            productName: "LCdrDataTests",
            bundleId: "com.xvir.LCdrDataTests",
            deploymentTargets: .macOS("26.4"),
            sources: ["LCdrDataTests/**"],
            dependencies: [
                .target(name: "LCdrData"),
                .external(name: "SwiftMocking"),
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
