# LCdrData — Design Document

## Overview

LCdrData is a native macOS dual-panel file manager inspired by orthodox file managers
(Total Commander, ForkLift, Midnight Commander). It is built entirely with Swift and
SwiftUI, targeting macOS 26.4+. The name "LCDR" stands for "Lieutenant Commander" — a nod
to the tradition of naming file managers with military/naval ranks (Commander, Captain, etc.)
and a reference to Lieutenant Commander Data from Star Trek: The Next Generation.

The app provides a keyboard-driven, power-user-oriented file management experience with
two side-by-side directory panels, a command bar, and rich file operations.

## Design Principles

1. **Keyboard-first** — every action reachable via keyboard shortcut; mouse is optional
2. **Native macOS** — use system APIs (FileManager, NSWorkspace, FSEvents), respect
   sandboxing, support macOS services and Finder integration
3. **Performance** — handle directories with 100k+ files; lazy loading, background I/O
4. **Simplicity** — avoid feature bloat; ship a focused core before adding plugins
5. **Transparency** — file operations show real progress; errors surface clearly

## Architecture

### Layer Diagram

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI Views                  │  Presentation
│  (MainWindow, PanelView, Toolbar, Dialogs)      │
├─────────────────────────────────────────────────┤
│               ViewModels / State                │  State Management
│  (PanelViewModel, FileOperationVM, AppState)    │
├─────────────────────────────────────────────────┤
│                   Services                      │  Business Logic
│  (FileSystemService, OperationQueue,            │
│   SearchService, BookmarkService)               │
├─────────────────────────────────────────────────┤
│                    Models                       │  Data
│  (FileItem, PanelState, SortDescriptor,         │
│   FileOperation, Bookmark)                      │
└─────────────────────────────────────────────────┘
```

### Target Module Layout

All source code lives in the `LCdrData/` app target. Organize by feature/layer:

```
LCdrData/
├── App/
│   └── LCdrDataApp.swift               # @main entry point, window/scene setup
├── Models/
│   ├── FileItem.swift                  # Single file/directory representation
│   ├── PanelState.swift                # State of one file panel
│   ├── SortDescriptor.swift            # Column sort configuration
│   ├── FileOperation.swift             # Copy/move/delete operation descriptor
│   ├── Bookmark.swift                  # Saved location / security-scoped bookmark
│   └── AppConfiguration.swift          # Strongly-typed config model (parsed from KDL)
├── ViewModels/
│   ├── AppState.swift                  # Global app state (active panel, theme, etc.)
│   ├── PanelViewModel.swift            # Drives one panel: listing, selection, navigation
│   └── FileOperationViewModel.swift    # Manages queued file operations and progress
├── Services/
│   ├── FileSystemService.swift         # Directory listing, metadata, file watching
│   ├── FileOperationService.swift      # Copy, move, rename, delete, create
│   ├── SearchService.swift             # File name / content search
│   ├── BookmarkService.swift           # Security-scoped bookmark persistence
│   └── ConfigurationService.swift      # KDL config load/parse/apply/save
├── Views/
│   ├── MainWindowView.swift            # Root view: two panels + toolbar + command bar
│   ├── PanelView.swift                 # Single file panel (table, path bar, status bar)
│   ├── FileTableView.swift             # Sortable file/directory list (Table or List)
│   ├── PathBarView.swift               # Breadcrumb / editable path bar
│   ├── ToolbarView.swift               # Top toolbar with common actions
│   ├── CommandBarView.swift            # Bottom command/quick-action bar
│   ├── StatusBarView.swift             # Per-panel status: item count, selection size
│   ├── FileOperationProgressView.swift # Operation progress sheet/overlay
│   └── ConfigurationView.swift         # Dual-pane KDL: defaults (read-only) + user overrides, Apply/Cancel
├── Utilities/
│   ├── KeyboardShortcuts.swift         # Centralized shortcut definitions
│   ├── FileFormatter.swift             # Size, date, permissions formatting
│   ├── Icons.swift                     # System icon helpers
│   └── KDLSyntaxHighlighter.swift      # KDL syntax highlighting for config editor
└── Resources/
    └── Assets.xcassets/
```

## Data Models

### FileItem

```swift
struct FileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?              // nil for directories (computed on demand)
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let isSymlink: Bool
    let permissions: UInt16
}
```

### PanelState

```swift
struct PanelState {
    var currentDirectory: URL
    var items: [FileItem]
    var selectedItemIDs: Set<UUID>
    var focusedItemID: UUID?
    var sortDescriptor: SortDescriptor
    var showHiddenFiles: Bool
    var history: [URL]            // back/forward navigation stack
    var historyIndex: Int
}
```

### SortDescriptor

```swift
struct SortDescriptor {
    enum Column: String { case name, size, dateModified, dateCreated, kind }
    var column: Column
    var ascending: Bool
}
```

## Core Features (MVP)

### 1. Dual-Panel Layout

- Two side-by-side file panels, each independently navigable
- One panel is "active" (focused) at any time — indicated visually
- Tab key switches active panel
- Each panel has: path bar, file table, status bar
- Resizable splitter between panels

### 2. File Table

- Columns: Icon, Name, Size, Date Modified, Kind
- Sortable by clicking column headers
- Single-click selects; Cmd+click for multi-select; Shift+click for range select
- Enter: enter directories; for a focused **file**, Enter starts rename (macOS-style).
- F2: rename the focused item (not the `..` row).
- Double-click or Cmd+Down opens files and enters directories.
- **Delete** (⌫) and **forward delete** (⌦): go to parent directory when the file list has keyboard focus and the path bar is not being edited—same outcome as activating `..`. **Cmd+Up** also goes to parent via the menu command **Go to Parent Directory**.
- Show/hide hidden files toggle (Cmd+Shift+.)
- `..` entry at top to navigate to parent

### 3. File Operations

All operations work from the active panel to the inactive panel (as target):

| Operation       | Shortcut | Description                              |
|-----------------|----------|------------------------------------------|
| Copy            | F5       | Copy selected items to other panel       |
| Move            | F6       | Move selected items to other panel       |
| Delete          | F8       | Move selected items to Trash             |
| Permanent delete| Cmd+Delete | Remove immediately (not Trash); confirmation |
| New Folder      | F7       | Create directory in active panel         |
| Rename          | Enter / F2 | Rename focused file (Enter Finder-style; F2 orthodox) |
| View            | F3       | Quick Look preview                       |
| Edit            | F4       | Open in default editor                   |
| Refresh         | Cmd+R    | Reload active panel                      |

Menu commands (same shortcuts where shown in the menu bar) also expose **Go to Parent**, **Open**, **Delete Immediately…**, **Copy Selected Paths**, etc. The **Edit › Delete** list command can still move the selection to Trash when chosen from the menu; the physical **Delete** / **forward delete** keys in the main window are bound to parent navigation only.

- Confirmation dialogs for destructive operations
- Progress sheet for long-running copy/move with cancel support
- Conflict resolution: skip, overwrite, rename, apply to all

### 4. Navigation

- Path bar: clickable breadcrumbs; editable via Cmd+L (go to path)
- Parent directory: `..` row, **Cmd+Up** (**Go to Parent Directory** in the menu), or plain **Delete** / **forward delete** when the list is focused (see File Table above).
- Back/forward history per panel (Cmd+[ / Cmd+])
- Bookmarks sidebar or dropdown for saved locations
- Volumes list accessible from path bar root
- Drag and drop support (files into/out of panels)

### 5. Keyboard Navigation

- Arrow keys navigate the file list
- Type-ahead / incremental search: start typing to jump to matching filename
- Space opens Quick Look preview for the focused file (same as F3)
- Cmd+A selects all; Cmd+Shift+A collapses multi-selection to the focused row
- Home / End: first / last row in the list; Cmd+Down opens the focused item (same as double-click)

### 6. Command Bar

Bottom bar with function-key labels (F3 View, F5 Copy, F6 Move, F7 Mkdir, F8 Delete)
reminiscent of classic orthodox file managers. Clickable and acts as keyboard hint.

## Future Features (Post-MVP)

These are explicitly out of scope for the initial implementation but inform
architectural decisions (keep extension points open):

- **Dependency injection** - use Swinject https://github.com/swinject/swinject for dependency injectsion management in the app
- **Tabs** — multiple tabs per panel
- **Archive support** — browse zip/tar/gz as directories
- **File preview panel** — Quick Look-style inline preview using QLPreviewView in the file panel

## State Management

Use the `@Observable` macro (Observation framework) for view models:

```swift
@Observable
final class PanelViewModel {
    var state: PanelState
    private let fileSystemService: FileSystemService
    // ...
}
```

Global app state held in `AppState`, injected via SwiftUI environment:

```swift
@Observable
final class AppState {
    var leftPanel: PanelViewModel
    var rightPanel: PanelViewModel
    var activePanel: PanelSide  // .left or .right
}
```

Inject into the view hierarchy:

```swift
WindowGroup {
    MainWindowView()
        .environment(appState)
}
```

## Configuration

### Language: KDL 2.0

App configuration uses [KDL 2.0](https://kdl.dev/) ("cuddle") — a human-friendly document
language with node-based semantics. KDL is parsed via the
[kdl-swift](https://github.com/danini-the-panini/kdl-swift) library (Swift Package Manager).

The configuration file lives at:
`~/Library/Application Support/com.xvir.LCdrData/config.kdl`

Example configuration:

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
    bookmark "Projects" "~/Projects"
    bookmark "Downloads" "~/Downloads"
}

editor {
    default-app "com.apple.TextEdit"
}

keyboard {
    // Override default shortcuts (function keys for file ops).
    // Plain Delete / forward-delete always mean “go to parent” in the main window;
    // they are not assigned here.
    copy F5
    move F6
    delete F8
    mkdir F7
}
```

### Configuration Window

The configuration window is a dedicated macOS window (opened via Cmd+, or the app menu)
laid out as **two side-by-side panels** (split view), consistent with the app’s dual-panel
metaphor:

1. **Left panel — default configuration (read-only)** — A scrollable, monospaced view of
   the **full default** configuration expressed in KDL, with the same syntax highlighting
   as the editable side (keywords, strings, numbers, comments, node names in distinct
   colors). It lists **every** supported option together with its built-in default value.
   This pane is not editable; it is the reference for “what the app assumes” when the user
   file does not override something.

2. **Right panel — your customizations** — A scrollable, monospaced **editable** KDL text
   area for the user’s overrides. Only what appears here is persisted as the user config
   (see path above). Any option or value you set in the right panel **overwrites** the
   corresponding default from the left panel for the running app; options you omit keep
   their defaults.

3. **"Apply" button** — Parses the right panel’s KDL, validates it, merges it on top of the
   defaults, and applies the **effective** configuration to the running app. If parsing
   fails, an inline error message is shown with the line number and description of the
   problem; the config is not applied.

4. **"Cancel" button** — Discards unsaved edits in the right panel and closes the window,
   reverting that panel to the last-applied user configuration.

The window does **not** auto-save. Changes only take effect when the user explicitly
clicks "Apply". On successful apply, the right panel’s KDL is written to the config file
on disk and all observable state that depends on configuration is updated immediately.

### Configuration Data Flow

Effective configuration is **defaults ∪ user file**: bundled default KDL (shown read-only
in the configuration window’s left panel) is merged with `config.kdl` from disk (edited
in the right panel); user values win on conflict.

```
bundled default KDL  ──┐
                       ├──► merge ──► AppConfiguration (effective)
config.kdl on disk  ───┘
       ▲
       │ read on launch; write on Apply
 ConfigurationService          ← reads/writes user file, parses KDL via kdl-swift
       │
       ▼
 AppState / ViewModels         ← observe configuration changes
```

### ConfigurationService

```swift
@Observable
final class ConfigurationService {
    var current: AppConfiguration
    
    func load() throws                       // Read user file, merge with bundled defaults
    func apply(fromUserKDL kdlText: String) throws  // Parse overrides, merge, validate, write user file
    func defaultKDLText() -> String          // Bundled full defaults (left pane, read-only)
    func userKDLText() -> String             // Last-applied user overrides (right pane)
}
```

## File System Interaction

### Directory Listing

Use `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
with resource keys pre-fetched for performance:

```swift
let keys: [URLResourceKey] = [
    .nameKey, .isDirectoryKey, .fileSizeKey,
    .contentModificationDateKey, .creationDateKey,
    .isHiddenKey, .isSymbolicLinkKey
]
```

Run listing on a background thread; publish results to the view model.

### File Watching

Use `DispatchSource.makeFileSystemObjectSource` or `FSEventStreamCreate` to watch
the current directory for changes and auto-refresh the panel.

### Security-Scoped Bookmarks

Since the app runs in a sandbox with user-selected file access:

- When the user selects a folder via `NSOpenPanel`, persist a security-scoped bookmark
- On relaunch, resolve the bookmark and call `startAccessingSecurityScopedResource()`
- Store bookmarks in `UserDefaults` or a small plist file
- The `BookmarkService` handles the full lifecycle

### File Operations

Use `FileManager` for copy/move/delete. For long operations:

- Run on a background `OperationQueue` with configurable concurrency
- Report progress via `Progress` objects bridged to SwiftUI
- Support cancellation via cooperative `Task` cancellation

## Window and Layout

### Minimum Window Size

800 x 500 points. Default: 1100 x 700.

### Window Configuration

```swift
WindowGroup {
    MainWindowView()
}
.defaultSize(width: 1100, height: 700)
.windowResizability(.contentMinSize)
```

### Layout Sketch

```
┌──────────────────────────────────────────────────────────┐
│  [Toolbar: Back/Fwd | Bookmarks | Search | Preferences]  │
├────────────────────────┬─────────────────────────────────┤
│  /Users/dan/Documents  │  /Users/dan/Downloads           │  Path bars
├────────────────────────┼─────────────────────────────────┤
│  ..                    │  ..                              │
│  > Projects/      4 KB │  archive.zip          12.3 MB   │
│  > Photos/       12 KB │  report.pdf            2.1 MB   │
│    notes.txt      1 KB │  > screenshots/        4 KB     │
│    readme.md      3 KB │    image.png          845 KB    │
│                        │                                  │
│                        │                                  │
├────────────────────────┼─────────────────────────────────┤
│  3 items, 8 KB         │  4 items, 15.2 MB               │  Status bars
├────────────────────────┴─────────────────────────────────┤
│  [F3 View] [F5 Copy] [F6 Move] [F7 Mkdir] [F8 Delete]   │  Command bar
└──────────────────────────────────────────────────────────┘
```

## Keyboard Shortcut Map

| Shortcut          | Action                          |
|-------------------|---------------------------------|
| Tab               | Switch active panel             |
| Enter             | Enter directory, or rename focused **file** |
| F2                | Rename focused item (not `..`)  |
| Delete / forward delete | Go to parent directory (list focused; not while editing path) |
| Cmd+Down / Dbl-click | Open file / enter directory  |
| Cmd+Up            | Go to parent directory (menu)   |
| Cmd+L             | Focus path bar (go to path)     |
| Cmd+Shift+O       | Open Folder…                    |
| Cmd+R             | Refresh panel                   |
| Cmd+Shift+.       | Toggle hidden files             |
| Cmd+[ / Cmd+]     | History back / forward          |
| Cmd+A             | Select all (excludes `..`)      |
| Cmd+Shift+A       | Collapse selection to focused row |
| Cmd+Option+C      | Copy selected paths to clipboard |
| Cmd+Delete        | Permanent delete (with confirmation) |
| Space             | Quick Look preview (same as F3) |
| F3                | Quick Look preview              |
| F4                | Open in editor                  |
| F5                | Copy to other panel             |
| F6                | Move to other panel             |
| F7                | Create new folder               |
| F8                | Move to Trash                   |
| Home / End        | First / last list row           |
| Arrows            | Navigate list                   |
| Type characters   | Incremental filename search     |

## Dependencies

| Package | URL | Purpose |
|---------|-----|---------|
| kdl-swift | https://github.com/danini-the-panini/kdl-swift | KDL 2.0 parser for configuration files |
| swift-mocking | https://github.com/DanielCardonaRojas/swift-mocking | Mock generation for unit tests |

Added via Swift Package Manager in Xcode (File > Add Package Dependencies).

## Sandbox and Entitlements

Required entitlements (`LCdrData.entitlements`):

```xml
<key>com.apple.security.app-sandbox</key>          <true/>
<key>com.apple.security.files.user-selected.read-write</key>  <true/>
<key>com.apple.security.files.bookmarks.app-scope</key>       <true/>
```

The project has `read-write` user-selected file access and app-scope bookmarks,
enabling copy, move, rename, and delete operations. Bookmarked folders persist
across launches.

## Implementation Phases

### Phase 1 — Skeleton and Navigation
- Dual-panel layout with resizable splitter
- Directory listing with FileItem model
- Basic navigation: enter directories, go to parent, path bar
- Column sorting
- Panel switching with Tab

### Phase 2 — File Operations
- Copy, move, delete (to Trash) with confirmation dialogs
- New folder creation
- Rename (inline editing)
- Progress reporting for long operations
- Conflict resolution dialog

### Phase 3 — Power User Features
- Keyboard shortcut system (full map above)
- Type-ahead incremental search
- Space-to-preview (mirrors F3 Quick Look)
- Hidden files toggle
- Back/forward history
- Command bar with function key labels

### Phase 4 — Configuration and Polish
- KDL 2.0 configuration system (ConfigurationService, AppConfiguration model)
- Configuration window: dual-pane KDL (read-only defaults, editable overrides), syntax highlighting, Apply/Cancel
- Security-scoped bookmarks (remember folders across launches)
- Bookmarks sidebar / favorites
- File watching with auto-refresh
- Drag and drop (within panels, to/from Finder)
- Menu bar integration with standard macOS File/Edit/View menus

### Phase 5 — Advanced Features
- Tabs per panel

