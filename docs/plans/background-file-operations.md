# Background file operations

Long-running file operations keep the panels usable. A small circle in the trailing edge of the window title bar fills with their combined progress. Clicking it opens a list of what is running, what finished, and what failed, and each running row can be stopped.

No reference image was attached to the request. The indicator below is specified from the description: a small circle that fills as work proceeds.

## Summary

Copy, move (including pack and unpack), Move to Trash, permanent delete, and delete-from-archive always run as **background tasks**. The blocking progress overlay goes away. The user can keep browsing, and can start another long operation while one is already running.

Each window shows a **task indicator** in the title bar when that window has work to report. The circle's fill is the combined progress of that window's running tasks. Clicking it opens the **task list**: every running task, then the most recent finished, failed, and cancelled ones, capped at `max(10, number of running tasks)`. A running row has a Stop button. Stopping abandons the rest of that task. It does not resume, and it does not undo items already copied, moved, or removed.

Rename and New Folder stay as they are: a short dialog, then a single quick change.

## Goals

- The panels, keyboard, and command bar stay usable during copy, move, unpack, pack, and folder removal.
- Several of those operations can run at the same time in one window.
- Progress is visible without covering the file lists.
- Finished and failed work stays visible long enough to read, without an unbounded log.
- Stop means "do not process the remaining items." Already-finished items stay as they are.

## Non-goals

- Resume, retry, or undo of a stopped or failed task.
- A byte-level progress report inside one `FileManager` copy or remove. Progress stays per top-level item, which is what the services report today.
- A global queue shared by every window. Each window keeps its own tasks, matching `FileOperationViewModel` living on that window's `AppState`.
- Serialising operations so they cannot touch the same files. Overlapping tasks are allowed; a conflict or a failure is reported on the task that hit it.
- Persisting the task list across relaunch. Quit and relaunch start from an empty list.
- Changing confirmation copy, conflict choices (overwrite / skip / rename / apply to all), or the command set. Unpack is still Copy. There is no Extract command.

## Product principles

1. Long work never takes the window away from the user.
2. The indicator is quiet when nothing is running and impossible to miss while something is.
3. Every running task is always listed. History fills whatever room is left.
4. Stop is per task and final.
5. A failure is a row in the list, not a modal alert that interrupts browsing.

---

## What becomes a background task

| User action | Today | This plan |
|---|---|---|
| Copy (`F5`), including copy out of an archive (unpack) and copy into an archive (pack) | Confirmation, then a blocking progress overlay | Confirmation, then a background task |
| Move (`F6`), including move in or out of an archive | Same overlay | Background task |
| Move to Trash (`F8`) | Confirmation, then the UI waits with no progress | Background task |
| Delete permanently (`⌘⌫`) | Confirmation, then the UI waits | Background task |
| Delete inside an archive | Confirmation, then the UI waits | Background task |
| Drop files onto a panel | Runs untracked, no progress | Background task, no extra confirmation |
| New Folder (`F7`), Rename (`Return` / `F2`) | Dialog, then one quick change | Unchanged. Not background tasks |

Confirmation dialogs stay. DESIGN requires destructive operations to ask first, and copy/move already ask. The dialog is only the decision to start. Once the user confirms, the task is running and the panels are free.

---

## User experience

### Task indicator

A 16 pt circle, vertically centered in the window's title bar, inset a few points from the trailing edge. It is a button.

The circle has two layers:

- A quiet track: a full circle in a tertiary label color, low emphasis.
- A fill: the accent color, drawn as a pie that grows clockwise from 12 o'clock. At 0 the pie is empty (only the track shows). At 1 the pie covers the track.

The fill fraction is the combined progress of every running task in this window:

```
completed items across running tasks / total items across running tasks
```

A running task that has not reported progress yet counts as 0 completed. If the total is still 0, the fraction is 0.

The control's accessibility label names the state: "Background tasks, 2 running, 40 percent" while work is in progress, or "Background tasks, finished" / "Background tasks, 1 failed" when nothing is running but the list is still showing results.

There is no separate toolbar row. The window does not grow a toolbar to hold this control.

#### When it is visible

| Situation | Indicator |
|---|---|
| Nothing running, and the list has nothing left to show | Hidden |
| One or more tasks running | Visible, pie filling |
| Nothing running, but finished / failed / cancelled rows are still unacknowledged | Visible, pie full. If any of those rows failed, the fill uses the error color. Otherwise it uses a secondary color, so a settled circle does not look like work is still moving |

Opening the task list does not hide the indicator. Closing the list acknowledges every task that had already finished, failed, or been stopped. If nothing is still running, the indicator hides and those rows leave the list. Tasks that were still running when the list closed stay, and so does the indicator.

If the user never opens the list, a settled circle remains, so a finished or failed task is not silent.

### Task list

Clicking the circle toggles a popover anchored to it, opening downward into the window. Clicking outside, or pressing Escape while the popover is key, closes it. Escape does not reach the panels while the popover is open. Closing it is what acknowledges settled rows (see above).

The popover is wide enough for one line of description, a status, and a Stop button (about 320 pt). It does not cover both panels as a modal overlay.

#### How many rows

Let `running` be the tasks still in progress, and `settled` be finished, failed, and cancelled tasks, newest last.

```
cap     = max(10, running.count)
visible = all of running, then the newest (cap - running.count) settled tasks
```

Examples:

- 0 running, 15 settled → the 10 newest settled rows.
- 3 running, 20 settled → 3 running + the 7 newest settled.
- 12 running, 5 settled → all 12 running, and no settled rows. Running work is never clipped to make room for history.

Order inside the popover, top to bottom: running tasks, oldest first; then settled tasks, newest first. The thing the user can still stop is at the top. The thing that just finished is the first history row.

Storage can keep more settled tasks than the cap (a small buffer, 50 is enough). The cap is a display rule. Acknowledging on close drops the acknowledged rows from storage.

#### A row

Every row shows:

- The operation description already on `FileOperation.displayDescription` ("Copying 4 items", "Moving 1 item", "Deleting 12 items", "Permanently deleting 3 items", and the same words for archive pack, unpack, and delete-from-archive — those are still Copy, Move, and Delete).
- One line of detail, truncated in the middle: the current item name while running, the destination path when there is one, and for a failure the error text.
- A status: Running, Waiting (blocked on a conflict dialog), Finished, Failed, Stopped.

A running or waiting row also shows its own progress ("3 of 12", or an indeterminate spinner until the first report) and a Stop button. Settled rows have no Stop button.

Stop asks for no extra confirmation. It cancels that task only.

### What the user can do while tasks run

- Browse either panel, switch panels, switch tabs, navigate, select, type-ahead, Quick Look, rename, and create folders.
- Start another copy, move, or delete. It is another row. It does not pause the ones already running.
- Confirm or cancel the *next* operation's confirmation dialog. That dialog is still modal to keyboard routing, exactly as today, because the operation has not started.
- Resolve a name conflict. The conflict sheet still appears, for one task at a time. Other tasks keep running. The waiting task's row reads Waiting. The conflict sheet gains a Cancel button that stops that task (same effect as Stop in the list). Overwrite, skip, and rename are unchanged.
- If a second task also needs a conflict decision, it waits. Its row stays Waiting. The sheet appears when the first decision returns.

### What Stop does

- The task stops before the next top-level item.
- Items already copied, moved, trashed, or deleted stay that way. Nothing is rolled back.
- The in-flight item is allowed to finish. `FileManager.copyItem`, `moveItem`, `trashItem`, and `removeItem` do not report progress or accept cancellation in the middle of one call. A single huge folder is one item, so Stop on that task takes effect when that call returns, and the circle stays put until then.
- The row becomes Stopped and counts as settled.
- The panels the task was acting on reload, the same as a finish, so partial results show up.
- There is no Resume.

### Failures

A background task that fails marks its row Failed and keeps the error text on the row. It does not raise the window's error alert. The settled indicator uses the error color until the user opens and closes the list.

Rename and New Folder still use the error alert. They are not background tasks.

### Closing the window or quitting

Closing a window that has running tasks asks first: how many tasks are still running, and that closing stops them. The default button is Stop and Close; the other is Keep Open. The same question is asked on quit if any window still has running tasks.

A settled-only indicator does not block close. Those rows are discarded with the window.

---

## Behaviour that has to stay correct

### Which panels reload

Today `confirmOperation` reloads "the active panel" and "the inactive panel" when the task *ends*. Once the user can switch panels while a copy runs, that would refresh the wrong sides.

Capture the source panel and the destination panel at the moment of Confirm (or at the moment a drop starts). Reload those two when the task finishes, fails, or stops — even if the user has since switched the active panel or navigated. Cursor intent:

- Copy: keep selection on both panels.
- Move and both kinds of delete: land on the neighbour of the removed items in the source panel; keep selection in the destination.

The confirmation handler's intent switch currently matches only the URL-based `.move` / `.delete` / `.permanentDelete` cases. The live operations are `.browseMove` and `.browseDelete`, so they already fall through to keep-selection. Fix that in the same change, using the items' URLs the cursor resolver already compares.

### One task handle is not enough

`FileOperationViewModel` stores a single `currentTask`. A second Confirm replaces it, so Stop can only see the latest task. Replace that with a map from operation id to its `Task`. Stop cancels that task. Closing the window cancels every task still in the map.

`showProgressOverlay` and `FileOperationProgressView` go away. Keyboard routing stops treating "a progress overlay is up" as a reason to swallow keys. It still goes quiet for the confirmation dialog, the conflict sheet, rename, and new folder.

### Cancellation has to reach the loop

Copy and move already call `Task.checkCancellation()` between top-level items on the task that Confirm started, so Stop works between items.

Trash and permanent delete wrap the whole loop in `Task.detached` and never check cancellation. A detached task does not see the parent task being cancelled. Move those loops onto the task the user stopped (or forward cancellation into the detached task) and check between items. Report progress per item so the circle moves during a large trash or delete.

Archive delete walks entries in a loop with no cancellation check. Check between entries. Pack and unpack already report per item; they need the same between-item cancellation check if any branch of `BrowseOperationService` does not have one.

### Conflicts are per task

The view model has one `conflictContinuation`. With several tasks, a conflict belongs to the task that raised it. Keep a single sheet — one decision at a time — and queue the other waiting tasks behind it. Stopping a waiting task resumes its continuation by throwing cancellation, and dismisses the sheet if that task is the one on screen.

`applyToAll` stays per task. One copy's "apply to all" must not answer another copy's conflicts.

### Drops

`performDrop` calls the browse copy service with an empty progress callback and never enters `activeOperations`. It becomes a normal background copy: a row, progress, Stop, and a reload of the destination panel when it ends.

### Same files, two tasks

No lock. If the user trashes a folder that another task is copying, that task fails and its row says why. The directory watcher still refreshes a panel that is showing the affected folder.

### Progress shape

`FileOperationProgress` stays item counts (`completedItems` / `totalItems` plus the current name). Do not add byte totals in this work. The plan should not pretend a one-folder copy will animate smoothly: that copy is one item, so the pie jumps from empty to full when `copyItem` returns.

### Several windows

The indicator and the list are per window. A copy started on the left window does not appear in the right window's title bar. The other window still sees the files change through its directory watcher.

The Settings window has no indicator.

---

## Vocabulary

Add these to [CONTEXT.md](../CONTEXT.md) when the feature lands. Use them in code and in the design doc.

### Background task

A copy, move, or delete that runs while the panels stay usable. Tracked on the window's `FileOperationViewModel`. Rename and New Folder are not background tasks.

_Avoid_: job; operation queue (nothing is queued except conflict questions); Extract (unpack is Copy).

### Task indicator

The circle in the trailing title bar. Hidden when the window has nothing to report. Its fill is the combined item-progress of that window's running background tasks.

_Avoid_: spinner (it fills, it does not spin); toolbar button (it lives in the title bar).

### Task list

The popover opened from the task indicator. Every running background task, plus recent finished, failed, and stopped ones, capped at `max(10, running count)`.

_Avoid_: progress overlay (that is the view this replaces); notification center.

### Stop

Cancel one background task before the next top-level item. Partial results remain. There is no resume.

_Avoid_: pause; continue; undo.

---

## Architecture

```
WindowRootView / MainWindowView
  └── WindowConfigurator
        └── NSTitlebarAccessoryViewController (.right)
              └── TaskIndicatorButton          SwiftUI circle, 16 pt
                    └── click → NSPopover
                          └── TaskListView     rows + Stop

AppState (per window, unchanged owner)
  └── FileOperationViewModel
        ├── running: [FileOperation]          status inProgress, including Waiting
        ├── settled: [FileOperation]          completed / failed / cancelled
        ├── tasks: [UUID: Task<Void, Never>]
        ├── conflictQueue                     one sheet, one continuation per waiting task
        └── indicatorState                    hidden / running(fraction) / settled(hasFailure)

Models
  └── TaskListPolicy                          pure: visible rows + aggregate fraction

Services (unchanged routing)
  └── BrowseOperationService / FileOperationService / ArchiveService
        check cancellation between items; trash and delete report progress
```

`FileOperation`, `FileOperationStatus`, and `FileOperationProgress` stay. `.cancelled` is what Stop writes; the row title is "Stopped". No new operation kind. Archive pack and unpack stay `.copy` and `.move`.

### Title bar, not a toolbar

The window has no toolbar today. `WindowConfigurator` already reaches the `NSWindow` for `titlebarSeparatorStyle`. Extend that path:

- One `NSTitlebarAccessoryViewController` with `layoutAttribute = .right`, added once per window. `updateNSView` on the configurator must not add a second controller.
- Its view is an `NSHostingView` of the circle button.
- The popover is an AppKit `NSPopover` (transient) presented from that accessory view. A SwiftUI `.popover` attached inside a title-bar hosting view is the fallback only if the AppKit popover cannot anchor; prefer AppKit so the anchor stays on the circle when the window resizes.

Do not introduce `.toolbar` or a unified toolbar style for this. That would add a toolbar band under the title or change the chrome around the path bar.

The accessory is created with the window and kept up to date from `FileOperationViewModel` (the hosting view observes it). The view model does not import AppKit.

### Task list policy

A pure value type in `Models`, tested without a service or a window:

```swift
package struct TaskListPolicy: Sendable {
    package static let minimumSlots = 10
    package static let settledCapacity = 50

    package func visible(
        running: [FileOperation],
        settledNewestLast: [FileOperation]
    ) -> [FileOperation]

    /// Nil when nothing is running. Otherwise 0...1.
    package func aggregateFraction(running: [FileOperation]) -> Double?
}
```

`visible` implements the cap in the User experience section. `FileOperationViewModel` trims `settled` to `settledCapacity` on every insert, dropping the oldest.

### View model

`confirmOperation` and `performDrop` start work by recording a `FileOperation`, storing its `Task` in the map, and returning immediately. The task body is the existing `executeBrowseTransfer` / `executeBrowseDelete` path with three changes:

- Do not set `showProgressOverlay`.
- On finish, fail, or cancel, move the operation from `running` to `settled` instead of deleting it.
- Record which task owns the in-flight conflict, so Stop and the sheet's Cancel target that id.

`cancelCurrentOperation()` becomes `stop(id: UUID)`. Remove the overlay flag once nothing reads it.

Indicator state is computed:

- `running` non-empty → `.running(aggregateFraction)`.
- `running` empty and `settled` non-empty → `.settled(hasFailure:)` where failure means any settled row is `.failed`.
- both empty → `.hidden`.

Closing the popover calls `acknowledgeSettled()`, which drops settled rows. It does not touch `running`.

### Modules

| Piece | Module | Why |
|---|---|---|
| `TaskListPolicy` | `Models` | Leaf, no services, unit-tested beside `FileOperation` |
| Task map, stop, acknowledge, conflict queue | `ViewModels` (`FileOperationViewModel`) | Already the coordinator |
| Circle, list rows | `Views` | Presentation only |
| Title-bar controller and popover | `Views`, next to `WindowConfigurator` | AppKit stays out of the view model |
| Cancellation and progress in trash, delete, archive remove | `Services` | The loops live there |

No new Bazel target. `Views` still has no unit-test directory; the policy and the view model carry the tests. UI tests are out of this plan's routine check (run them only when explicitly asked).

---

## Documentation to update in the implementation

- [DESIGN.md](../DESIGN.md) — replace "Long copies and moves show a progress overlay that can be cancelled part-way" with the indicator, the list, and Stop. Mention that folder removal is included and that the panels stay usable.
- [CONTEXT.md](../CONTEXT.md) — the four terms above.
- [CURRENT_ARCH.md](../CURRENT_ARCH.md) — `FileOperationProgressView` is removed; describe the accessory and the view-model task map. Note that `FileOperationViewModel` is still per window.

---

## Implementation slices

Each slice is shippable on its own and keeps `bazel test //LCdrDataTests/...` green.

### 1. Policy and a multi-task view model

Add `TaskListPolicy` and tests: cap math, aggregate fraction with a not-yet-started task, empty running.

Change `FileOperationViewModel` so each confirmed operation and each drop has its own task. `stop(id:)` cancels one and leaves the others. Settled rows accumulate and trim to 50. Delete `showProgressOverlay` once the view no longer reads it — until slice 3, the window simply does not show the overlay (slice 1 can land behind a temporary "no overlay" if slice 3 follows immediately; do not leave the user with silent copies for long).

Tests in `FileOperationViewModelTests`: two copies, stop the first, the second runs on; a failure is a settled row and does not set `showErrorAlert`; acknowledge clears settled and leaves running; drop creates a row.

### 2. Services honour Stop and report delete progress

Trash, permanent delete, and archive remove check cancellation between items and report `FileOperationProgress`. Copy, move, pack, and unpack already report progress; add a missing check if a branch has none.

Test with the existing fakes: a cancelled task does not process the item after the check; progress is published per item.

### 3. Title-bar indicator and task list

Add the accessory, the circle, and the popover. Wire Stop, the Waiting row, and the conflict sheet's Cancel. Remove `FileOperationProgressView`.

Keyboard routing no longer depends on the overlay. Confirmation, conflict, rename, and new-folder dialogs still suspend it.

Fix completion reload to capture the source and destination panels, and to use neighbour-landing for browse move and browse delete.

Window close and quit prompt when `running` is non-empty.

### 4. Docs

Update DESIGN, CONTEXT, and CURRENT_ARCH as listed above. Same change as slice 3, or the commit immediately after it. Do not update them in slice 1 while the overlay is still the real UI.

---

## Tests

Unit tests only, under Bazel:

- `LCdrDataTests/Core/Models` — `TaskListPolicy`.
- `LCdrDataTests/ViewModels` — concurrent tasks, stop one, settled cap, acknowledge, drop, failure without an alert, conflict `applyToAll` isolated per task.
- `LCdrDataTests/Services` — cancellation between items for trash, permanent delete, and archive remove; progress callbacks.

No new UI test in the routine run. When UI tests are explicitly requested, cover: the circle appears after a copy of several files, the list shows the row, Stop leaves the already-copied files in place, and the panels still accept a click while the task is running.

---

## Decisions locked by this plan

These are the choices an implementation should follow. They are called out so they are not re-litigated mid-slice.

| Topic | Decision |
|---|---|
| Parallelism | Tasks in one window run together. They are not queued behind each other. |
| History cap | `max(10, running count)` visible rows. Running rows are never omitted. |
| Settled rows | Finished, failed, and stopped. All three share the history slots. |
| Indicator after success | Stays, full, secondary color, until the list is opened and closed. |
| Indicator after failure | Stays, full, error color, until the same acknowledgement. No error alert. |
| Stop | Between top-level items. No rollback, no resume. |
| One huge file or folder | One item. The pie does not move until that call returns. |
| Conflicts | Still a sheet, one at a time, with Cancel meaning Stop. |
| Scope | Per window. |
| Rename, New Folder | Not background tasks. |
