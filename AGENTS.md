# AGENTS.md — LCdrData

LCdrData is a native macOS **dual-panel file manager** inspired by orthodox file managers
(Total Commander, ForkLift, Midnight Commander). It provides a keyboard-driven,
power-user-oriented file management experience with two side-by-side directory panels,
a command bar, and rich file operations. "LCDR" stands for "Lieutenant Commander" —
a reference to Lt. Cmdr. Data from Star Trek: The Next Generation.

Built with SwiftUI, Xcode 26.4, Swift 5.0, targeting macOS 26.4.
Bundle identifier: `com.xvir.LCdrData`.

See **[docs/DESIGN.md](docs/DESIGN.md)** for the full design document — architecture, data
models, feature list, keyboard shortcuts, implementation phases, and sandbox requirements.
**[docs/CONTEXT.md](docs/CONTEXT.md)** defines the project's vocabulary, and
**[docs/CURRENT_ARCH.md](docs/CURRENT_ARCH.md)** describes the architecture as built.

## Which tool for which task

This repo uses **two build tools on purpose**. Neither is being phased out.

| Task | Tool | Command |
|------|------|---------|
| Build the app | **Bazel** | `bazel build //LCdrData` |
| Run unit tests | **Bazel** | `bazel test //LCdrDataTests/...` |
| Generate an Xcode project | **Tuist** | `tuist generate` |
| Run UI tests | **Tuist**, via script | `scripts/run-ui-tests.sh` |
| Declare a dependency | **Both** read `Tuist/Package.swift` |

Bazel is the build system. Tuist keeps the two jobs it does better: generating a working
Xcode project (so SwiftUI previews and the debugger behave normally), and running macOS
UI tests, which Bazel's Apple test runner cannot drive at all.

There is only **one** dependency manifest. `Tuist/Package.swift` is read by Tuist and, via
`rules_swift_package_manager`, by Bazel too — so there is no second version list to drift.

See **[docs/BAZEL_MIGRATION.md](docs/BAZEL_MIGRATION.md)** for why the split falls this way,
and for the non-obvious constraints behind it.

## Bazel

Bazel builds the app and runs the unit tests. Version pinned in `.bazelversion`: **9.2.0**.

### Manifest Files

| File | Purpose |
|------|---------|
| `MODULE.bazel` | bzlmod dependencies (`rules_apple`, `rules_swift`, `apple_support`, `rules_swift_package_manager`) |
| `MODULE.bazel.lock` | Committed on purpose, for reproducible resolution |
| `BUILD.bazel` | Root: shared config only. Targets live in per-package BUILD files |
| `defs.bzl` | Shared `SWIFT_COPTS` and `PACKAGE_NAME` |
| `.bazelrc` | macOS deployment target, pinned `DEVELOPER_DIR`, the `release` config |
| `.bazelignore` | Keeps Bazel out of `Tuist/.build`, `Derived/`, and the generated Xcode projects |
| `Bazel/Info.plist` | Hand-written app plist |
| `Bazel/LCdrData.entitlements` | Production entitlements (release builds) |
| `Bazel/LCdrData.debug.entitlements` | Adds `get-task-allow` and the `testmanagerd` exceptions |

No setup step is needed — Bazel resolves everything on first build.

### Gotchas

- **Debug builds carry extra entitlements, and must.** An app-hosted `macos_unit_test`
  cannot bootstrap without them: the sandboxed host is refused its connection to
  `testmanagerd`. `--config=release` selects the two-key production set.
- **`bazel build //LCdrData` outputs `bazel-bin/LCdrData/LCdrData.zip`**, not a `.app`
  directory. Unzip it to inspect or run it.
- **Each module declares who may depend on it** via `visibility` in its own BUILD file, so
  a layering violation is an analysis-time error. The app target is named for its package
  (`//LCdrData`) rather than `app`, because `bin/LCdrData/app` and `bin/LCdrData/App/` are
  the same path on a case-insensitive filesystem.
- **The unit test targets are tagged `local`.** They do not run inside Bazel's sandbox.
- **Every test target declares `size = "small"`.** Each runs in roughly 7–10s, which is
  below the range Bazel expects of the default `medium` size, so without it every run ends
  in `Consider setting timeout="short" or size="small"` warnings. The resulting timeout is
  60s — ample, but worth knowing if a test ever starts hanging rather than failing.
- **UI tests are tagged `manual`**, so wildcards skip them. `//:LCdrDataUITests_build_test`
  provides their compile coverage instead.

## Xcode Project Generation (Tuist)

**Tuist 4** generates the Xcode project and workspace — it is not the build system, but it is
still the way to get an IDE. The `.xcodeproj` and `.xcworkspace` are **not** checked into git;
they are generated from the manifest files.

### Tuist Version

Pinned in `.tuist-version`: **4.182.0**

### Manifest Files

| File | Purpose |
|------|---------|
| `Tuist.swift` | Tuist project configuration (generation options) |
| `Project.swift` | Project manifest — defines targets, settings, and dependencies |
| `Tuist/Package.swift` | SPM dependency declarations — read by **both** Tuist and Bazel |

### Tuist Workflow

Needed before opening the project in Xcode, after cloning or pulling changes. Not needed to
build or test with Bazel:

```bash
# 1. Fetch/resolve SPM dependencies
tuist install

# 2. Generate the Xcode workspace
tuist generate
```

`tuist generate` opens the workspace in Xcode by default. Use `--no-open` to suppress that.

### Other Useful Tuist Commands

```bash
# Edit the manifest files in a temporary Xcode project (with autocompletion)
tuist edit

# Clean all Tuist-generated artifacts
tuist clean

# Dump the resolved project manifest as JSON (useful for debugging)
tuist dump
```

## Build Commands

Use Bazel:

```bash
# Build (debug — the default configuration)
bazel build //LCdrData

# Build (release — optimised, production entitlements)
bazel build //LCdrData --config=release

# Clean
bazel clean
```

The output is `bazel-bin/LCdrData/LCdrData.zip`. Unzip it to get `LCdrData.app`:

```bash
unzip -o bazel-bin/LCdrData/LCdrData.zip -d /tmp/lcdr && open /tmp/lcdr/LCdrData.app
```

Building through Xcode still works after `tuist generate`, and is the right choice when you
need the debugger or previews:

```bash
xcodebuild -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -configuration Debug build
```

## Test Commands

The project uses two test frameworks:
- **Swift Testing** (`import Testing`) for unit tests — struct-based, `@Test` attribute, `#expect(...)` assertions
- **XCTest** (`import XCTest`) for UI tests — class-based, `XCTestCase` subclass

> **During development, only run unit tests (`LCdrDataTests`).** UI tests (`LCdrDataUITests`)
> require a running app and a GUI login session — do not run them as part of automated or
> routine development workflows.

### Unit tests — Bazel

```bash
# Run all unit tests (use this during development)
bazel test //LCdrDataTests/...

# One module's tests — each test folder is its own package, and the target is
# named for it, so the label is just the folder
bazel test //LCdrDataTests/Services
bazel test //LCdrDataTests/Core/Models

# Everything Bazel is willing to run: unit tests + UI test compile coverage
bazel test //...

# Force a re-run, ignoring cached results
bazel test //LCdrDataTests/... --nocache_test_results
```

The suite is **193 test cases split across six targets** — Core/Models 50, Core/Utilities 18,
Services 46, ViewModels 69, AppEnvironment 9, App 1. They **sum** to 193; no single target
reports that number, so a target showing 50 is not a sign of lost tests.

Take counts from Swift Testing's own summary line in each test log
(`Test run with 50 tests in ... passed`) rather than counting `✔` marks, which over-counts
by including the summary line itself. Note the line reads "1 test" singular for
`AppTests`.

> One test is currently **skipped**, not run: `FileOperationServiceTests.trashFile()` is
> marked `@Test(.disabled(...))`. It still counts toward the 193, so a green run does not
> mean every test executed. `FileManager.trashItem` needs an application context, which
> makes it the only test requiring `test_host` — see
> [docs/PHASE8_MODULARISATION.md](docs/PHASE8_MODULARISATION.md) section 6.

### UI tests — Tuist, via script

```bash
scripts/run-ui-tests.sh                                # whole suite
scripts/run-ui-tests.sh PanelSelectionUITests          # one class
scripts/run-ui-tests.sh PanelSelectionUITests/testFoo  # one test
```

`bazel test //:LCdrDataUITests` does **not** work: `rules_apple`'s test runner rejects macOS
XCUITEST outright. Bazel builds these targets but never runs them. The script delegates to
Tuist and checks for a GUI session first, since without an Aqua session UI tests hang rather
than fail.

> `PanelSelectionUITests.testClickingEmptySpaceKeepsRowSelected` currently fails, and did so
> before the Bazel migration. It asserts on blank space below the file rows, so it depends on
> window size and directory contents.

### Running tests through Tuist

Occasionally useful for comparison, or to run a test in Xcode's harness:

```bash
tuist test "LCdrData" --skip-ui-tests --no-selective-testing
```

`--no-selective-testing` matters. By default Tuist skips the run when target hashes are
unchanged, reporting `no tests to run, finishing early` and exiting 0 — which looks alarmingly
like a regression and is useless as a comparison.

## Lint / Format

No linting or formatting tools are currently configured (no SwiftLint, SwiftFormat, etc.).
If added later, update this section.

## Project Structure

```
LCdrData/
├── MODULE.bazel                # Bazel dependencies (bzlmod)
├── MODULE.bazel.lock           # Committed for reproducible resolution
├── BUILD.bazel                 # Shared config; targets are per-package
├── defs.bzl                    # Shared SWIFT_COPTS and PACKAGE_NAME
├── .bazelrc                    # Deployment target, DEVELOPER_DIR, release config
├── .bazelversion               # Pinned Bazel version (9.2.0)
├── .bazelignore                # Directories Bazel must not traverse
├── Bazel/                      # Hand-written Info.plist and entitlements
├── Tuist.swift                 # Tuist project configuration
├── Project.swift               # Project manifest (targets, settings, deps)
├── Tuist/
│   ├── BUILD.bazel             # Exports the manifests to Bazel
│   └── Package.swift           # SPM dependencies — read by Tuist AND Bazel
├── .tuist-version              # Pinned Tuist version (4.182.0)
├── scripts/
│   └── run-ui-tests.sh         # UI test runner (delegates to Tuist)
├── LCdrData/                   # BUILD.bazel here defines //LCdrData (the app)
│   ├── Core/                   # Layer 1 — one module
│   │   ├── Models/             # Data models
│   │   └── Utilities/          # Formatters, keyboard shortcuts
│   ├── Services/               # Layer 2 — file system and sandbox services
│   ├── ViewModels/             # Layer 3 — observable state objects
│   ├── App/                    # Layer 4 (AppEnvironment) + layer 6 (entry point)
│   ├── Views/                  # Layer 5 — SwiftUI views
│   ├── AppIcon.icon/           # Icon Composer bundle (used by Bazel)
│   └── Assets.xcassets/        # Asset catalog (.appiconset used by Tuist)
├── LCdrDataTests/              # Unit tests (Swift Testing); every folder here
│                               # is its own Bazel package and test target
│   ├── Core/                   # Mirrors the production layout, but as two
│   │   ├── Models/             # packages: the test files, unlike the
│   │   └── Utilities/          # production sources, are not interdependent
│   ├── Services/
│   ├── ViewModels/
│   ├── AppEnvironment/
│   ├── App/
│   └── TestSupport/            # Test doubles shared across test targets
├── LCdrDataUITests/            # UI tests (XCTest)
├── Derived/                    # Tuist-generated files (gitignored)
├── docs/
│   ├── DESIGN.md               # Full design document
│   ├── CONTEXT.md              # Project vocabulary and domain terms
│   ├── CURRENT_ARCH.md         # Architecture as built
│   ├── BAZEL_MIGRATION.md      # Why the Bazel/Tuist split looks like this
│   ├── FUTURE_IMPROVEMENTS.md
│   ├── MULTIWINDOW.md
│   ├── SANDBOX_ACCESS_REDESIGN.md
│   └── parity-baseline/        # Tuist reference bundle + parity report
├── README.md                   # Project overview, build and run instructions
└── AGENTS.md                   # This file (CLAUDE.md is a symlink to it)
```

> The app icon exists in **two** formats. `rules_apple` rejects `.appiconset` for macOS 26+
> targets, so Bazel uses `AppIcon.icon` (Icon Composer) while Tuist continues to use the
> `.appiconset`. Change one and you probably want to change the other.

## Swift Concurrency Settings

The project has strict Swift 6 concurrency enabled:
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types default to MainActor isolation
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — Swift 6 approachable concurrency mode
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — stricter import visibility

These settings mean:
- All types are implicitly `@MainActor` unless explicitly opted out with `nonisolated`
- You must handle sendability and actor isolation correctly
- Imports must be explicit about what they expose to downstream modules

## Code Style Guidelines

### File Header

**Do not add Xcode file headers** (the `//  FileName.swift` / `//  LCdrData` / `//  Created by ...`
comment block) to any Swift file. Files should start directly with `import` statements.

### Imports

- One `import` per line
- Framework imports first (`import SwiftUI`, `import Foundation`)
- `@testable import` on the line directly after framework imports in test files
```swift
import Testing
@testable import LCdrData
```

### Naming Conventions

| Element           | Convention       | Example                          |
|-------------------|------------------|----------------------------------|
| Types/Protocols   | `UpperCamelCase` | `ContentView`, `DataManager`     |
| Functions/Methods | `lowerCamelCase` | `fetchData()`, `setUpWithError()`|
| Properties/Vars   | `lowerCamelCase` | `body`, `isLoading`              |
| Constants         | `lowerCamelCase` | `let maxRetryCount = 3`          |
| Enum cases        | `lowerCamelCase` | `case loading`, `case error`     |

### Types and Protocols

- Use `struct` for SwiftUI views conforming to `View`
- Use `struct` for data models (prefer value types)
- Use `class` only when reference semantics are required (e.g., `ObservableObject`)
- Use `final class` for XCTest test cases
- Use `struct` for Swift Testing test suites
- Prefer opaque return types: `some View`, `some Scene`

### SwiftUI Patterns

- Use `#Preview` macro for previews (not the deprecated `PreviewProvider`)
- Chain view modifiers on separate lines, each indented and starting with `.`:
```swift
Image(systemName: "globe")
    .imageScale(.large)
    .foregroundStyle(.tint)
```
- Group views with `VStack`, `HStack`, `ZStack` with proper alignment
- Apply `.padding()` at the outermost appropriate level

### Error Handling

- Use `throws` / `async throws` for functions that can fail
- Prefer Swift's typed error handling (`throw`/`catch`) over optionals for recoverable errors
- In tests, let errors propagate as test failures via `throws` on test functions
- Use `do`/`catch` blocks when you need to handle errors at a specific call site
- Avoid force-unwrapping (`!`) except in tests or when the invariant is guaranteed

### Formatting

- **Indentation:** 4 spaces (no tabs)
- **Braces:** Opening brace on the same line as the declaration
- **Line length:** Keep lines under 120 characters when practical
- **Trailing closures:** Use trailing closure syntax for the last closure parameter
- **Blank lines:** One blank line between functions/methods; no trailing whitespace

### Test Conventions

- Every class and struct with logic must have a corresponding unit test file
- Design code for testability: use protocol-based dependencies injected via initializer
- Avoid static methods — use instance methods on injectable types instead
- Break large classes into smaller, focused types that are easier to test in isolation
- Write test doubles **by hand**. Define a protocol for the dependency and implement a
  `Fake*` / `Mock*` / `Stub*` type in the test target, as `FakeBookmarkStore`,
  `MockFileSystemService` and `StubHomeDirectoryProvider` already do. No mocking framework
  is used — `swift-mocking` was removed, since it was declared but never imported and it
  pulled `swift-syntax` in as a macro dependency
- Follow the Arrange / Act / Assert pattern in every test

**Unit tests (Swift Testing):**
```swift
import Testing
@testable import LCdrData

struct SomeFeatureTests {
    @Test func descriptiveName() async throws {
        // Arrange
        // Act
        // Assert with #expect(...)
    }
}
```

**UI tests (XCTest):**
```swift
import XCTest

final class SomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDescriptiveName() throws {
        let app = XCUIApplication()
        app.launch()
        // Test interactions and assertions
    }
}
```

### Dependencies

| Package | URL | Purpose |
|---------|-----|---------|
| kdl-swift | https://github.com/danini-the-panini/kdl-swift | KDL 2.0 parser for configuration files |

`kdl-swift` is the only direct dependency. It pulls in BigDecimal, BigInt, UInt128 and
swift-numerics transitively.

Declare dependencies in **`Tuist/Package.swift` only** — it is the single source of truth
that both tools read. After changing it:

```bash
tuist install    # re-resolve, updating Tuist/Package.resolved
bazel mod tidy   # sync MODULE.bazel's use_repo list
```

Bazel consumes the same manifest through `rules_swift_package_manager`, so there is no
second place to add a version.

### App Sandbox

The app has App Sandbox enabled with read-write user-selected file access
and app-scope bookmarks. Files explicitly selected by the user (via open panels)
are accessible for both reading and writing, and bookmarked folders persist
across launches.
