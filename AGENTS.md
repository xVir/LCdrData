# AGENTS.md — LCdrData

LCdrData is a native macOS **dual-panel file manager** inspired by orthodox file managers
(Total Commander, ForkLift, Midnight Commander). It provides a keyboard-driven,
power-user-oriented file management experience with two side-by-side directory panels,
a command bar, and rich file operations. "LCDR" stands for "Lieutenant Commander" —
a reference to Lt. Cmdr. Data from Star Trek: The Next Generation.

Built with SwiftUI, Xcode 26.4, Swift 5.0, targeting macOS 26.4.
Bundle identifier: `com.xvir.LCdrData`.

See **[DESIGN.md](DESIGN.md)** for the full design document — architecture, data models,
feature list, keyboard shortcuts, implementation phases, and sandbox requirements.

## Tuist

The project uses **Tuist 4** to generate the Xcode project and workspace. The `.xcodeproj`
and `.xcworkspace` are **not** checked into git — they are generated from the manifest files.

### Tuist Version

Pinned in `.tuist-version`: **4.182.0**

### Manifest Files

| File | Purpose |
|------|---------|
| `Tuist.swift` | Tuist project configuration (generation options) |
| `Project.swift` | Project manifest — defines targets, settings, and dependencies |
| `Tuist/Package.swift` | SPM dependency declarations (consumed by Tuist) |

### Tuist Workflow

After cloning or pulling changes, always run these two commands before opening the project:

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

```bash
# Build (Debug) — via workspace (after tuist generate)
xcodebuild -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -configuration Debug build

# Build (Release)
xcodebuild -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -configuration Release build

# Clean build
xcodebuild -workspace "LCdrData.xcworkspace" -scheme "LCdrData" clean build
```

## Test Commands

The project uses two test frameworks:
- **Swift Testing** (`import Testing`) for unit tests — struct-based, `@Test` attribute, `#expect(...)` assertions
- **XCTest** (`import XCTest`) for UI tests — class-based, `XCTestCase` subclass

> **During development, only run unit tests (`LCdrDataTests`).** UI tests (`LCdrDataUITests`)
> require a running app and must be run manually — do not run them as part of automated or
> routine development workflows.

```bash
# Run unit tests only (use this during development)
tuist test "LCdrData" --skip-ui-tests

# Run a SINGLE unit test (Swift Testing: TargetName/StructName/functionName)
tuist test "LCdrData" --test-targets "LCdrDataTests/LCdrDataTests/example"
```

Alternatively, via `xcodebuild` directly:

```bash
# Run unit tests only (use this during development)
xcodebuild test -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -destination 'platform=macOS' \
  -only-testing:"LCdrDataTests"

# Run UI tests only (manual only — do not run during development)
xcodebuild test -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -destination 'platform=macOS' \
  -only-testing:"LCdrDataUITests"

# Run a SINGLE unit test (Swift Testing: TargetName/StructName/functionName)
xcodebuild test -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -destination 'platform=macOS' \
  -only-testing:"LCdrDataTests/LCdrDataTests/example"

# Run a SINGLE UI test (XCTest: TargetName/ClassName/testMethodName)
xcodebuild test -workspace "LCdrData.xcworkspace" -scheme "LCdrData" -destination 'platform=macOS' \
  -only-testing:"LCdrDataUITests/LCdrDataUITests/testExample"
```

## Lint / Format

No linting or formatting tools are currently configured (no SwiftLint, SwiftFormat, etc.).
If added later, update this section.

## Project Structure

```
LCdrData/
├── Tuist.swift                 # Tuist project configuration
├── Project.swift               # Project manifest (targets, settings, deps)
├── Tuist/
│   └── Package.swift           # SPM dependency declarations
├── .tuist-version              # Pinned Tuist version (4.182.0)
├── LCdrData/                   # Main app target
│   ├── App/                    # App entry point and delegate
│   ├── Assets.xcassets/        # Asset catalog (colors, app icon)
│   ├── Models/                 # Data models
│   ├── Services/               # File system and sandbox services
│   ├── Utilities/              # Formatters, keyboard shortcuts
│   ├── ViewModels/             # Observable state objects
│   └── Views/                  # SwiftUI views
├── LCdrDataTests/              # Unit tests (Swift Testing)
├── LCdrDataUITests/            # UI tests (XCTest)
├── Derived/                    # Tuist-generated files (gitignored)
├── AGENTS.md
└── DESIGN.md
```

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
- Use [swift-mocking](https://github.com/DanielCardonaRojas/swift-mocking) for creating
  mocks in tests — define protocols for dependencies and mock them via swift-mocking
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
| swift-mocking | https://github.com/DanielCardonaRojas/swift-mocking | Mock generation for unit tests |

Dependencies are managed via Swift Package Manager in Xcode.
Declared in `Tuist/Package.swift` and resolved by `tuist install`.

### App Sandbox

The app has App Sandbox enabled with read-write user-selected file access
and app-scope bookmarks. Files explicitly selected by the user (via open panels)
are accessible for both reading and writing, and bookmarked folders persist
across launches.
