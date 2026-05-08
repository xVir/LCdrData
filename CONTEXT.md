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
   (`userDidSelect(_:)`, `userDidClickEmpty()`, etc.).
2. **Reloads.** When the listing changes, `Cursor.resolve(intent:listing:previous:)`
   computes the new cursor based on the **intent** the caller declared.

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

## Highlight

The transient green-flash animation drawn on a row to draw the user's attention
(e.g. just after a folder is created). Independent of the cursor: a row can be
highlighted whether or not it is focused, and a focused row is not normally
highlighted. Triggered via `PanelViewModel.highlight(url:)`.

## Sandbox access / security scope

LCdrData runs sandboxed; access to a directory requires the user to have granted
it via an `NSOpenPanel` (or via a stored security-scoped bookmark resolved at
launch). `DirectorySession` is responsible for `startAccessingSecurityScopedResource()`
on construction and the matching `stopAccessingSecurityScopedResource()` on
teardown. `SandboxAccessService` owns the **prompt** flow shown in the panel's
error view when a listing fails with EPERM / NSFileReadNoPermissionError.

## Type-ahead

Incremental row search driven by printable keystrokes typed into the active panel.
A 1-second pause resets the buffer. Type-ahead mutates the cursor (focused +
selected ← matched row) on the **current listing** — it never triggers a reload,
so it has no `Cursor.Intent`.
