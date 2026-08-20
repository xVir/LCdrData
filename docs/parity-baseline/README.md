# Tuist Parity Baseline

Reference snapshot of the **Tuist-built** app, captured in Phase 0 of
[BAZEL_MIGRATION.md](../BAZEL_MIGRATION.md). Phase 7 diffs the Bazel-built bundle
against these files.

Captured 2026-08-20 with Xcode 26.6 (`DTXcode 2660`), macOS SDK 26.5,
Tuist 4.182.0, at commit `5b9feb5` with `swift-mocking` already removed.

## Files

| File | Source |
|---|---|
| `info-plist.txt` | `plutil -p LCdrData.app/Contents/Info.plist` |
| `entitlements.plist` | `codesign -d --entitlements :- LCdrData.app` |
| `bundle-files.txt` | `find LCdrData.app`, `_CodeSignature` contents excluded |
| `entitlements-test-hosted.plist` | Same, but from a test-instrumented build — see below |

## How it was produced

A **clean, non-test** Debug build, deliberately isolated from the shared
DerivedData:

```bash
xcodebuild -workspace LCdrData.xcworkspace -scheme LCdrData \
    -configuration Debug -derivedDataPath /tmp/lcdr-baseline-dd build
```

This distinction matters. The app produced by `tuist test` additionally embeds
`Contents/PlugIns/LCdrDataTests.xctest` and six XCTest frameworks
(`XCTest`, `XCTestCore`, `XCTestSupport`, `XCUnit`, `XCUIAutomation`,
`XCTAutomationSupport`, plus `Testing.framework` and two dylibs). A Bazel
`macos_application` contains none of that, so diffing against a test-hosted build
would produce ~85 spurious differences. `entitlements-test-hosted.plist` is kept
only to document the extra debug entitlements that Xcode injects for test runs —
`temporary-exception.files.absolute-path.read-only` and the `testmanagerd`
mach-lookup exceptions — which is what a UI-test host needs.

## Unit test baseline

`tuist test "LCdrData" --skip-ui-tests` — **193 test cases across 24 suites, 0
failures**. Phase 4 requires the Bazel run to match this count, not merely to be
green.

## Expected differences at Phase 7

Not every difference is a defect. These are intentional:

- **`NSMainStoryboardFile`** — present here, must be *absent* from the Bazel
  Info.plist. The app is pure SwiftUI with no storyboard; this is inert Tuist
  boilerplate (finding 2.6).
- **`DT*` keys and `BuildMachineOSBuild`** — toolchain provenance stamped by
  whichever builder ran. Values will differ.
- **`LCdrData.debug.dylib` / `__preview.dylib`** — Xcode debug-dylib and previews
  artifacts. Bazel produces a single static binary at
  `Contents/MacOS/LCdrData`.
- **`com.apple.security.get-task-allow`** — debug-only. Must be present for local
  debug builds but absent from a Bazel release build.

These must match:

- `com.apple.security.app-sandbox` and
  `com.apple.security.files.user-selected.read-write` — the two production
  entitlements (finding 2.3).
- `Contents/Resources/DefaultConfig.kdl` at exactly that path. Confirms the
  Phase 3 resource-placement check: `ConfigurationService` looks the file up at
  the root of `Resources`, so a nested path would break it at runtime.
- `Contents/Resources/Assets.car` and `AppIcon.icns`, with `CFBundleIconFile` and
  `CFBundleIconName` both set to `AppIcon`.
- `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`,
  `CFBundleShortVersionString`, `LSMinimumSystemVersion`, `NSPrincipalClass`.
