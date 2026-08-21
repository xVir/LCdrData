# CONTEXT.md — LCdrData domain glossary

The shared vocabulary used in design conversations and code reviews. When a term is
sharpened or a new term emerges from a design session, update this file inline so
the language stays consistent.

> Architecture vocabulary (deep / shallow / interface / seam / leverage / locality)
> lives in the `improve-codebase-architecture` skill's `LANGUAGE.md` and is not
> repeated here — this file is for **domain** terms specific to LCdrData.

---

## Panel

One side of the dual-pane file manager. A panel browses **one directory at a time**,
displays a **listing**, and tracks a **cursor**. The two panels are named **left**
and **right**. Exactly one is the **active panel** at any moment; keyboard shortcuts
and file operations target the active panel (or the inactive one as the destination,
for copy / move).

A panel's mutable surface is `PanelState`; its behaviour lives on `PanelViewModel`.

## Active panel

The panel that receives keyboard input and is the implicit source for file
operations. Tracked on `AppState.activePanel: PanelSide`. The other panel is the
**inactive panel** and acts as the destination for cross-panel operations.

## Listing

The ordered array of `FileItem` rows shown in a panel. Always begins with a synthetic
`..` row when the panel's directory is not the filesystem root. Sort is determined by
the panel's `FileSortDescriptor`; directories always sort before files within a sort
group.

## File item

A `FileItem` is one row in a listing — either a real filesystem entry or the
synthetic `..` parent row (`isParentDirectory == true`). Its `id: UUID` is
deterministic (SHA-256 of the standardized URL path), so the same file produces
the same identity across reloads.

## Cursor

The pair `(focused: UUID?, selected: Set<UUID>)` describing **where the user's
attention is** in a panel's listing. Lives on `PanelState.cursor` as a `Cursor`
value type that owns all mutation rules:

- `focused` — the single row the user is "on" (drives Quick Look target, sort
  reference, type-ahead anchor).
- `selected` — the set of rows participating in the next file operation. Always
  contains `focused` after any user-driven mutation that produces a single
  selection.

Cursor mutations come from two sources:

1. **User events** (clicks, arrow keys, type-ahead, Commander-Space, Cmd+A,
   focusFirst/focusLast). Expressed as mutating methods on `Cursor`
   (`userDidSelect(_:)`, `selectAll(in:)`, `focusFirst(in:)`, etc.).
2. **Reloads.** When the listing changes, `Cursor.resolve(intent:listing:previous:)`
   computes the new cursor based on the **intent** the caller declared.

A click on empty space below the rows reaches `userDidSelect(_:)` as an empty
set, and the cursor refuses it — the focused row is put straight back, so a panel
is never left without a cursor. The list clears its own highlight before
reporting that empty set, so `PanelViewModel.cursorDidChangeSelection(to:)`
publishes the empty state for one runloop turn before restoring; without that
round trip the binding never changes value, SwiftUI never writes the selection
back down, and the row stays visually deselected while the cursor still points
at it.

## Cursor.Intent

A value passed by every reload caller declaring **where the cursor should land**
when the new listing arrives. Intents are explicit — the panel does not infer
them.

| Case | Used by | Meaning |
|---|---|---|
| `.fresh` | first load, history back/forward, bookmark / path-bar navigation | First row of the listing — the `..` row when present, otherwise the first real item, or empty cursor for an empty listing |
| `.keepSelection` | background watcher reload, sort change, hidden-files toggle, configuration apply | Preserve previous focused/selected; if focused row vanished, fall back to the same index |
| `.landOnChild(URL)` | `navigateToParent()` | Focus the directory the panel just left |
| `.landOnNeighbourOf([URL])` | after delete (Trash + permanent) and after move (source side) | Focus the row adjacent to the doomed URLs in the previous listing, mapped to the new listing |
| `.landOnNew(URL)` | after rename and mkdir | Focus the newly created/renamed item |

The resolver runs **after** the new listing has been fetched, with both the
previous and the new listing in hand, so `.landOnNeighbourOf` can compute the
neighbour from the diff (replacing the old "set a target ID before deleting"
dance).

## Reload

The single act of "fetch a fresh listing for the panel's current directory and
reposition the cursor." Triggered through `PanelViewModel.reload(_ intent:
Cursor.Intent)`. Replaces the prior split between `loadDirectory()` and
`reloadKeepingSelection()`.

## DirectorySession

The panel's grip on **one** directory. A short-lived handle that, while it exists:

- holds security-scoped access to the URL,
- watches the FD for filesystem changes,
- debounces those changes (~280 ms) before notifying via `onChange`.

The session is replaced — not mutated — when the panel navigates to a different
URL: the old session's `deinit` releases the scope, cancels the watcher, and
closes the FD. Listing I/O does **not** go through the session; the panel still
calls `FileSystemServiceProtocol.listDirectory` directly. The session is purely
the URL-scoped lifecycle wrapper.

## Panel session

The pair of directories one window's panels are showing, carried as a
`PanelSession` by `WindowGroup(for:)`.

macOS window restoration round-trips that value, but only when the system elects
to restore windows — never when "Close windows when quitting an application" is
enabled, and never when the app is killed rather than quit (as `tuist run` does).
Resuming therefore cannot rely on it. `PanelSessionStore` records the directories
in `UserDefaults` on every navigation, and `AppEnvironment.makeFreshSession()`
seeds a new window from, in order: the frontmost window (so Cmd+N opens beside
what the user is looking at), the directories recorded on the previous run, then
Home on a genuine first launch.

Resuming a directory outside the container also needs its security scope back,
which works because the same navigation that records the paths also stores a
bookmark — see **Sandbox access / security scope**.

## Highlight

The transient green-flash animation drawn on a row to draw the user's attention
(e.g. just after a folder is created). Independent of the cursor: a row can be
highlighted whether or not it is focused, and a focused row is not normally
highlighted. Triggered via `PanelViewModel.highlight(url:)`.

## Sandbox access / security scope

LCdrData runs sandboxed; access to a directory requires the user to have granted
it via an `NSOpenPanel` (or via a stored security-scoped bookmark resolved at
launch). **Scope is owned app-wide by `AppEnvironment`**, not by individual panels:
`AppEnvironment.start()` iterates `BookmarkStore`, calls
`startAccessingSecurityScopedResource()` on every resolved bookmark URL, and
tracks them in `activeScopes`; `applicationWillTerminate` releases them.
`DirectorySession` is a pure FD watcher and does not touch scope.

`SandboxAccessService` (an actor on `AppEnvironment`) owns the app-modal
**reactive grant prompt** (`NSOpenPanel` pre-navigated to the resolved target).
The prompt is triggered when `PanelViewModel` detects no `bookmarkStore.bookmarkCovering(url:)`
match for the navigation target (**bookmark-coverage gate** — primary trigger);
a permission-error classifier remains as a safety net for the rare
covered-but-still-denied race. The pre-redesign embedded "Access Denied" panel
view is gone.

_Avoid_: "permission error trigger" (it's a *fallback*, not the primary signal);
"DirectorySession holds scope" (no longer true since the redesign).

## Type-ahead

Incremental row search driven by printable keystrokes typed into the active panel.
A 1-second pause resets the buffer. Type-ahead mutates the cursor (focused +
selected ← matched row) on the **current listing** — it never triggers a reload,
so it has no `Cursor.Intent`.

## Secondary click

The macOS term for a right-click / two-finger / Control-click — the trigger for
the **context menu**. Prefer "secondary click" over "right click" in code and
conversation (matches AppKit's `rightMouseDown` / `.secondaryAction`).

A secondary click on a panel row does three things, in order, before the menu is
visible:

1. **Activates the panel** (sets it as the **active panel**).
2. **Moves the cursor**: if the clicked row is not part of the current
   **selection**, the selection collapses to just that row (previously selected
   rows are deselected); if the row is already in a multi-selection, the whole
   selection is kept. This reuses the existing `Cursor.userDidSelect(_:)` path —
   it is **not** a new cursor mutation.
3. **Presents the context menu** for the resulting selection.

## Context menu

The menu shown on **secondary click** of a panel. It has three variants,
determined by what the click resolves to:

- **Selection context menu** — one or more real (non-`..`) rows are selected.
  Offers file actions (Open — single selection only; Move to Trash; Rename —
  single only; Copy / Move to the inactive panel; Copy Path; Reveal in Finder)
  plus an extension section reserved for LCdrData-specific actions.
- **Parent context menu** — the click resolves to only the synthetic `..` row.
  A single "Open" item that navigates to the parent directory.
- **Background context menu** — a click on empty space below the rows (empty
  selection). Directory-scoped actions (New Folder, Select All, Toggle Hidden
  Files, Reload).

The menu is built from a pure `FileContextMenuModel` (which variant, and the
resolved non-parent items), so the decision logic is testable independently of
the SwiftUI view.

## Command

A user action that can be triggered from any UI surface — the window key
handler, the menu bar (`MainCommands`), the command bar (`CommandBarView`), or a
**context menu** — modelled as the `Command` enum. Most cases are parameterless
(the target is resolved from the active panel's **cursor**); `.openItem` and
`.rename` carry an explicit `FileItem` for surfaces that already have the row in
hand (row double-click, context menu on a specific row).

UI surfaces never assemble file-operation calls or decide which panel is source
vs. destination — they name a `Command` and hand it to the **command runner**.

## Command runner

`CommandRunner` — the single place that *executes* a **Command** against a
window's `AppState`. It resolves the **active panel** / **inactive panel**, reads
the **cursor** for targets, and delegates to `PanelViewModel` /
`FileOperationViewModel` / `AppState`. It also answers `isEnabled(_:)` (the one
source of truth for whether an action is currently available) and resolves the
Rename target from the cursor. Exposed as `AppState.commands`, a lightweight
value recreated per access (no retained state, no cycle with `AppState`).

Keyboard shortcuts for commands live in `CommandCatalog` (the single
command-to-shortcut map that every surface reads); titles stay per-surface
because the same command is labelled differently in different places
(e.g. "Copy" in the command bar vs. "Copy to Other Panel" in a context menu).
