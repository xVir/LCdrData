# LCdrData

A native macOS **dual-panel file manager** in the orthodox tradition of Total Commander,
ForkLift and Midnight Commander: two directory panels side by side, a function-key command
bar along the bottom, and enough keyboard coverage that the mouse is optional.

"LCDR" stands for Lieutenant Commander — a nod to Lt. Cmdr. Data of *Star Trek: The Next
Generation*.

Written in SwiftUI, sandboxed, and built with Bazel.

## Requirements

| | |
|---|---|
| macOS | 26.4 or later |
| Xcode | 26.4 (at `/Applications/Xcode.app`, pinned in `.bazelrc`) |
| Bazel | 9.2.0 — pinned in `.bazelversion`, so [Bazelisk](https://github.com/bazelbuild/bazelisk) picks it up automatically |
| Tuist | 4.182.0 — only needed for an Xcode project or UI tests |

Nothing else to install. Bazel resolves its own dependencies on the first build.

## Build and run

```bash
bazel run //LCdrData
```

That builds the app, unzips the bundle to a temporary directory and launches it. The
terminal stays attached until you quit the app.

For a copy that outlives the run, build and unzip it yourself. Note that
`bazel build` produces a **zip**, not a `.app` directory:

```bash
bazel build //LCdrData
unzip -o bazel-bin/LCdrData/LCdrData.zip -d /tmp/lcdr
open /tmp/lcdr/LCdrData.app
```

Both of the above are debug builds, whose entitlements include `get-task-allow` and the
`testmanagerd` exceptions that app-hosted unit tests need in order to launch. For an
optimised build carrying only the two production entitlement keys:

```bash
bazel build //LCdrData --config=release
```

### Tests

```bash
bazel test //LCdrDataTests/...   # all unit tests
bazel test //LCdrDataTests/Core/Models   # one module's tests
```

193 test cases written with [Swift Testing](https://github.com/swiftlang/swift-testing),
split across six targets whose counts sum to that total. `bazel test //...` adds compile
coverage for the UI tests.

UI tests need a GUI login session and are driven by Tuist rather than Bazel, since Bazel's
Apple test runner refuses macOS XCUITEST:

```bash
scripts/run-ui-tests.sh
```

### Working in Xcode

Bazel cannot give you SwiftUI previews or a comfortable debugger, so the Xcode project is
generated on demand with Tuist. It is not checked in:

```bash
tuist install    # resolve SPM dependencies
tuist generate   # generate and open the workspace
```

Both tools read the same dependency manifest, `Tuist/Package.swift`, so there is no second
version list to keep in sync. See [docs/BAZEL_MIGRATION.md](docs/BAZEL_MIGRATION.md) for why
the work is divided this way.

## Features

**Panels and navigation.** Two resizable panels, each with a breadcrumb path bar that is
also editable (`⌘L`, with `~` expansion), independent back/forward history, and a status
bar. `Tab` moves between them.

**Listing.** Name, size, date and kind columns, sortable by header click, directories first
within each sort group. Multi-select, type-ahead search, a togglable hidden-file filter, and
a cursor model that keeps your place sensibly across reloads.

**File operations.** Copy and move between panels, trash, permanent delete, create folder
and rename — with a progress overlay you can cancel and a conflict dialog offering
overwrite, skip or auto-rename, each applicable to the whole batch.

**Previewing.** Quick Look via the system preview panel (`Space` or `F3`), open in the
default application (`F4`), and reveal in Finder.

**Multiple windows.** `⌘N` opens another window with its own panel state, seeded from the
frontmost window; the file-system services are shared. Sessions are restored on relaunch.

**Sandboxed by design.** Access to folders outside the sandbox is granted through the
standard open panel and remembered as security-scoped bookmarks, so a granted folder stays
available across launches. Panels auto-refresh when their directory changes on disk.

**Configuration.** A KDL file with a built-in editor (`⌘,`) — see below.

Not implemented yet: tabs, archive browsing, an inline preview pane, a file-search service,
and remappable keyboard shortcuts.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `Tab` | Switch active panel |
| `Return` | Enter directory, or rename a file |
| `⌘↑` / `Delete` | Go to parent directory |
| `⌘↓` | Open the focused item |
| `⌘L` | Edit the path bar |
| `⌘[` / `⌘]` | History back / forward |
| `⌘R` | Refresh |
| `⌘⇧.` | Toggle hidden files |
| `⌘A` / `⌘⇧A` | Select all / collapse selection to the focused row |
| `⌘⌥C` | Copy selected paths to the clipboard |
| `Space` / `F3` | Quick Look |
| `F2` | Rename |
| `F4` | Open in default application |
| `F5` / `F6` | Copy / move to the other panel |
| `F7` | New folder |
| `F8` / `⌘⌫` | Move to trash / delete permanently |
| `Home` / `End` | First / last row |
| any letter | Type-ahead search |

## Configuration

Settings live in a [KDL 2.0](https://kdl.dev) file, merged over the bundled defaults in
`LCdrData/Resources/DefaultConfig.kdl`. `⌘,` opens an editor showing the defaults beside
your overrides; changes apply on **Apply**, without a restart. Because the app is sandboxed,
the file itself lives inside the container:

```
~/Library/Containers/com.xvir.LCdrData/Data/Library/Application Support/com.xvir.LCdrData/config.kdl
```

It is created on the first **Apply**, and deleting it restores the defaults.

```kdl
panel {
    show-hidden-files #false
    sort-by name
    sort-ascending #true
}

appearance {
    font-size 13
    date-format "yyyy-MM-dd HH:mm"
}

bookmarks {
    - "Projects|~/Projects"
    - "Downloads|~/Downloads"
}
```

`bookmarks` entries become the Favorites menu.

## Architecture

Nine modules, each a separate Swift module and Bazel target, stacked so dependencies only
ever point downward:

```
App  →  Views  →  AppEnvironment  →  ViewModels  →  Services  →  Core (four modules)
```

Every module's BUILD file names, via Bazel `visibility`, exactly which packages may depend
on it, so a layering violation fails at analysis time rather than in review.

```
LCdrData/
├── Core/          Utilities and Models, both dependency-free, plus
│                  Formatting and Bindings, one file each
├── Services/      File system, sandbox access, configuration, persistence
├── ViewModels/    Observable state: panels, app state, operations
├── App/           AppEnvironment (shared services) and the app entry point
└── Views/         SwiftUI views
```

`Core/` is the one place where folders and modules deliberately do not line up. Two files
each need something from both halves — `FileFormatter` takes a `FileItem`, and
`CommandCatalog` maps a `Command` to a key — so each compiles as its own small module above
the two leaves. That is what lets `Models` and `Utilities` depend on nothing at all; see
[docs/CURRENT_ARCH.md](docs/CURRENT_ARCH.md) §3.

## Documentation

| | |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | Product spec — layout, behaviour, keyboard map, configuration |
| [docs/CURRENT_ARCH.md](docs/CURRENT_ARCH.md) | The architecture as built |
| [docs/CONTEXT.md](docs/CONTEXT.md) | Project vocabulary — panel, cursor, listing, session |
| [docs/BAZEL_MIGRATION.md](docs/BAZEL_MIGRATION.md) | Why Bazel and Tuist both stay |
| [AGENTS.md](AGENTS.md) | Contributor and agent guide: commands, conventions, gotchas |
