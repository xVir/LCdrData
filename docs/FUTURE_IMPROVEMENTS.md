# FUTURE_IMPROVEMENTS.md

Architectural deepening opportunities surfaced during a `/improve-codebase-architecture`
review on 2026-05-08. Captured here so they don't get lost while the higher-priority
panel-internals refactor (Cursor / DirectorySession / unified directory load) is in flight.

---

## 4. `PanelCommand` + `KeyboardRouter` — one named test surface for keyboard input

**Files:**
- `LCdrData/Views/MainWindowView.swift:47-85` — `KeyShortcutModifier` invocation site
- `LCdrData/Views/MainWindowView.swift:290-313` — type-ahead key-press handling
- `LCdrData/Views/MainWindowView.swift:378-529` — `KeyShortcutModifier` itself

### Problem

`KeyShortcutModifier` takes **19 closures**. Each `onKeyPress` body repeats the same
`keyboardRoutingActive` guard, sometimes plus `pathEditingBlocksDelete`. The keyboard
interface has leaked into a long parameter list, and the actual rules — "Cmd+Down
opens; Tab switches panel; Space selects-and-advances; Delete is parent-nav unless
Cmd is held; printable chars feed type-ahead unless modifiers are present" — are buried
in SwiftUI handlers that can only be exercised end-to-end through UI tests.

### Solution

- A `PanelCommand` enum naming everything the user can ask the active panel to do:
  `.copy`, `.move`, `.delete`, `.permanentDelete`, `.openSelected`, `.toggleSelection`,
  `.navigateParent`, `.navigateBack`, `.navigateForward`, `.typeAhead(String)`,
  `.editPathBar`, `.quickLook`, `.editFile`, `.rename`, `.focusFirst`, `.focusLast`,
  `.switchPanel`, etc.
- A pure `KeyboardRouter.command(for: KeyPress, context: RoutingContext) -> PanelCommand?`
  where `RoutingContext` carries the small set of "what's currently true" flags
  (any modal open? path bar editing? type-ahead modifiers present?).
- The view becomes `onKeyPress { press in router.command(for: press, context: ctx).map(dispatcher.run) ?? .ignored }`.

### Benefits

- **Locality.** The entire keyboard map sits in one file, ordered by precedence.
- **Leverage.** Adding a new shortcut means one enum case + one router clause, not
  "thread one more closure through `MainWindowView`, `KeyShortcutModifier`, and
  `handleTypeAheadKeyPress`."
- **Tests.** Keyboard routing becomes a unit-testable function (no SwiftUI required).
  `PanelViewModelPhase3Tests.swift` stops being the only thing that exercises
  shortcut effects.

### Deletion test

Delete `KeyShortcutModifier` — the routing rules reappear scattered through whatever
consumes them. The seam is real; it's just collapsed into a 19-parameter closure bag
instead of a named type.

---

## 5. `OperationRunner` + `ConflictPolicy` — collapse the four near-identical `execute…` methods

**Files:**
- `LCdrData/ViewModels/FileOperationViewModel.swift:281-432` — the four `execute…` methods
- `LCdrData/ViewModels/FileOperationViewModel.swift:32-46,437-460` — `applyToAll` /
  `storedResolution` / `resolveConflict` / `resolveCurrentConflict`
- `LCdrData/Services/FileOperationService.swift:166-225` — `performBatchOperation`
  (already factored on the service side)

### Problem

`executeCopy`, `executeMove`, `executeDelete`, `executePermanentDelete` are
~30 lines each and ~90% identical: append a `FileOperation`, call the service,
swap on `CancellationError` / error, set status, hide overlay, reload both panels,
clean up. The conflict-resolution wrapper (`applyToAll`, `storedResolution`) is also
a small policy object pretending to be three loose fields plus one `async` closure
on the view model.

`FileOperationViewModel` mixes:

- Dialog state (5 sets of `show…` flag + payload pairs)
- Operation orchestration (the four `execute…` methods)
- Conflict resolution policy (`applyToAll`, `storedResolution`, the continuation)
- Active operation tracking + progress
- Error alerting

`FileOperationViewModelTests` largely assert "did `showConfirmationDialog` flip?" —
they exercise the field-flipping, not the orchestration, because orchestration is
glued directly into the SwiftUI flow.

### Solution

- **`ConflictPolicy`** (value): "first time, ask; if `applyToAll` latched, return
  the stored resolution." A ~20-line struct with one async method.
- **`OperationRunner`** (struct): one async `run(_ operation: FileOperationType,
  prompt: ConflictPolicy, onProgress: …) async throws`. The four execute methods
  become one switch over `FileOperationType`.
- Leave `FileOperationViewModel` as the dialog/state coordinator that *uses* an
  `OperationRunner` — but the runner itself is testable without booting SwiftUI.

### Benefits

- **Locality.** The cancellation / error / status pattern lives in one place.
- **Leverage.** Adding a new operation kind is "add an enum case + a runner branch,"
  not "duplicate a 30-line method."
- **Tests.** The runner can be unit-tested with the existing `MockFileOperationService`
  more sharply — e.g. "`applyToAll = .skip` returns `.skip` on subsequent conflicts
  without prompting" becomes a one-shot `ConflictPolicy` test instead of a
  view-model state-flag chase.

### Deletion test

Delete the four `execute…` methods individually — each looks load-bearing in
isolation, but deleting all four exposes that the same logic is being repeated four
times. That's the textbook signal for an unnamed deep module.
